"""Standalone WARP retains the morning build's native-readiness polling.

The native READY flag is consulted only through the owning service/request,
never directly from Activity or a different protocol's runtime.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / 'android/app/src/main/kotlin/com/forwin/vpn'


class WarpMorningReadinessContractTest(unittest.TestCase):
    def test_activity_polls_the_owning_service_before_waiting_for_a_callback(self):
        source = (NATIVE / 'MainActivity.kt').read_text()
        start = source.index('if (isWarp) {', source.index('"connectXray", "connectMix"'))
        wait = source[start:source.index('"disconnectXray"', start)]
        self.assertIn('XrayVpnService.pollWarpReadiness(warpRequest)', wait)
        self.assertNotIn('NativeCore.isReady()', wait)
        self.assertLess(wait.index('XrayVpnService.pollWarpReadiness(warpRequest)'),
                        wait.index('WarpConnectionState.timeout(warpRequest'))
        self.assertIn('outcome.connected -> result.success(true)', wait)

    def test_poll_is_request_and_generation_scoped_before_reading_native_ready(self):
        source = (NATIVE / 'XrayVpnService.kt').read_text()
        start = source.index('private fun pollNativeWarpReadiness(request: Long)')
        poll = source[start:source.index('private fun acceptWarpReadiness', start)]
        self.assertIn('val token = aetherGeneration ?: return', poll)
        guard = 'request != warpRequest || !isCurrent(token) || !aetherActive || !isRunning'
        self.assertIn(guard, poll)
        self.assertLess(poll.index(guard), poll.index('NativeCore.isReady()'))
        self.assertIn('acceptWarpReadiness(request, token)', poll)
        self.assertNotIn('NativeCore.start(', poll)
        self.assertNotIn('NativeCore.prepare(', poll)

    def test_polled_ready_and_callback_share_the_same_guarded_completion(self):
        source = (NATIVE / 'XrayVpnService.kt').read_text()
        start = source.index('private fun acceptWarpReadiness')
        accept = source[start:source.index('fun onEvent', start)]
        self.assertIn('request != warpRequest || !isCurrent(token)', accept)
        self.assertIn('if (!WarpConnectionState.connected(request)) return', accept)
        self.assertLess(accept.index('WarpConnectionState.connected(request)'),
                        accept.index('aetherConnected = true'))
        event = source[source.index('fun onEvent'):source.index('fun protectSocket')]
        self.assertIn('acceptWarpReadiness(warpRequest, token)', event)
        self.assertIn('activeAetherService = this', source)
        self.assertIn('if (activeAetherService === this) activeAetherService = null', source)


if __name__ == '__main__':
    unittest.main()
