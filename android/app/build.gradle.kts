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
        }
    }
}

flutter { source = "../.." }

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
    val outFile = layout.buildDirectory.file("psiphon/psiphontunnel-2.0.40-relocated.aar")
    inputs.file(script)
    inputs.files(psiphonOriginal)
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
        val src = psiphonOriginal.singleFile
        val dst = outFile.get().asFile
        dst.parentFile.mkdirs()
        logger.lifecycle("Relocating Psiphon AAR (${src.name}) → ${dst.name}")
        exec {
            commandLine(python, script.absolutePath, "--in", src.absolutePath, "--out", dst.absolutePath)
        }
    }
}

dependencies {
    implementation(files("libs/libv2ray.aar"))

    compileOnly("com.github.nizwar:openvpn_library:b3941ef040")

    // The relocated Psiphon AAR produced by relocatePsiphonAar (always built;
    // wiring the task output here makes every compile/dex task depend on it).
    implementation(files(relocatePsiphonAar.map { it.outputs.files.singleFile }))

    implementation("org.json:json:20231013")
}
