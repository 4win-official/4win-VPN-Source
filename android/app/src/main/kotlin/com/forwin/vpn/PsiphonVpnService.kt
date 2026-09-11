package com.forwin.vpn

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
import android.util.Log
import androidx.core.app.NotificationCompat
import ca.psiphon.PsiphonTunnel
import gi.Seq
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Semaphore

/**
 * Psiphon VPN service. Runs in the dedicated `:psiphon` process (see
 * AndroidManifest). Its gomobile/Go runtime is the RELOCATED Psiphon one
 * (`gi.Seq` + `libpsiphon-gojni.so`, produced by the Gradle
 * `relocatePsiphonAar` task) — it never shares a process with Xray's Go
 * runtime (`go.Seq` + `libgojni.so`, main + `:psiphonbridge` processes),
 * because loading both Go runtimes in one process natively crashes the app
 * (their native symbols collide process-wide).
 *
 * Because of the process split, state is published to the main process via
 * package-scoped [ACTION_STATUS] broadcasts (state changes + 2s heartbeat),
 * consumed by [PsiphonStatusStore]. Never rely on the companion statics below
 * from another process — they are only valid inside `:psiphon`.
 */
class PsiphonVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var psiphonTunnel: PsiphonTunnel? = null
    @Volatile private var tunnelRunning = false
    @Volatile private var killSwitchActive = false
    private var currentRegion = ""
    private var psiphonSocksPort = 0
    private var lastStatusText = ""
    // Exit regions the Psiphon core last reported as available (from
    // onAvailableEgressRegions). Published in every status broadcast so the
    // main process can show the live server count in the Psiphon settings.
    @Volatile private var egressRegions: List<String> = emptyList()
    private val lifecycleLock = Semaphore(1)
    private var bridgeStatusReceiver: BroadcastReceiver? = null
    // True once Psiphon's own tunnel-core reports onConnected(). The public
    // isConnected() below additionally requires bridgeConfirmed, so "connected"
    // means the device traffic is ACTUALLY being routed, not just that
    // Psiphon's internal proxy is up.
    @Volatile private var psiphonCoreConnected = false
    @Volatile private var bridgeConfirmed = false

    @Volatile private var heartbeatRunning = false
    private var heartbeatThread: Thread? = null

    // Log lines buffered since the last status broadcast (also mirrored to
    // logcat immediately). Drained into every ACTION_STATUS broadcast.
    private val pendingLogs = ArrayList<String>()
    private val logTime = SimpleDateFormat("HH:mm:ss", Locale.US)

    companion object {
        const val ACTION_CONNECT = "com.forwin.vpn.PSIPHON_CONNECT"
        const val ACTION_DISCONNECT = "com.forwin.vpn.PSIPHON_DISCONNECT"
        const val ACTION_RECONNECT = "com.forwin.vpn.PSIPHON_RECONNECT"
        const val EXTRA_EGRESS_REGION = "egress_region"

        /** Cross-process state snapshot broadcast (consumed via PsiphonStatusStore). */
        const val ACTION_STATUS = "com.forwin.vpn.PSIPHON_STATUS"
        const val EXTRA_RUNNING = "running"
        const val EXTRA_CONNECTED = "connected"
        const val EXTRA_KILLSWITCH = "killswitch"
        const val EXTRA_UPLINK = "uplink"
        const val EXTRA_DOWNLINK = "downlink"
        const val EXTRA_STATUS_TEXT = "status_text"
        const val EXTRA_REGION = "region"
        const val EXTRA_LOG_LINES = "log_lines"
        /** Exit regions currently reported available by the Psiphon core. */
        const val EXTRA_EGRESS_REGIONS = "egress_regions"

        /** Fire-and-forget native log broadcast (also from the bridge service). */
        const val ACTION_LOG = "com.forwin.vpn.PSIPHON_LOG"

        private const val TAG = "PsiphonVpnService"
        private const val NOTIFICATION_ID = 3
        private const val CHANNEL_ID = "PsiphonVpnChannel"
        private const val VPN_MTU = 1500
        private const val PRIVATE_VLAN4 = "10.8.0.1"
        private const val PSIPHON_NATIVE_LIBRARY = "psiphon-gojni"
        private const val PSIPHON_SOCKS_PORT = 1080
        private const val PSIPHON_HTTP_PORT = 8080
        private const val HEARTBEAT_MS = 2000L
        private const val MAX_PENDING_LOGS = 60

        @Volatile private var isServiceRunning = false
        // "Connected" as observed from OUTSIDE this service (polled by Flutter
        // via PsiphonStatusStore) means the device TUN bridge is confirmed
        // active, NOT merely that Psiphon's own tunnel-core callback fired. See
        // psiphonCoreConnected / bridgeConfirmed above.
        @Volatile private var isTunnelConnected = false
        @Volatile private var totalUplink = 0L
        @Volatile private var totalDownlink = 0L

        // NOTE: only valid inside the :psiphon process. Other processes must
        // use PsiphonStatusStore (kept for backward compatibility).
        @JvmStatic
        fun isRunning() = isServiceRunning
        @JvmStatic
        fun isConnected() = isTunnelConnected
        @JvmStatic
        fun queryTrafficStats() = longArrayOf(totalUplink, totalDownlink)
    }

    /** Recomputes the externally-visible isTunnelConnected flag. */
    private fun updateConnectedState() {
        isTunnelConnected = psiphonCoreConnected && bridgeConfirmed
    }

    // ------------------------------------------------------------------ logging

    /** Timestamped log: always to logcat, plus buffered for the Flutter log viewer. */
    private fun plog(msg: String) {
        val line = try {
            "[${logTime.format(Date())}] $msg"
        } catch (_: Throwable) {
            msg
        }
        try {
            Log.d(TAG, msg)
        } catch (_: Throwable) {}
        synchronized(pendingLogs) {
            if (pendingLogs.size >= MAX_PENDING_LOGS) pendingLogs.removeAt(0)
            pendingLogs.add(line)
        }
    }

    // ------------------------------------------------------- cross-process sync

    /** Publishes the current snapshot + buffered logs to the main process. */
    private fun sendStatus() {
        try {
            val lines: ArrayList<String> = synchronized(pendingLogs) {
                val copy = ArrayList(pendingLogs)
                pendingLogs.clear()
                copy
            }
            val intent = Intent(ACTION_STATUS).apply {
                setPackage(packageName)
                putExtra(EXTRA_RUNNING, tunnelRunning || killSwitchActive)
                putExtra(EXTRA_CONNECTED, isTunnelConnected)
                putExtra(EXTRA_KILLSWITCH, killSwitchActive)
                putExtra(EXTRA_UPLINK, totalUplink)
                putExtra(EXTRA_DOWNLINK, totalDownlink)
                putExtra(EXTRA_STATUS_TEXT, lastStatusText)
                putExtra(EXTRA_REGION, currentRegion)
                putStringArrayListExtra(EXTRA_EGRESS_REGIONS, ArrayList(egressRegions))
                putStringArrayListExtra(EXTRA_LOG_LINES, lines)
            }
            sendBroadcast(intent)
        } catch (t: Throwable) {
            try {
                Log.w(TAG, "sendStatus failed: ${t.message}")
            } catch (_: Throwable) {}
        }
    }

    private fun startHeartbeat() {
        if (heartbeatRunning) return
        heartbeatRunning = true
        val t = Thread({
            while (heartbeatRunning) {
                try {
                    sendStatus()
                } catch (_: Throwable) {}
                try {
                    Thread.sleep(HEARTBEAT_MS)
                } catch (_: InterruptedException) {
                    break
                } catch (_: Throwable) {
                    break
                }
            }
        }, "psiphon-heartbeat")
        t.isDaemon = true
        heartbeatThread = t
        try {
            t.start()
        } catch (_: Throwable) {
            heartbeatRunning = false
        }
    }

    private fun stopHeartbeat() {
        heartbeatRunning = false
        try {
            heartbeatThread?.interrupt()
        } catch (_: Throwable) {}
        heartbeatThread = null
    }

    // --------------------------------------------------------------- lifecycle

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        try {
            // gi.Seq = the build-time-relocated Psiphon bridge (go → gi).
            // Its static initializer loads libpsiphon-gojni.so only, so this
            // process never sees Xray's libgojni.so. The explicit load below
            // is a no-op safeguard (System.loadLibrary is idempotent).
            Seq.setContext(applicationContext)
            System.loadLibrary(PSIPHON_NATIVE_LIBRARY)
            Log.d(TAG, "Psiphon native runtime loaded and gomobile context initialized")
        } catch (t: Throwable) {
            Log.e(TAG, "Psiphon native runtime initialization failed", t)
        }

        // Listen for the :psiphonbridge process reporting whether the actual
        // TUN -> SOCKS packet bridge succeeded or failed. Without this,
        // "connected" would be decided purely by Psiphon's own onConnected()
        // callback, independent of whether device traffic is really flowing.
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                try {
                    val success = intent?.getBooleanExtra(
                        PsiphonTunBridgeService.EXTRA_BRIDGE_SUCCESS, false
                    ) ?: false
                    plog("Bridge status report: success=$success")
                    Thread { onBridgeStatus(success) }.start()
                } catch (t: Throwable) {
                    try {
                        Log.w(TAG, "bridge status handling failed: ${t.message}")
                    } catch (_: Throwable) {}
                }
            }
        }
        bridgeStatusReceiver = receiver
        val filter = IntentFilter(PsiphonTunBridgeService.ACTION_BRIDGE_STATUS)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(receiver, filter)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to register bridge status receiver", t)
        }
    }

    override fun onDestroy() {
        try {
            stopHeartbeat()
        } catch (_: Throwable) {}
        try {
            bridgeStatusReceiver?.let { unregisterReceiver(it) }
        } catch (_: Throwable) {}
        bridgeStatusReceiver = null
        super.onDestroy()
    }

    /** Another VPN took over (or permission was revoked): tear everything down. */
    override fun onRevoke() {
        try {
            plog("VPN revoked by system — stopping")
        } catch (_: Throwable) {}
        try {
            Thread { stopPsiphon(fullStop = true) }.start()
        } catch (_: Throwable) {}
        try {
            super.onRevoke()
        } catch (_: Throwable) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                currentRegion = intent.getStringExtra(EXTRA_EGRESS_REGION) ?: ""
                try {
                    showNotification("Connecting to Psiphon...", true)
                } catch (_: Throwable) {}
                Thread { startPsiphon(currentRegion) }.start()
            }
            ACTION_DISCONNECT -> Thread { stopPsiphon(fullStop = true) }.start()
            ACTION_RECONNECT -> Thread {
                stopPsiphon(fullStop = false)
                try {
                    Thread.sleep(500)
                } catch (_: InterruptedException) {
                    return@Thread
                }
                try {
                    showNotification("Connecting to Psiphon...", true)
                } catch (_: Throwable) {}
                startPsiphon(currentRegion)
            }.start()
        }
        return START_STICKY
    }

    private fun startPsiphon(region: String) {
        var locked = false
        try {
            lifecycleLock.acquire()
            locked = true
            if (tunnelRunning) {
                plog("start requested while already running — ignoring")
                sendStatus()
                return
            }

            // A previous kill-switch blackhole may still hold a stale TUN.
            // Always re-establish a fresh interface for a new attempt.
            if (killSwitchActive) {
                plog("clearing previous kill-switch blackhole for new attempt")
                try {
                    vpnInterface?.close()
                } catch (_: Throwable) {}
                vpnInterface = null
                killSwitchActive = false
            }

            isServiceRunning = true
            psiphonCoreConnected = false
            bridgeConfirmed = false
            updateConnectedState()
            psiphonSocksPort = 0
            egressRegions = emptyList()
            totalUplink = 0
            totalDownlink = 0
            lastStatusText = "Connecting to Psiphon..."
            plog("starting (region=${if (region.isBlank()) "auto" else region})")
            sendStatus()
            startHeartbeat()

            val builder = Builder()
                .setSession("4win VPN - Psiphon")
                .setMtu(VPN_MTU)
                .addAddress(PRIVATE_VLAN4, 32)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("8.8.8.8")
                .addDnsServer("1.1.1.1")

            try {
                builder.addAddress("fc00::1", 128)
                builder.addRoute("::", 0)
            } catch (_: Throwable) {}

            // Split tunneling (same semantics as Xray): in INCLUDE mode the
            // helper owns the allow-list, so our own package must NOT be
            // pre-added to the disallowed list (the two lists are mutually
            // exclusive). Otherwise keep our app outside the tunnel to
            // prevent routing loops.
            val splitMode = try {
                SplitTunnel.mode(applicationContext)
            } catch (_: Throwable) {
                "off"
            }
            if (splitMode != "include") {
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (_: Throwable) {}
            }
            SplitTunnel.apply(applicationContext, builder, packageName)
            if (splitMode != "off") plog("split tunnel mode: $splitMode")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

            val tun = builder.establish()
                ?: throw IllegalStateException("VpnService.Builder.establish() returned null")
            vpnInterface = tun
            plog("Android TUN established fd=${tun.fd}")

            initializePsiphonTunnel(region)
            tunnelRunning = true
            lastStatusText = "Psiphon is starting..."
            showNotification(lastStatusText, true)
            sendStatus()
        } catch (t: Throwable) {
            plog("startup failed: ${t.message ?: "unknown error"}")
            Log.e(TAG, "Psiphon startup failed", t)
            tunnelRunning = false
            psiphonCoreConnected = false
            bridgeConfirmed = false
            updateConnectedState()
            try {
                stopBridgeProcess()
            } catch (_: Throwable) {}
            try {
                psiphonTunnel?.stop()
            } catch (_: Throwable) {}
            psiphonTunnel = null

            if (KillSwitch.isEnabled(applicationContext) && vpnInterface != null) {
                // Kill switch: keep the TUN up as a blackhole so no traffic
                // can leak, and stay alive for the next reconnect attempt.
                enterBlackhole("startup failed: ${t.message ?: "unknown error"}")
            } else {
                isServiceRunning = false
                try {
                    vpnInterface?.close()
                } catch (_: Throwable) {}
                vpnInterface = null
                lastStatusText = "Psiphon failed: ${t.message ?: "unknown error"}"
                try {
                    showNotification(lastStatusText, false)
                } catch (_: Throwable) {}
                sendStatus()
                stopHeartbeat()
                try {
                    stopSelf()
                } catch (_: Throwable) {}
            }
        } finally {
            if (locked) lifecycleLock.release()
        }
    }

    /**
     * @param fullStop true for user disconnect / revoke (tears down the TUN and
     * stops the service), false for an internal reconnect (keeps the foreground
     * service alive and just restarts the tunnel).
     */
    private fun stopPsiphon(fullStop: Boolean) {
        var locked = false
        try {
            lifecycleLock.acquire()
            locked = true
            tunnelRunning = false
            killSwitchActive = false
            psiphonCoreConnected = false
            bridgeConfirmed = false
            updateConnectedState()
            try {
                stopBridgeProcess()
            } catch (_: Throwable) {}
            try {
                psiphonTunnel?.stop()
            } catch (t: Throwable) {
                Log.w(TAG, "Psiphon stop: ${t.message}")
            }
            psiphonTunnel = null
            psiphonSocksPort = 0
            egressRegions = emptyList()
            try {
                vpnInterface?.close()
            } catch (_: Throwable) {}
            vpnInterface = null

            if (fullStop) {
                isServiceRunning = false
                lastStatusText = "Disconnected"
                plog("stopped")
                sendStatus()
                stopHeartbeat()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
                else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                try {
                    stopSelf()
                } catch (_: Throwable) {}
            } else {
                plog("tunnel stopped for reconnect")
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Psiphon stop failed", t)
        } finally {
            if (locked) lifecycleLock.release()
        }
    }

    /** Handles the :psiphonbridge TUN->SOCKS status report (background thread). */
    private fun onBridgeStatus(success: Boolean) {
        var locked = false
        try {
            lifecycleLock.acquire()
            locked = true
            if (!tunnelRunning) return // stale report after stop; ignore
            bridgeConfirmed = success
            updateConnectedState()
            if (success) {
                lastStatusText = if (currentRegion.isBlank()) "Connected to Psiphon"
                else "Connected to $currentRegion"
                plog("device traffic bridge confirmed — connected")
                try {
                    showNotification(lastStatusText, true)
                } catch (_: Throwable) {}
            } else {
                // Bridge failed to start: with kill switch on, hold the TUN as
                // a blackhole; otherwise tear down so traffic flows normally.
                if (KillSwitch.isEnabled(applicationContext)) {
                    enterBlackhole("traffic bridge failed to start")
                } else {
                    lastStatusText = "Psiphon bridge failed to start"
                    plog(lastStatusText)
                    sendStatus()
                    // Release the lock before the full stop to avoid
                    // self-deadlock (stopPsiphon acquires the same semaphore).
                    lifecycleLock.release()
                    locked = false
                    stopPsiphon(fullStop = true)
                    return
                }
            }
            sendStatus()
        } catch (t: Throwable) {
            Log.e(TAG, "bridge status handling failed", t)
        } finally {
            if (locked) lifecycleLock.release()
        }
    }

    /**
     * Kill-switch blackhole: stops the core + bridge but KEEPS the VPN
     * interface established with nothing forwarding behind it, so all routed
     * traffic is dropped instead of leaking. Caller must hold [lifecycleLock].
     */
    private fun enterBlackhole(reason: String) {
        tunnelRunning = false
        killSwitchActive = true
        psiphonCoreConnected = false
        bridgeConfirmed = false
        updateConnectedState()
        try {
            stopBridgeProcess()
        } catch (_: Throwable) {}
        try {
            psiphonTunnel?.stop()
        } catch (_: Throwable) {}
        psiphonTunnel = null
        psiphonSocksPort = 0
        lastStatusText = "Kill switch active — traffic blocked"
        plog("KILL SWITCH engaged ($reason) — holding TUN blackhole")
        try {
            showNotification(lastStatusText, true)
        } catch (_: Throwable) {}
        sendStatus()
        // Keep the heartbeat alive so the main process knows we are holding.
        startHeartbeat()
    }

    private fun initializePsiphonTunnel(region: String) {
        val hostService = object : PsiphonTunnel.HostService {
            override fun getContext(): Context = applicationContext
            override fun getPsiphonConfig(): String = JSONObject()
                .put("EgressRegion", region)
                .put("LocalSocksProxyPort", PSIPHON_SOCKS_PORT)
                .put("LocalHttpProxyPort", PSIPHON_HTTP_PORT)
                .put("EmitBytesTransferred", true)
                .put("EstablishTunnelTimeoutSeconds", 0)
                .toString()
            override fun loadLibrary(library: String) {
                // Psiphon's Java layer asks the host to load its native
                // runtime by the original name "gojni"; map it to the
                // renamed, symbol-patched libpsiphon-gojni.so.
                if (library == "gojni") System.loadLibrary(PSIPHON_NATIVE_LIBRARY)
                else System.loadLibrary(library)
            }
            override fun bindToDevice(fileDescriptor: Long) {
                if (!protect(fileDescriptor.toInt())) throw IllegalStateException("VpnService.protect failed for fd=$fileDescriptor")
            }
            // NOTE: all callbacks below are invoked from Psiphon/Go threads —
            // each is individually guarded so a failure can never escape onto
            // a foreign thread and kill the process.
            override fun onConnecting() {
                runGuarded("onConnecting") {
                    plog("tunnel connecting")
                    lastStatusText = "Connecting to Psiphon..."
                    showNotification(lastStatusText, true)
                    sendStatus()
                }
            }
            override fun onConnected() {
                runGuarded("onConnected") {
                    // NOTE: this only means Psiphon's own local proxy is up. The
                    // externally-visible connected flag stays false until the
                    // separate :psiphonbridge process confirms the device-wide
                    // TUN bridge (see updateConnectedState()/bridgeConfirmed).
                    plog("tunnel core connected")
                    psiphonCoreConnected = true
                    updateConnectedState()
                    val port = psiphonSocksPort
                    if (port > 0) startTunBridge(port)
                    else plog("connected before SOCKS port notification — waiting for port")
                    lastStatusText = "Psiphon core up — starting traffic bridge..."
                    showNotification(lastStatusText, true)
                    sendStatus()
                }
            }
            override fun onListeningSocksProxyPort(port: Int) {
                runGuarded("onListeningSocksProxyPort") {
                    psiphonSocksPort = port
                    plog("SOCKS5 listening on 127.0.0.1:$port")
                    startTunBridge(port)
                }
            }
            override fun onListeningHttpProxyPort(port: Int) {
                runGuarded("onListeningHttpProxyPort") {
                    plog("HTTP proxy listening on $port")
                }
            }
            override fun onBytesTransferred(sent: Long, received: Long) {
                try {
                    totalUplink += sent
                    totalDownlink += received
                } catch (_: Throwable) {}
            }
            override fun onAvailableEgressRegions(regions: MutableList<String>?) {
                runGuarded("onAvailableEgressRegions") {
                    egressRegions = regions?.toList() ?: emptyList()
                    plog("available regions (${egressRegions.size}): $regions")
                    // Push the fresh server list to the main process so the
                    // Psiphon settings screen can show the live count.
                    sendStatus()
                }
            }
            override fun onSplitTunnelRegions(regions: MutableList<String>?) {
                runGuarded("onSplitTunnelRegions") {
                    plog("split regions: $regions")
                }
            }
            override fun onUpstreamProxyError(message: String?) {
                runGuarded("onUpstreamProxyError") {
                    plog("upstream proxy error: $message")
                }
            }
            override fun onStartedWaitingForNetworkConnectivity() {
                runGuarded("onStartedWaitingForNetworkConnectivity") {
                    plog("waiting for network connectivity")
                    lastStatusText = "Waiting for network..."
                    try {
                        showNotification(lastStatusText, true)
                    } catch (_: Throwable) {}
                    sendStatus()
                }
            }
            override fun onStoppedWaitingForNetworkConnectivity() {
                runGuarded("onStoppedWaitingForNetworkConnectivity") {
                    plog("network connectivity restored")
                    sendStatus()
                }
            }
            override fun onDiagnosticMessage(message: String?) {
                runGuarded("onDiagnosticMessage") {
                    if (!message.isNullOrBlank()) plog("core: $message")
                }
            }
        }

        val tunnel = PsiphonTunnel.newPsiphonTunnel(hostService)
        tunnel.setVpnMode(true)
        psiphonTunnel = tunnel
        plog("starting tunnel core")
        tunnel.startTunneling("")
    }

    /** Runs [block], converting any throwable into a log line (never rethrows). */
    private fun runGuarded(tag: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            try {
                plog("$tag failed: ${t.message}")
            } catch (_: Throwable) {}
            try {
                Log.e(TAG, "callback $tag failed", t)
            } catch (_: Throwable) {}
        }
    }

    private fun startTunBridge(port: Int) {
        val tun = vpnInterface ?: run {
            plog("cannot start bridge: TUN is closed")
            return
        }
        if (port !in 1..65535) {
            plog("cannot start bridge: invalid SOCKS port $port")
            return
        }
        try {
            val bridgeIntent = Intent(this, PsiphonTunBridgeService::class.java).apply {
                action = PsiphonTunBridgeService.ACTION_START
                putExtra(PsiphonTunBridgeService.EXTRA_TUN_FD, ParcelFileDescriptor.dup(tun.fileDescriptor))
                putExtra(PsiphonTunBridgeService.EXTRA_SOCKS_PORT, port)
            }
            PsiphonTunBridgeService.start(this, bridgeIntent)
            plog("requested isolated traffic bridge on SOCKS port $port")
        } catch (t: Throwable) {
            plog("failed to launch traffic bridge: ${t.message}")
            Log.e(TAG, "Failed to launch isolated Psiphon bridge", t)
            bridgeConfirmed = false
            updateConnectedState()
            sendStatus()
        }
    }

    private fun stopBridgeProcess() {
        try {
            PsiphonTunBridgeService.stop(this)
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to stop isolated bridge: ${t.message}")
        }
    }

    private fun showNotification(status: String, foreground: Boolean) {
        val launch = try {
            packageManager.getLaunchIntentForPackage(packageName)
        } catch (_: Throwable) {
            null
        } ?: Intent(Intent.ACTION_MAIN)
            .setPackage(packageName)
            .addCategory(Intent.CATEGORY_LAUNCHER)
        val pending = PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE)
        val disconnect = Intent(this, PsiphonVpnService::class.java).apply { action = ACTION_DISCONNECT }
        val disconnectPending = PendingIntent.getService(this, 0, disconnect, PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🔐 Psiphon VPN")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", disconnectPending)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(foreground)
            .build()
        if (foreground) startForeground(NOTIFICATION_ID, notification)
        else getSystemService(Context.NOTIFICATION_SERVICE)?.let { (it as NotificationManager).notify(NOTIFICATION_ID, notification) }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Psiphon VPN Service", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Psiphon VPN tunnel status"
            channel.setShowBadge(false)
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }
}
