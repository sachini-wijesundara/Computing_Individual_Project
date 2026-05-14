plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.example.virtual_tryon_makeup"
        compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.virtual_tryon_makeup"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
            targetSdk = 36
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

flutter {
    source = "../.."
}

configurations.configureEach {
    resolutionStrategy.dependencySubstitution {
        // MediaPipe 0.10.14+ pulls LiteRT (`com.google.ai.edge.litert`), which re-exports the same
        // `org.tensorflow.lite.*` types as classic `org.tensorflow:tensorflow-lite` → duplicate classes.
        substitute(module("com.google.ai.edge.litert:litert"))
            .using(module("org.tensorflow:tensorflow-lite:2.14.0"))
            .because("Use single TFLite runtime with tflite_flutter + nail Interpreter")
        substitute(module("com.google.ai.edge.litert:litert-api"))
            .using(module("org.tensorflow:tensorflow-lite-api:2.14.0"))
            .because("Use single TFLite API artifact; avoid LiteRT / TFLite duplicate classes")
    }
}

dependencies {
    // MediaPipe — FaceLandmarker, ImageSegmenter, etc.
    implementation("com.google.mediapipe:tasks-vision:0.10.14")

    // CameraX — ImageProxy, planes, ImageAnalysis, PreviewView, ProcessCameraProvider
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
    implementation("androidx.camera:camera-view:1.3.4")

    // Lifecycle
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")

    // TensorFlow Lite — nail segmentation (`Interpreter`); same version as substitution target above.
    implementation("org.tensorflow:tensorflow-lite:2.14.0")
    implementation("org.tensorflow:tensorflow-lite-support:0.4.4")
}
