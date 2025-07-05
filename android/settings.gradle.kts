// file: android/settings.gradle.kts

pluginManagement {
    repositories {
        // 只保留官方仓库
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

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // 只保留官方仓库
        google()
        mavenCentral()
    }
}