plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    //id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.my_new_diary"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.my_new_diary"
        // VVV 1. 确保 minSdkVersion 不低于 22 VVV
        minSdkVersion(24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // VVV 2. 在这里添加对 .aar 文件的引用 VVV
    // 请确保文件名与您放入 libs 文件夹的文件名完全一致
    implementation(files("libs/bdasr_V3_20250507_b610f20.jar"))
}

configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "androidx.core" && requested.name == "core-ktx") {
            useVersion("1.9.0")
            because("Force specific version to resolve conflict")
        }
    }
}