import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

android {
    namespace = "com.example.my_new_diary"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // 【修正1】: 在这里添加签名配置代码块
    signingConfigs {
        create("release") {
            // 这些getenv方法会从Codemagic的环境变量中读取您上传的密钥信息
            val configuredPath = keystoreProperties.getProperty("storeFile")
            if (configuredPath != null) storeFile = rootProject.file(configuredPath)
            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
        }
    }

    defaultConfig {
        applicationId = "com.huajianwu.shiguangdiary.v2"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // 【修正2】: 将签名配置指向我们刚刚创建的 "release" 配置
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // VVV 3. 在这里添加 Desugaring 库的依赖 VVV
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "androidx.core" && requested.name == "core-ktx") {
            useVersion("1.9.0")
            because("Force specific version to resolve conflict")
        }

        // 如果发现其他冲突，可以按下面的格式继续添加
        // if (requested.group == "group.name" && requested.name == "library-name") {
        //     useVersion("version.number")
        //     because("Reason for forcing version")
        // }
    }
}
