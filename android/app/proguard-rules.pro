# ── 4win VPN release R8/ProGuard rules ──────────────────────────────────────
#
# Minification + resource shrinking are enabled for the release build type
# (see app/build.gradle.kts) purely to cut dead code/resources out of the
# universal APK — no protocol, feature, or ABI is removed by this file. Every
# rule below exists because the class it protects is reached ONLY through
# reflection, JNI, a gomobile bridge, or a third-party manifest declaration
# that R8's static analysis cannot see, so removing/renaming it would break
# a real feature at runtime even though R8 sees no source-level reference.

# ── Xray core (gomobile) ─────────────────────────────────────────────────
# `go.Seq` is loaded through JNI (libgojni.so calls back into the Java
# bridge via baked-in class/method names) and libv2ray.* is the AAR's own
# public API surface used from Kotlin (XrayVpnService.kt, MainActivity.kt).
# The AAR ships these same two rules in its own proguard.txt; repeating them
# here keeps the app safe even if that consumer proguard file is ever
# dropped or the AAR is swapped for one that lacks it.
-keep class go.** { *; }
-keep class libv2ray.** { *; }

# ── Psiphon core (gomobile, relocated go -> gi at build time) ───────────
# relocate_psiphon_aar.py rewrites Psiphon's own `go.*` bridge to `gi.*`
# specifically so it cannot collide with Xray's `go.*` in the same APK (see
# the big comment above relocatePsiphonAar in build.gradle.kts). Once
# relocated, `gi.Seq` is reached the exact same way `go.Seq` is: JNI calls
# back into it by baked-in name, invisible to R8's reference graph.
-keep class gi.** { *; }

# ── Psiphon public API (ca.psiphon.*) ────────────────────────────────────
# PsiphonTunBridge.kt / PsiphonVpnService.kt drive this API directly, but
# psiphontunnel itself also uses reflection internally (e.g. for its own
# JSON/config plumbing), so keep the whole package intact.
-keep class ca.psiphon.** { *; }

# ── openvpn_library / de.blinkt.openvpn (OpenVPN core) ───────────────────
# AndroidManifest.xml overrides `de.blinkt.openvpn.core.OpenVPNService` by
# exact class name, and the plugin's own native (JNI) and reflective config
# parsing (ConfigParser, VpnProfile serialization) resolve classes by name
# at runtime. compileOnly in build.gradle.kts means these classes come from
# the openvpn_flutter plugin's own Android sources at app-assembly time.
-keep class de.blinkt.openvpn.** { *; }
-keep class id.laskarmedia.openvpn_flutter.** { *; }

# ── This app's own Kotlin classes referenced from AndroidManifest.xml ────
# Activities/services/providers named in the manifest by fully-qualified
# class name must survive with their original name; R8 can rename/inline
# unreferenced members of a kept class, so keep entire classes to be safe
# with MethodChannel handler methods invoked by name from Dart via
# reflection-free but string-keyed method dispatch.
-keep class com.forwin.vpn.** { *; }

# ── Flutter / plugin generated glue ───────────────────────────────────────
# Standard Flutter embedding keep rules (safe even though the Flutter Gradle
# plugin normally supplies its own consumer rules; explicit here for
# resilience against R8 config changes).
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# ── org.json ───────────────────────────────────────────────────────────────
# Used directly for Xray/Psiphon/WARP config JSON construction; nothing
# reflective here, but org.json ships obfuscation-unfriendly static
# initializers in some versions — keep to be safe.
-keep class org.json.** { *; }

# ── General Android/Kotlin hygiene ────────────────────────────────────────
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes SourceFile,LineNumberTable

# Keep native-method holder classes intact (JNI resolves by exact
# class+method+signature name).
-keepclasseswithmembernames class * {
    native <methods>;
}

# Enums used via values()/valueOf() reflection-adjacent codegen (Kotlin/AGP
# sometimes generates code that trips up naive shrinking of enum classes).
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
