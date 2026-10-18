package com.forwin.vpn.mix.sstp.extension

import android.content.SharedPreferences
import com.forwin.vpn.mix.sstp.preference.TEMP_KEY_HEADER


internal fun SharedPreferences.removeTemporaryPreferences() {
    val editor = edit()

    all.keys.filter { it.startsWith(TEMP_KEY_HEADER) }.forEach { editor.remove(it) }

    editor.apply()
}
