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
// The same test the app applies at launch (SupabaseConfiguration.from): the .env.example
// placeholder ("your-project") counts as missing.
val configured = supabaseUrl.startsWith("https://") && "your-project" !in supabaseUrl &&
    supabaseKey.startsWith("sb_publishable_")
if (!configured) {
    if (gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }) {
        throw GradleException("Release builds need SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in .env.local (docs/android.md).")
    }
    logger.warn("warning: ${rootProject.file("../.env.local")} has no usable SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY " +
        "(missing or the .env.example placeholder); this Debug build opens on \"Configuration unavailable\".")
}

fun quoted(value: String) = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

/**
 * Release signing with the owner's Google Play upload key, which never enters the repository
 * (scripts/android-upload-key.sh creates it). The keystore path, alias and password come from
 * Gradle properties (~/.gradle/gradle.properties) or environment variables of the same names;
 * a release build without them refuses rather than producing an unsigned or debug-signed file.
 */
fun signingValue(name: String): String? =
    (providers.gradleProperty(name).orNull ?: providers.environmentVariable(name).orNull)?.takeIf { it.isNotBlank() }
val uploadStoreFile = signingValue("DC_UPLOAD_STORE_FILE")?.let { file(it.replaceFirst(Regex("^~(?=/)"), System.getProperty("user.home"))) }
val uploadStorePassword = signingValue("DC_UPLOAD_STORE_PASSWORD")
val uploadKeyAlias = signingValue("DC_UPLOAD_KEY_ALIAS")
val uploadSigned = uploadStoreFile != null && uploadStorePassword != null && uploadKeyAlias != null
gradle.taskGraph.whenReady {
    val releasePackaging = allTasks.any { it.project == project && it.name in setOf("packageRelease", "signReleaseBundle") }
    if (!releasePackaging) return@whenReady
    if (!uploadSigned) {
        throw GradleException("Release builds need the upload key: set DC_UPLOAD_STORE_FILE, DC_UPLOAD_STORE_PASSWORD " +
            "and DC_UPLOAD_KEY_ALIAS in ~/.gradle/gradle.properties or the environment (docs/play-release.md).")
    }
    if (!uploadStoreFile!!.isFile) throw GradleException("DC_UPLOAD_STORE_FILE does not exist: $uploadStoreFile")
    if (uploadStoreFile.canonicalPath.startsWith(rootProject.file("..").canonicalPath + File.separator)) {
        throw GradleException("The upload keystore must live outside the repository, not at $uploadStoreFile.")
    }
}

android {
    namespace = "app.dailychallenge.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.dailychallenge.android"
        minSdk = 29
        targetSdk = 36
        // versionCode counts uploads: raise it by one for every bundle uploaded to any Play
        // track, never reuse or lower it. versionName is what people see (docs/play-release.md).
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "SUPABASE_URL", quoted(supabaseUrl))
        buildConfigField("String", "SUPABASE_PUBLISHABLE_KEY", quoted(supabaseKey))
    }

    signingConfigs {
        if (uploadSigned) create("upload") {
            storeFile = uploadStoreFile
            storePassword = uploadStorePassword
            keyAlias = uploadKeyAlias
            keyPassword = signingValue("DC_UPLOAD_KEY_PASSWORD") ?: uploadStorePassword
        }
    }

    buildTypes {
        release {
            if (uploadSigned) signingConfig = signingConfigs.getByName("upload")
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
    implementation(libs.androidx.glance.appwidget)
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
    androidTestImplementation(libs.androidx.glance.appwidget.testing)
}
