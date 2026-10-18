package com.forwin.vpn.mix.sstp.preference.accessor

import android.content.SharedPreferences
import com.forwin.vpn.mix.sstp.preference.DEFAULT_STRING_MAP
import com.forwin.vpn.mix.sstp.preference.OscPrefKey


internal fun getStringPrefValue(key: OscPrefKey, prefs: SharedPreferences): String {
    return prefs.getString(key.name, DEFAULT_STRING_MAP[key]!!)!!
}

internal fun setStringPrefValue(value: String, key: OscPrefKey, prefs: SharedPreferences) {
    prefs.edit().also {
        it.putString(key.name, value)
        it.apply()
    }
}
