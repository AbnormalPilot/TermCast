plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.termcast.android"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.termcast.android"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.11"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.04.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.camera:camera-camera2:1.3.3")
    implementation("androidx.camera:camera-lifecycle:1.3.3")
    implementation("androidx.camera:camera-view:1.3.3")
    implementation("com.google.mlkit:barcode-scanning:17.2.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    implementation("com.google.accompanist:accompanist-permissions:0.34.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.0")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
}
