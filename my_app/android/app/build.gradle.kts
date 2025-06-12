plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.my_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Java 8+ API desugaring support
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.my_app"
        // 안드로이드 7.1.2 (API 25) 호환성을 위한 설정
        minSdk = 25  // 안드로이드 7.1.2 지원
        targetSdk = 34  // 최신 타겟 SDK 유지
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // 멀티덱스 지원 (안드로이드 7.1.2에서 필요할 수 있음)
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
    // WebView 호환성 문제를 해결하기 위한 설정
    packagingOptions {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

// 안드로이드 7.1.2 호환성을 위한 의존성 설정
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    
    // 멀티덱스 지원 (안드로이드 7.1.2에서 필요)
    implementation("androidx.multidex:multidex:2.0.1")
    
    // WebView 지원을 위한 호환성 의존성 (낮은 버전 사용)
    implementation("androidx.webkit:webkit:1.6.1")  // API 25 호환
    implementation("androidx.browser:browser:1.5.0")  // API 25 호환
    
    // XHApi.jar 라이브러리 추가
    implementation(files("libs/XHApi.jar"))
}

flutter {
    source = "../.."
}
