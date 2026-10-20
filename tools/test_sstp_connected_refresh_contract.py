"""Regression contract for SSTP connected readiness session wiring."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "packages/sstp_flutter/android/src/main/kotlin/com/example/sstp_flutter/service/SstpVpnService.kt"


class SstpConnectedRefreshContractTest(unittest.TestCase):
    def test_home_status_is_read_from_the_active_session_source(self):
        source = SERVICE.read_text()
        on_create = source.split("override fun onCreate()", 1)[1].split("override fun onStartCommand", 1)[0]
        self.assertNotIn("OscPrefKey.HOME_STATUS.name", on_create)

        initialize = source.split("private fun initializeClient(", 1)[1].split("private fun prepareLogWriter", 1)[0]
        self.assertIn("detachHomeStatusListener()", initialize)
        self.assertIn("observedPrefs.registerOnSharedPreferenceChangeListener(registeredHomeStatusListener)", initialize)
        self.assertIn("source === observedPrefs", initialize)
        self.assertIn("observedHomeStatusPrefs === observedPrefs", initialize)
        self.assertIn("homeStatusListenerGeneration == listenerGeneration", initialize)
        self.assertIn("sessionGeneration == generation", initialize)
        self.assertIn("activeSessionPrefs === observedPrefs", initialize)
        self.assertIn("observedPrefs.getString(OscPrefKey.HOME_STATUS.name", initialize)

    def test_listener_is_detached_before_replacement_and_teardown(self):
        source = SERVICE.read_text()
        self.assertIn("detachHomeStatusListener()\n                controlClient?.kill", source)
        self.assertIn("observedPrefs.unregisterOnSharedPreferenceChangeListener(listener)", source)
        close = source.split("internal fun close()", 1)[1].split("override fun onDestroy", 1)[0]
        destroy = source.split("override fun onDestroy()", 1)[1]
        self.assertIn("detachHomeStatusListener()", close)
        self.assertIn("detachHomeStatusListener()", destroy)


if __name__ == "__main__":
    unittest.main()
