package com.forwin.vpn

import android.content.Context
import android.net.VpnService

/// Shared Split Tunneling helper. Reads the user's per-app tunnel selection
/// (persisted by Flutter's shared_preferences, which stores keys with a
/// "flutter." prefix in "<package>_preferences") and applies it to a
/// [VpnService.Builder].
///
/// Modes:
///   • "off"          → no per-app filtering (whole device is tunnelled).
///   • "include"      → ONLY the selected apps go through the VPN
///                      (addAllowedApplication).
///   • "exclude"      → every app EXCEPT the selected ones is tunnelled
///                      (addDisallowedApplication) — the selected apps bypass.
object SplitTunnel {
    private const val MODE_KEY = "flutter.split_tunnel_mode"
    private const val APPS_KEY = "flutter.split_tunnel_apps"

    fun apply(context: Context, builder: VpnService.Builder, ownPackage: String) {
        try {
            val prefs = context.getSharedPreferences(
                "${context.packageName}_preferences",
                Context.MODE_PRIVATE
            )
            val mode = prefs.getString(MODE_KEY, "off") ?: "off"
            if (mode == "off") return

            // shared_preferences stores a List<String> as a special encoded
            // string; to stay dependency-free we ALSO persist a plain
            // comma-separated copy under a mirror key from Flutter. Prefer that.
            val raw = prefs.getString(APPS_KEY, null) ?: return
            val pkgs = raw.split(",")
                .map { it.trim() }
                .filter { it.isNotEmpty() && it != ownPackage }
            if (pkgs.isEmpty()) return

            when (mode) {
                "include" -> {
                    for (p in pkgs) {
                        try {
                            builder.addAllowedApplication(p)
                        } catch (_: Throwable) { /* app uninstalled */ }
                    }
                    // Our own app must never be inside an include list or the
                    // core can't reach the network; when include mode is used
                    // we simply don't add ourselves (already filtered above).
                }
                "exclude" -> {
                    for (p in pkgs) {
                        try {
                            builder.addDisallowedApplication(p)
                        } catch (_: Throwable) { }
                    }
                }
            }
        } catch (_: Throwable) {
            // Never let split-tunnel config break the tunnel — fail open.
        }
    }
}
