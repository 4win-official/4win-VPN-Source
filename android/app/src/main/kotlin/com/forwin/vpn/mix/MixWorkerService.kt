package com.forwin.vpn.mix

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.forwin.vpn.R
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicBoolean

/** Each declared subclass has its own Android process and exactly one native engine. */
open class MixWorkerService : Service() {
    private var adapter: MixAdapter? = null
    private val generation = AtomicLong()
    private val stopping = AtomicBoolean(false)
    private var sessionId = ""
    private var hopId = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(CHANNEL, "Mix engine", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        startForeground(NOTIFICATION + (javaClass.simpleName.removePrefix("MixWorker").toIntOrNull() ?: 0), NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher).setContentTitle("Mix engine")
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
        if (adapter != null) {
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
                }, workerSlot = intent.getIntExtra("workerSlot", 0)))
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
            if (sessionId.isNotEmpty()) emit(sessionId, hopId, "stopped")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }.start()
    }

    private fun emit(session: String, hop: String, state: String, error: String? = null, udp: Boolean = false) {
        sendBroadcast(Intent(ACTION_STATUS).setPackage(packageName)
            .putExtra("sessionId", session).putExtra("hopId", hop).putExtra("state", state)
            .putExtra("error", error).putExtra("supportsUdp", udp))
    }

    override fun onDestroy() { stopAdapter(); super.onDestroy() }

    companion object {
        const val ACTION_START = "com.forwin.vpn.mix.START_WORKER"
        const val ACTION_STOP = "com.forwin.vpn.mix.STOP_WORKER"
        const val ACTION_STATUS = "com.forwin.vpn.mix.WORKER_STATUS"
        private const val CHANNEL = "MixWorker"
        private const val NOTIFICATION = 40
        val CLASSES = arrayOf(
            MixWorker0::class.java, MixWorker1::class.java, MixWorker2::class.java, MixWorker3::class.java,
            MixWorker4::class.java, MixWorker5::class.java, MixWorker6::class.java, MixWorker7::class.java,
            MixWorker8::class.java, MixWorker9::class.java, MixWorker10::class.java, MixWorker11::class.java,
            MixWorker12::class.java, MixWorker13::class.java, MixWorker14::class.java, MixWorker15::class.java)
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
