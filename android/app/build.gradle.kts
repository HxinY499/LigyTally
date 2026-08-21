import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("LIGY_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("LIGY_STORE_PASSWORD")
val releaseKeyPassword = System.getenv("LIGY_KEY_PASSWORD")
val releaseKeyAlias = System.getenv("LIGY_KEY_ALIAS")
val hasReleaseSigning = listOf(
    releaseKeystorePath,
    releaseStorePassword,
    releaseKeyPassword,
    releaseKeyAlias,
).all { !it.isNullOrBlank() }
val isReleaseTask = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (isReleaseTask && !hasReleaseSigning) {
    error("Release signing is missing. Build with scripts/build_release.sh")
}

android {
    namespace = "com.ligy.ligy_tally"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ligy.ligy_tally"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 过滤必须写在 defaultConfig：只写在 release 时，插件 AAR 里的
        // v7a / x86_64 so 仍会打进包。系统会以为这台 32 位机可装，一点就缺引擎。
        if (isReleaseTask) {
            ndk {
                abiFilters += "arm64-v8a"
            }
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = File(releaseKeystorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    packaging {
        jniLibs {
            if (isReleaseTask) {
                excludes += listOf(
                    "lib/armeabi-v7a/**",
                    "lib/armeabi/**",
                    "lib/x86/**",
                    "lib/x86_64/**",
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
