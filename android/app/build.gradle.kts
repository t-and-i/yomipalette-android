import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play builds must opt in explicitly; GitHub test APKs keep debug signing.
val playRelease = providers.gradleProperty("PLAY_RELEASE").orNull == "true"
val playSigning = Properties()
gradle.taskGraph.whenReady {
    if (!playRelease && allTasks.any { it.project == project && it.name == "bundleRelease" }) {
        throw GradleException("Release AABs require the upload key. Use scripts/build-play.ps1.")
    }
}
if (playRelease) {
    val propertiesPath = providers.gradleProperty("PLAY_SIGNING_PROPERTIES").orNull
        ?: throw GradleException("Play signing is not configured. Use scripts/build-play.ps1.")
    val propertiesFile = file(propertiesPath)
    if (!propertiesFile.isFile) {
        throw GradleException("Play signing properties file does not exist.")
    }
    propertiesFile.reader(Charsets.UTF_8).use { playSigning.load(it) }
    for (name in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        if (playSigning.getProperty(name).isNullOrBlank()) {
            throw GradleException("Missing Play signing property: $name")
        }
    }
    if (!file(playSigning.getProperty("storeFile")).isFile) {
        throw GradleException("Play upload keystore does not exist.")
    }
}

android {
    namespace = "com.tjsongwei.tts_text_mp3_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tjsongwei.tts_text_mp3_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (playRelease) {
            create("playUpload") {
                storeFile = file(playSigning.getProperty("storeFile"))
                storePassword = playSigning.getProperty("storePassword")
                keyAlias = playSigning.getProperty("keyAlias")
                keyPassword = playSigning.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (playRelease) "playUpload" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
