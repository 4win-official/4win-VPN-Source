plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
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

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.forwin.vpn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // libv2ray (AndroidLibXrayLite) requires minSdk 24.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // openvpn_library ships an orphan libgojni.so (no Java loader) that
            // collides with the real Xray core's libgojni.so (provided via
            // app/src/main/jniLibs). Keep the first one found; our local jniLibs
            // copy (the Xray core) takes precedence over the aar's.
            pickFirsts += listOf("**/libgojni.so")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // The real Xray core, identical to the one used by v2rayNG
    // (AndroidLibXrayLite / libv2ray.aar). Bundles tun2socks + geoip/geosite.
    implementation(files("libs/libv2ray.aar"))
}
