package com.forwin.vpn.mix

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.forwin.vpn.R
import com.forwin.vpn.VpnNotificationLabels
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicBoolean

/** Each declared subclass has its own Android process and exactly one native engine. */
open class MixWorkerService : Service() {
    private var adapter: MixAdapter? = null
    private val generation = AtomicLong()
    private val stopping = AtomicBoolean(false)
    private val destroyed = AtomicBoolean(false)
    private val adapterClosed = AtomicBoolean(false)
    private val stoppedSent = AtomicBoolean(false)
    private val main = Handler(Looper.getMainLooper())
    private var sessionId = ""
    private var hopId = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(CHANNEL, VpnNotificationLabels.MIX_PROTOCOL, NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        startForeground(NOTIFICATION + (javaClass.simpleName.removePrefix("MixWorker").toIntOrNull() ?: 0), NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher).setContentTitle(VpnNotificationLabels.MIX_PROTOCOL)
            .setContentText("Preparing an isolated tunnel stage").setOngoing(true).build())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) { stopSelf(); return START_NOT_STICKY }
        val incomingSession = intent.getStringExtra("sessionId") ?: ""
        val incomingHop = intent.getStringExtra("hopId") ?: ""
        if (intent.action == ACTION_STOP) {
            // A late stop from an old strategy must not terminate a new session.
            if (incomingSession == sessionId && incomingHop == hopId) stopAdapter()
            else emit(incomingSession, incomingHop, "stopped")
            return START_NOT_STICKY
        }
        if (intent.action != ACTION_START || incomingSession.isBlank() || incomingHop.isBlank()) {
            stopSelf(); return START_NOT_STICKY
        }
        if (adapter != null || stopping.get()) {
            emit(incomingSession, incomingHop, "error", "Worker is still occupied by another stage")
            return START_NOT_STICKY
        }
        sessionId = incomingSession
        hopId = incomingHop
        val token = generation.incrementAndGet()
        try {
            val protocol = intent.getStringExtra("protocol") ?: error("Missing engine protocol")
            val implementation = when (protocol) {
                "warp" -> "com.forwin.vpn.mix.WarpMixAdapter"
                "psiphon" -> "com.forwin.vpn.mix.PsiphonMixAdapter"
                "sstp" -> "com.forwin.vpn.mix.SstpMixAdapter"
                "openvpn" -> "com.forwin.vpn.mix.openvpn.OpenVpnMixAdapter"
                else -> error("Unknown Mix engine: $protocol")
            }
            // Reflection keeps the worker itself free of all Go/JNI runtime initializers.
            val engine = Class.forName(implementation).getDeclaredConstructor().newInstance() as MixAdapter
            adapter = engine
            val config = JSONObject(intent.getStringExtra("config") ?: "{}")
            val port = intent.getIntExtra("listenPort", 0)
            require(port in 1..65535) { "Invalid worker SOCKS port" }
            val upstream = intent.getStringExtra("upstreamSocksUrl")
            engine.start(config, MixAdapterEnvironment(applicationContext, sessionId, hopId, port, upstream,
                onReady = { udp ->
                    if (generation.get() == token) emit(sessionId, hopId, "ready", udp = udp)
                },
                onFailure = { message ->
                    if (generation.get() == token) {
                        emit(sessionId, hopId, "error", message)
                        stopAdapter()
                    }
                }, workerSlot = intent.getIntExtra("workerSlot", 0),
                upstreamSupportsUdp = intent.getBooleanExtra("upstreamSupportsUdp", true)))
        } catch (error: Throwable) {
            emit(sessionId, hopId, "error", error.message ?: "Mix engine failed")
            stopAdapter()
        }
        return START_NOT_STICKY
    }

    @Synchronized private fun stopAdapter() {
        if (!stopping.compareAndSet(false, true)) return
        generation.incrementAndGet()
        val engine = adapter
        adapter = null
        Thread {
            try { engine?.stop() } catch (_: Throwable) { }
            finally {
                adapterClosed.set(true)
                main.post {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    emitStoppedIfClosed()
                }
            }
        }.start()
    }

    private fun emitStoppedIfClosed() {
        // A new strategy must not reuse this instance while it is still stopping.
        if (destroyed.get() && adapterClosed.get() && sessionId.isNotEmpty() &&
            stoppedSent.compareAndSet(false, true)) emit(sessionId, hopId, "stopped")
    }

    private fun emit(session: String, hop: String, state: String, error: String? = null, udp: Boolean = false) {
        sendBroadcast(Intent(ACTION_STATUS).setPackage(packageName)
            .putExtra("sessionId", session).putExtra("hopId", hop).putExtra("state", state)
            .putExtra("error", error).putExtra("supportsUdp", udp))
    }

    override fun onDestroy() {
        destroyed.set(true)
        stopAdapter()
        emitStoppedIfClosed()
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "com.forwin.vpn.mix.START_WORKER"
        const val ACTION_STOP = "com.forwin.vpn.mix.STOP_WORKER"
        const val ACTION_STATUS = "com.forwin.vpn.mix.WORKER_STATUS"
        private const val CHANNEL = "MixWorker"
        private const val NOTIFICATION = 40
        val CLASSES = arrayOf(
            MixWorker0::class.java,
            MixWorker1::class.java,
            MixWorker2::class.java,
            MixWorker3::class.java,
            MixWorker4::class.java,
            MixWorker5::class.java,
            MixWorker6::class.java,
            MixWorker7::class.java,
            MixWorker8::class.java,
            MixWorker9::class.java,
            MixWorker10::class.java,
            MixWorker11::class.java,
            MixWorker12::class.java,
            MixWorker13::class.java,
            MixWorker14::class.java,
            MixWorker15::class.java,
            MixWorker16::class.java,
            MixWorker17::class.java,
            MixWorker18::class.java,
            MixWorker19::class.java,
            MixWorker20::class.java,
            MixWorker21::class.java,
            MixWorker22::class.java,
            MixWorker23::class.java,
            MixWorker24::class.java,
            MixWorker25::class.java,
            MixWorker26::class.java,
            MixWorker27::class.java,
            MixWorker28::class.java,
            MixWorker29::class.java,
            MixWorker30::class.java,
            MixWorker31::class.java,
            MixWorker32::class.java,
            MixWorker33::class.java,
            MixWorker34::class.java,
            MixWorker35::class.java,
            MixWorker36::class.java,
            MixWorker37::class.java,
            MixWorker38::class.java,
            MixWorker39::class.java,
            MixWorker40::class.java,
            MixWorker41::class.java,
            MixWorker42::class.java,
            MixWorker43::class.java,
            MixWorker44::class.java,
            MixWorker45::class.java,
            MixWorker46::class.java,
            MixWorker47::class.java,
            MixWorker48::class.java,
            MixWorker49::class.java
        )
    }
}

