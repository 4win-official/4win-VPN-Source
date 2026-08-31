package com.forwin.vpn

import android.content.Context
import android.net.VpnService

/// Shared Split Tunneling helper for Android VpnService builders.
///
/// The Flutter shared_preferences plugin stores its Android preferences in
/// "FlutterSharedPreferences" and prefixes keys with "flutter.". The previous
/// implementation opened a package-named preferences file, so it never saw the
/// mode/app selection saved by SplitTunnelScreen.
///
/// Modes:
///   • "off"     → no per-app filtering (whole device is tunnelled).
///   • "include" → ONLY the selected apps go through the VPN.
///   • "exclude" → every app EXCEPT the selected apps goes through the VPN.
object SplitTunnel {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val MODE_KEY = "flutter.split_tunnel_mode"
    private const val APPS_KEY = "flutter.split_tunnel_apps"

    fun apply(context: Context, builder: VpnService.Builder, ownPackage: String) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val mode = prefs.getString(MODE_KEY, "off") ?: "off"
            if (mode == "off") return

            val raw = prefs.getString(APPS_KEY, null) ?: return
            val pkgs = raw.split(",")
                .map { it.trim() }
                .filter { it.isNotEmpty() && it != ownPackage }

            if (pkgs.isEmpty()) return

            when (mode) {
                "include" -> {
                    // Android VpnService.Builder treats allowed and disallowed
                    // application lists as mutually exclusive. Include mode
                    // therefore ONLY calls addAllowedApplication(). The caller
                    // must not pre-add the VPN app to the disallowed list.
                    for (pkg in pkgs) {
                        try {
                            builder.addAllowedApplication(pkg)
                        } catch (_: Throwable) {
                            // Package may have been uninstalled since selection.
                        }
                    }
                }
                "exclude" -> {
                    for (pkg in pkgs) {
                        try {
                            builder.addDisallowedApplication(pkg)
                        } catch (_: Throwable) {
                            // Package may have been uninstalled since selection.
                        }
                    }
                }
            }
        } catch (_: Throwable) {
            // Never let split-tunnel configuration prevent the VPN from starting.
        }
    }

    /** Returns the configured mode so callers can avoid conflicting builder calls. */
    fun mode(context: Context): String {
        return try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(MODE_KEY, "off") ?: "off"
        } catch (_: Throwable) {
            "off"
        }
    }
}
