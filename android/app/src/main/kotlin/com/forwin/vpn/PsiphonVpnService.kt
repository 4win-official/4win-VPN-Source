package com.forwin.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import ca.psiphon.PsiphonTunnel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Android host for the official Psiphon MobileLibrary. */
class PsiphonVpnService : VpnService(), PsiphonTunnel.HostService {
    companion object {
        const val ACTION_START = "com.forwin.vpn.psiphon.START"
        const val ACTION_STOP = "com.forwin.vpn.psiphon.STOP"
        const val ACTION_RECONNECT = "com.forwin.vpn.psiphon.RECONNECT"
        const val CHANNEL_ID = "4win_psiphon"
        const val NOTIFICATION_ID = 4107
        const val EXTRA_EGRESS_REGION = "egressRegion"

        @Volatile private var running = false
        @Volatile private var tunnel: PsiphonTunnel? = null
        @Volatile private var connected = false

        fun isRunning(): Boolean = running
        fun isConnected(): Boolean = connected
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val stopping = AtomicBoolean(false)
    private var tunInterface: ParcelFileDescriptor? = null
    private var selectedRegion: String = ""

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Starting Psiphon…"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopTunnel()
            ACTION_RECONNECT -> reconnectTunnel()
            else -> startTunnel(intent?.getStringExtra(EXTRA_EGRESS_REGION) ?: "")
        }
        return START_STICKY
    }

    private fun startTunnel(region: String) {
        if (running) return
        stopping.set(false)
        connected = false
        selectedRegion = region
        executor.execute {
            try {
                val builder = Builder()
                    .setSession("4win Psiphon")
                    .setMtu(1500)
                    .addAddress("10.2.0.2", 32)
                    .addRoute("0.0.0.0", 0)
                    .addRoute("::", 0)
                    .addDnsServer("1.1.1.1")
                    .addDnsServer("8.8.8.8")
                    .setBlocking(false)
                SplitTunnel.apply(applicationContext, builder, packageName)
                val vpn = builder.establish()

                if (vpn == null) {
                    updateNotification("VPN permission was not granted")
                    stopSelf()
                    return@execute
                }

                tunInterface?.close()
                tunInterface = vpn
                tunnel = PsiphonTunnel.newPsiphonTunnel(this)
                tunnel?.setVpnMode(true)
                tunnel?.startTunneling("")
                running = true
                updateNotification("Connecting to Psiphon…")
            } catch (t: Throwable) {
                running = false
                connected = false
                updateNotification("Psiphon connection failed")
                closeTun()
                stopSelf()
            }
        }
    }

    private fun reconnectTunnel() {
        executor.execute {
            try {
                connected = false
                tunnel?.reconnectPsiphon()
                updateNotification("Reconnecting to Psiphon…")
            } catch (_: Throwable) {
                updateNotification("Reconnect failed")
            }
        }
    }

    private fun stopTunnel() {
        if (!stopping.compareAndSet(false, true)) return
        executor.execute {
            try { tunnel?.stop() } catch (_: Throwable) {}
            finally {
                tunnel = null
                running = false
                connected = false
                closeTun()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                stopping.set(false)
            }
        }
    }

    private fun closeTun() {
        try { tunInterface?.close() } catch (_: Throwable) {}
        tunInterface = null
    }

    override fun onDestroy() {
        try { tunnel?.stop() } catch (_: Throwable) {}
        tunnel = null
        running = false
        connected = false
        closeTun()
        executor.shutdownNow()
        super.onDestroy()
    }

    override fun onBind(intent: Intent): IBinder? = super.onBind(intent)

    override fun getContext() = applicationContext

    override fun getPsiphonConfig(): String {
        val fd = tunInterface?.fd ?: -1
        return """
        {
          "ClientPlatform": "Android",
          "ClientVersion": "4win-1.4.7",
          "PropagationChannelId": "FFFFFFFFFFFFFFFF",
          "SponsorId": "FFFFFFFFFFFFFFFF",
          "EgressRegion": "$selectedRegion",
          "LocalSocksProxyPort": 0,
          "LocalHttpProxyPort": 0,
          "PacketTunnelTunFileDescriptor": $fd,
          "PacketTunnelTransparentDNSIPv4Address": "10.2.0.1",
          "UseIndistinguishableTLS": true,
          "RemoteServerListDownloadFilename": "remote_server_list",
          "RemoteServerListUrl": "https://s3.amazonaws.com//psiphon/web/mjr4-p23r-puwl/server_list_compressed",
          "RemoteServerListSignaturePublicKey": "MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVpJfzq/xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk/y1dfq47Pdymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmvDmHgphQQ7WfXIGbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lqz/lH+T61sGjSjQ3CHMuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiyzTxJADvSytVtcTjijhPEV6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+Y6fy7GstZALQXwEDN/qhQI9kWkHijT8ns+i1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZAGVtJI1OgeF5fsPpXu4kctOfuZlGjVZXQNW34aOzm8r8S8VezpJr8u/YtlwjjreZrGRmG8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgWQFTEPICV7GCvgVlPRxnofqKSjgTWI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2xalKxF5szhGm8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgWQFTEPICV7GCvgVlPRxnofqKSjgTWI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2xalKxF5szhGm8lccoc5MZr8kfE0uxMgsxz4er68iCID+rsCAQM="
        }
        """.trimIndent()
    }

    override fun bindToDevice(fileDescriptor: Long) {
        try { protect(fileDescriptor.toInt()) } catch (_: Throwable) {}
    }

    override fun onDiagnosticMessage(message: String) {
        when {
            message.contains("connected", true) -> updateNotification("Connected to Psiphon")
            message.contains("connecting", true) -> updateNotification("Connecting to Psiphon…")
            message.contains("stopping", true) -> updateNotification("Disconnecting…")
        }
    }

    override fun onConnected() {
        connected = true
        running = true
        updateNotification("Connected to Psiphon")
    }

    override fun onConnecting() {
        connected = false
        updateNotification("Connecting to Psiphon…")
    }

    override fun onExiting() {
        connected = false
        running = false
        updateNotification("Disconnected")
    }

    override fun onBytesTransferred(bytesUp: Long, bytesDown: Long) {}

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "4win Psiphon", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    private fun buildNotification(text: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(com.forwin.vpn.R.drawable.ic_stat_vpn)
            .setContentTitle("4win VPN")
            .setContentText(text)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOnlyAlertOnce(true)
            .build()

    private fun updateNotification(text: String) {
        try {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification(text))
        } catch (_: Throwable) {}
    }
}
