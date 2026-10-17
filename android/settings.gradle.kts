// Fix for AGP AndroidLocationsException when both ANDROID_PREFS_ROOT and ANDROID_USER_HOME are set in environment
try {
    val processEnvClass = Class.forName("java.lang.ProcessEnvironment")
    val unsafeClass = Class.forName("sun.misc.Unsafe")
    val unsafeField = unsafeClass.getDeclaredField("theUnsafe")
    unsafeField.isAccessible = true
    val unsafe = unsafeField.get(null)

    val longType = java.lang.Long.TYPE
    val staticFieldBaseMethod = unsafeClass.getMethod("staticFieldBase", java.lang.reflect.Field::class.java)
    val staticFieldOffsetMethod = unsafeClass.getMethod("staticFieldOffset", java.lang.reflect.Field::class.java)
    val getObjectMethod = unsafeClass.getMethod("getObject", Any::class.java, longType)

    val envField = processEnvClass.getDeclaredField("theEnvironment")
    val base = staticFieldBaseMethod.invoke(unsafe, envField)
    val offset = staticFieldOffsetMethod.invoke(unsafe, envField) as Long
    @Suppress("UNCHECKED_CAST")
    val envMap = getObjectMethod.invoke(unsafe, base, offset) as? MutableMap<String, String>
    val removed = envMap?.remove("ANDROID_PREFS_ROOT")
    println("WAVELY_GRADLE_FIX: Removed ANDROID_PREFS_ROOT: $removed")
} catch (e: Throwable) {
    println("WAVELY_GRADLE_FIX_ERROR: ${e.javaClass.name}: ${e.message}")
}

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
