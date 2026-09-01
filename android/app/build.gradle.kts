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

    packaging {
        jniLibs {
            pickFirsts += listOf("**/libgojni.so")
        }
    }
}

flutter { source = "../.." }

repositories {
    maven { url = uri("https://raw.github.com/Psiphon-Labs/psiphon-tunnel-core-Android-library/master") }
}

dependencies {
    implementation(files("libs/libv2ray.aar"))
    compileOnly("com.github.nizwar:openvpn_library:b3941ef040")
    // Official Psiphon Android MobileLibrary distribution
    implementation("ca.psiphon:psiphontunnel:2.0.40")
    // JSON parsing for Psiphon config
    implementation("org.json:json:20231013")
}