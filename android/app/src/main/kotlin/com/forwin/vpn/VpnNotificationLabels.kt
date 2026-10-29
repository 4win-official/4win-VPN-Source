package com.forwin.vpn

import android.app.Notification
import android.app.NotificationManager
import android.os.Build
import android.content.Context
import androidx.core.app.NotificationCompat

/** Native notification copy follows the saved in-app language without translating protocol names. */
object VpnNotificationLabels {
    const val MIX_PROTOCOL = "Mix Protocol"

    private const val PREFS_FILE = "FlutterSharedPreferences"
    private const val LANGUAGE_KEY = "flutter.app_language"

    private val exactTranslations = mapOf(
        "🔒 WARP Connected" to "🔒 WARP متصل است",
        "🔒 Xray Connected" to "🔒 Xray متصل است",
        "Reconnect" to "اتصال مجدد",
        "Disconnect" to "قطع اتصال",
        "Update" to "به‌روزرسانی",
        "Update available" to "به‌روزرسانی آماده است",
        "App updates" to "به‌روزرسانی‌های برنامه",
        "Notifications when a new 4win VPN version is available" to "هنگامی که نسخهٔ جدید 4win VPN در دسترس باشد، اعلان ارسال می‌شود.",
        "Tap to open • Reconnect or disconnect" to "برای باز کردن بزنید • اتصال مجدد یا قطع اتصال",
        "Local proxy running • Reconnect or disconnect" to "پراکسی محلی فعال است • اتصال مجدد یا قطع اتصال",
        "Psiphon traffic bridge active" to "پل ترافیک Psiphon فعال است",
        "Preparing an isolated tunnel stage" to "در حال آماده‌سازی یک مرحلهٔ مستقل تونل",
        "Preparing the complete chain" to "در حال آماده‌سازی زنجیرهٔ کامل",
        "Testing the complete chain" to "در حال آزمایش زنجیرهٔ کامل",
        "Reconnecting the complete chain" to "در حال اتصال مجدد به زنجیرهٔ کامل",
        "Connecting; traffic is blocked until ready" to "در حال اتصال؛ تا آماده‌شدن، ترافیک مسدود است",
        "Reconnecting; traffic is blocked until ready" to "در حال اتصال مجدد؛ تا آماده‌شدن، ترافیک مسدود است",
        "Connection failed; traffic is blocked" to "اتصال ناموفق بود؛ ترافیک مسدود است",
        "Connection failed; VPN not started" to "اتصال ناموفق بود؛ VPN راه‌اندازی نشد",
        "Connecting to Psiphon..." to "در حال اتصال به Psiphon...",
        "Reconnecting to Psiphon..." to "در حال اتصال مجدد به Psiphon...",
        "Psiphon is starting..." to "Psiphon در حال راه‌اندازی است...",
        "Disconnected" to "اتصال قطع است",
        "Reconnecting — traffic blocked" to "در حال اتصال مجدد — ترافیک مسدود است",
        "Psiphon core up — starting traffic bridge..." to "هستهٔ Psiphon آماده است — در حال راه‌اندازی پل ترافیک...",
        "Waiting for network..." to "در انتظار شبکه...",
        "Connected to Psiphon" to "به Psiphon متصل شد",
        "Psiphon bridge failed to start" to "راه‌اندازی پل Psiphon ناموفق بود",
        "Psiphon traffic bridge failed" to "پل ترافیک Psiphon ناموفق بود",
        "Xray VPN Service" to "سرویس Xray VPN",
        "Xray VPN connection status" to "وضعیت اتصال Xray VPN",
        "Xray Proxy Service" to "سرویس پراکسی Xray",
        "Xray local proxy status" to "وضعیت پراکسی محلی Xray",
        "DNS VPN Service" to "سرویس DNS VPN",
        "Shows when DNS VPN is active" to "هنگامی که DNS VPN فعال است نشان می‌دهد",
        "Psiphon VPN Service" to "سرویس Psiphon VPN",
        "Psiphon VPN tunnel status" to "وضعیت تونل Psiphon VPN",
        "Psiphon VPN bridge" to "پل Psiphon VPN",
    )

    @JvmStatic
    fun localized(context: Context, source: String): String {
        val language = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getString(LANGUAGE_KEY, "en")
        if ('\n' in source) {
            return source.split('\n').joinToString("\n") { localized(context, it) }
        }
        if (language != "fa") return englishSource(source) ?: source
        exactTranslations[source]?.let { return it }

        Regex("^Version (.+) is ready to install\\.$").matchEntire(source)?.let {
            return "نسخهٔ ${it.groupValues[1]} برای نصب آماده است."
        }
        Regex("^DNS: (.+) • Speed unavailable \\(DNS-only\\)$").matchEntire(source)?.let {
            return "DNS: ${it.groupValues[1]} • سرعت در دسترس نیست (فقط DNS)"
        }
        Regex("^DNS: (.+) • Reconnect or disconnect$").matchEntire(source)?.let {
            return "DNS: ${it.groupValues[1]} • اتصال مجدد یا قطع اتصال"
        }
        Regex("^Download: (.+) • Upload: (.+)$").matchEntire(source)?.let {
            return "دریافت: ${it.groupValues[1]} • ارسال: ${it.groupValues[2]}"
        }
        Regex("^Connected via (.+)$").matchEntire(source)?.let {
            return "از طریق ${it.groupValues[1]} متصل شد"
        }
        Regex("^Connected to (.+)$").matchEntire(source)?.let {
            return "به ${it.groupValues[1]} متصل شد"
        }
        Regex("^Connecting stage (\\d+) of (\\d+)$").matchEntire(source)?.let {
            return "در حال اتصال به مرحلهٔ ${it.groupValues[1]} از ${it.groupValues[2]}"
        }
        Regex("^(\\d+) stages active( · TCP-only)?$").matchEntire(source)?.let {
            val suffix = if (it.groupValues[2].isEmpty()) "" else " · فقط TCP"
            return "${it.groupValues[1]} مرحله فعال$suffix"
        }
        Regex("^Psiphon failed: (.+) — traffic blocked by kill switch$").matchEntire(source)?.let {
            return "خطای Psiphon: ${it.groupValues[1]} — ترافیک با کلید قطع اضطراری مسدود شد"
        }
        Regex("^Psiphon failed: (.+)$").matchEntire(source)?.let {
            return "اتصال Psiphon ناموفق بود: ${it.groupValues[1]}"
        }
        Regex("^Psiphon bridge failed to start: (.+)$").matchEntire(source)?.let {
            return "راه‌اندازی پل Psiphon ناموفق بود: ${it.groupValues[1]}"
        }
        Regex("^Psiphon traffic bridge failed: (.+)$").matchEntire(source)?.let {
            return "پل ترافیک Psiphon ناموفق بود: ${it.groupValues[1]}"
        }
        return source
    }

