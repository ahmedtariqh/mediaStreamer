allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Use the root toolchain for Flutter plugins as well. Otherwise each plugin
// resolves/instruments a separate AGP/Kotlin version, wasting memory and making
// builds dependent on conflicting plugin classpaths.
subprojects {
    buildscript.configurations.configureEach {
        resolutionStrategy.force(
            "com.android.tools.build:gradle:8.11.1",
            "org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20",
        )
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
        val target = project.extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
            ?.compileOptions?.targetCompatibility?.toString()
        if (target != null) {
            compilerOptions.jvmTarget.set(
                when (target) {
                    "1.8" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                    "11" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                    else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                }
            )
        } else {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}





tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
