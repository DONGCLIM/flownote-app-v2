// Firebase 플랫폼별 초기화 설정.
//
// 🔴 왜 이 파일이 필요한가
//
// Android 는 `android/app/google-services.json` 을 Gradle 플러그인이 읽어서
// 빌드 시점에 네이티브 리소스로 심어 준다. 그래서 `Firebase.initializeApp()`
// 을 인자 없이 불러도 동작한다.
//
// **웹에는 그 메커니즘이 아예 없다.** 브라우저는 google-services.json 을
// 읽을 방법이 없으므로, 설정값을 Dart 코드에 직접 담아 넘겨야 한다.
// 이걸 빼먹으면 웹에서 이런 오류가 난다:
//
//   [Firebase.initializeApp] Null check operator used on a null value
//
// (실제로 첫 웹 빌드에서 로그인 화면에 이 배너가 그대로 떴다.)
//
// 🔴 apiKey 를 코드에 넣어도 되는가 → 된다.
//
// Firebase 웹 apiKey 는 비밀값이 아니다. 공식 문서가 명시하고 있고, 어떤
// 웹 앱이든 브라우저 번들에 그대로 노출된다. 실제 보호는 apiKey 가 아니라
//   - Firestore / Storage 보안 규칙
//   - Authentication → 승인된 도메인 (다른 도메인에서 로그인 차단)
// 이 담당한다. 그래서 이 파일은 gitignore 대상이 아니다.
//
// 이 값들은 손으로 적은 게 아니라
//   firebase apps:sdkconfig WEB 1:250664220370:web:fa701fbfc559a8886adf0b
// 출력을 그대로 옮긴 것이다.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// 현재 플랫폼에 맞는 설정.
  ///
  /// Android / iOS 는 네이티브 설정 파일이 이미 동작하고 있으므로 굳이
  /// 여기서 덮어쓰지 않는다. 잘 돌아가는 걸 건드리면 새 버그만 생긴다.
  /// → 네이티브에서는 `null` 을 돌려주고, 호출부에서
  ///   `Firebase.initializeApp(options: ...)` 대신 인자 없는 호출로 빠진다.
  static FirebaseOptions? get currentPlatformOrNull {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return null; // google-services.json / GoogleService-Info.plist 사용
      default:
        return null;
    }
  }

  /// 웹 앱 설정. Firebase 콘솔 > 프로젝트 설정 > 내 앱 > FlowNote Web.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBYgo_CZzp-Q7_TPXgYhEyl62bMLs9Zvw8',
    appId: '1:250664220370:web:fa701fbfc559a8886adf0b',
    messagingSenderId: '250664220370',
    projectId: 'flownote-404ef',
    authDomain: 'flownote-404ef.firebaseapp.com',
    storageBucket: 'flownote-404ef.firebasestorage.app',
    measurementId: 'G-TYWWE4NBGK',
  );
}