    private fun englishSource(source: String): String? {
        exactTranslations.entries.firstOrNull { it.value == source }?.let { return it.key }
        Regex("^نسخهٔ (.+) برای نصب آماده است\\.$").matchEntire(source)?.let {
            return "Version ${it.groupValues[1]} is ready to install."
        }
        Regex("^DNS: (.+) • سرعت در دسترس نیست \\(فقط DNS\\)$").matchEntire(source)?.let {
            return "DNS: ${it.groupValues[1]} • Speed unavailable (DNS-only)"
        }
        Regex("^DNS: (.+) • اتصال مجدد یا قطع اتصال$").matchEntire(source)?.let {
            return "DNS: ${it.groupValues[1]} • Reconnect or disconnect"
        }
        Regex("^دریافت: (.+) • ارسال: (.+)$").matchEntire(source)?.let {
            return "Download: ${it.groupValues[1]} • Upload: ${it.groupValues[2]}"
        }
        Regex("^از طریق (.+) متصل شد$").matchEntire(source)?.let {
            return "Connected via ${it.groupValues[1]}"
        }
        Regex("^به (.+) متصل شد$").matchEntire(source)?.let {
            return "Connected to ${it.groupValues[1]}"
        }
        Regex("^در حال اتصال به مرحلهٔ (\\d+) از (\\d+)$").matchEntire(source)?.let {
            return "Connecting stage ${it.groupValues[1]} of ${it.groupValues[2]}"
        }
        Regex("^(\\d+) مرحله فعال( · فقط TCP)?$").matchEntire(source)?.let {
            val suffix = if (it.groupValues[2].isEmpty()) "" else " · TCP-only"
            return "${it.groupValues[1]} stages active$suffix"
        }
        Regex("^خطای Psiphon: (.+) — ترافیک با کلید قطع اضطراری مسدود شد$").matchEntire(source)?.let {
            return "Psiphon failed: ${it.groupValues[1]} — traffic blocked by kill switch"
        }
        Regex("^اتصال Psiphon ناموفق بود: (.+)$").matchEntire(source)?.let {
            return "Psiphon failed: ${it.groupValues[1]}"
        }
        Regex("^راه‌اندازی پل Psiphon ناموفق بود: (.+)$").matchEntire(source)?.let {
            return "Psiphon bridge failed to start: ${it.groupValues[1]}"
        }
        Regex("^پل ترافیک Psiphon ناموفق بود: (.+)$").matchEntire(source)?.let {
            return "Psiphon traffic bridge failed: ${it.groupValues[1]}"
        }
        return null
    }

    /** Refreshes active OS notifications after the app language changes. */
    @JvmStatic
    fun refreshExisting(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.notificationChannels.forEach { channel ->
                val currentName = channel.name?.toString()
                val currentDescription = channel.description
                val translatedName = currentName?.let { localized(context, it) }
                val translatedDescription = currentDescription?.let { localized(context, it) }
                if (translatedName != currentName || translatedDescription != currentDescription) {
                    if (translatedName != null) channel.name = translatedName
                    channel.description = translatedDescription
                    manager.createNotificationChannel(channel)
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            manager.activeNotifications.forEach { active ->
                runCatching {
                    val notification = active.notification
                    val extras = notification.extras ?: return@runCatching
                    val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                    val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                    val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
                    val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                    if (title == null && text == null && subText == null && bigText == null) return@runCatching
                    val builder = NotificationCompat.Builder.recoverBuilder(context, notification)
                    if (title != null) builder.setContentTitle(localized(context, title))
                    if (text != null) builder.setContentText(localized(context, text))
                    if (subText != null) builder.setSubText(localized(context, subText))
                    if (bigText != null) {
                        builder.setStyle(NotificationCompat.BigTextStyle().bigText(localized(context, bigText)))
                    }
                    manager.notify(active.tag, active.id, builder.build())
                }
            }
        }
    }

    fun xrayTitle(context: Context, mixMode: Boolean, isWarp: Boolean): String = when {
        // Mix may use Xray/WARP internally; neither may replace its top-level name.
        mixMode -> MIX_PROTOCOL
        isWarp -> localized(context, "🔒 WARP Connected")
        else -> localized(context, "🔒 Xray Connected")
    }
}
