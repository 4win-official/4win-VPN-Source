plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.forwin.vpn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }

    defaultConfig {
        applicationId = "com.forwin.vpn"
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // R8 code shrinking + resource shrinking. Safe here because every
            // reflectively-used / manifest-referenced package (go.*, gi.*,
            // libv2ray.*, ca.psiphon.*, de.blinkt.openvpn.*, our own
            // com.forwin.vpn.* services/activities) is explicitly kept in
            // proguard-rules.pro. Does NOT touch ABIs or produce app bundles —
            // still one universal APK with all 4 ABIs, just with dead Dart/
            // Kotlin/Java code and unused resources stripped out.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // ── Native library packaging: favor a smaller universal APK ────────────
    // AGP's modern default (useLegacyPackaging = false) stores jniLibs
    // UNCOMPRESSED + page-aligned in the APK so they can be mmap'd directly
    // without extraction — optimized for install footprint/startup speed at
    // the cost of a bigger APK/download. This app never exec()s a native lib
    // as a subprocess (Xray/Psiphon are both dlopen()'d via JNI), so there is
    // no functional reason to avoid legacy packaging, and legacy packaging
    // compresses the ~128MB of libgojni.so (Xray) + libpsiphon-gojni.so
    // (Psiphon, all 4 ABIs each) inside the APK itself — measured ~65%
    // shrink with plain deflate on these libs. This changes NOTHING about
    // which ABIs are shipped (still all 4, one universal APK); it only
    // changes how those bytes are stored inside that one file.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}

flutter { source = "../.." }

// Build the native WARP core from source for the ABIs shipped by the
// universal APK. This deliberately avoids copying a package-specific binary
// from another application.
val aetherAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
aetherAbis.forEach { abi ->
    val taskName = "buildAether${abi.split('-').joinToString("") { it.replaceFirstChar(Char::uppercase) }}"
    tasks.register<Exec>(taskName) {
        group = "build"
        description = "Builds the Aether WARP core for $abi"
        val script = rootProject.file("../core/build-android.sh")
        commandLine("bash", script.absolutePath, "--abi", abi)
        environment("ANDROID_HOME", android.sdkDirectory.absolutePath)
        environment("ANDROID_SDK_ROOT", android.sdkDirectory.absolutePath)
        inputs.dir(rootProject.file("../core/aether/src"))
        inputs.dir(rootProject.file("../core/quiche"))
        inputs.file(rootProject.file("../core/aether/Cargo.toml"))
        inputs.file(script)
        outputs.file(file("src/main/jniLibs/$abi/libaether.so"))
    }
    tasks.named("preBuild").configure { dependsOn(taskName) }
}

repositories {
    maven { url = uri("https://raw.github.com/Psiphon-Labs/psiphon-tunnel-core-Android-library/master") }
}

// ── Psiphon runtime isolation (go → gi relocation) ──────────────────────────
//
// This app embeds TWO gomobile-built Go runtimes: Xray (libv2ray + jniLibs'
// libgojni.so, Java bridge package `go`) and Psiphon (psiphontunnel AAR, Java
// bridge package `go` as well!). Two Go runtimes can never share one process:
// their .so files export ~90 identical default-visibility C symbols
// (main.main, crosscall*, _cgo_*, go_seq_*) and Android resolves symbols
// process-wide, so the second runtime ends up executing the first one's
// scheduler → native crash. The app therefore runs Psiphon in the dedicated
// `:psiphon` process and Xray in the main + `:psiphonbridge` processes.
//
// Process isolation alone is not enough, though: gomobile's magic `go.Seq`
// class has a static initializer `System.loadLibrary("gojni")`, and every
// binding is hard-wired to the `go` package. If the Psiphon AAR kept its
// `go.*` bridge classes, the :psiphon process would resolve them to the
// Xray copies packaged in the APK — loading the whole Xray runtime into the
// Psiphon process and routing Psiphon's Java→Go calls into the wrong runtime.
//
// The `relocatePsiphonAar` task below rewrites the Psiphon AAR at build time
// (identically on CI and local machines):
//   1. Java bridge package `go` → `gi` in every class of classes.jar,
//      including the loadLibrary("gojni") constant → "psiphon-gojni";
//   2. jni/<abi>/libgojni.so → libpsiphon-gojni.so, with the JNI export
//      names (Java_go_* → Java_gi_*) and the baked-in FindClass strings
//      (go/Seq → gi/Seq, …) patched in place inside the .so;
//   3. verifies no `go` bridge reference survives (hard build failure).
// Result: `gi.Seq` + libpsiphon-gojni.so (Psiphon) exist ONLY in :psiphon;
// `go.Seq` + libgojni.so (Xray) exist ONLY in the main/:psiphonbridge
// processes. Every process hosts exactly one Go runtime.
//
// `tools/relocate_psiphon_aar.py` needs python3 (preinstalled on macOS,
// Linux and most Windows dev setups).

val psiphonOriginal by configurations.creating {
    isVisible = false
    isCanBeConsumed = false
    isTransitive = false
}

dependencies {
    add("psiphonOriginal", "ca.psiphon:psiphontunnel:2.0.40")
}

val relocatePsiphonAar = tasks.register("relocatePsiphonAar") {
    group = "build"
    description = "Relocates the Psiphon gomobile bridge (go → gi) so its Go " +
        "runtime can never share a process with Xray's."
    val script = rootProject.file("../tools/relocate_psiphon_aar.py")
    // Optional local override: if this file exists it is used instead of the
    // maven artifact (handy for offline builds and CI mirrors).
    val localAar = file("libs/psiphontunnel-2.0.40.aar")
    val outFile = layout.buildDirectory.file("psiphon/psiphontunnel-2.0.40-relocated.aar")
    inputs.file(script)
    inputs.files(if (localAar.exists()) files(localAar) else psiphonOriginal)
    outputs.file(outFile)
    doLast {
        if (!script.exists()) {
            throw GradleException("relocate_psiphon_aar.py not found at ${script.absolutePath}")
        }
        val python = listOf("python3", "python").firstOrNull { cmd ->
            runCatching {
                ProcessBuilder(cmd, "--version").start().waitFor() == 0
            }.getOrDefault(false)
        } ?: throw GradleException(
            "python3 is required to build the Psiphon runtime relocation step. " +
            "Install Python 3 and re-run the build."
        )
        val src = if (localAar.exists()) localAar else psiphonOriginal.singleFile
        val dst = outFile.get().asFile
        dst.parentFile.mkdirs()
        logger.lifecycle("Relocating Psiphon AAR (${src.name}) → ${dst.name}")
        exec {
            commandLine(python, script.absolutePath, "--in", src.absolutePath, "--out", dst.absolutePath)
        }
    }
}

// ── Xray core AAR trimming (drop unused GeoIP/GeoSite databases) ───────────
//
// libv2ray.aar bundles assets/geoip.dat + assets/geosite.dat +
// assets/geoip-only-cn-private.dat (~31.2 MB combined) for `geoip:`/
// `geosite:` routing-rule tags. Nothing in this app's Xray configs (see
// lib/services/xray_config_builder.dart) ever uses those tags — routing is
// done with literal outbound tags and IP/CIDR rules only — so these assets
// are pure dead weight in every release APK. `trimLibv2rayAar` strips them
// out of the AAR at build time, byte-identical otherwise (classes.jar, the
// AndroidManifest, proguard.txt and res/ are untouched). This does NOT
// remove any feature/protocol and does NOT touch ABIs: it only deletes three
// unused data files, shrinking the universal APK by ~31 MB uncompressed.
val trimLibv2rayAar = tasks.register("trimLibv2rayAar") {
    group = "build"
    description = "Strips unused GeoIP/GeoSite database assets out of " +
        "libv2ray.aar (never referenced by this app's Xray configs)."
    val script = rootProject.file("../tools/trim_libv2ray_aar.py")
    val srcAar = file("libs/libv2ray.aar")
    val outFile = layout.buildDirectory.file("xray/libv2ray-trimmed.aar")
    inputs.file(script)
    inputs.file(srcAar)
    outputs.file(outFile)
    doLast {
        if (!script.exists()) {
            throw GradleException("trim_libv2ray_aar.py not found at ${script.absolutePath}")
        }
        if (!srcAar.exists()) {
            throw GradleException("libv2ray.aar not found at ${srcAar.absolutePath}")
        }
        val python = listOf("python3", "python").firstOrNull { cmd ->
            runCatching {
                ProcessBuilder(cmd, "--version").start().waitFor() == 0
            }.getOrDefault(false)
        } ?: throw GradleException(
            "python3 is required to build the libv2ray.aar trimming step. " +
            "Install Python 3 and re-run the build."
        )
        val dst = outFile.get().asFile
        dst.parentFile.mkdirs()
        logger.lifecycle("Trimming libv2ray.aar (dropping unused geoip/geosite assets) -> ${dst.name}")
        exec {
            commandLine(python, script.absolutePath, "--in", srcAar.absolutePath, "--out", dst.absolutePath)
        }
    }
}

dependencies {
    implementation(files(trimLibv2rayAar.map { it.outputs.files.singleFile }))

    compileOnly("com.github.nizwar:openvpn_library:b3941ef040")

    // The relocated Psiphon AAR produced by relocatePsiphonAar (always built;
    // wiring the task output here makes every compile/dex task depend on it).
    implementation(files(relocatePsiphonAar.map { it.outputs.files.singleFile }))

    implementation("org.json:json:20231013")
}

// Belt & suspenders: virtually every AGP task depends on preBuild, so this
// guarantees the relocated/trimmed AARs exist before anything compiles/
// packages them, regardless of file-collection dependency inference.
tasks.named("preBuild") {
    dependsOn(relocatePsiphonAar)
    dependsOn(trimLibv2rayAar)
}
