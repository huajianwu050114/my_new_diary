allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    val sourceRoot = project.projectDir.toPath().root
    val outputRoot = newSubprojectBuildDir.asFile.toPath().root
    if (sourceRoot != null && outputRoot != null && sourceRoot != outputRoot) {
        val workspaceId = rootProject.rootDir.absolutePath.hashCode().toUInt().toString(16)
        val temporaryPluginBuild = file(
            "${System.getProperty("java.io.tmpdir")}/new_diary_gradle/$workspaceId/${project.name}",
        )
        project.layout.buildDirectory.set(temporaryPluginBuild)
    } else {
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
