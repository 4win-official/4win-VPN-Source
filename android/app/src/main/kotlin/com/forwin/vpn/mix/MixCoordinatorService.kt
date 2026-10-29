package com.forwin.vpn.mix

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Handler
import android.os.Looper
import android.net.Uri
import androidx.core.app.NotificationCompat
import com.forwin.vpn.R
import com.forwin.vpn.VpnStateBroadcast
import com.forwin.vpn.VpnNotificationLabels
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import org.json.JSONObject
import java.net.ServerSocket
import java.util.UUID
import java.util.LinkedHashMap
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Mix alone owns the Android TUN. A persistent, TUN-less Xray router exports each
 * prefix; isolated engines consume their previous prefix and publish the next
 * SOCKS endpoint. The prefix router is never restarted when attaching the TUN.
 */
class MixCoordinatorService : VpnService() {
    private val executor = Executors.newSingleThreadExecutor()
    private val workers = ConcurrentHashMap<String, Worker>()
    private var router: CoreController? = null
    private var finalCore: CoreController? = null
    private val resolverCores = LinkedHashMap<Int, CoreController>()
    private val udpRelays = LinkedHashMap<Int, MixUdpRelay>()
    private val socks4Proxies = LinkedHashMap<Int, MixSocks4Proxy>()
    private var tun: ParcelFileDescriptor? = null
    private var request: Request? = null
    private var receiverRegistered = false
    private val cleaned = AtomicBoolean(false)
    private val destroyed = AtomicBoolean(false)
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var reconnectFrom: Request? = null

    private data class Worker(val slot: Int, val hop: Int,
        var started: Boolean = false,
        val ready: CompletableFuture<Boolean> = CompletableFuture(),
        val stopped: CompletableFuture<Unit> = CompletableFuture())

    class Request(val id: String, val plan: JSONObject,
        val connected: CompletableFuture<Long> = CompletableFuture()) {
        val cancelled = AtomicBoolean(false)
        val stopped = CompletableFuture<Unit>()
    }

