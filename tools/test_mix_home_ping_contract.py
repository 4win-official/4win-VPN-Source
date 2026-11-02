"""Source contracts for the home-screen Mix delay probe.

These are intentionally executable without Android/Gradle: they inspect the
actual Kotlin method bodies and startup/cleanup call sites.  They are
structural contracts rather than a device/network test; the assertions model
the four important outcomes of each extracted probe method (inactive,
success, exception, and session replacement/reconnect) by requiring the real
method's pre/post guards and exception fallback.

Run from the repository root with:
    python3 -m unittest tools.test_mix_home_ping_contract -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from tools.test_mix_notification_contract import source
from tools.test_vpn_background_contract import method_body


class MixHomePingContractTest(unittest.TestCase):
    ROOT = Path(__file__).resolve().parents[1]

    def test_mix_probe_captures_exact_startup_probe_and_reuses_it(self):
        text = source("mix/MixCoordinatorService.kt")
        self.assertIn("private data class DelayProbe(val request: Request, val config: String)", text)
        start = method_body(text, "startChain")
        self.assertIn(
            'val probe = MixRouting.vpn(plan, prefixPorts.last(), supportsUdp, probe = true,',
            start,
        )
        self.assertIn(
            'val delay = Libv2ray.measureOutboundDelay(probe.toString(), "https://www.gstatic.com/generate_204")',
            start,
        )
        self.assertIn("delayProbe = DelayProbe(current, probe.toString())", start)
        # A home tap must not select/rebuild a chain or use a different config.
        probe = method_body(text, "measureActiveDelay")
        self.assertIn("Libv2ray.measureOutboundDelay(probe.config, url)", probe)
        self.assertNotIn("MixRouting.vpn", probe)
        self.assertNotIn("JSONObject", probe)

    def test_mix_probe_covers_inactive_success_exception_and_replaced_session(self):
        body = method_body(source("mix/MixCoordinatorService.kt"), "measureActiveDelay")
        # Inactive/cancelled/reconnecting calls are rejected before native work.
        for guard in (
            "isRunning",
            "!isReconnecting",
            "active === probe.request",
            "!probe.request.cancelled.get()",
            "delayProbe === probe",
        ):
            self.assertIn(guard, body)
        self.assertIn("if (!current()) return -1L", body)
        # Native exceptions become the established failure value.
        self.assertIn("runCatching", body)
        self.assertIn("getOrDefault(-1L)", body)
        # A reconnect/replacement while native work is in flight is ignored.
        self.assertIn("return if (current()) delay else -1L", body)

    def test_xray_mix_probe_has_same_guards_and_exception_contract(self):
        text = source("XrayVpnService.kt")
        self.assertIn("private data class MixDelayProbe(val controller: CoreController, val config: String)", text)
        body = method_body(text, "measureActiveMixDelay")
        for guard in (
            "isServiceRunning",
            "isMixModeRunning",
            "!isMixModeReconnecting",
            "activeController === probe.controller",
            "mixDelayProbe === probe",
        ):
            self.assertIn(guard, body)
        self.assertIn("if (!current()) return -1L", body)
        self.assertIn("Libv2ray.measureOutboundDelay(probe.config, url)", body)
        self.assertIn("runCatching", body)
        self.assertIn("getOrDefault(-1L)", body)
        self.assertIn("return if (current()) delay else -1L", body)

    def test_xray_probe_reuses_configuration_without_reselecting(self):
        text = source("XrayVpnService.kt")
        start = method_body(text, "startXray")
        self.assertIn("val probe = JSONObject(config).apply { remove(\"inbounds\") }", start)
        self.assertIn("MixDelayProbe(controller, probe.toString())", start)
        body = method_body(text, "measureActiveMixDelay")
        self.assertNotIn("JSONObject", body)
        self.assertNotIn("startXray", body)
        self.assertNotRegex(body, r"(?i)\b(?:start|re)connect(?:Mix|Xray)?\s*\(")

    def test_mix_probe_is_cleared_on_cleanup_and_xray_invalidation(self):
        mix = source("mix/MixCoordinatorService.kt")
        self.assertIn("delayProbe = null", method_body(mix, "cleanup"))
        xray = source("XrayVpnService.kt")
        self.assertIn("mixDelayProbe = null", method_body(xray, "invalidateConnectionLocked"))
        self.assertIn("mixDelayProbe = null", method_body(xray, "teardown"))

    def test_home_handler_uses_live_mix_services_and_never_activity_http(self):
        activity = source("MainActivity.kt")
        body = method_body(activity, "configureFlutterEngine")
        handler = body.split('"measureMixDelay" -> {', 1)[1].split('"getWarpRtt" -> {', 1)[0]
        self.assertIn('MixCoordinatorService.isRunning -> MixCoordinatorService.measureActiveDelay(url)', handler)
        self.assertIn('XrayVpnService.isMixModeRunning -> XrayVpnService.measureActiveMixDelay(url)', handler)
        self.assertIn("else -> -1L", handler)
        self.assertIn('"https://www.gstatic.com/generate_204"', handler)
        self.assertNotRegex(handler, r"(?i)HttpURLConnection|URL\(|openConnection|measureXrayDelay|connectMix|connectXray")
        self.assertNotIn("MixCoordinatorService.connect", handler)
        self.assertNotIn("XrayVpnService.ACTION_CONNECT", handler)

    def test_standalone_delay_and_dns_handlers_remain_separate(self):
        activity = source("MainActivity.kt")
        body = method_body(activity, "configureFlutterEngine")
        standalone = body.split('"measureDelay" -> {', 1)[1].split('"measureMixDelay" ->', 1)[0]
        self.assertIn("measureXrayDelay(configJson, url)", standalone)
        self.assertIn("startCancelableDelayProbe(requestId, result)", standalone)
        self.assertIn('if (configJson.contains("__APP_FILES__"))', standalone)
        self.assertIn("result.success(-1L)", standalone)
        self.assertNotIn("HttpURLConnection", standalone)

        warp_handler = body.split('"getWarpRtt" -> {', 1)[1].split('else -> result.notImplemented()', 1)[0]
        self.assertIn("WarpConnectionState.snapshot()", warp_handler)
        self.assertIn("state.connected", warp_handler)
        self.assertIn("XrayVpnService.isAetherActive()", warp_handler)
        self.assertIn("!XrayVpnService.isMixModeRunning", warp_handler)
        self.assertIn("NativeCore.isReady()", warp_handler)
        self.assertIn("NativeCore.lastRttMs()", warp_handler)
        self.assertNotRegex(warp_handler, r"(?i)HttpURLConnection|URL\(|openConnection")
        self.assertNotIn("measureFreshWarpDelay", activity)
        self.assertNotIn("activeDelayConnections", activity)

        dns_handler = body.split('"pingDns" -> {', 1)[1].split('"scanDns" ->', 1)[0]
        self.assertIn("pingDnsServer(dnsIp)", dns_handler)
        dns = method_body(activity, "pingDnsServer")
        for path in ("pingViaService", "pingIcmp", "pingTcp", "pingDnsUdp"):
            self.assertIn(path, dns)

    def test_warp_ping_uses_the_live_tun_and_never_direct_http(self):
        activity = source("MainActivity.kt")
        body = method_body(activity, "configureFlutterEngine")
        handler = body.split('"pingWarp" -> {', 1)[1].split('"getWarpRtt" -> {', 1)[0]
        self.assertIn("WarpConnectionState.snapshot().connected", handler)
        self.assertIn("XrayVpnService.isAetherActive()", handler)
        self.assertIn("NativeCore.pingMs()", handler)
        self.assertNotRegex(handler, r"(?i)HttpURLConnection|URL\(|openConnection|measureXrayDelay")

        ffi = (self.ROOT / "core/aether/src/ffi.rs").read_text(encoding="utf-8")
        self.assertIn("pub extern \"C\" fn aether_ping_ms()", ffi)
        self.assertIn("recv_timeout(std::time::Duration::from_secs(6))", ffi)
        bridge = (self.ROOT / "core/aether/src/tun.rs").read_text(encoding="utf-8")
        self.assertIn("ffi::register_warp_ping_channel(ping_tx)", bridge)
        self.assertIn("crate::exitip::Probe::whoami(local_ipv4)", bridge)
        self.assertIn("probe.matches(&packet)", bridge)


if __name__ == "__main__":
    unittest.main()
