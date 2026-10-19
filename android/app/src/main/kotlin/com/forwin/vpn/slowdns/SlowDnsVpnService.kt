package com.forwin.vpn.slowdns

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import com.forwin.vpn.R
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import org.json.JSONObject
import java.io.File
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Owns one standalone TUN and one separately executed dnstt Go runtime. */
class SlowDnsVpnService : VpnService() {
    private class Session(val id: Long, val result: CompletableFuture<Map<String, Any>>) {
        val lock = Any()
        @Volatile var cancelled = false
        @Volatile var failed = false
        @Volatile var resolver = ""
        var process: Process? = null
        var tun: ParcelFileDescriptor? = null
        var coreTun: ParcelFileDescriptor? = null
        var core: CoreController? = null
    }

    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var session: Session? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, "Slow DNS VPN", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val id = intent.getLongExtra(EXTRA_REQUEST, -1)
                val future = requests.remove(id)
                if (future == null) {
                    if (session == null) stopSelf()
                    return START_NOT_STICKY
                }
                cancelCurrent()
                val next = Session(id, future)
                session = next
                state = snapshot(false, "", "Connecting")
                notifyState("Connecting; traffic is blocked until ready")
                val raw = intent.getStringExtra(EXTRA_CONFIG) ?: ""
                worker.execute { connect(next, raw) }
            }
            ACTION_DISCONNECT -> {
                cancelCurrent()
                state = snapshot(false, "", "Disconnected")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            else -> if (session == null) stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun active(s: Session) = session === s && !s.cancelled && !s.failed

    private fun connect(s: Session, raw: String) {
        try {
            val cfg = SlowDnsConfig.fromJson(raw)
            if (!active(s)) return
            val builder = Builder().setSession("4win VPN - Slow DNS").setMtu(1280)
                .addAddress("26.26.26.1", 30).addRoute("0.0.0.0", 0)
                .addAddress("da26:2626::1", 126).addRoute("::", 0)
                .addDnsServer("1.1.1.1")
            applySplitTunnel(builder)
            if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)
            // Establish before probing: captured apps cannot escape during startup.
            val tun = builder.establish() ?: error("Unable to establish the Slow DNS VPN interface.")
            synchronized(s.lock) {
                if (!active(s)) { tun.close(); return }
                s.tun = tun
            }
            val localPort = ServerSocket().use {
                it.bind(InetSocketAddress("127.0.0.1", 0)); it.localPort
            }
            val candidates = if (cfg.dnsTransport == SlowDnsConfig.Transport.DOH)
                cfg.resolvers.take(1) else cfg.resolvers
            var selected = false
            for (resolver in candidates) {
                if (!active(s)) return
                s.resolver = if (cfg.dnsTransport == SlowDnsConfig.Transport.DOH) cfg.dohUrl!! else resolver.authority()
                state = snapshot(false, s.resolver, "Checking authenticated tunnel")
                val process = ProcessBuilder(SlowDnsCommand.build(cfg, resolver, applicationInfo.nativeLibraryDir, localPort))
                    .redirectOutput(File("/dev/null")).redirectError(File("/dev/null")).start()
                synchronized(s.lock) {
                    if (!active(s)) { process.destroyForcibly(); return }
                    s.process = process
                }
                selected = runCatching {
                    Socks5Probe.connectAndQuery(localPort, cfg.username, cfg.password, 15_000)
                }.getOrDefault(false)
                if (selected && active(s)) break
                process.destroyForcibly()
                synchronized(s.lock) { if (s.process === process) s.process = null }
            }
            check(selected) { "No resolver passed the authenticated SOCKS5 and tunneled DNS checks. Verify the domain, public key and server SOCKS5 endpoint." }
            if (!active(s)) return
            Seq.setContext(applicationContext)
            Libv2ray.initCoreEnv(filesDir.absolutePath, "")
            val controller = Libv2ray.newCoreController(Callback(s))
            synchronized(s.lock) {
                if (!active(s)) return
                s.core = controller
                val coreTun = ParcelFileDescriptor.dup(tun.fileDescriptor)
                s.coreTun = coreTun
                controller.startLoop(SlowDnsXrayConfig.build(localPort, cfg.username, cfg.password), coreTun.fd)
            }
            check(controller.isRunning) { "The Slow DNS packet routing core did not start." }
            if (!active(s)) return
            state = snapshot(true, s.resolver, "")
            notifyState("Connected via ${s.resolver}")
            s.result.complete(state)
            var lastHealth = System.nanoTime()
            while (active(s)) {
                check(s.process?.isAlive == true && controller.isRunning) { "The Slow DNS backend stopped." }
                if (System.nanoTime() - lastHealth >= TimeUnit.SECONDS.toNanos(20)) {
                    check(Socks5Probe.connectAndQuery(localPort, cfg.username, cfg.password, 15_000)) {
                        "The authenticated Slow DNS health check failed."
                    }
                    lastHealth = System.nanoTime()
                }
                Thread.sleep(500)
            }
        } catch (failure: Throwable) {
            if (active(s)) failClosed(s, failure)
        }
    }

    /** App-UID exclusion also covers the dnstt child process; no socket can loop. */
    private fun applySplitTunnel(builder: Builder) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val mode = prefs.getString("flutter.split_tunnel_mode", "off") ?: "off"
        val packages = (prefs.getString("flutter.split_tunnel_apps", "") ?: "")
            .split(',').map { it.trim() }.filter { it.isNotEmpty() && it != packageName }.distinct()
        if (mode == "include") {
            var allowed = 0
            for (pkg in packages) {
                if (runCatching { builder.addAllowedApplication(pkg) }.isSuccess) allowed++
            }
            check(allowed > 0) { "Select at least one installed app other than this VPN in split-tunnel include mode." }
        } else {
            builder.addDisallowedApplication(packageName)
            if (mode == "exclude") packages.forEach { runCatching { builder.addDisallowedApplication(it) } }
        }
    }

    private fun failClosed(s: Session, failure: Throwable) {
        if (session !== s || s.cancelled || s.failed) return
        s.failed = true
        val blocked = synchronized(s.lock) { s.tun != null }
        val error = (failure.message ?: "Slow DNS failed.") + if (blocked)
            " Traffic remains blocked until you disconnect or retry." else " The VPN did not start."
        state = snapshot(false, s.resolver, error)
        s.result.completeExceptionally(IllegalStateException(error))
        notifyState(if (blocked) "Connection failed; traffic is blocked" else "Connection failed; VPN not started")
        // Keep the TUN/routes installed, but remove every forwarding engine.
        closeResources(s, keepTun = true)
    }

    private fun cancelCurrent() {
        val previous = session ?: return
        session = null
        previous.cancelled = true
        previous.result.completeExceptionally(IllegalStateException("Slow DNS connection cancelled."))
        closeResources(previous, keepTun = false)
    }

    private fun closeResources(s: Session, keepTun: Boolean) {
        val oldCore: CoreController?
        val oldProcess: Process?
        val oldTun: ParcelFileDescriptor?
        val oldCoreTun: ParcelFileDescriptor?
        synchronized(s.lock) {
            oldCore = s.core; s.core = null
            oldProcess = s.process; s.process = null
            oldTun = if (keepTun) null else s.tun.also { s.tun = null }
            oldCoreTun = s.coreTun; s.coreTun = null
        }
        // Never hold the resource lock while Go calls back into this service.
        runCatching { oldProcess?.destroyForcibly() }
        runCatching { oldCore?.stopLoop() }
        runCatching { oldCoreTun?.close() }
        runCatching { oldTun?.close() }
    }

    private inner class Callback(private val owner: Session) : CoreCallbackHandler {
        override fun startup() = 0L
        override fun onEmitStatus(level: Long, msg: String?) = 0L
        override fun shutdown(): Long {
            // Do not call stopLoop reentrantly from a Go callback.
            if (active(owner)) Thread { failClosed(owner, IllegalStateException("The Slow DNS packet routing core stopped.")) }.start()
            return 0L
        }
    }

    private fun notifyState(text: String) {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
        val disconnect = PendingIntent.getService(this, 0,
            Intent(this, SlowDnsVpnService::class.java).setAction(ACTION_DISCONNECT), PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, CHANNEL).setContentTitle("Slow DNS")
            .setContentText(text).setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", disconnect)
            .setOngoing(true).setPriority(NotificationCompat.PRIORITY_LOW).build()
        startForeground(NOTIFICATION_ID, notification)
    }

    override fun onRevoke() { cancelCurrent(); state = snapshot(false, "", "VPN permission revoked."); stopSelf(); super.onRevoke() }
    override fun onDestroy() {
        cancelCurrent(); worker.shutdownNow()
        if (instance === this) { instance = null; state = snapshot(false, "", "Disconnected") }
        super.onDestroy()
    }

    companion object {
        const val ACTION_CONNECT = "com.forwin.vpn.SLOWDNS_CONNECT"
        const val ACTION_DISCONNECT = "com.forwin.vpn.SLOWDNS_DISCONNECT"
        private const val EXTRA_CONFIG = "config_json"
        private const val EXTRA_REQUEST = "request_id"
        private const val CHANNEL = "SlowDnsVpn"
        private const val NOTIFICATION_ID = 17
        private val sequence = AtomicLong()
        private val requests = ConcurrentHashMap<Long, CompletableFuture<Map<String, Any>>>()
        @Volatile private var instance: SlowDnsVpnService? = null
        @Volatile private var state = snapshot(false, "", "Disconnected")
        private fun snapshot(ready: Boolean, resolver: String, error: String): Map<String, Any> =
            mapOf("ready" to ready, "connected" to ready, "resolver" to resolver, "error" to error)

        fun start(context: Context, config: JSONObject): CompletableFuture<Map<String, Any>> {
            SlowDnsConfig.fromJson(config)
            val id = sequence.incrementAndGet()
            val result = CompletableFuture<Map<String, Any>>()
            requests[id] = result
            val intent = Intent(context, SlowDnsVpnService::class.java).setAction(ACTION_CONNECT)
                .putExtra(EXTRA_CONFIG, config.toString()).putExtra(EXTRA_REQUEST, id)
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            } catch (failure: Throwable) {
                requests.remove(id); result.completeExceptionally(failure)
            }
            return result
        }
        fun stop(context: Context) {
            requests.values.forEach { it.completeExceptionally(IllegalStateException("Slow DNS cancelled.")) }
            requests.clear()
            instance?.let {
                it.cancelCurrent(); state = snapshot(false, "", "Disconnected")
                it.stopForeground(STOP_FOREGROUND_REMOVE); it.stopSelf()
            }
        }
        fun disconnect() { instance?.let { stop(it.applicationContext) } }
        fun status(): Map<String, Any> = state.toMap()
    }
}