class MixWorker0 : MixWorkerService()
class MixWorker1 : MixWorkerService()
class MixWorker2 : MixWorkerService()
class MixWorker3 : MixWorkerService()
class MixWorker4 : MixWorkerService()
class MixWorker5 : MixWorkerService()
class MixWorker6 : MixWorkerService()
class MixWorker7 : MixWorkerService()
class MixWorker8 : MixWorkerService()
class MixWorker9 : MixWorkerService()
class MixWorker10 : MixWorkerService()
class MixWorker11 : MixWorkerService()
class MixWorker12 : MixWorkerService()
class MixWorker13 : MixWorkerService()
class MixWorker14 : MixWorkerService()
class MixWorker15 : MixWorkerService()
class MixWorker16 : MixWorkerService()
class MixWorker17 : MixWorkerService()
class MixWorker18 : MixWorkerService()
class MixWorker19 : MixWorkerService()
class MixWorker20 : MixWorkerService()
class MixWorker21 : MixWorkerService()
class MixWorker22 : MixWorkerService()
class MixWorker23 : MixWorkerService()
class MixWorker24 : MixWorkerService()
class MixWorker25 : MixWorkerService()
class MixWorker26 : MixWorkerService()
class MixWorker27 : MixWorkerService()
class MixWorker28 : MixWorkerService()
class MixWorker29 : MixWorkerService()
class MixWorker30 : MixWorkerService()
class MixWorker31 : MixWorkerService()
class MixWorker32 : MixWorkerService()
class MixWorker33 : MixWorkerService()
class MixWorker34 : MixWorkerService()
class MixWorker35 : MixWorkerService()
class MixWorker36 : MixWorkerService()
class MixWorker37 : MixWorkerService()
class MixWorker38 : MixWorkerService()
class MixWorker39 : MixWorkerService()
class MixWorker40 : MixWorkerService()
class MixWorker41 : MixWorkerService()
class MixWorker42 : MixWorkerService()
class MixWorker43 : MixWorkerService()
class MixWorker44 : MixWorkerService()
class MixWorker45 : MixWorkerService()
class MixWorker46 : MixWorkerService()
class MixWorker47 : MixWorkerService()
class MixWorker48 : MixWorkerService()
class MixWorker49 : MixWorkerService()
