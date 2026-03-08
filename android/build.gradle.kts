allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val pName = project.name
        compilerOptions.jvmTarget.set(
            when (pName) {
                "receive_sharing_intent" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                "bonsoir_android" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
            }
        )
    }
}





tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
