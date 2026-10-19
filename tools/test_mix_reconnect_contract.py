"""Non-APK source wiring checks for notification-triggered Mix reconnect.

These guard lifecycle ordering and exact-plan reuse; device testing is still
needed to exercise native engines and Android PendingIntent delivery.
"""
import unittest
from tools.test_mix_notification_contract import source
from tools.test_vpn_background_contract import method_body


class MixReconnectContractTest(unittest.TestCase):
    def test_both_notifications_target_coordinator_with_same_session(self):
        for name in ("mix/MixCoordinatorService.kt", "mix/MixWorkerService.kt"):
            text = source(name)
            body = method_body(text, "showNotification")
            self.assertIn('"Disconnect"', body)
            self.assertIn('"Reconnect"', body)
            self.assertIn("notificationIntent(this,", body)
            self.assertIn("ACTION_RECONNECT", body)
            self.assertIn("FLAG_IMMUTABLE", body)
        coordinator = source("mix/MixCoordinatorService.kt")
        self.assertIn('.setData(Uri.parse("forwin-mix://notification/$session/$action"))', coordinator)
        self.assertIn('.putExtra("sessionId", session)', coordinator)

    def test_stale_actions_cannot_stop_or_restart_a_new_chain(self):
        body = method_body(source("mix/MixCoordinatorService.kt"), "onStartCommand")
        self.assertIn('intent.getStringExtra("sessionId") == next.id', body)
        self.assertIn("if (request == null) stopSelf(startId)", body)

    def test_duplicate_taps_are_coalesced_and_stop_cancels_restart(self):
        text = source("mix/MixCoordinatorService.kt")
        reconnect = method_body(text, "requestReconnect")
        self.assertIn("isReconnecting", reconnect)
        self.assertIn("compareAndSet(false, true)", reconnect)
        self.assertIn("request !== current", reconnect)
        stop = method_body(text, "requestStop")
        self.assertIn("reconnectFrom = null", stop)
        self.assertIn("isReconnecting = false", stop)
        for name in ("onDestroy",):
            self.assertIn("reconnectFrom = null", method_body(text, name))
        self.assertIn("requestStop(it)", method_body(text, "onRevoke"))

    def test_exact_plan_restarts_only_after_full_cleanup(self):
        text = source("mix/MixCoordinatorService.kt")
        cleanup = method_body(text, "cleanup")
        self.assertIn("if (request !== current) return", cleanup)
        self.assertLess(cleanup.index("worker.stopped.get"), cleanup.index("finishCleanup(current)"))
        self.assertLess(cleanup.index("router?.stopLoop()"), cleanup.index("finishCleanup(current)"))
        finish = method_body(text, "finishCleanup")
        self.assertIn("JSONObject(current.plan.toString())", finish)
        self.assertIn("UUID.randomUUID().toString()", finish)
        self.assertIn("active === current", finish)
        self.assertIn("startChain(next)", finish)
        self.assertLess(finish.index("startChain(next)"), finish.index("stopSelf()"))
        self.assertIn("isReconnecting = false", method_body(text, "startChain"))


if __name__ == "__main__":
    unittest.main()
