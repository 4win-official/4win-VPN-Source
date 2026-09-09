package com.forwin.vpn

import android.content.Context

/**
 * Reads the shared kill-switch setting saved by Flutter's SettingsScreen.
 *
 * The Flutter shared_preferences plugin stores its Android preferences in
 * "FlutterSharedPreferences" with a "flutter." key prefix. This helper works
 * from any process (the `:psiphon` process reads the file fresh on first
 * access, so a toggle saved in the main process is visible there).
 *
 * Semantics: when enabled and the Psiphon tunnel fails or drops, the VPN
 * interface is KEPT UP with no forwarding behind it (a blackhole), so no app
 * traffic can leak onto the raw network until the user reconnects or
 * explicitly disconnects. When disabled, a failure tears the interface down so
 * traffic flows normally again.
 */
object KillSwitch {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY = "flutter.kill_switch"

    @JvmStatic
    fun isEnabled(context: Context): Boolean {
        return try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY, false) == true
        } catch (_: Throwable) {
            false
        }
    }
}
