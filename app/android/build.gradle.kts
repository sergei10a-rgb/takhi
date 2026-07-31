allprojects {
    repositories {
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
// Pin every plugin module to one JVM target: Java 17 and Kotlin 17.
//
// Gradle 9 + Kotlin 2.3 compile plugin Kotlin at a much newer target than
// the plugins themselves declare for Java, and AGP refuses the mismatch:
//
//   Inconsistent JVM-target compatibility detected for tasks
//   'compileReleaseJavaWithJavac' (1.8) and 'compileReleaseKotlin' (17)
//
// Two plugins hit this -- `tflite_flutter` (11 vs 21), which the driver
// portrait face check needs, and `flutter_webrtc` (1.8 vs 17), which the
// in-app calling needs. Both are third-party, so neither can be fixed at
// source. 17 matches what `app/build.gradle.kts` already sets for itself,
// so this states one answer for the whole build instead of a per-plugin
// patch that the next dependency reopens.
//
// The Java half is set on the ANDROID EXTENSION, not on the `JavaCompile`
// tasks. Setting the tasks looks like it works and does not: AGP derives
// its own `compileOptions` onto them afterwards, so `flutter_webrtc` came
// back at 1.8 even with every JavaCompile task pinned to 17. The extension
// is where AGP actually reads the value from.
//
// Reached through `withGroovyBuilder` rather than a typed AGP class so this
// file does not need the Android Gradle Plugin on its own compile
// classpath, and so an AGP upgrade that moves those classes cannot break
// the root build script.
subprojects {
    // The Java half, set on the ANDROID EXTENSION in `afterEvaluate`.
    //
    // Timing is the whole difficulty, and three earlier attempts failed on
    // it, so the dead ends are written down rather than left to be
    // rediscovered:
    //
    //   * From a `plugins.withId` callback -- runs BEFORE the plugin's own
    //     build script, which then sets 1.8 straight over the top.
    //   * On the `JavaCompile` tasks from inside `subprojects {}` -- runs
    //     before AGP derives `compileOptions` onto those same tasks, so
    //     AGP wins and `flutter_webrtc` still compiled at 1.8.
    //   * On the `JavaCompile` tasks at `projectsEvaluated` -- late enough
    //     to stick, and it breaks the build a different way: assigning
    //     source/targetCompatibility directly drops Android's bootclasspath,
    //     so `android.os.Build` stops resolving and 100 errors come out of
    //     `flutter_secure_storage`.
    //
    // `afterEvaluate` is the one hook that lands in the gap: after the
    // plugin's script has had its say, before AGP reads the extension to
    // configure its tasks, and without touching the tasks at all.
    val pinJavaTarget = {
        extensions.findByName("android")?.withGroovyBuilder {
            "compileOptions" {
                setProperty("sourceCompatibility", JavaVersion.VERSION_17)
                setProperty("targetCompatibility", JavaVersion.VERSION_17)
            }
        }
        Unit
    }
    // `evaluationDependsOn(":app")` below means some project may already be
    // evaluated by the time this block reaches it, and registering an
    // `afterEvaluate` on an evaluated project is a hard Gradle error.
    if (state.executed) pinJavaTarget() else afterEvaluate { pinJavaTarget() }

    // Lazy, so it reaches tasks the Android plugin registers later.
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>()
        .configureEach {
            compilerOptions.jvmTarget.set(
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
            )
        }

    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
