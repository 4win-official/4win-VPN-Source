package com.forwin.vpn

import android.content.Context
import android.net.VpnService

/**
 * Shared Split Tunneling rules for standalone Android VpnService builders.
 * Flutter shared_preferences stores values in "FlutterSharedPreferences"
 * and prefixes keys with "flutter.".
 *
 * Modes:
 *   - "include": ONLY selected apps go through the VPN.
 *   - "exclude": selected apps bypass the VPN; all other apps use it.
 */
object SplitTunnel {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val MODE_KEY = "flutter.split_tunnel_mode"
    private const val APPS_KEY = "flutter.split_tunnel_apps"
    private const val OPT_OUT_KEY = "flutter.split_tunnel_banking_opt_outs"
    private const val MODE_MIGRATED_KEY = "flutter.split_tunnel_mode_migrated_v1"

    // Keep in sync with SplitTunnelScreen and AndroidManifest.xml package queries.
    private val defaultBypassPackages = setOf(
        "com.isc.bminew",
        "com.isc.bsinew",
        "mob.banking.android.pasargad",
        "com.adpdigital.mbs.ayande",
        "com.pmb.mobile",
        "com.bmelat.mobile",
        "com.bpm.sekeh",
        "com.refahbank.dpi.android",
        "com.refah.superapp",
        "com.parsmobapp",
        "com.ada.mbank.mehr",
        "com.rahand.qkids",
        "com.rahand.qbank",
        "com.tosan.dara.sina",
        "com.tosan.dara.sepah",
        "ir.stts.bjt",
        "com.maskanmobilebank",
        "com.bki.mobilebanking.android",
        "com.citydi.hplus",
        "ir.mobillet.app",
        "mob.banking.android.resalat",
        "ir.stsepehr.hamrahcard",
        "com.farazpardazan.enbank",
        "ir.tes.sarmayeh",
        "co.nilin.faraznative",
        "com.tosan.dara.day",
        "digital.neobank",
        "ir.omidbank",
        "com.gostaresh.mobilebank.boilerplate",
        "com.samanpr.blu",
        "co.redbank.app",
        "app.rbmain.a",
        "ir.sep.sesoot",
        "mobi.mmdt.ott",
        "mobi.mmdt.ottplus",
        "ir.eitaa.messenger",
        "ir.resaneh1.iptv",
        "com.app.shadplus",
        "com.bestapps.shadimadareswebbrowser",
        "ir.nasim",
        "com.farsitel.bazaar",
        "com.digikala",
        "com.mydigipay.app.android",
        "ir.divar",
        "com.fidibo.app",
        "com.myirancell",
        "ir.mci.ecareapp",
        "ir.mservices.market",
        "org.rajman.neshan.traffic.tehran.navigator",
        "cab.snapp.passenger",
        "ir.torob",
        "com.dotin.wepod",
        "com.pdpsoft.android.saapa",
        "com.delfan.madp",
        "net.pajal.nili.hamta",
    )
    /**
     * One-time migration makes old "off" and "include" preferences safe by
     * moving them to the default bypass-selected mode. Later explicit user
     * selections of either supported mode are preserved.
     */
    fun mode(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(MODE_MIGRATED_KEY, false)) {
            prefs.edit()
                .putString(MODE_KEY, "exclude")
                .putBoolean(MODE_MIGRATED_KEY, true)
                .apply()
            return "exclude"
        }

        return when (prefs.getString(MODE_KEY, "exclude")) {
            "include" -> "include"
            "exclude" -> "exclude"
            else -> {
                prefs.edit().putString(MODE_KEY, "exclude").apply()
                "exclude"
            }
        }
    }

    /** Apply the same default selection and mode semantics to every VPN builder. */
    fun apply(context: Context, builder: VpnService.Builder, ownPackage: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val mode = mode(context)
        val selected = (prefs.getString(APPS_KEY, "") ?: "")
            .split(",")
            .map { it.trim() }
            .filter { it.isNotEmpty() && it != ownPackage }
            .toMutableSet()
        val optedOut = (prefs.getString(OPT_OUT_KEY, "") ?: "")
            .split(",")
            .map { it.trim() }
            .filter { it.isNotEmpty() && it in defaultBypassPackages }
            .toSet()
        selected.removeAll(optedOut)

        // Compute defaults natively as well as in the picker. This keeps the
        // first connection safe even if the user connects before opening Settings.
        val installedDefaults = defaultBypassPackages.filter { pkg ->
            pkg != ownPackage && runCatching {
                context.packageManager.getApplicationInfo(pkg, 0)
            }.isSuccess
        }
        selected.addAll(installedDefaults.filterNot { it in optedOut })

        if (mode == "include") {
            var allowed = 0
            for (pkg in selected) {
                if (runCatching { builder.addAllowedApplication(pkg) }.isSuccess) {
                    allowed++
                }
            }
            // With no allowed apps Android treats the VPN as applying to every
            // app. Fail closed rather than silently turning include into "all".
            check(allowed > 0) {
                "Select at least one installed app in Only selected mode."
            }
        } else {
            // Keep the VPN app outside the tunnel to prevent routing loops.
            builder.addDisallowedApplication(ownPackage)
            for (pkg in selected) {
                if (pkg in installedDefaults) {
                    builder.addDisallowedApplication(pkg)
                } else {
                    runCatching { builder.addDisallowedApplication(pkg) }
                }
            }
        }
    }
}
