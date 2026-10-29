package com.forwin.vpn.mix.sstp.preference

import android.content.Context
import android.content.SharedPreferences
import android.widget.Toast
import com.forwin.vpn.mix.sstp.MAX_MRU
import com.forwin.vpn.mix.sstp.MAX_MTU
import com.forwin.vpn.mix.sstp.MIN_MRU
import com.forwin.vpn.mix.sstp.MIN_MTU
import com.forwin.vpn.mix.sstp.preference.accessor.*


private fun localizedPreferenceMessage(context: Context, source: String): String {
    if (context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.app_language", "en") != "fa"
    ) return source
    Regex("^The given MRU is out of (\\d+)-(\\d+)$").matchEntire(source)?.let {
        return "مقدار MRU باید در بازهٔ ${it.groupValues[1]} تا ${it.groupValues[2]} باشد."
    }
    return when (source) {
        "Hostname is missing" -> "نام میزبان وارد نشده است."
        "The given port is out of 0-65535" -> "شمارهٔ درگاه باید بین 0 تا 65535 باشد."
        "Adding trusted certificates needs SSL version to be specified" -> "برای افزودن گواهی‌های مورد اعتماد، باید نسخهٔ SSL مشخص شود."
        "No certificates directory was selected" -> "پوشهٔ گواهی‌ها انتخاب نشده است."
        "No cipher suite was selected" -> "هیچ مجموعهٔ رمزنگاری انتخاب نشده است."
        "Proxy server hostname is missing" -> "نام میزبان پراکسی وارد نشده است."
        "The given proxy server port is out of 0-65535" -> "شمارهٔ درگاه پراکسی باید بین 0 تا 65535 باشد."
        "No network protocol was enabled" -> "هیچ پروتکل شبکه‌ای فعال نشده است."
        "No static IPv4 address was given" -> "نشانی ثابت IPv4 وارد نشده است."
        "No authentication protocol was enabled" -> "هیچ پروتکل احراز هویتی فعال نشده است."
        "PPP authentication timeout period must be >=1 second" -> "مهلت احراز هویت PPP باید دست‌کم 1 ثانیه باشد."
        "No custom DNS server address was given" -> "نشانی سرور DNS سفارشی وارد نشده است."
        "Retry Count must be a positive integer" -> "تعداد تلاش مجدد باید عدد صحیح مثبت باشد."
        "No log directory was selected" -> "پوشهٔ گزارش انتخاب نشده است."
        else -> source
    }
}

internal fun toastInvalidSetting(message: String, context: Context) {
    val persian = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        .getString("flutter.app_language", "en") == "fa"
    val title = if (persian) "تنظیم نامعتبر" else "INVALID SETTING"
    Toast.makeText(context, "$title: ${localizedPreferenceMessage(context, message)}", Toast.LENGTH_LONG).show()
}

internal fun checkPreferences(prefs: SharedPreferences): String? {
    getStringPrefValue(OscPrefKey.HOME_HOSTNAME, prefs).also {
        if (it.isEmpty()) return "Hostname is missing"
    }

    getIntPrefValue(OscPrefKey.SSL_PORT, prefs).also {
        if (it !in 0..65535) return "The given port is out of 0-65535"
    }

    val doAddCerts = getBooleanPrefValue(OscPrefKey.SSL_DO_ADD_CERT, prefs)
    val version = getStringPrefValue(OscPrefKey.SSL_VERSION, prefs)
    val certDir = getURIPrefValue(OscPrefKey.SSL_CERT_DIR, prefs)
    if (doAddCerts && version == "DEFAULT") return "Adding trusted certificates needs SSL version to be specified"

    if (doAddCerts && certDir == null) return "No certificates directory was selected"

    val doSelectSuites = getBooleanPrefValue(OscPrefKey.SSL_DO_SELECT_SUITES, prefs)
    val suites = getSetPrefValue(OscPrefKey.SSL_SUITES, prefs)
    if (doSelectSuites && suites.isEmpty()) return "No cipher suite was selected"

    if (getBooleanPrefValue(OscPrefKey.PROXY_DO_USE_PROXY, prefs)) {
        getStringPrefValue(OscPrefKey.HOME_HOSTNAME, prefs).also {
            if (it.isEmpty()) return "Proxy server hostname is missing"
        }

        getIntPrefValue(OscPrefKey.PROXY_PORT, prefs).also {
            if (it !in 0..65535) return "The given proxy server port is out of 0-65535"
        }
    }

    getIntPrefValue(OscPrefKey.PPP_MRU, prefs).also {
        if (it !in MIN_MRU..MAX_MRU) return "The given MRU is out of $MIN_MRU-$MAX_MRU"
    }

    getIntPrefValue(OscPrefKey.PPP_MTU, prefs).also {
        if (it !in MIN_MTU..MAX_MTU) return "The given MRU is out of $MIN_MTU-$MAX_MTU"
    }

    val isIPv4Enabled = getBooleanPrefValue(OscPrefKey.PPP_IPv4_ENABLED, prefs)
    val isIPv6Enabled = getBooleanPrefValue(OscPrefKey.PPP_IPv6_ENABLED, prefs)
    if (!isIPv4Enabled && !isIPv6Enabled) return "No network protocol was enabled"

    val isStaticIPv4Requested = getBooleanPrefValue(OscPrefKey.PPP_DO_REQUEST_STATIC_IPv4_ADDRESS, prefs)
    if (isIPv4Enabled && isStaticIPv4Requested) {
        getStringPrefValue(OscPrefKey.PPP_STATIC_IPv4_ADDRESS, prefs).also {
            if (it.isEmpty()) return "No static IPv4 address was given"
        }
    }

    val isPAPEnabled = getBooleanPrefValue(OscPrefKey.PPP_PAP_ENABLED, prefs)
    val isMSChapv2Enabled = getBooleanPrefValue(OscPrefKey.PPP_MSCHAPv2_ENABLED, prefs)
    if (!isPAPEnabled && !isMSChapv2Enabled) return "No authentication protocol was enabled"

    getIntPrefValue(OscPrefKey.PPP_AUTH_TIMEOUT, prefs).also {
        if (it < 1) return "PPP authentication timeout period must be >=1 second"
    }

    val isCustomDNSServerUsed = getBooleanPrefValue(OscPrefKey.DNS_DO_USE_CUSTOM_SERVER, prefs)
    val isCustomAddressEmpty = getStringPrefValue(OscPrefKey.DNS_CUSTOM_ADDRESS, prefs).isEmpty()
    if (isCustomDNSServerUsed && isCustomAddressEmpty) {
        return "No custom DNS server address was given"
    }

    getIntPrefValue(OscPrefKey.RECONNECTION_COUNT, prefs).also {
        if (it < 1) return "Retry Count must be a positive integer"
    }

    val doSaveLog = getBooleanPrefValue(OscPrefKey.LOG_DO_SAVE_LOG, prefs)
    val logDir = getURIPrefValue(OscPrefKey.LOG_DIR, prefs)
    if (doSaveLog && logDir == null) return "No log directory was selected"


    return null
}
