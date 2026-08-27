// ✅ CRITICAL: Required imports for signing configuration
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// ══════════════════════════════════════════════════════════════
// 카카오 네이티브 앱 키 로드
//
// AndroidManifest 의 리다이렉트 스킴(kakao{키}://oauth)은 **빌드 시점에**
// 값이 확정돼야 한다. dart-define 은 Dart 코드에만 전달되므로 매니페스트에는
// 닿지 않는다. 그래서 Gradle 이 secrets/kakao.json 을 직접 읽는다.
// (Dart 쪽과 같은 파일을 쓰므로 키가 두 곳으로 갈라지지 않는다)
//
// 키가 없으면 실제로 쓰이지 않는 더미 스킴을 넣는다. 빈 문자열을 넣으면
// 매니페스트 병합이 실패해서 빌드 자체가 깨진다.
// ══════════════════════════════════════════════════════════════
val kakaoSecretsFile = rootProject.file("../secrets/kakao.json")
val kakaoNativeAppKey: String = if (kakaoSecretsFile.exists()) {
    Regex("\"KAKAO_NATIVE_APP_KEY\"\\s*:\\s*\"([^\"]*)\"")
        .find(kakaoSecretsFile.readText())
        ?.groupValues?.get(1)
        ?.trim()
        .orEmpty()
} else {
    ""
}
val kakaoScheme: String =
    if (kakaoNativeAppKey.length >= 20) "kakao$kakaoNativeAppKey" else "kakao-not-configured"
println("==> Kakao scheme: $kakaoScheme")

// key.properties 로드
val keyPropertiesFile = rootProject.file("../android/key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.flownote.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            storeFile = file(keyProperties["storeFile"] as String)
            storePassword = keyProperties["storePassword"] as String
            keyAlias = keyProperties["keyAlias"] as String
            keyPassword = keyProperties["keyPassword"] as String
        }
    }

    defaultConfig {
        applicationId = "com.flownote.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // AndroidManifest 의 ${KAKAO_SCHEME} 를 채운다.
        manifestPlaceholders["KAKAO_SCHEME"] = kakaoScheme
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation(platform("com.google.firebase:firebase-bom:33.5.1"))
}
