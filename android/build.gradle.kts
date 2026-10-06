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
subprojects {
    project.evaluationDependsOn(":app")
}

// --- Compatibility shims for legacy plugin Android modules --------------------
// Some plugin packages still ship Android modules written for AGP 7 / Gradle 7.
// The worst offender is on_audio_query_android 1.1.0 -- still the latest release
// -- which fails on AGP 9 in three separate ways. Rather than editing the pub
// cache (wiped by `pub get` / `pub cache repair`), normalise them here.

// 1. AGP 8+ requires every Android library module to declare a `namespace`. These
//    plugins omit it from build.gradle and only set `package` in their
//    AndroidManifest.xml, which AGP 9 rejects while creating the library variant:
//      "Namespace not specified. Specify a namespace in the module's build file"
//    Backfill from the module's own `group`, which they set to their package name.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            if (namespace == null) {
                namespace = project.group.toString()
            }
            // 2. These modules pin no Java target, so javac falls back to AGP's
            //    default (11) while kotlinc falls back to the toolchain JVM (25),
            //    failing the build with "Inconsistent JVM Target Compatibility
            //    Between Java and Kotlin Tasks". Pin both to 17, the level :app uses.
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

// 3. They compile against an old compileSdk (on_audio_query_android hardcodes 33)
//    while their androidx dependencies require 34+. This one has to be corrected
//    after the module's build script has run, because a plugin's own
//    `android { compileSdkVersion 33 }` block executes *after* the plugin is
//    applied and would otherwise overwrite anything set from plugins.withId.
//    Registering from here is deliberate: the root script is evaluated before the
//    plugin modules, so these hooks run ahead of AGP's own afterEvaluate and
//    still take effect. :app is skipped because evaluationDependsOn(":app") above
//    has already evaluated it (and it is an application module, not a library).
val flutterCompileSdk = 36

subprojects {
    if (!state.executed) {
        afterEvaluate {
            plugins.withId("com.android.library") {
                extensions.configure<com.android.build.gradle.LibraryExtension> {
                    if (compileSdk != flutterCompileSdk) {
                        compileSdk = flutterCompileSdk
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