    companion object {
        private const val CHANNEL = "MixCoordinator"
        private const val NOTIFICATION = 39
        private const val ACTION_START = "com.forwin.vpn.mix.CONNECT"
        const val ACTION_STOP = "com.forwin.vpn.mix.DISCONNECT"
        const val ACTION_RECONNECT = "com.forwin.vpn.mix.RECONNECT"
        @Volatile private var active: Request? = null
        @Volatile private var instance: MixCoordinatorService? = null
        @Volatile var isRunning = false
            private set
        @Volatile var isReconnecting = false
            private set
        @Volatile private var statsCore: CoreController? = null
        private data class DelayProbe(val request: Request, val config: String)
        @Volatile private var delayProbe: DelayProbe? = null

        fun measureActiveDelay(url: String): Long {
            val probe = delayProbe ?: return -1L
            fun current() = isRunning && !isReconnecting &&
                active === probe.request && !probe.request.cancelled.get() &&
                delayProbe === probe
            if (!current()) return -1L
            val delay = runCatching {
                Libv2ray.measureOutboundDelay(probe.config, url)
            }.getOrDefault(-1L)
            return if (current()) delay else -1L
        }

        private var uplink = 0L
        private var downlink = 0L

        /** Redacted, thread-safe snapshot exposed to Flutter without waiting on the engine. */
        private class DiagnosticsSnapshot(val attemptId: String, blockCount: Int) {
            private val lock = Any()
            private val states = MutableList(blockCount) { "pending" }
            private val details = MutableList<String?>(blockCount) { null }
            private var phase = "Preparing chain"
            private var failure: String? = null
            fun starting(index: Int) = synchronized(lock) {
                if (index in states.indices && states[index] != "failed") states[index] = "starting"
                if (failure == null) phase = "Initializing blocks"
            }
            fun ready(index: Int) = synchronized(lock) {
                if (index in states.indices && states[index] != "failed") {
                    states[index] = "ready"; details[index] = null
                }
                if (failure == null && states.all { it == "ready" }) phase = "Blocks initialized"
            }
            fun verifiedWarp(index: Int, ip: String) = synchronized(lock) {
                if (index in states.indices && states[index] != "failed") {
                    states[index] = "verified"
                    details[index] = "WARP reachable · exit IP $ip"
                }
                if (failure == null) phase = "Verifying WARP egress"
            }
            fun failed(index: Int, detail: String = "Hop failed while starting") = synchronized(lock) {
                if (index in states.indices && states[index] != "failed") {
                    states[index] = "failed"; details[index] = detail
                }
                phase = "Chain failed"; if (failure == null) failure = detail
            }
            /** Global errors are deliberately not attributed to the final hop. */
            fun globalFailure(message: String) = synchronized(lock) {
                if (states.none { it == "failed" }) failure = message
                phase = "Chain failed"
            }
            fun setPhase(value: String) = synchronized(lock) {
                if (failure == null) phase = value
            }
            fun asMap(): Map<String, Any?> = synchronized(lock) {
                val blocks = states.indices.map { index ->
                    val block = LinkedHashMap<String, Any?>()
                    block["index"] = index; block["state"] = states[index]
                    details[index]?.let { block["detail"] = it }; block
                }
                val out = LinkedHashMap<String, Any?>()
                out["attemptId"] = attemptId; out["phase"] = phase; out["blocks"] = blocks
                failure?.let { out["error"] = it }; out
            }
        }
        @Volatile private var diagnostics: DiagnosticsSnapshot? = null
        private fun newDiagnostics(plan: JSONObject): DiagnosticsSnapshot {
            val count = plan.optJSONArray("hops")?.length()?.coerceIn(0, 50) ?: 0
            return DiagnosticsSnapshot(plan.optString("diagnosticsAttemptId", ""), count)
        }
        fun getMixDiagnostics(): Map<String, Any?> = diagnostics?.asMap()
            ?: mapOf("attemptId" to "", "phase" to "idle", "blocks" to emptyList<Map<String, Any?>>())

        /** Expose only Psiphon's native startup detail; other protocol diagnostics stay unchanged. */
        internal fun psiphonFailureDetail(protocol: String?, error: String?): String? =
            if (protocol == "psiphon") error?.trim()?.takeIf { it.isNotEmpty() }?.take(600) else null

        @Synchronized fun connect(context: Context, plan: JSONObject): CompletableFuture<Long> {
            check(active == null || active!!.stopped.isDone) { "Previous Mix session is not stopped" }
            diagnostics = newDiagnostics(plan)
            val next = Request(UUID.randomUUID().toString(), JSONObject(plan.toString()))
            active = next
            val intent = Intent(context, MixCoordinatorService::class.java).setAction(ACTION_START)
                .putExtra("sessionId", next.id)
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            } catch (error: Throwable) {
                next.connected.completeExceptionally(error)
                next.stopped.complete(Unit)
            }
            return next.connected
        }

        fun disconnect(): CompletableFuture<Unit> {
            val current = active ?: return CompletableFuture.completedFuture(Unit)
            current.cancelled.set(true)
            current.connected.completeExceptionally(IllegalStateException("Mix connection cancelled"))
            instance?.requestStop(current)
            return current.stopped
        }

