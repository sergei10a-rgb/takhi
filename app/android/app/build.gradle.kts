import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real release signing (Task 10 Step 11) -- `android/key.properties` and
// the `.jks` keystore it points at are both gitignored (Step 12); a
// contributor who hasn't generated their own keystore still gets a
// working (debug-signed) release build below rather than a hard error.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Drop the LiteRT GPU delegate.
//
// `tflite_flutter` pulls in both `litert` and `litert-gpu`. The portrait
// face check runs ONE 128x128 BlazeFace inference, and only when a driver
// edits their profile -- a few milliseconds of CPU work that a GPU delegate
// cannot meaningfully speed up and would spend longer initialising than
// running. Shipping it costs 2.5MB on arm64 and 6.7MB across all three
// ABIs, on an app aimed at cheap handsets over Mongolian mobile data.
//
// Excluded at the dependency level rather than stripped from the packaged
// APK with a `packaging { jniLibs { excludes } }` rule: excluding the
// artifact means the native library is never downloaded or built into the
// merge at all, whereas a packaging exclude carries it the whole way and
// deletes it at the end. It also fails loudly -- if some future code path
// really does ask for the GPU delegate, it will not link, instead of
// silently falling back at runtime on a driver's phone.
configurations.all {
    exclude(group = "com.google.ai.edge.litert", module = "litert-gpu")
}

android {
    namespace = "mn.takhi.takhi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "mn.takhi.takhi"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
