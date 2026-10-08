import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "org.soqu.soqushield"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "org.soqu.soqushield"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Release builds MUST be release-signed. The old fallback silently
            // produced debug-signed "release" APKs when key.properties was
            // missing; a release build fails instead (the check below, on the
            // task graph). A debug build, `gradlew tasks` and an IDE sync need
            // no keystore, so a fresh clone can run them.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// Without the keystore, a build that packages the release variant stops
// before its first task runs. The task graph is the test, not the requested
// task names: `clean assembleDebug` names no debug task in `clean`, and an
// IDE sync or `gradlew tasks` names none at all. The test is the packaging
// tasks of the release variant, since `clean` itself pulls in the variant's
// native-build clean, which packages nothing.
if (!keystorePropertiesFile.exists()) {
    val packaging = listOf("assemble", "bundle", "package", "sign", "install")
    gradle.taskGraph.whenReady {
        val release = allTasks.map { it.name }.distinct().filter { name ->
            name.contains("Release") && packaging.any { name.startsWith(it) }
        }
        if (release.isNotEmpty()) {
            throw GradleException(
                "key.properties not found: release builds must be release-signed. " +
                "Provide android/key.properties. Release tasks in this build: $release")
        }
    }
}

flutter {
    source = "../.."
}
