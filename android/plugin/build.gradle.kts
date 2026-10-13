plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

// The Godot library the plugin compiles against and the Play Games SDK are compileOnly: the game's Godot build supplies the
// engine, and the export plugin adds the games-v2 dependency to the game's Gradle build (so versions are not baked into the AAR).
android {
    namespace = "com.syntaxcircus.godot.gamesservices"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    compileOnly("org.godotengine:godot:4.7.2.stable")
    compileOnly("com.google.android.gms:play-services-games-v2:22.1.0")
    testImplementation("junit:junit:4.13.2")
}
