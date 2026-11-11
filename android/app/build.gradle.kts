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

// 16 KB page-size fix. shared_preferences_android pins androidx.datastore 1.2.0,
// whose libdatastore_shared_counter.so ends its GNU_RELRO segment at 0xd000 on
// arm64-v8a and on x86_64. That is not a 16 KB boundary, so Play flags it as a
// crash risk on 16 KB devices. DataStore 1.3.0 ends RELRO at 0xc000 on both.
// This overrides the plugin's transitive pin without forking it.
//
// Before an upload, read the .so out of the rebuilt bundle and check it with
// `readelf -l`: for each 64-bit ABI, GNU_RELRO's p_vaddr + p_memsz must be a
// multiple of 0x4000. Do not check LOAD p_align instead. It is 0x4000 in 1.2.0
// as well, so it accepts the broken library. The version pin is not an
// official guarantee, so measure the binary that is about to ship.
configurations.all {
    resolutionStrategy {
        force(
            "androidx.datastore:datastore:1.3.0",
            "androidx.datastore:datastore-preferences:1.3.0",
            "androidx.datastore:datastore-core:1.3.0",
            "androidx.datastore:datastore-core-android:1.3.0",
        )
    }
}

flutter {
    source = "../.."
}
