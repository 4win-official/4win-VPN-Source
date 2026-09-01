package com.forwin.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import ca.psiphon.PsiphonTunnel
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Psiphon foreground host.
 *
 * Psiphon runs in local-proxy mode. 4win's existing Xray VPN service remains
 * the sole owner of the Android TUN and routes the device through Psiphon's
 * localhost SOCKS endpoint. This prevents two VpnService instances from
 * competing for the same system tunnel.
 */
class PsiphonVpnService : Service() {
    companion object {
        const val ACTION_START = "com.forwin.vpn.PSIPHON_START"
        const val ACTION_STOP = "com.forwin.vpn.PSIPHON_STOP"
        const val ACTION_RECONNECT = "com.forwin.vpn.PSIPHON_RECONNECT"
        const val ACTION_STATE = "com.forwin.vpn.PSIPHON_STATE"
        const val EXTRA_STATE = "state"
        const val EXTRA_MESSAGE = "message"
        const val EXTRA_REGION = "region"
        const val EXTRA_PORT = "port"
        const val EXTRA_SENT = "sent"
        const val EXTRA_RECEIVED = "received"

        private const val CHANNEL_ID = "4win_psiphon_vpn"
        private const val NOTIFICATION_ID = 4107
        private const val TAG = "4winPsiphon"

        @Volatile var running = false
            private set
        @Volatile var socksPort = 0
            private set
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val stopping = AtomicBoolean(false)
    private var psiphon: PsiphonTunnel? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopTunnelAsync()
            ACTION_RECONNECT -> reconnectAsync()
            ACTION_START, null -> startTunnelAsync()
        }
        return START_STICKY
    }

    private fun startTunnelAsync() {
        if (running) return
        running = true
        stopping.set(false)
        startForeground(NOTIFICATION_ID, buildNotification("Connecting…"))
        sendState("connecting", null)

        executor.execute {
            try {
                val host = object : PsiphonTunnel.HostService {
                    override fun getContext() = this@PsiphonVpnService
                    override fun getPsiphonConfig(): String = defaultPsiphonConfig()
                    override fun bindToDevice(fileDescriptor: Long) {
                        // Local-proxy mode does not require an Android TUN fd.
                    }
                    override fun onConnecting() {
                        updateNotification("Connecting…")
                        sendState("connecting", null)
                    }
                    override fun onConnected() {
                        updateNotification("Connected")
                        sendState("connected", null)
                    }
                    override fun onListeningSocksProxyPort(port: Int) {
                        socksPort = port
                        sendPort(port)
                    }
                    override fun onConnectedServerRegion(region: String) = sendRegion(region)
                    override fun onClientRegion(region: String) = sendRegion(region)
                    override fun onBytesTransferred(sent: Long, received: Long) = sendBytes(sent, received)
                    override fun onStartedWaitingForNetworkConnectivity() {
                        updateNotification("Waiting for network…")
                        sendState("waiting_network", null)
                    }
                    override fun onStoppedWaitingForNetworkConnectivity() {
                        updateNotification("Connecting…")
                        sendState("connecting", null)
                    }
                    override fun onUpstreamProxyError(message: String) = sendState("error", message)
                    override fun onDiagnosticMessage(message: String) = Log.d(TAG, message)
                    override fun onExiting() = sendState("disconnected", null)
                }

                psiphon = PsiphonTunnel.newPsiphonTunnel(host).also {
                    it.setVpnMode(false)
                }
                psiphon!!.startTunneling("")
                Log.i(TAG, "Psiphon local proxy started")
            } catch (t: Throwable) {
                Log.e(TAG, "Psiphon start failed", t)
                sendState("error", t.message ?: "Psiphon failed to start")
                cleanup()
                running = false
                stopSelf()
            }
        }
    }

    private fun reconnectAsync() {
        executor.execute {
            try {
                psiphon?.reconnectPsiphon()
            } catch (t: Throwable) {
                sendState("error", t.message ?: "Reconnect failed")
            }
        }
    }

    private fun stopTunnelAsync() {
        if (stopping.getAndSet(true)) return
        executor.execute {
            try {
                sendState("disconnecting", null)
                psiphon?.stop()
            } catch (_: Throwable) {
            } finally {
                cleanup()
                running = false
                socksPort = 0
                sendState("disconnected", null)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                stopping.set(false)
            }
        }
    }

    private fun cleanup() {
        try { psiphon?.stop() } catch (_: Throwable) {}
        psiphon = null
        socksPort = 0
    }

    private fun sendState(state: String, message: String?) {
        val intent = Intent(ACTION_STATE).setPackage(packageName).putExtra(EXTRA_STATE, state)
        if (message != null) intent.putExtra(EXTRA_MESSAGE, message)
        sendBroadcast(intent)
    }

    private fun sendRegion(region: String) {
        sendBroadcast(Intent(ACTION_STATE).setPackage(packageName)
            .putExtra(EXTRA_STATE, "region").putExtra(EXTRA_REGION, region))
    }

    private fun sendPort(port: Int) {
        sendBroadcast(Intent(ACTION_STATE).setPackage(packageName)
            .putExtra(EXTRA_STATE, "proxy_ready").putExtra(EXTRA_PORT, port))
    }

    private fun sendBytes(sent: Long, received: Long) {
        sendBroadcast(Intent(ACTION_STATE).setPackage(packageName)
            .putExtra(EXTRA_STATE, "bytes").putExtra(EXTRA_SENT, sent).putExtra(EXTRA_RECEIVED, received))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "4win Psiphon", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    private fun buildNotification(text: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this, 4107, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_vpn)
            .setContentTitle("4win VPN • Psiphon")
            .setContentText(text)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(pending)
            .build()
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun defaultPsiphonConfig(): String = JSONObject().apply {
        put("LocalSocksProxyPort", 0)
        put("LocalHttpProxyPort", 0)
        put("EgressRegion", "")
        put("PropagationChannelId", "FFFFFFFFFFFFFFFF")
        put("RemoteServerListDownloadFilename", "remote_server_list")
        put("RemoteServerListSignaturePublicKey", "MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVpJfzq/xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk/y1dfq47Pdymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmvDmHgphQQ7WfXIGbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lqz/lH+T61sGjSjQ3CHMuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiyzTxJADvSytVtcTjijhPEV6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+6Yfy7GstZALQXwEDN/qhQI9kWkHijT8ns+i1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZAGVtJI1OgeF5fsPpXu4kctOfuZlGjVZXQNW34aOzm8r8S8eZVJitPlbhcPiR4gT/aSMz/wd8lZlzZYsje/Jr8u/YtlwjjreZrGRmG8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgWQFTEPICV7GCvgVlPRxnofqKSjgTWI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2xalKxF5szhGm8lccoc5MZr8kfE0uxMgsxz4er68iCID+rsCAQM=")
        put("RemoteServerListUrl", "https://s3.amazonaws.com//psiphon/web/mjr4-p23r-puwl/server_list_compressed")
        put("SponsorId", "FFFFFFFFFFFFFFFF")
        put("UseIndistinguishableTLS", true)
        put("EmitBytesTransferred", true)
        put("EstablishTunnelTimeoutSeconds", 0)
    }.toString()

    override fun onDestroy() {
        stopTunnelAsync()
        executor.shutdownNow()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
