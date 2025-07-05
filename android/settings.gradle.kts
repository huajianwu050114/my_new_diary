// file: android/settings.gradle.kts

import org.gradle.api.initialization.resolve.RepositoriesMode
import java.util.Properties
import java.io.File
import java.io.FileInputStream

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.3.2" apply false
    kotlin("android") version "1.9.22" apply false
}

include(":app")

// VVVV  这是我们之前遗漏掉的最关键的部分 VVVV
val localPropertiesFile = File(rootProject.projectDir, "local.properties")
val properties = Properties()

if (localPropertiesFile.exists()) {
    FileInputStream(localPropertiesFile).use { fis ->
        properties.load(fis)
    }
}

val flutterSdkPath = properties.getProperty("flutter.sdk")
if (flutterSdkPath == null) {
    throw GradleException("Flutter SDK not found. Define location with flutter.sdk in the local.properties file.")
}

apply(from = File(flutterSdkPath, "packages/flutter_tools/gradle/app_plugin_loader.gradle"))
// ^^^^ 这行代码会“注入”Flutter的插件，解决“找不到”的问题 ^^^^


dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}