import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// A standalone synthetic device test must never use the billing application's ID.
val faceFixtureBuild = (project.findProperty("dart-defines") as? String)
    ?.split(",")?.filter { it.isNotBlank() }
    ?.map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    ?.contains("NUBIBILL_FACE_FIXTURE=true") == true
val faceFixtureTarget = project.findProperty("target")?.toString()
    ?.substringAfterLast('/') == "face_attendance_device_fixture_main.dart"
check(faceFixtureBuild == faceFixtureTarget) {
    "The synthetic face fixture requires both its standalone target and NUBIBILL_FACE_FIXTURE=true."
}

android {
    namespace = "com.example.testflutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.testflutter"
        manifestPlaceholders["applicationLabel"] = if (faceFixtureBuild) "NubiBill Storage Tests" else "testflutter"
        if (faceFixtureBuild) {
            applicationIdSuffix = ".attendancefixture"
            versionNameSuffix = "-synthetic-fixture"
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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
}


dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.18.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
