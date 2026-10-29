package com.forwin.vpn

import android.app.NotificationManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import com.example.sstp_flutter.TrafficRateSampler
import java.util.concurrent.atomic.AtomicLong

/** Updates the existing notification, never its action PendingIntents or service state. */
internal class LiveTrafficNotification(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val revision = AtomicLong()
    private val lock = Any()
    private var pending: Runnable? = null
    private var clearRate: (() -> Unit)? = null

    fun start(
        id: Int,
        builder: NotificationCompat.Builder,
        status: String,
        connected: () -> Boolean,
        counters: () -> LongArray?
    ) {
        val version = revision.incrementAndGet()
        val localizedStatus = { VpnNotificationLabels.localized(context, status) }
        handler.post {
            synchronized(lock) {
                if (version != revision.get()) return@post
                pending?.let { handler.removeCallbacks(it) }
                val sampler = TrafficRateSampler()
                clearRate = {
                    builder.setOnlyAlertOnce(true).setContentText(localizedStatus()).setStyle(null)
                    manager?.notify(id, builder.build())
                }
                val tick = object : Runnable {
                    override fun run() {
                        synchronized(lock) {
                            if (version != revision.get()) return
                            if (!connected()) {
                                sampler.reset()
                                builder.setContentText(localizedStatus()).setStyle(null)
                            } else {
                                val totals = runCatching { counters() }.getOrNull()
                                val speed = if (totals != null && totals.size >= 2) {
                                    sampler.sample(totals[0], totals[1], SystemClock.elapsedRealtime())
                                } else {
                                    sampler.reset()
                                    null
                                }
                                val currentStatus = localizedStatus()
                                val currentSpeed = speed?.let { VpnNotificationLabels.localized(context, it) }
                                val text = currentSpeed ?: currentStatus
                                builder.setOnlyAlertOnce(true).setContentText(text)
                                    .setStyle(NotificationCompat.BigTextStyle().bigText(
                                        if (currentSpeed == null) currentStatus else "$currentStatus\n$currentSpeed"
                                    ))
                            }
                            if (version != revision.get()) return
                            manager?.notify(id, builder.build())
                            handler.postDelayed(this, 1_000L)
                        }
                    }
                }
                pending = tick
                tick.run()
            }
        }
    }

    fun stop() {
        synchronized(lock) {
            revision.incrementAndGet()
            pending?.let { handler.removeCallbacks(it) }
            pending = null
            // Clear before the caller removes foreground state, never in a late
            // posted callback that could resurrect a disconnected notification.
            runCatching { clearRate?.invoke() }
            clearRate = null
        }
    }
}
