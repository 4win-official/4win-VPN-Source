"""Exercise the actual OpenVPN notification helper on a host JVM, without an APK."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "android/app/src/main/java/com/forwin/vpn/OpenVpnNotificationActions.java"

STUBS = {
    "android/R.java": "package android; public class R { public static class drawable { public static int ic_popup_sync=1, ic_menu_close_clear_cancel=2; }}",
    "android/os/RemoteException.java": "package android.os; public class RemoteException extends Exception {}",
    "android/net/Uri.java": "package android.net; public class Uri { public String value; public static Uri parse(String s) { Uri u=new Uri(); u.value=s; return u; }}",
    "android/content/Intent.java": """package android.content;
        public class Intent {
            public String action; public android.net.Uri data;
            private java.util.Map<String,String> extras=new java.util.HashMap<>();
            public Intent(Object owner, Class<?> type) {}
            public Intent setAction(String a) { action=a; return this; }
            public String getAction() { return action; }
            public Intent setData(android.net.Uri d) { data=d; return this; }
            public Intent putExtra(String k,String v) { extras.put(k,v); return this; }
            public String getStringExtra(String k) { return extras.get(k); }
            public boolean hasExtra(String k) { return extras.containsKey(k); }
        }""",
    "android/app/PendingIntent.java": """package android.app;
        public class PendingIntent {
            public static int FLAG_UPDATE_CURRENT=1, FLAG_IMMUTABLE=2;
            public android.content.Intent intent;
            public static PendingIntent getService(Object c,int n,android.content.Intent i,int f) {
                PendingIntent p=new PendingIntent(); p.intent=i; return p;
            }
        }""",
    "android/app/Notification.java": """package android.app;
        public class Notification { public static class Builder {
            public java.util.List<String> labels=new java.util.ArrayList<>();
            public java.util.List<PendingIntent> actions=new java.util.ArrayList<>();
            public Builder addAction(int icon,String label,PendingIntent intent) {
                labels.add(label); actions.add(intent); return this;
            }
        }}""",
    "de/blinkt/openvpn/core/ConnectionStatus.java": "package de.blinkt.openvpn.core; public enum ConnectionStatus { LEVEL_CONNECTED, LEVEL_START, LEVEL_AUTH_FAILED }",
    "de/blinkt/openvpn/core/OpenVPNManagement.java": "package de.blinkt.openvpn.core; public interface OpenVPNManagement { void reconnect(); }",
    "de/blinkt/openvpn/core/OpenVPNService.java": """package de.blinkt.openvpn.core;
        public class OpenVPNService {
            public static final String DISCONNECT_VPN="disconnect";
            private Object mProfile;
            private OpenVPNManagement mManagement;
            public int stops;
            public void set(Object profile,OpenVPNManagement management) { mProfile=profile; mManagement=management; }
            public String getPackageName() { return "test.vpn"; }
            public boolean stopVPN(boolean replacement) throws android.os.RemoteException { stops++; return true; }
        }""",
    "com/forwin/vpn/mix/FakeService.java": "package com.forwin.vpn.mix; public class FakeService extends de.blinkt.openvpn.core.OpenVPNService {}",
    "com/forwin/vpn/VpnStateBroadcast.java": "package com.forwin.vpn; public final class VpnStateBroadcast { public static int calls; public static String lastProtocol; public static void notifyDisconnected(de.blinkt.openvpn.core.OpenVPNService service, String protocol) { calls++; lastProtocol=protocol; } }",
    "ReconnectTest.java": """import android.app.Notification;
        import android.content.Intent;
        import com.forwin.vpn.OpenVpnNotificationActions;
        import de.blinkt.openvpn.core.*;
        public class ReconnectTest {
            static class Engine implements OpenVPNManagement { int calls; public void reconnect() { calls++; } }
            static void check(boolean ok,String message) { if (!ok) throw new AssertionError(message); }
            static Notification.Builder notification(OpenVPNService service) {
                Notification.Builder builder=new Notification.Builder();
                check(OpenVpnNotificationActions.addActions(service,builder),"standalone actions missing");
                check(builder.labels.equals(java.util.Arrays.asList("Reconnect","Disconnect")),"labels not English/exact");
                return builder;
            }
            public static void main(String[] args) {
                OpenVPNService service=new OpenVPNService();
                Object activeProfile=new Object(); Engine engine=new Engine(); service.set(activeProfile,engine);
                Notification.Builder first=notification(service);
                Intent old=first.actions.get(0).intent;
                check(OpenVpnNotificationActions.handleReconnect(service,old),"action not consumed");
                check(engine.calls==1,"active engine did not reconnect");
                check(OpenVpnNotificationActions.isReconnecting(),"reconnect gap not exposed");
                check(com.forwin.vpn.VpnStateBroadcast.calls==0,"reconnect emitted disconnect");
                OpenVpnNotificationActions.handleReconnect(service,old);
                check(engine.calls==1,"old tap repeated reconnect");
                Notification.Builder pending=notification(service);
                check(!old.data.value.equals(pending.actions.get(0).intent.data.value),"identity not rotated");
                OpenVpnNotificationActions.handleReconnect(service,pending.actions.get(0).intent);
                check(engine.calls==1,"new notification bypassed in-flight guard");
                OpenVpnNotificationActions.onState(service,ConnectionStatus.LEVEL_CONNECTED);
                OpenVpnNotificationActions.handleReconnect(service,pending.actions.get(0).intent);
                check(engine.calls==1,"stale connected callback cleared guard");
                OpenVpnNotificationActions.onState(service,ConnectionStatus.LEVEL_START);
                OpenVpnNotificationActions.onState(service,ConnectionStatus.LEVEL_CONNECTED);
                OpenVpnNotificationActions.handleReconnect(service,pending.actions.get(0).intent);
                check(engine.calls==2,"completed reconnect cannot reconnect again");
                Engine other=new Engine(); service.set(new Object(),other);
                OpenVpnNotificationActions.handleReconnect(service,pending.actions.get(0).intent);
                check(other.calls==0,"old profile action touched replacement");
                Notification.Builder current=notification(service);
                OpenVpnNotificationActions.handleReconnect(service,current.actions.get(1).intent);
                check(service.stops==1 && other.calls==0,"disconnect restarted VPN");
                check(com.forwin.vpn.VpnStateBroadcast.calls==1 && "openvpn".equals(com.forwin.vpn.VpnStateBroadcast.lastProtocol),"disconnect event missing");
                check(!OpenVpnNotificationActions.isReconnecting(),"disconnect retained reconnect intent");
                OpenVpnNotificationActions.handleReconnect(service,current.actions.get(1).intent);
                check(com.forwin.vpn.VpnStateBroadcast.calls==1,"stale disconnect emitted event");
                OpenVpnNotificationActions.handleReconnect(service,current.actions.get(0).intent);
                check(other.calls==0,"stopped session was resurrected");
                OpenVPNService recreated=new OpenVPNService();
                check(OpenVpnNotificationActions.handleReconnect(recreated,old),"stale action fell through to default startup");
                check(recreated.stops==0,"stale action mutated recreated service");
                OpenVPNService mix=new com.forwin.vpn.mix.FakeService();
                check(!OpenVpnNotificationActions.addActions(mix,new Notification.Builder()),"underlying Mix controls exposed");
                check(!OpenVpnNotificationActions.handleReconnect(mix,old),"Mix command was intercepted");
                System.out.println("OpenVPN notification session, duplicate, stale, stop, and Mix checks passed");
            }
        }""",
}


@unittest.skipUnless(shutil.which("javac") and shutil.which("java"), "JDK required")
class OpenVpnReconnectTest(unittest.TestCase):
    def test_actual_helper_session_and_reconnect_contract(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            for name, content in STUBS.items():
                path = directory / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            target = directory / "com/forwin/vpn/OpenVpnNotificationActions.java"
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(HELPER, target)
            subprocess.run(["javac", "-d", str(directory), *map(str, directory.rglob("*.java"))], check=True, capture_output=True, text=True)
            result = subprocess.run(["java", "-ea", "-cp", str(directory), "ReconnectTest"], check=True, capture_output=True, text=True)
            self.assertIn("checks passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