        @Synchronized fun traffic(): LongArray {
            val core = statsCore
            if (core != null) {
                runCatching { uplink += core.queryStats("proxy", "uplink").coerceAtLeast(0) }
                runCatching { downlink += core.queryStats("proxy", "downlink").coerceAtLeast(0) }
            }
            return longArrayOf(uplink, downlink)
        }
    }

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val current = request ?: return
            if (intent?.getStringExtra("sessionId") != current.id) return
            val hop = intent.getStringExtra("hopId") ?: return
            val worker = workers[hop] ?: return
            when (intent.getStringExtra("state")) {
                "ready" -> worker.ready.complete(intent.getBooleanExtra("supportsUdp", false))
                "stopped" -> worker.stopped.complete(Unit)
                "error" -> {
                    val reportedError = intent.getStringExtra("error")
                    val protocol = current.plan.optJSONArray("hops")
                        ?.optJSONObject(worker.hop)?.optString("protocol")
                    val detail = psiphonFailureDetail(protocol, reportedError)
                    if (detail == null) diagnostics?.failed(worker.hop)
                    else diagnostics?.failed(worker.hop, detail)
                    val error = IllegalStateException("Stage ${worker.hop + 1}: ${reportedError ?: "engine failed"}")
                    worker.ready.completeExceptionally(error)
                    if (current.connected.isDone && !current.cancelled.get()) fail(current, error)
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        val channel = NotificationChannel(CHANNEL, VpnNotificationLabels.MIX_PROTOCOL, NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        showNotification("Preparing the complete chain")
        val filter = IntentFilter(MixWorkerService.ACTION_STATUS)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(statusReceiver, filter)
        receiverRegistered = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val next = active
        if (intent?.action == ACTION_STOP || intent?.action == ACTION_RECONNECT) {
            // Notification actions belong to one chain only, including worker notifications.
            if (next != null && intent.getStringExtra("sessionId") == next.id) {
                if (intent.action == ACTION_RECONNECT) {
                    runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, false) }
                    requestReconnect(next)
                } else {
                    runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, false) }
                    VpnStateBroadcast.notifyDisconnected(this, "mix")
                    requestStop(next)
                }
            } else if (request == null) stopSelf(startId)
            return START_NOT_STICKY
        }
        if (intent?.action != ACTION_START || next == null || intent.getStringExtra("sessionId") != next.id) {
            if (request == null) stopSelf(startId)
            return START_NOT_STICKY
        }
        if (request != null) return START_NOT_STICKY
        request = next
        executor.execute {
            try {
                ensureLive(next)
                startChain(next)
            } catch (error: Throwable) {
                diagnostics?.globalFailure("Mix connection failed")
                if (reconnectFrom !== next) next.connected.completeExceptionally(error)
                next.cancelled.set(true)
                cleanup(next)
            }
        }
        return START_NOT_STICKY
    }

    private fun startChain(current: Request) {
        val plan = current.plan
        require(plan.getInt("version") == 1) { "Unsupported Mix plan version" }
        val hops = plan.getJSONArray("hops")
        require(hops.length() in 1..50) { "Mix supports 1 to 50 blocks" }
        val heldPorts = ArrayList<ServerSocket>()
        val relayConfig = plan.optJSONObject("udpRelay")?.let { MixUdpRelay.Config.fromJson(it) }
        // Reject known impossible UDP underlays before binding listeners or
        // starting any worker. Native readiness still validates real transport.
        MixCapabilities.validatePlan(plan, relayConfig != null)
        com.example.sstp_flutter.VpnConnectionObserver.notifyStarting(this)
        fun reservePort(): Int {
            val socket = ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1"))
            heldPorts.add(socket)
            return socket.localPort
        }
        val prefixPorts = List(hops.length()) { reservePort() }
        val workerPorts = HashMap<Int, Int>()
        val dnsPorts = HashMap<Int, Int>()
        val rawPrefixPorts = HashMap<Int, Int>()
        val relayPorts = HashMap<Int, Int>()
        val relayUnderlayPorts = HashMap<Int, Int>()
        var slot = 0
        for (i in 0 until hops.length()) {
            if (relayConfig != null && MixCapabilities.needsRelay(hops.getJSONObject(i))) {
                relayPorts[i] = reservePort()
                relayUnderlayPorts[i] = reservePort()
            }
            when (hops.getJSONObject(i).getString("protocol")) {
                in MixRouting.nativeProtocols -> {
                    workerPorts[i] = reservePort()
                    workers[i.toString()] = Worker(slot++, i)
                }
                "direct_dns" -> {
                    dnsPorts[i] = reservePort()
                    if (i > 0) rawPrefixPorts[i - 1] = reservePort()
                }
                "proxy" -> if (hops.getJSONObject(i).has("socks4")) workerPorts[i] = reservePort()
            }
        }
        val routerConfig = try { MixRouting.sidecar(plan, prefixPorts, workerPorts, dnsPorts, rawPrefixPorts,
            relayPorts, relayUnderlayPorts) }
            finally { heldPorts.forEach { runCatching { it.close() } } }
        // Workers and router must bind themselves. Ports are randomized and a
        // stage cannot become ready if its actual bind fails.
        Seq.setContext(applicationContext)
        Libv2ray.initCoreEnv(filesDir.absolutePath, "")
        router = newController(current)
        router!!.startLoop(routerConfig.toString(), -1)
        ensureLive(current)

        var supportsUdp = true
        for (i in 0 until hops.length()) {
            ensureLive(current)
            diagnostics?.starting(i)
            try {
                val hop = hops.getJSONObject(i)
                val protocol = hop.getString("protocol")
                val worker = workers[i.toString()]
                if (protocol == "direct_dns") {
                    val resolver = newController(current)
                    resolverCores[i] = resolver
                    resolver.startLoop(MixRouting.resolver(hop.optString("address").trim(), dnsPorts.getValue(i),
                        if (i == 0) null else rawPrefixPorts.getValue(i - 1)).toString(), -1)
                    diagnostics?.ready(i)
                } else if (worker == null) {
                    if (protocol == "proxy" && hop.has("socks4")) {
                        val settings = hop.getJSONObject("socks4")
                        val adapter = MixSocks4Proxy(workerPorts.getValue(i), settings.getString("host"), settings.getInt("port"),
                            settings.optString("userId"), if (i == 0) null else prefixPorts[i - 1])
                        socks4Proxies[i] = adapter; adapter.start()
                    }
                    if (protocol == "xray" || protocol == "proxy") supportsUdp = MixCapabilities.afterXray(hop, supportsUdp)
                    if (relayPorts.containsKey(i)) {
                        startRelay(i, relayConfig!!, relayPorts.getValue(i), relayUnderlayPorts.getValue(i)); supportsUdp = true
                    }
                    diagnostics?.ready(i)
                } else {
                    require(i == 0 || supportsUdp || protocol != "warp") {
                        "Stage ${i + 1}: WARP needs a UDP-capable preceding path; HTTP CONNECT and SOCKS4 do not carry UDP by themselves. No direct-network fallback is allowed"
                    }
                    showNotification("Connecting stage ${i + 1} of ${hops.length()}")
                    val intent = Intent(this, MixWorkerService.CLASSES[worker.slot])
                        .setAction(MixWorkerService.ACTION_START).putExtra("sessionId", current.id)
                        .putExtra("hopId", i.toString()).putExtra("protocol", protocol)
                        .putExtra("workerSlot", worker.slot).putExtra("upstreamSupportsUdp", supportsUdp)
                        .putExtra("config", JSONObject(hop.optJSONObject("config")?.toString() ?: "{}").toString())
                        .putExtra("listenPort", workerPorts.getValue(i))
                    if (i > 0) intent.putExtra("upstreamSocksUrl", "socks5://127.0.0.1:${prefixPorts[i - 1]}")
                    worker.started = true
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                    supportsUdp = awaitReady(current, worker)
                    diagnostics?.ready(i)
                    if (relayPorts.containsKey(i)) {
                        startRelay(i, relayConfig!!, relayPorts.getValue(i), relayUnderlayPorts.getValue(i)); supportsUdp = true
                    }
                }
                if (protocol == "warp") {
                    val trace = try {
                        MixEgressProbe.fetch(prefixPorts[i]).also { MixEgressProbe.requireWarpOn(it.warp, it.ip) }
                    } catch (error: Throwable) {
                        val detail = error.message ?: "Remote WARP egress could not be verified"
                        diagnostics?.failed(i, detail)
                        throw IllegalStateException("Stage ${i + 1}: $detail", error)
                    }
                    diagnostics?.verifiedWarp(i, trace.ip)
                }
            } catch (error: Throwable) {
                diagnostics?.failed(i)
                throw error
            }
        }
        ensureLive(current)
        diagnostics?.setPhase("Testing complete chain")
        showNotification("Testing the complete chain")
        val dnsPrefixPort = (0 until hops.length()).lastOrNull {
            hops.getJSONObject(it).optString("protocol") == "direct_dns"
        }?.let { prefixPorts[it] } ?: prefixPorts.last()
        val probe = MixRouting.vpn(plan, prefixPorts.last(), supportsUdp, probe = true,
            dnsExitPort = dnsPrefixPort)
        val hasWarp = (0 until hops.length()).any { hops.getJSONObject(it).getString("protocol") == "warp" }
        val delay = if (hasWarp) {
            val cloudflare = runCatching {
                Libv2ray.measureOutboundDelay(probe.toString(), MixEgressProbe.TRACE_URL)
            }.getOrDefault(-1L)
            if (cloudflare >= 0) cloudflare else runCatching {
                Libv2ray.measureOutboundDelay(probe.toString(), "https://www.gstatic.com/generate_204")
            }.getOrDefault(-1L)
        } else {
            Libv2ray.measureOutboundDelay(probe.toString(), "https://www.gstatic.com/generate_204")
        }
        require(delay >= 0) { "The complete chain failed its connection test; no system tunnel was started" }
        ensureLive(current)
        diagnostics?.setPhase("Starting system tunnel")
        val builder = Builder().setSession("4win VPN - Mix").setMtu(1280)
            .addAddress("172.19.0.1", 30).addRoute("0.0.0.0", 0)
            .addAddress("fdfe:dcba:9876::1", 126).addRoute("::", 0)
            .addDnsServer(plan.optString("dns", "1.1.1.1"))
        // Only this app's control sockets are excluded; all OTHER apps are
        // tunneled. Standalone split-tunnel preferences are never modified.
        builder.addDisallowedApplication(packageName)
        if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)
        tun = builder.establish() ?: error("Android refused the Mix VPN interface")
        ensureLive(current)
        finalCore = newController(current)
        finalCore!!.startLoop(MixRouting.vpn(plan, prefixPorts.last(), supportsUdp,
            dnsExitPort = dnsPrefixPort).toString(), tun!!.fd)
        ensureLive(current)
        statsCore = finalCore
        uplink = 0L
        downlink = 0L
        // Keep the exact exit prefix, DNS boundary and UDP policy from startup.
        // A tap reuses live workers; it never rebuilds/reorders the strategy.
        delayProbe = DelayProbe(current, probe.toString())
        isRunning = true
        runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, true) }
        isReconnecting = false
        showNotification("${hops.length()} stages active${if (supportsUdp) "" else " · TCP-only"}")
        diagnostics?.setPhase("Connected — complete-chain test passed")
        current.connected.complete(delay)
    }

    private fun startRelay(stage: Int, config: MixUdpRelay.Config, port: Int, underlayPort: Int) {
        val relay = MixUdpRelay(config, port, underlayPort)
        udpRelays[stage] = relay // Register before a blocking TLS/auth handshake, for cleanup on failure.
        relay.start()
    }

    private fun awaitReady(current: Request, worker: Worker): Boolean {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(130)
        while (System.nanoTime() < deadline) {
            ensureLive(current)
            try { return worker.ready.get(200, TimeUnit.MILLISECONDS) }
            catch (_: TimeoutException) { }
        }
        error("Stage ${worker.hop + 1} did not become ready")
    }

    private fun newController(current: Request): CoreController = Libv2ray.newCoreController(object : CoreCallbackHandler {
        override fun startup(): Long = 0L
        override fun onEmitStatus(level: Long, msg: String?): Long = 0L
        override fun shutdown(): Long {
            if (!current.cancelled.get()) fail(current, IllegalStateException("Mix routing core stopped"))
            return 0L
        }
    })

    private fun ensureLive(current: Request) {
        check(!current.cancelled.get() && active === current) { "Mix connection cancelled" }
    }

    private fun fail(current: Request, error: Throwable) {
        current.connected.completeExceptionally(error)
        requestStop(current)
    }

    private fun requestReconnect(current: Request) {
        if (request !== current || destroyed.get() || isReconnecting ||
            !current.cancelled.compareAndSet(false, true)) return
        isReconnecting = true
        reconnectFrom = current
        if (!executor.isShutdown) executor.execute { cleanup(current) }
    }

    private fun requestStop(current: Request) {
        reconnectFrom = null
        isReconnecting = false
        current.cancelled.set(true)
        current.connected.completeExceptionally(IllegalStateException("Mix connection cancelled"))
        if (!executor.isShutdown) executor.execute { cleanup(current) }
    }

    private fun cleanup(current: Request) {
        if (request !== current) return
        if (!cleaned.compareAndSet(false, true)) return
        current.cancelled.set(true)
        runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, false) }
        isRunning = false
        delayProbe = null
        statsCore = null
        runCatching { finalCore?.stopLoop() }
        finalCore = null
        runCatching { tun?.close() }
        tun = null
        // Resolver cores depend on prefixes, so stop them in reverse stage order
        // before stopping workers and the router that owns those prefixes.
        resolverCores.values.toList().asReversed().forEach { resolver ->
            runCatching { resolver.stopLoop() }
        }
        resolverCores.clear()
        udpRelays.values.toList().asReversed().forEach { runCatching { it.close() } }
        udpRelays.clear()
        socks4Proxies.values.toList().asReversed().forEach { runCatching { it.close() } }
        socks4Proxies.clear()
        // Tear down from the exit towards the physical entry, keeping every
        // previous prefix available while its dependent engine is stopped.
        workers.values.filter { it.started }.sortedByDescending { it.hop }.forEach { worker ->
            val stop = Intent(this, MixWorkerService.CLASSES[worker.slot])
                .setAction(MixWorkerService.ACTION_STOP).putExtra("sessionId", current.id)
                .putExtra("hopId", worker.hop.toString())
            runCatching { startService(stop) }
            runCatching { worker.stopped.get(8, TimeUnit.SECONDS) }
            stopService(Intent(this, MixWorkerService.CLASSES[worker.slot]))
            if (reconnectFrom === current && !worker.stopped.isDone) {
                // stopService is asynchronous. Never reuse an occupied native worker.
                val stopped = runCatching { worker.stopped.get(8, TimeUnit.SECONDS) }.isSuccess
                if (!stopped) {
                    reconnectFrom = null
                    isReconnecting = false
                }
            }
        }
        workers.clear()
        runCatching { router?.stopLoop() }
        router = null
        main.post { finishCleanup(current) }
    }

    private fun finishCleanup(current: Request) {
        if (request !== current) return
        if (reconnectFrom === current && !destroyed.get() && active === current) {
            // Deep-copy the actual running plan: strategy, ordered blocks and all configs.
            val next = Request(UUID.randomUUID().toString(), JSONObject(current.plan.toString()),
                if (!current.connected.isDone) current.connected else CompletableFuture())
            diagnostics = newDiagnostics(next.plan)
            reconnectFrom = null
            current.stopped.complete(Unit)
            active = next
            request = next
            cleaned.set(false)
            showNotification("Reconnecting the complete chain")
            executor.execute {
                try { ensureLive(next); startChain(next) }
                catch (error: Throwable) {
                    diagnostics?.globalFailure("Mix connection failed")
                    if (reconnectFrom !== next) next.connected.completeExceptionally(error)
                    next.cancelled.set(true)
                    isReconnecting = false
                    cleanup(next)
                }
            }
            return
        }
        if (receiverRegistered) {
            runCatching { unregisterReceiver(statusReceiver) }
            receiverRegistered = false
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        current.connected.completeExceptionally(IllegalStateException("Mix connection stopped"))
        if (destroyed.get()) current.stopped.complete(Unit)
    }

    private fun showNotification(text: String) {
        val session = request?.id ?: active?.id ?: ""
        val stop = PendingIntent.getService(this, 0,
            notificationIntent(this, ACTION_STOP, session),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val reconnect = PendingIntent.getService(this, 1,
            notificationIntent(this, ACTION_RECONNECT, session),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        startForeground(NOTIFICATION, NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher).setContentTitle(VpnNotificationLabels.MIX_PROTOCOL)
            .setContentText(VpnNotificationLabels.localized(this, text))
            .setOngoing(true).addAction(android.R.drawable.ic_menu_close_clear_cancel, VpnNotificationLabels.localized(this, "Disconnect"), stop)
            .addAction(android.R.drawable.ic_popup_sync, VpnNotificationLabels.localized(this, "Reconnect"), reconnect).build())
    }

    override fun onRevoke() { request?.let { requestStop(it) }; super.onRevoke() }
    override fun onDestroy() {
        destroyed.set(true)
        reconnectFrom = null
        isReconnecting = false
        request?.let { current ->
            if (cleaned.get()) current.stopped.complete(Unit) else requestStop(current)
        }
        if (instance === this) instance = null
        executor.shutdown()
        super.onDestroy()
    }
}

/** Unique PendingIntent identity prevents an old notification from controlling a new chain. */
internal fun notificationIntent(context: Context, action: String, session: String): Intent =
    Intent(context, MixCoordinatorService::class.java).setAction(action)
        .setData(Uri.parse("forwin-mix://notification/$session/$action"))
        .putExtra("sessionId", session)
