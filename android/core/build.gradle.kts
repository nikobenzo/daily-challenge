// The platform-neutral port of ChallengeCore and ChallengeSyncKit: rules, wire format,
// the local store and queue, sync and auth. Plain JVM, so its tests run without a device.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

// The app runs this code on Android 10, whose Java library is roughly Java 8's. Compiling the
// main sources against the Java 8 API makes a newer call (such as LocalDate.ofInstant) a build
// error instead of a crash on the phone. Tests run on the Mac and may use any API.
tasks.named<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>("compileKotlin") {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
        freeCompilerArgs.add("-Xjdk-release=1.8")
    }
}
tasks.named<JavaCompile>("compileJava") { options.release.set(8) }

dependencies {
    implementation(libs.kotlinx.coroutines.core)
    api(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
}

tasks.test {
    // The shared parity vectors live at the repository root, next to the Swift tests that read them.
    systemProperty("parityVectors", rootProject.file("../test-vectors").absolutePath)
    testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}
