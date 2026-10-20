"""Validate OpenVPN AAR instrumentation against the pinned, original upstream AAR."""
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
TRANSFORMER = ROOT / "tools/OpenVpnAarTransformer.java"
ORIGINAL = pathlib.Path(
    "/home/ubuntu/.gradle/caches/modules-2/files-2.1/com.github.nizwar/"
    "openvpn_library/b3941ef040/c9edcf453b26ee9aef2e428ca1ea74d14270a1e4/"
    "openvpn_library-b3941ef040.aar"
)
ASM = sorted(pathlib.Path.home().glob(
    ".gradle/caches/modules-2/files-2.1/org.ow2.asm/asm/*/*/asm-*.jar"
))[-1]
SERVICE = "de/blinkt/openvpn/core/OpenVPNService.class"


@unittest.skipUnless(shutil.which("javac") and shutil.which("java") and shutil.which("javap"), "JDK required")
class OpenVpnRefreshTransformerTest(unittest.TestCase):
    def test_pinned_original_engine_hook_and_fail_closed_descriptors(self):
        self.assertTrue(ORIGINAL.is_file(), f"missing pinned AAR: {ORIGINAL}")
        with tempfile.TemporaryDirectory() as temporary:
            d = pathlib.Path(temporary)
            classes = d / "classes"
            subprocess.run(["javac", "-cp", str(ASM), "-d", str(classes), str(TRANSFORMER)], check=True)
            output = d / "instrumented.aar"
            subprocess.run(["java", "-cp", f"{classes}:{ASM}", "OpenVpnAarTransformer", str(ORIGINAL), str(output)], check=True)
            with zipfile.ZipFile(output) as aar:
                aar.extract("classes.jar", d / "out")
            classes_jar = d / "out/classes.jar"
            javap = subprocess.run(
                ["javap", "-classpath", str(classes_jar), "-c", "-p", "de.blinkt.openvpn.core.OpenVPNService"],
                check=True, capture_output=True, text=True,
            ).stdout

            start = javap[javap.index("private void startOpenVPN();"):]
            start = start[:re.search(r"\n  [^ ]", start[5:]).start() + 1] if re.search(r"\n  [^ ]", start[5:]) else start
            on_start = javap[javap.index("public int onStartCommand"):]
            on_start = on_start[:re.search(r"\n  [^ ]", on_start[5:]).start() + 1] if re.search(r"\n  [^ ]", on_start[5:]) else on_start
            self.assertIn("OpenVpnNotificationActions.onEngineStarting", start)
            self.assertEqual(start.count("OpenVpnNotificationActions.onEngineStarting"), 1)
            self.assertNotIn("OpenVpnNotificationActions.onEngineStarting", on_start)
            self.assertIn("OpenVpnNotificationActions.handleReconnect", on_start)
            self.assertNotIn("OpenVpnNotificationActions.onStartCommand", javap)
            for method, hook in {
                "addVpnActionsToNotification": "addActions",
                "updateState": "onState",
                "onDestroy": "invalidate",
                "onRevoke": "invalidate",
                "stopVPN": "invalidate",
            }.items():
                self.assertIn(f"OpenVpnNotificationActions.{hook}", javap, method)

            # Replace classes.jar with a class that lacks the pinned descriptors;
            # every touched[] slot must be found or transformation must abort.
            source = d / "OpenVPNService.java"
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("package de.blinkt.openvpn.core; public class OpenVPNService {}")
            missing_classes = d / "missing-classes"
            subprocess.run(["javac", "-d", str(missing_classes), str(source)], check=True)
            missing_jar = d / "missing.jar"
            subprocess.run(["jar", "cf", str(missing_jar), "-C", str(missing_classes), "."], check=True)
            missing_aar = d / "missing.aar"
            with zipfile.ZipFile(ORIGINAL) as source_aar, zipfile.ZipFile(missing_aar, "w") as target_aar:
                for item in source_aar.infolist():
                    target_aar.writestr(item, missing_jar.read_bytes() if item.filename == "classes.jar" else source_aar.read(item))
            failed = subprocess.run(
                ["java", "-cp", f"{classes}:{ASM}", "OpenVpnAarTransformer", str(missing_aar), str(d / "should-not-exist.aar")],
                capture_output=True, text=True,
            )
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("descriptor not found", failed.stderr + failed.stdout)
            self.assertFalse((d / "should-not-exist.aar").exists())


if __name__ == "__main__":
    unittest.main()
