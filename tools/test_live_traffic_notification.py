#!/usr/bin/env python3
"""Host behavior test for the Android LiveTrafficNotification updater.

This deliberately compiles the production Kotlin file and Java TrafficRateSampler,
then runs them against small deterministic Android/AndroidX stubs. It does not
build an APK or require a device/network.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "android/app/src/main/kotlin/com/forwin/vpn/LiveTrafficNotification.kt"
SAMPLER = ROOT / "packages/sstp_flutter/android/src/main/java/com/example/sstp_flutter/TrafficRateSampler.java"
KOTLIN = Path("/tmp/gradle-8.14/lib/kotlin-compiler-embeddable-2.0.21.jar")
STDLIB = Path("/tmp/gradle-8.14/lib/kotlin-stdlib-2.0.21.jar")
REFLECT = Path("/tmp/gradle-8.14/lib/kotlin-reflect-2.0.21.jar")
TROVE = Path("/tmp/gradle-8.14/lib/trove4j-1.0.20200330.jar")

STUBS = {
"android/app/Notification.java": '''package android.app; public final class Notification {
  public final CharSequence text; public final Object style; public final boolean onlyAlertOnce;
  public final java.util.List<Object> actions;
  public Notification(CharSequence t, Object s, boolean once, java.util.List<Object> a) { text=t; style=s; onlyAlertOnce=once; actions=a; }
}''',
"android/app/NotificationManager.java": '''package android.app; public class NotificationManager {
  public final java.util.List<Notification> posted = new java.util.ArrayList<>();
  public void notify(int id, Notification n) { posted.add(n); }
}''',
"android/content/Context.java": '''package android.content; import android.app.NotificationManager;
public class Context { private final NotificationManager manager; public Context(NotificationManager m) { manager=m; }
  public <T> T getSystemService(Class<T> type) { return type.cast(manager); }
}''',
"android/os/Looper.java": '''package android.os; public final class Looper { private static final Looper MAIN=new Looper(); public static Looper getMainLooper(){return MAIN;} }''',
"android/os/SystemClock.java": '''package android.os; public final class SystemClock { public static long now;
  public static long elapsedRealtime(){ return now; } }''',
"android/os/Handler.java": '''package android.os; public class Handler {
  public static Handler last; private final java.util.ArrayList<Runnable> delayed=new java.util.ArrayList<>();
  public Handler(Looper ignored) { last=this; }
  public boolean post(Runnable r) { r.run(); return true; }
  public boolean postDelayed(Runnable r, long ignored) { delayed.add(r); return true; }
  public void removeCallbacks(Runnable r) { while (delayed.remove(r)) {} }
  public void runNextDelayed() { if (!delayed.isEmpty()) delayed.remove(0).run(); }
  public Runnable firstDelayed() { return delayed.isEmpty() ? null : delayed.get(0); }
}''',
"androidx/core/app/NotificationCompat.java": '''package androidx.core.app; import android.app.Notification;
public final class NotificationCompat {
  public static class Style { public CharSequence bigText; }
  public static class BigTextStyle extends Style { public BigTextStyle bigText(CharSequence s){bigText=s; return this;} }
  public static class Action { public final String label; public Action(String l){label=l;} }
  public static class Builder {
    public CharSequence text; public Style style; public boolean onlyAlertOnce; public final java.util.List<Action> actions=new java.util.ArrayList<>();
    public Builder setContentText(CharSequence s){text=s; return this;} public Builder setStyle(Style s){style=s; return this;}
    public Builder setOnlyAlertOnce(boolean b){onlyAlertOnce=b; return this;} public Builder addAction(Action a){actions.add(a); return this;}
    public Notification build(){return new Notification(text,style,onlyAlertOnce,new java.util.ArrayList<Object>(actions));}
  }
}''',
}

HARNESS = r'''package com.forwin.vpn;
import android.app.*; import android.content.*; import android.os.*; import androidx.core.app.NotificationCompat;
public final class LiveTrafficNotificationHostTest {
  static void check(boolean ok, String message) { if (!ok) throw new AssertionError(message); }
  static Notification last(NotificationManager m) { check(!m.posted.isEmpty(), "no notification posted"); return m.posted.get(m.posted.size()-1); }
  static boolean contains(Object value, String needle) { return value != null && value.toString().contains(needle); }
  public static void main(String[] args) {
    NotificationManager manager = new NotificationManager(); Context context = new Context(manager);
    NotificationCompat.Builder builder = new NotificationCompat.Builder().addAction(new NotificationCompat.Action("stop"));
    LiveTrafficNotification updater = new LiveTrafficNotification(context);
    final boolean[] connected = {true}; final long[][] counters = {{0L, 0L}};
    SystemClock.now = 1_000L;
    updater.start(7, builder, "Connected", () -> connected[0], () -> counters[0]);
    Notification baseline = last(manager);
    check(contains(baseline.text, "Connected") && !contains(baseline.text, "Download"), "baseline must not fabricate a rate");
    check(baseline.actions.size() == 1 && ((NotificationCompat.Action) baseline.actions.get(0)).label.equals("stop"), "same builder actions must be retained");

    SystemClock.now = 2_000L; counters[0] = new long[]{2048L, 4096L}; Handler.last.runNextDelayed();
    Notification rate = last(manager); check(contains(rate.text, "Download:") && contains(((NotificationCompat.BigTextStyle) rate.style).bigText, "Upload:"), "periodic sample must contain real rates");
    int postedAfterRate = manager.posted.size();

    counters[0] = null; Handler.last.runNextDelayed();
    Notification failed = last(manager); check(failed.text.equals("Connected") && contains(((NotificationCompat.BigTextStyle) failed.style).bigText, "Connected"), "counter failure must reset to status, not retain stale rate");

    connected[0] = false; Handler.last.runNextDelayed();
    Notification disconnected = last(manager); check(disconnected.text.equals("Connected") && disconnected.style == null, "false connected must hide rate/style");

    connected[0] = true; counters[0] = new long[]{2048L, 4096L}; SystemClock.now = 3_000L; Handler.last.runNextDelayed();
    counters[0] = new long[]{4096L, 8192L}; SystemClock.now = 4_000L; Handler.last.runNextDelayed();
    check(contains(last(manager).text, "Download:"), "rate must be visible before stop");
    updater.stop(); int beforeStop = manager.posted.size(); Handler.last.runNextDelayed();
    check(last(manager).text.equals("Connected") && last(manager).style == null, "stop must immediately clear stale throughput");
    check(manager.posted.size() == beforeStop, "stop must prevent a posted stale tick");

    // A manually invoked old runnable must be inert after a replacement session.
    connected[0] = true; counters[0] = new long[]{0L, 0L}; SystemClock.now = 3_000L;
    updater.start(7, builder, "New", () -> connected[0], () -> counters[0]);
    Runnable oldTick = Handler.last.firstDelayed();
    updater.start(7, builder, "Replacement", () -> connected[0], () -> counters[0]);
    int beforeOld = manager.posted.size(); if (oldTick != null) oldTick.run();
    check(manager.posted.size() == beforeOld, "replacement session must invalidate old tick");
    check(last(manager).text.equals("Replacement"), "replacement must post its own baseline");
    check(manager.posted.size() > postedAfterRate, "test exercised multiple updater cycles");
    System.out.println("PASS: LiveTrafficNotification host behavior");
  }
}
'''

def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, **kwargs)

def main():
    required = [TARGET, SAMPLER, KOTLIN, STDLIB, REFLECT, TROVE]
    missing = [str(p) for p in required if not p.exists()]
    if missing:
        raise SystemExit("missing required compiler/source files: " + ", ".join(missing))
    if shutil.which("javac") is None or shutil.which("java") is None:
        raise SystemExit("javac and java are required")
    with tempfile.TemporaryDirectory(prefix="live-traffic-host-") as td:
        work = Path(td); src = work / "src"; classes = work / "classes"; src.mkdir(); classes.mkdir()
        for rel, content in STUBS.items():
            p = src / rel; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(textwrap.dedent(content))
        harness = src / "com/forwin/vpn/LiveTrafficNotificationHostTest.java"; harness.parent.mkdir(parents=True, exist_ok=True); harness.write_text(textwrap.dedent(HARNESS))
        java_sources = [str(p) for p in src.rglob("*.java") if p != harness]
        run(["javac", "-d", str(classes)] + java_sources + [str(SAMPLER)])
        run(["java", "-cp", "/tmp/gradle-8.14/lib/*", "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler", "-jvm-target", "11", "-classpath", f"{classes}:{STDLIB}", "-d", str(classes), str(TARGET)])
        run(["javac", "-cp", f"{classes}:{STDLIB}", "-d", str(classes), str(harness)])
        run(["java", "-cp", f"{classes}:{STDLIB}", "com.forwin.vpn.LiveTrafficNotificationHostTest"])

if __name__ == "__main__":
    main()
