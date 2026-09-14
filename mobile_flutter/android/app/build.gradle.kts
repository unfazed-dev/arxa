import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing lives in a gitignored android/key.properties (written by
// CI from secrets — see .github/workflows/mobile-release.yml). Debug builds
// alone use the debug key; a release build with no signing inputs FAILS
// (below) instead of silently falling back to the debug key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseSigningReady = keystorePropertiesFile.exists() &&
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all { keystoreProperties[it] != null }

android {
    namespace = "solutions.arxadigital.arxa_studio_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "solutions.arxadigital.arxa.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningReady) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningReady) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Clear failure (not a debug-signed or unsigned artifact) when a release
// packaging task runs without signing inputs. Scoped to execution so debug
// builds and plain `gradle help` never trip it.
tasks.matching {
    it.name.contains("Release", ignoreCase = true) &&
        (it.name.contains("package", ignoreCase = true) || it.name.contains("bundle", ignoreCase = true))
}.configureEach {
    if (!releaseSigningReady) {
        doFirst {
            throw GradleException(
                "release signing inputs absent: create android/key.properties " +
                    "(storeFile/storePassword/keyAlias/keyPassword — gitignored) " +
                    "or let CI write it from secrets; see docs/ci/setup.md",
            )
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
