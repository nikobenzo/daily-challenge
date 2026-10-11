import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

/**
 * The public Supabase configuration comes from the repository's gitignored `.env.local`
 * at build time, as the iPhone and Mac builds read it; nothing is committed. Debug builds
 * without it still build and show "Configuration unavailable"; release builds refuse.
 */
fun envLocal(): Map<String, String> {
    val file = rootProject.file("../.env.local")
    if (!file.exists()) return emptyMap()
    return file.readLines().map { it.trim() }
        .filter { it.isNotEmpty() && !it.startsWith("#") && it.contains('=') }
        .associate { line ->
            val (key, value) = line.split('=', limit = 2)
            key.trim() to value.trim().trim('"', '\'')
        }
}

val env = envLocal()
val supabaseUrl = env["SUPABASE_URL"].orEmpty()
val supabaseKey = env["SUPABASE_PUBLISHABLE_KEY"].orEmpty()
val configured = supabaseUrl.startsWith("https://") && supabaseKey.startsWith("sb_publishable_")
if (!configured && gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }) {
    throw GradleException("Release builds need SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in .env.local (docs/android.md).")
}

fun quoted(value: String) = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

android {
    namespace = "app.dailychallenge.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.dailychallenge.android"
        minSdk = 29
        targetSdk = 36
        // Raise versionCode for every build uploaded to Google Play.
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "SUPABASE_URL", quoted(supabaseUrl))
        buildConfigField("String", "SUPABASE_PUBLISHABLE_KEY", quoted(supabaseKey))
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // Also checks `core` against minSdk: it is plain JVM code, so a newer Java API would
    // compile but crash on older Android versions.
    lint { checkDependencies = true }

    packaging {
        resources.excludes += setOf("/META-INF/{AL2.0,LGPL2.1}", "/META-INF/versions/9/previous-compilation-data.bin")
    }
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.work.runtime)
    implementation(libs.kotlinx.coroutines.android)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(libs.androidx.test.runner)
}
