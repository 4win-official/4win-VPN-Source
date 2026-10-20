"""Host-JVM checks for VpnConnectionObserver; no APK or Android device required."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
OBSERVER = ROOT / "packages/sstp_flutter/android/src/main/java/com/example/sstp_flutter/VpnConnectionObserver.java"

STUBS = {
    "android/content/Context.java": """package android.content;
        public class Context { private Context app; public Context() { app=this; }
        public Context(Context app) { this.app=app; } public Context getApplicationContext() { return app; } }""",
    "com/example/sstp_flutter/ObserverTest.java": """package com.example.sstp_flutter;
        import android.content.Context;
        public class ObserverTest {
          static class App extends Context implements VpnConnectionObserver { int calls; int states; boolean connected; boolean fail;
            public void onVpnConnectionStarting(Context source) { if (source == null) throw new AssertionError("source lost"); calls++; if (fail) throw new RuntimeException(); }
            public void onVpnConnectionStateChanged(Context source, boolean value) { if (source == null) throw new AssertionError("state source lost"); states++; connected=value; if (fail) throw new RuntimeException(); } }
          static void check(boolean ok, String msg) { if (!ok) throw new AssertionError(msg); }
          public static void main(String[] args) {
            App app=new App(); VpnConnectionObserver.notifyStarting(new Context(app)); check(app.calls==1,"application context not used");
            app.fail=true; VpnConnectionObserver.notifyStarting(app); check(app.calls==2,"observer exception escaped");
            VpnConnectionObserver.notifyState(app,true); check(app.states==1 && app.connected,"connected state missing");
            VpnConnectionObserver.notifyState(app,false); check(app.states==2 && !app.connected,"disconnected state missing");
            VpnConnectionObserver.notifyState(null,true);
            VpnConnectionObserver.notifyStarting(new Context()); check(app.calls==2,"non-observer notified");
            System.out.println("observer checks passed");
          }
        }""",
}

@unittest.skipUnless(shutil.which("javac") and shutil.which("java"), "JDK required")
class NativeVpnObserverTest(unittest.TestCase):
    def test_observer_contract(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            for name, content in STUBS.items():
                path = directory / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(content)
            target = directory / "com/example/sstp_flutter/VpnConnectionObserver.java"
            target.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(OBSERVER, target)
            subprocess.run(["javac", "-d", str(directory), *map(str, directory.rglob("*.java"))], check=True)
            result = subprocess.run(["java", "-ea", "-cp", str(directory), "com.example.sstp_flutter.ObserverTest"], check=True, capture_output=True, text=True)
            self.assertIn("checks passed", result.stdout)

if __name__ == "__main__":
    unittest.main()
