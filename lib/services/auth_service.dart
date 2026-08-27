import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'firebase_status.dart';
import 'kakao_config.dart';
// 웹 카카오 로그인 (SDK 우회 · 직접 OAuth).
// 네이티브에서는 stub 이 들어가므로 조건부 import 로 안전하다.
import 'kakao_web_login.dart';

/// Firebase Authentication 래퍼.
///
/// 기존 `AuthProvider` 는 비밀번호를 **SharedPreferences 에 평문 저장**하고
/// `Future.delayed` 로 로그인을 흉내내는 로컬 가짜 인증이었다.
/// 이 서비스로 실제 서버 인증(Firebase Auth)으로 교체한다.
///
/// - 비밀번호는 Firebase 가 단방향 암호화 보관 → 앱/기기에 절대 저장하지 않음
/// - 계정이 서버에 있으므로 기기를 바꿔도 로그인 가능
/// - 구글 로그인 + 애플 로그인 지원
///
/// Firebase 가 초기화되지 않은 환경(웹 프리뷰 등)에서도 앱이 죽지 않도록
/// 모든 진입점에서 `isAvailable` 을 확인한다.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  FirebaseAuth? _auth;
  bool _initialized = false;

  /// Firebase Auth 사용 가능 여부. false 면 로그인 기능 전체가 비활성.
  bool get isAvailable => _initialized && _auth != null;

  /// `Firebase.initializeApp()` 이후에 호출한다.
  void init() {
    if (_initialized) return;
    try {
      _auth = FirebaseAuth.instance;
      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] 초기화 실패: $e');
    }
  }

  User? get currentUser => isAvailable ? _auth!.currentUser : null;
  String? get uid => currentUser?.uid;
  bool get isSignedIn => currentUser != null;

  /// 로그인 상태 변화 스트림 (앱 시작 시 자동 복원에도 사용)
  Stream<User?> get authStateChanges =>
      isAvailable ? _auth!.authStateChanges() : const Stream<User?>.empty();

  // ──────────────────────────────────────────────────────────
  // 이메일 / 비밀번호
  // ──────────────────────────────────────────────────────────

  /// 회원가입. 성공 시 `User`, 실패 시 [AuthFailure] 를 throw.
  Future<User> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _requireAvailable();
    try {
      // 서버 응답이 없으면 스피너가 영구히 돌아 "아무 일도 안 일어남" 이 된다.
      final cred = await _auth!
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          )
          .timeout(_authTimeout);
      final user = cred.user;
      if (user == null) throw const AuthFailure('계정 생성에 실패했습니다.');

      // 표시 이름 반영 (실패해도 가입 자체는 성공으로 본다)
      try {
        await user.updateDisplayName(displayName.trim());
        await user.reload();
      } catch (_) {}

      return _auth!.currentUser ?? user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageOf(e), code: e.code);
    } on TimeoutException {
      throw const AuthFailure(_timeoutMessage, code: 'timeout');
    }
  }

  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _requireAvailable();
    try {
      // 타임아웃이 없으면 네트워크가 막힌 환경에서 영구 대기 → 버튼을 눌러도
      // 스피너만 돌고 아무 문구도 뜨지 않는다. (로그인 무반응의 원인)
      final cred = await _auth!
          .signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          )
          .timeout(_authTimeout);
      final user = cred.user;
      if (user == null) throw const AuthFailure('로그인에 실패했습니다.');
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageOf(e), code: e.code);
    } on TimeoutException {
      throw const AuthFailure(_timeoutMessage, code: 'timeout');
    }
  }

  /// 비밀번호 재설정 메일 발송.
  Future<void> sendPasswordReset(String email) async {
    _requireAvailable();
    try {
      await _auth!
          .sendPasswordResetEmail(email: email.trim())
          .timeout(_authTimeout);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageOf(e), code: e.code);
    } on TimeoutException {
      throw const AuthFailure(_timeoutMessage, code: 'timeout');
    }
  }

  // ──────────────────────────────────────────────────────────
  // 구글 로그인
  // ──────────────────────────────────────────────────────────

  /// 구글 계정으로 로그인/가입.
  ///
  /// 사용자가 구글 선택 창을 닫으면 [AuthCancelled] 를 throw 한다.
  Future<User> signInWithGoogle() async {
    _requireAvailable();

    // ── 웹은 완전히 다른 경로로 간다 ─────────────────────────────
    //
    // 🔴 `google_sign_in` 은 웹에서 그냥 쓸 수 없다.
    //    `google_sign_in_web` 은 `web/index.html` 에
    //      <meta name="google-signin-client_id" content="...">
    //    가 있어야 동작한다(패키지 README 명시). 우리 index.html 에는
    //    그 태그가 없었고, 그래서 사장님 화면에 이렇게 떴다:
    //      "구글 로그인 중 오류가 발생했어요. (minified:Pv)"
    //    `minified:Pv` 는 릴리즈 빌드에서 이름이 뭉개진 내부 예외 타입이라
    //    사용자도 우리도 원인을 알 수 없는 메시지였다.
    //
    // 🔴 meta 태그를 넣는 대신 `signInWithPopup` 을 쓴다.
    //    - meta 방식은 Google Cloud 콘솔에서 "승인된 JavaScript 원본"을
    //      도메인마다 따로 등록해야 한다(로컬 개발 포트까지).
    //    - `signInWithPopup` 은 Firebase Auth 가 자기 authDomain
    //      (flownote-404ef.firebaseapp.com) 으로 처리하므로, 이미 등록된
    //      "승인된 도메인" 설정만으로 끝난다. 관리 지점이 하나 줄어든다.
    if (kIsWeb) {
      try {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        final cred = await _auth!.signInWithPopup(provider);
        final user = cred.user;
        if (user == null) throw const AuthFailure('구글 로그인에 실패했습니다.');
        return user;
      } on FirebaseAuthException catch (e) {
        // 팝업 차단/사용자가 창을 닫음 → 실패가 아니라 취소로 다룬다.
        if (e.code == 'popup-closed-by-user' ||
            e.code == 'cancelled-popup-request' ||
            e.code == 'user-cancelled') {
          throw const AuthCancelled();
        }
        if (e.code == 'popup-blocked') {
          throw const AuthFailure(
              '브라우저가 로그인 창을 막았어요.\n주소창의 팝업 차단을 해제하고 다시 시도해 주세요.',
              code: 'popup-blocked');
        }
        throw AuthFailure(_messageOf(e), code: e.code);
      } on AuthCancelled {
        rethrow;
      } on AuthFailure {
        rethrow;
      } catch (e) {
        if (kDebugMode) debugPrint('[AuthService] 웹 구글 로그인 오류: $e');
        throw AuthFailure('구글 로그인 중 오류가 발생했어요.\n(${e.runtimeType})',
            code: 'google-web-unknown');
      }
    }

    try {
      // 이전 세션이 남아있으면 계정 선택 창이 안 뜨므로 먼저 정리
      final google = GoogleSignIn(scopes: const ['email', 'profile']);
      try {
        await google.signOut();
      } catch (_) {
        // 이전 세션이 없거나 정리에 실패해도 로그인 자체는 계속 진행한다.
      }

      final account = await google.signIn();
      if (account == null) throw const AuthCancelled();

      final gAuth = await account.authentication;
      if (gAuth.idToken == null && gAuth.accessToken == null) {
        throw const AuthFailure('구글 인증 토큰을 받지 못했습니다. 다시 시도해 주세요.');
      }

      final credential = GoogleAuthProvider.credential(
        idToken: gAuth.idToken,
        accessToken: gAuth.accessToken,
      );

      // 네트워크가 막히면 무한 대기가 되어 "아무 일도 안 일어남" 처럼 보인다.
      final cred = await _auth!
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 30));
      final user = cred.user;
      if (user == null) throw const AuthFailure('구글 로그인에 실패했습니다.');
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageOf(e), code: e.code);
    } on AuthCancelled {
      rethrow;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
          '구글 로그인 응답이 너무 늦어요.\n네트워크를 확인하고 다시 시도해 주세요.',
          code: 'timeout');
    } on PlatformException catch (e) {
      // google_sign_in 네이티브 예외.
      // 예전에는 원인을 감춘 채 "준비가 아직 안 됐어요" 만 띄워서
      // 사용자가 무엇을 고쳐야 할지 알 수 없었다. → 원인별로 안내한다.
      if (kDebugMode) {
        debugPrint('[AuthService] 구글 PlatformException ${e.code}: ${e.message}');
      }
      throw AuthFailure(_googleMessageOf(e.code), code: e.code);
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] 구글 로그인 오류: $e');
      // 최소한 원인을 화면에 남겨서 사용자가 그대로 알려줄 수 있게 한다.
      throw AuthFailure(
          '구글 로그인 중 오류가 발생했어요.\n(${e.runtimeType})',
          code: 'google-unknown');
    }
  }

  /// google_sign_in 플랫폼 오류 코드 → 사장님이 이해할 수 있는 안내.
  ///
  /// - `sign_in_failed` + `ApiException: 10` : SHA-1 지문 미등록 또는
  ///   google-services.json 이 지문 등록 전 버전
  /// - `sign_in_failed` + `ApiException: 12500` : Play 서비스 설정 문제
  /// - `network_error` : 네트워크
  static String _googleMessageOf(String code) {
    switch (code) {
      case 'sign_in_failed':
        return '구글 로그인 설정이 완료되지 않았어요.\n'
            'Firebase 콘솔에서 Google 로그인이 켜져 있는지 확인해 주세요.\n'
            '(코드 sign_in_failed)';
      case 'network_error':
        return '네트워크 연결을 확인해 주세요.';
      case 'sign_in_canceled':
        return '구글 로그인이 취소되었습니다.';
      default:
        return '구글 로그인에 실패했어요. ($code)';
    }
  }

  // ──────────────────────────────────────────────────────────
  // 애플 로그인
  // ──────────────────────────────────────────────────────────

  /// 애플 로그인을 이 기기에서 쓸 수 있는지.
  ///
  /// iOS/macOS 는 항상 true, 안드로이드는 웹 리다이렉트 방식이라
  /// serviceId 설정 없이는 불가하므로 false 로 둔다.
  bool get isAppleSignInSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  /// 리플레이 공격 방지용 nonce 생성.
  String _randomNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)])
        .join();
  }

  String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  /// 애플 계정으로 로그인/가입.
  ///
  /// 애플은 **최초 1회만** 이름과 이메일을 넘겨준다. 두 번째부터는 null 이므로
  /// 첫 로그인 때 받은 이름을 displayName 에 반드시 저장해 둔다.
  ///
  /// 사용자가 창을 닫으면 [AuthCancelled] 를 throw 한다.
  Future<User> signInWithApple() async {
    _requireAvailable();
    if (!isAppleSignInSupported) {
      throw const AuthFailure('애플 로그인은 아이폰에서만 사용할 수 있어요.');
    }
    try {
      final rawNonce = _randomNonce();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: _sha256(rawNonce),
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthFailure('애플 인증 토큰을 받지 못했습니다. 다시 시도해 주세요.');
      }

      final oauth = OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
        accessToken: credential.authorizationCode,
      );

      final cred = await _auth!.signInWithCredential(oauth);
      final user = cred.user;
      if (user == null) throw const AuthFailure('애플 로그인에 실패했습니다.');

      // 애플이 이름을 준 최초 로그인에서만 displayName 을 채운다.
      final given = credential.givenName?.trim() ?? '';
      final family = credential.familyName?.trim() ?? '';
      final appleName = '$family$given'.trim();
      final needsName =
          (user.displayName == null || user.displayName!.trim().isEmpty);
      if (needsName && appleName.isNotEmpty) {
        try {
          await user.updateDisplayName(appleName);
          await user.reload();
        } catch (_) {}
      }

      return _auth!.currentUser ?? user;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthCancelled();
      }
      if (kDebugMode) debugPrint('[AuthService] 애플 로그인 오류: $e');
      throw const AuthFailure('애플 로그인에 실패했습니다.\n다시 시도해 주세요.');
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageOf(e), code: e.code);
    } on AuthCancelled {
      rethrow;
    } on AuthFailure {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] 애플 로그인 오류: $e');
      throw const AuthFailure(
          '애플 로그인 준비가 아직 안 됐어요.\n이메일로 로그인해 주세요.');
    }
  }

  /// 새 사용자인지 판별 — 가입 직후 온보딩으로 보낼지 결정할 때 사용.
  bool isNewUser(UserCredential cred) =>
      cred.additionalUserInfo?.isNewUser ?? false;

  // ──────────────────────────────────────────────────────────
  // 로그아웃 / 탈퇴
  // ──────────────────────────────────────────────────────────

  Future<void> signOut() async {
    if (!isAvailable) return;
    // 웹에서는 `GoogleSignIn()` 자체를 만들지 않는다.
    // meta 태그가 없으면 생성 시점에 예외가 나고, 웹은 애초에
    // `signInWithPopup` 을 쓰므로 끊을 google_sign_in 세션이 없다.
    if (!kIsWeb) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
    }
    // 카카오로 들어온 계정이면 카카오 세션도 끊는다. 안 끊으면 다시
    // 로그인할 때 계정 선택 없이 이전 계정으로 바로 들어가 버린다.
    if (isKakaoAccount) await _signOutKakao();
    await _auth!.signOut();
  }

  /// 계정 삭제. 마지막 로그인이 오래되면 재인증이 필요하다.
  ///
  /// 재인증이 필요하면 [AuthReauthRequired] 를 throw 하므로 호출측에서
  /// 비밀번호를 다시 받거나 구글 재로그인 후 다시 호출해야 한다.
  Future<void> deleteAccount() async {
    _requireAvailable();
    final user = _auth!.currentUser;
    if (user == null) throw const AuthFailure('로그인 상태가 아닙니다.');
    final wasKakao = isKakaoAccount;
    try {
      await user.delete();
      // 🔴 카카오 계정은 Firebase 계정만 지우면 끝이 아니다.
      //    카카오 쪽에는 여전히 "이 앱에 연결됨" 상태가 남아서, 사용자가
      //    카카오 설정에서 직접 연결을 끊어야 한다. 탈퇴했는데 남의 서비스
      //    목록에 우리 앱이 계속 보이는 건 정보 처리 원칙에도 어긋난다.
      //    → 앱에서 연결까지 끊어준다.
      //    이미 Firebase 계정은 지워졌으므로 실패해도 탈퇴는 성공 처리한다.
      if (wasKakao) {
        try {
          await kakao.UserApi.instance.unlink();
        } catch (e) {
          if (kDebugMode) debugPrint('[AuthService] 카카오 연결 끊기 실패: $e');
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw const AuthReauthRequired();
      }
      throw AuthFailure(_messageOf(e), code: e.code);
    }
  }

  /// 탈퇴 전 재인증 (이메일 계정)
  Future<void> reauthenticateWithPassword(String password) async {
    _requireAvailable();
    final user = _auth!.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AuthFailure('로그인 상태가 아닙니다.');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageOf(e), code: e.code);
    }
  }

  /// 탈퇴 전 재인증 (구글 계정)
  Future<void> reauthenticateWithGoogle() async {
    _requireAvailable();
    final user = _auth!.currentUser;
    if (user == null) throw const AuthFailure('로그인 상태가 아닙니다.');
    try {
      // 웹은 로그인과 같은 팝업 경로를 쓴다. `google_sign_in` 을 쓰면
      // 탈퇴 마지막 단계에서 `minified:Pv` 로 막혀 계정을 지울 수 없다.
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        await user.reauthenticateWithPopup(provider);
        return;
      }
      final google = GoogleSignIn(scopes: const ['email', 'profile']);
      await google.signOut();
      final account = await google.signIn();
      if (account == null) throw const AuthCancelled();
      final gAuth = await account.authentication;
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(
          idToken: gAuth.idToken,
          accessToken: gAuth.accessToken,
        ),
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageOf(e), code: e.code);
    }
  }

  /// 탈퇴 전 재인증 (애플 계정)
  ///
  /// 애플은 재인증도 최초 로그인과 동일한 nonce 절차를 거친다.
  /// 카카오 계정 재인증.
  ///
  /// 커스텀 토큰 계정은 `reauthenticateWithCredential` 을 쓸 수 없다
  /// (재사용할 credential 이 없다). 대신 카카오 로그인을 처음부터 다시
  /// 해서 새 커스텀 토큰으로 로그인하면 최근 로그인 시각이 갱신된다.
  Future<void> reauthenticateWithKakao() async {
    await signInWithKakao();
  }

  Future<void> reauthenticateWithApple() async {
    _requireAvailable();
    final user = _auth!.currentUser;
    if (user == null) throw const AuthFailure('로그인 상태가 아닙니다.');
    if (!isAppleSignInSupported) {
      throw const AuthFailure('애플 재인증은 아이폰에서만 가능합니다.');
    }
    try {
      final rawNonce = _randomNonce();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: _sha256(rawNonce),
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthFailure('애플 인증 토큰을 받지 못했습니다.');
      }
      await user.reauthenticateWithCredential(
        OAuthProvider('apple.com').credential(
          idToken: idToken,
          rawNonce: rawNonce,
          accessToken: credential.authorizationCode,
        ),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthCancelled();
      }
      throw const AuthFailure('애플 재인증에 실패했습니다.');
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageOf(e), code: e.code);
    }
  }

  /// 현재 계정이 애플 계정으로 로그인했는지
  bool get isAppleAccount =>
      currentUser?.providerData.any((p) => p.providerId == 'apple.com') ??
      false;

  /// 현재 계정이 구글 계정으로 로그인했는지
  bool get isGoogleAccount =>
      currentUser?.providerData.any((p) => p.providerId == 'google.com') ??
      false;

  // ──────────────────────────────────────────────────────────

  /// 이메일/구글 인증 호출의 응답 상한. 넘으면 사용자에게 문구를 보여준다.
  static const Duration _authTimeout = Duration(seconds: 30);

  /// 카카오 토큰을 검증해 Firebase 통행증을 발급하는 서버 함수.
  ///
  /// 시세 갱신 함수와 같은 프로젝트/리전에 배포된다.
  static const _kakaoFnUrl =
      'https://asia-northeast3-flownote-404ef.cloudfunctions.net/kakaoCustomToken';

  static const String _timeoutMessage =
      '서버 응답이 너무 늦어요.\n네트워크를 확인하고 다시 시도해 주세요.';

  // ──────────────────────────────────────────────────────────
  // 카카오
  // ──────────────────────────────────────────────────────────

  /// 카카오 로그인 → Firebase 로그인.
  ///
  /// Firebase 는 카카오를 기본 지원하지 않으므로 서버 함수가 신원을 보증한다.
  ///   ① 카카오 SDK 로 로그인 → 액세스 토큰
  ///   ② 서버(`kakaoCustomToken`)가 카카오에 토큰을 검증하고 통행증 발급
  ///   ③ `signInWithCustomToken` 으로 Firebase 로그인
  ///
  /// 🔴 ② 를 앱에서 대신할 수 없다. 앱은 사용자가 고칠 수 있어서
  ///    "나 카카오 12345번" 이라는 주장을 그대로 믿으면 남의 계정에
  ///    들어가진다. 검증은 반드시 서버가 카카오에 직접 물어야 한다.
  Future<User> signInWithKakao() async {
    _requireAvailable();
    try {
      // ── ① 카카오 인증 ─────────────────────────────────────
      // 카카오톡이 깔려 있으면 앱으로, 없으면 웹으로. 사장님들 대부분
      // 카카오톡이 있어서 앱 경로가 훨씬 빠르다.
      String accessToken;
      if (kIsWeb) {
        // 🔴 웹에서는 카카오 SDK 를 아예 쓰지 않는다.
        //
        // #88 에서 `loginWithKakaoTalk()` → `loginWithKakaoAccount()` 로
        // 고친 것은 필요한 수정이었지만 **충분하지 않았다.** 그 뒤에도
        // 마지막 토큰 교환에서 이렇게 실패했다.
        //
        //   {error: misconfigured,
        //    error_description: Javascript env validation failed.}
        //   → 카카오 화면에는 "앱 관리자 설정 오류 (KOE101)"
        //
        // 원인은 SDK 웹 구현이 토큰 교환 요청에 붙이는 `KA` 헤더다.
        //
        // ```dart
        // // kakao_flutter_sdk_common/…/kakao_flutter_sdk_plugin.dart:329
        // String _getKaHeader() {
        //   return "os/javascript origin/${web.window.location.origin}";
        // }
        // ```
        //
        // 같은 요청에서 `KA` 헤더만 바꿔가며 실측한 결과:
        //
        //   os/javascript + origin=등록된 도메인   → KOE009 misconfigured
        //   os/javascript + origin=미등록 도메인   → KOE009
        //   os/javascript (origin 없음)          → KOE009
        //   sdk_type/flutter (os/ 없음)          → KOE320  ← 통과
        //   KA 헤더 없음                          → KOE320  ← 통과
        //
        // (KOE320 = "authorization code not found". 가짜 code 를 보냈으니
        //  이게 정상 응답이고, 즉 **검증을 통과했다**는 뜻이다)
        //
        // 즉 `origin` **값은 무관하다.** `os/javascript` 가 붙어 있느냐만으로
        // 갈린다. 그래서 콘솔에서 도메인을 몇 번 고쳐도 증상이 똑같았다.
        // 콘솔 설정(JavaScript SDK 도메인·리다이렉트 URI)은 이미 올바르다.
        //
        // → SDK 웹 경로를 버리고 표준 OAuth 2.0 + PKCE 를 직접 구현했다.
        //   우리가 보내는 요청에는 `KA` 헤더가 없으므로 문제의 검증이
        //   애초에 발생하지 않는다. (`kakao_web_login_web.dart`)
        //
        // 그리고 팝업이 아니라 **전체 페이지 이동**을 쓴다. 이 호출은
        // 정상적으로는 반환되지 않고, 카카오에서 돌아온 뒤 부팅 시점의
        // `completeKakaoWebLogin()` 이 이어받는다.
        final t = await kakaoWebLogin(javaScriptKey: KakaoConfig.javaScriptKey);
        accessToken = t.accessToken;
      } else {
        // ── 네이티브(안드로이드/iOS) ────────────────────────
        //
        // 여기서는 SDK 경로가 **정상이다.** 문제의 `os/javascript` 는 웹
        // 구현에서만 붙고, 네이티브는 `os/android` / `os/ios` 를 보낸다.
        // (실측: `os/android` 로 보내면 KOE008 "Not allowed for app key
        //  type" — 즉 키 종류만 맞으면 통과하는 경로다)
        // 그래서 네이티브 로직은 손대지 않고 그대로 유지한다.
        kakao.OAuthToken tok;
        if (await kakao.isKakaoTalkInstalled()) {
          try {
            tok = await kakao.UserApi.instance.loginWithKakaoTalk();
          } on PlatformException catch (e) {
            // 사용자가 카카오톡 화면에서 취소를 눌렀다 → 조용히 끝낸다.
            if (e.code == 'CANCELED') throw const AuthCancelled();
            // 카카오톡이 있어도 실패할 수 있다(구버전 등). 웹으로 재시도.
            tok = await kakao.UserApi.instance.loginWithKakaoAccount();
          }
        } else {
          tok = await kakao.UserApi.instance.loginWithKakaoAccount();
        }
        accessToken = tok.accessToken;
      }

      // ── ②③ 서버 검증 → Firebase 로그인 ────────────────────
      return _finishKakao(accessToken);
    } on AuthCancelled {
      rethrow;
    } on AuthFailure {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageOf(e), code: e.code);
    } on TimeoutException {
      throw const AuthFailure(_timeoutMessage, code: 'timeout');
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') throw const AuthCancelled();
      debugPrint('[kakao] PlatformException ${e.code}: ${e.message}');
      throw AuthFailure('카카오 로그인 중 오류가 발생했습니다. (${e.code})');
    } catch (e) {
      // kakao SDK 는 사용자 취소를 여러 형태로 던진다. 문자열로 걸러낸다.
      final t = e.toString();
      if (t.contains('CANCELED') || t.contains('cancel')) {
        throw const AuthCancelled();
      }

      // 🔴 진짜 원인을 삼키지 않는다.
      //
      // 예전에는 이 로그가 `if (kDebugMode)` 안에 있었다. 그래서 배포된
      // 웹에서는 **원인이 통째로 사라지고** 사장님 화면에도, 콘솔에도
      // "카카오 로그인 중 오류가 발생했습니다." 한 줄만 남았다.
      // 원인을 지우는 코드는 디버깅을 불가능하게 만든다.
      debugPrint('[kakao] 로그인 실패: $e');

      // 사용자에게도 최소한의 단서를 준다. 문의가 왔을 때 이 한 줄이
      // 있으면 어디를 볼지 바로 알 수 있다.
      final hint = t.length > 120 ? '${t.substring(0, 120)}…' : t;
      throw AuthFailure('카카오 로그인 중 오류가 발생했습니다.\n\n$hint');
    }
  }

  /// 웹 리다이렉트에서 돌아왔는지 (= 카카오가 `?code=…` 를 붙여 보냈는지).
  ///
  /// 부팅 화면에서 이 값이 true 면 로그인 화면을 보여주지 말고 잠깐
  /// 기다려야 한다. 안 그러면 로그인 화면이 번쩍 보이고 곧 홈으로
  /// 넘어가서 "왜 로그인 화면이 다시 나왔지?" 하는 혼란이 생긴다.
  bool get isKakaoWebReturning => kIsWeb && kakaoWebLoginReturning();

  /// 웹 카카오 로그인 마무리 — 리다이렉트로 돌아온 직후 한 번 호출한다.
  ///
  /// 돌아온 상황이 아니면 `null` 을 돌려준다(그게 정상이다).
  /// 전체 페이지 이동 방식이라 로그인 요청과 완료가 **서로 다른 실행**에서
  /// 일어난다. 그래서 시작은 `signInWithKakao()`, 완료는 이 함수가 맡는다.
  Future<User?> completeKakaoWebLogin() async {
    if (!kIsWeb) return null;
    if (!kakaoWebLoginReturning()) return null;
    _requireAvailable();
    try {
      final tok = await kakaoWebFinishRedirect();
      if (tok == null) return null;
      return await _finishKakao(tok.accessToken);
    } on KakaoWebLoginCancelled {
      throw const AuthCancelled();
    } on KakaoWebLoginException catch (e) {
      // 🔴 카카오가 준 원문을 그대로 노출한다. 원인을 감추면 이번처럼
      //    몇 차례를 낭비한다.
      debugPrint('[kakao] 웹 로그인 실패: ${e.code} ${e.message}');
      throw AuthFailure(
        '카카오 로그인 중 오류가 발생했습니다.\n\n${e.message}'
        '${e.code == null ? '' : ' (${e.code})'}',
        code: e.code,
      );
    } on AuthCancelled {
      rethrow;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(_timeoutMessage, code: 'timeout');
    } catch (e) {
      debugPrint('[kakao] 웹 로그인 마무리 실패: $e');
      final t = e.toString();
      final hint = t.length > 120 ? '${t.substring(0, 120)}…' : t;
      throw AuthFailure('카카오 로그인 중 오류가 발생했습니다.\n\n$hint');
    }
  }

  /// 액세스 토큰 → 서버 검증 → Firebase 로그인.
  ///
  /// 🔴 이 단계를 앱이 대신할 수 없다. 앱은 사용자가 고칠 수 있어서
  ///    "나 카카오 12345번" 이라는 주장을 그대로 믿으면 남의 계정에
  ///    들어가진다. 검증은 반드시 서버가 카카오에 직접 물어야 한다.
  ///    (그래서 우회로에서도 이 구조는 그대로 유지했다)
  ///
  /// 네이티브 경로와 웹 리다이렉트 복귀 경로가 함께 쓴다.
  Future<User> _finishKakao(String accessToken) async {
    // ── ② 서버 검증 + 통행증 발급 ─────────────────────────
    final res = await http
        .post(
          Uri.parse(_kakaoFnUrl),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'accessToken': accessToken}),
        )
        .timeout(_authTimeout);

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['ok'] != true) {
      throw AuthFailure(
        '카카오 로그인 확인에 실패했습니다.\n'
        '${body['error'] ?? 'HTTP ${res.statusCode}'}',
        code: 'kakao-verify-failed',
      );
    }

    // ── ③ Firebase 로그인 ────────────────────────────────
    final cred = await _auth!
        .signInWithCustomToken(body['token'] as String)
        .timeout(_authTimeout);
    final user = cred.user;
    if (user == null) throw const AuthFailure('카카오 로그인에 실패했습니다.');

    // 프로필 반영. 실패해도 로그인 자체는 성공으로 본다.
    // 서버에서 이메일을 Auth 레코드에 넣지 않으므로(구글 계정과 충돌 방지)
    // 표시 이름만 여기서 맞춘다.
    final mail = body['email'] as String?;
    lastKakaoEmail = (mail != null && mail.isNotEmpty) ? mail : null;

    final nick = body['displayName'] as String?;
    if (nick != null && nick.isNotEmpty && user.displayName != nick) {
      try {
        await user.updateDisplayName(nick);
        await user.reload();
      } catch (_) {/* 표시 이름은 없어도 동작한다 */}
    }
    return _auth!.currentUser ?? user;
  }

  /// 현재 계정이 카카오로 들어온 계정인지.
  ///
  /// 카카오 계정은 Firebase 기준 `custom` 이라 providerData 가 비어 있다.
  /// 서버가 uid 에 `kakao:` 접두사를 박아두므로 그걸로 판별한다.
  bool get isKakaoAccount => (uid ?? '').startsWith('kakao:');

  /// 카카오가 방금 알려준 이메일.
  ///
  /// 🔴 이 값을 Firebase 계정(Auth 레코드)에 넣지 않는 이유는, 같은 이메일을
  ///    쓰는 구글 계정이 이미 있으면 `email-already-exists` 로 **카카오
  ///    로그인 자체가 막히기** 때문이다. 그래서 계정에는 안 넣고 이렇게
  ///    따로 들고 있다가, 우리 쪽 사용자 문서에만 기록한다.
  ///    (동의를 안 받았으면 null 이고, 그건 정상이다)
  String? lastKakaoEmail;

  /// 카카오 세션도 함께 끊는다.
  ///
  /// 🔴 Firebase 만 로그아웃하면 카카오 세션이 남아서, 다시 로그인할 때
  ///    계정 선택 없이 곧바로 이전 계정으로 들어가 버린다. 기기를 공유하는
  ///    상황에서 문제가 된다.
  Future<void> _signOutKakao() async {
    try {
      await kakao.UserApi.instance.logout();
    } catch (_) {/* 이미 끊겼거나 미설정 — 무시 */}
  }

  void _requireAvailable() {
    if (!isAvailable) {
      // 원인을 감추지 않는다. Firebase 초기화가 실패한 경우 그 사유를 그대로
      // 붙여서, 사용자가 화면 문구만 알려주면 바로 진단할 수 있게 한다.
      final detail = FirebaseStatus.errorDetail;
      if (detail != null && detail.isNotEmpty) {
        throw AuthFailure(
          '로그인 서버에 연결하지 못했습니다.\n'
          '(${FirebaseStatus.errorStage}) $detail',
          code: 'firebase-unavailable',
        );
      }
      throw const AuthFailure(
        '로그인 서비스를 사용할 수 없습니다.\n네트워크 상태를 확인해 주세요.',
        code: 'firebase-unavailable',
      );
    }
  }

  /// Firebase 에러 코드를 사용자에게 보여줄 한국어 문구로 변환.
  static String _messageOf(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => '이메일 형식이 올바르지 않습니다.',
        'user-disabled' => '정지된 계정입니다. 고객센터에 문의해 주세요.',
        'user-not-found' => '등록되지 않은 이메일입니다.',
        'wrong-password' => '비밀번호가 올바르지 않습니다.',
        // Firebase 최신 버전은 아이디/비번 오류를 하나로 합쳐서 준다
        'invalid-credential' => '이메일 또는 비밀번호가 올바르지 않습니다.',
        'INVALID_LOGIN_CREDENTIALS' => '이메일 또는 비밀번호가 올바르지 않습니다.',
        'email-already-in-use' => '이미 가입된 이메일입니다. 로그인해 주세요.',
        'weak-password' => '비밀번호가 너무 쉬워요. 6자 이상으로 만들어 주세요.',
        'operation-not-allowed' =>
          '이 로그인 방식이 아직 활성화되지 않았습니다.\n관리자에게 문의해 주세요.',
        'too-many-requests' => '시도 횟수가 너무 많습니다. 잠시 후 다시 시도해 주세요.',
        'network-request-failed' => '네트워크 연결을 확인해 주세요.',
        'account-exists-with-different-credential' =>
          '같은 이메일로 다른 방식으로 가입된 계정이 있습니다.\n기존 방식으로 로그인해 주세요.',
        'requires-recent-login' => '보안을 위해 다시 로그인해 주세요.',
        _ => '로그인 처리 중 오류가 발생했습니다. (${e.code})',
      };
}

/// 사용자에게 그대로 보여줄 수 있는 인증 실패.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// 사용자가 스스로 취소한 경우 — 에러 토스트를 띄우지 않는다.
class AuthCancelled implements Exception {
  const AuthCancelled();
}

/// 계정 삭제 전 재인증이 필요한 경우.
class AuthReauthRequired implements Exception {
  const AuthReauthRequired();
}
