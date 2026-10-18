package com.forwin.vpn.mix.sstp.preference.accessor

import android.content.SharedPreferences
import com.forwin.vpn.mix.sstp.preference.DEFAULT_BOOLEAN_MAP
import com.forwin.vpn.mix.sstp.preference.OscPrefKey


internal fun getBooleanPrefValue(key: OscPrefKey, prefs: SharedPreferences): Boolean {
    return prefs.getBoolean(key.name, DEFAULT_BOOLEAN_MAP[key]!!)
}

internal fun setBooleanPrefValue(value: Boolean, key: OscPrefKey, prefs: SharedPreferences) {
    prefs.edit().also {
        it.putBoolean(key.name, value)
        it.apply()
    }
}
