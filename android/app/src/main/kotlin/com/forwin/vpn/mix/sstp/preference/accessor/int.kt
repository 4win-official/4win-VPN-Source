package com.forwin.vpn.mix.sstp.preference.accessor

import android.content.SharedPreferences
import com.forwin.vpn.mix.sstp.preference.DEFAULT_INT_MAP
import com.forwin.vpn.mix.sstp.preference.OscPrefKey


internal fun getIntPrefValue(key: OscPrefKey, prefs: SharedPreferences): Int {
    return prefs.getString(key.name, null)?.toIntOrNull() ?: DEFAULT_INT_MAP[key]!!
}

internal fun setIntPrefValue(value: Int, key: OscPrefKey, prefs: SharedPreferences) {
    prefs.edit().also {
        it.putString(key.name, value.toString())
        it.apply()
    }
}

internal fun resetReconnectionLife(prefs: SharedPreferences) {
    getIntPrefValue(OscPrefKey.RECONNECTION_COUNT, prefs).also {
        setIntPrefValue(it, OscPrefKey.RECONNECTION_LIFE, prefs)
    }
}
