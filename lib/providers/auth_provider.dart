import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/legal_documents.dart';
import '../services/user_repository.dart';

/// 앱 전역 인증 상태.
///
/// 이전 버전은 SharedPreferences 에 **평문 비밀번호**를 저장하고
/// `Future.delayed` 로 로그인을 흉내내는 가짜 인증이었다.
/// 이제 실제 Firebase Auth + Firestore 로 동작한다.
///
/// - 비밀번호: 기기에 저장하지 않음 (Firebase 서버 단방향 암호화)
/// - 개인정보: Firestore `users/{uid}` 문서 (기기 변경 시에도 유지)
/// - 로컬 캐시: `user_data` (오프라인에서도 화면이 비지 않게)
/// - **게스트 모드 삭제됨** — 로그인/회원가입 없이는 앱을 쓸 수 없다.
class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isBootstrapping = true;
  String? _error;

  StreamSubscription<fb.User?>? _authSub;

  static const String _cacheKey = 'user_data';

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;

  /// 앱 시작 직후 세션 복원이 끝났는지. false 인 동안은 스플래시를 유지한다.
  bool get isBootstrapping => _isBootstrapping;
  String? get error => _error;

  bool get isAuthAvailable => AuthService.instance.isAvailable;

  // ──────────────────────────────────────────────────────────
  // 초기화
  // ──────────────────────────────────────────────────────────

  Future<void> init() async {
    // 1) 로컬 캐시를 먼저 붙여서 첫 프레임이 비지 않게 한다.
    await _loadCache();

    final auth = AuthService.instance;
    if (!auth.isAvailable) {
      // Firebase 미설정 환경: 캐시가 있어도 신뢰할 수 없으므로 로그아웃 상태로 둔다.
      _currentUser = null;
      await _clearCache();
      _isBootstrapping = false;
      notifyListeners();
      return;
    }

    // 1.5) 카카오 웹 로그인 리다이렉트 복귀 처리.
    //
    // 🔴 웹 카카오 로그인은 **전체 페이지 이동** 방식이다. 그래서 로그인
    //    요청(`signInWithKakao`)과 완료가 서로 다른 실행에서 일어난다.
    //    카카오가 `?code=…` 를 붙여 우리 사이트로 돌려보내면, 앱은 처음부터
    //    다시 뜬다. 그 시점에 여기서 code 를 받아 로그인을 마무리한다.
    //    (팝업을 쓰지 않는 이유는 `kakao_web_login_web.dart` 주석 참고 —
    //     휴대폰 브라우저에서 팝업은 신뢰할 수 없다)
    //
    //    이 처리를 세션 확인보다 **먼저** 해야 한다. 나중에 하면 로그인
    //    화면이 한 번 번쩍 보이고 홈으로 넘어가서 사장님이 혼란스러워진다.
    if (auth.isKakaoWebReturning) {
      try {
        final u = await auth.completeKakaoWebLogin();
        if (u != null) {
          await _hydrate(u);
          await _ensureRequiredConsents(u.uid);
        }
      } on AuthCancelled {
        // 사장님이 카카오 화면에서 취소를 눌렀다. 오류가 아니다.
        _error = null;
      } on AuthFailure catch (e) {
        // 🔴 사유를 반드시 남긴다. 로그인 화면 토스트로 그대로 보여준다.
        _error = e.message;
      } catch (e) {
        debugPrint('[AuthProvider] 카카오 웹 복귀 실패: $e');
        _error = '카카오 로그인 중 오류가 발생했습니다.\n($e)';
      }
    }

    // 2) 실제 세션 확인
    final fbUser = auth.currentUser;
    if (fbUser != null) {
      await _hydrate(fbUser);
    } else {
      _currentUser = null;
      await _clearCache();
    }

    _isBootstrapping = false;
    notifyListeners();

    // 3) 이후 상태 변화 감시 (토큰 만료, 다른 화면에서의 로그아웃 등)
    _authSub?.cancel();
    _authSub = auth.authStateChanges.listen((u) async {
      if (u == null) {
        if (_currentUser != null) {
          _currentUser = null;
          await _clearCache();
          notifyListeners();
        }
      } else if (_currentUser == null || _currentUser!.id != u.uid) {
        await _hydrate(u);
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Firebase 계정 → Firestore 문서 → UserModel 로 조립한다.
  ///
  /// **중요** — Firestore 호출에 타임아웃을 둔다.
  /// 규칙이 아직 배포되지 않았거나 네트워크가 막히면 `fetch()` 가 응답 없이
  /// 매달려서 로그인 성공 후에도 화면이 전환되지 않는다.
  /// (구글 계정을 골랐는데 "아무 일도 안 일어난다" 던 증상의 원인)
  /// 사용자 문서는 없어도 Firebase 계정 정보만으로 앱을 쓸 수 있으므로
  /// 실패/지연 시엔 그냥 진행한다.
  Future<void> _hydrate(fb.User fbUser) async {
    final repo = UserRepository.instance;
    // 🔴 카카오는 `providerData` 가 **비어 있다.**
    //    Firebase 가 기본 지원하는 제공자(구글/애플/이메일)만 거기에 채워지고,
    //    카카오는 커스텀 토큰으로 들어오므로 아무 것도 없다. 그래서 이 값만
    //    보고 판단하면 카카오 계정이 'password' 로 잡혀서, 앱은 "이메일+
    //    비밀번호로 가입한 사람" 으로 착각한다.
    //    (탈퇴할 때 없는 비밀번호를 물어보게 되는 문제로 이어진다)
    //    uid 접두사가 유일하게 믿을 수 있는 단서다.
    final provider = fbUser.uid.startsWith('kakao:')
        ? 'kakao'
        : (fbUser.providerData.isNotEmpty
            ? fbUser.providerData.first.providerId
            : 'password');

    UserModel? remote = await repo
        .fetch(fbUser.uid)
        .timeout(const Duration(seconds: 8), onTimeout: () => null)
        .catchError((_) => null);

    // 카카오 이메일은 Firebase 계정에 안 들어가므로 별도 경로로 받는다.
    // 동의를 안 받았으면 null 이고, 그래도 로그인은 정상이다.
    final kakaoMail = provider == 'kakao'
        ? (AuthService.instance.lastKakaoEmail ?? '')
        : '';

    remote ??= UserModel(
      id: fbUser.uid,
      email: fbUser.email ?? kakaoMail,
      name: (fbUser.displayName ?? '').isNotEmpty
          ? fbUser.displayName!
          : _nameFromEmail(fbUser.email),
      createdAt: fbUser.metadata.creationTime ?? DateTime.now(),
      photoUrl: fbUser.photoURL ?? '',
      provider: provider,
    );

    // Firebase 쪽이 더 최신인 값들을 반영
    _currentUser = remote.copyWith(
      id: fbUser.uid,
      // 카카오는 로그인할 때마다 이메일을 새로 알려준다. 기존 문서에 빈
      // 값이 저장돼 있어도 새로 받은 값으로 채워준다.
      email: fbUser.email ??
          (remote.email.isNotEmpty ? remote.email : kakaoMail),
      name: (fbUser.displayName ?? '').isNotEmpty
          ? fbUser.displayName!
          : (remote.name.isNotEmpty ? remote.name : _nameFromEmail(fbUser.email)),
      photoUrl: fbUser.photoURL ?? remote.photoUrl,
      provider: provider,
    );

    // 문서 생성도 네트워크에 매달리지 않게 한다. Firestore SDK 는 오프라인
    // 큐를 갖고 있어서 나중에 자동으로 반영된다.
    await repo
        .createIfAbsent(_currentUser!)
        .timeout(const Duration(seconds: 8), onTimeout: () {})
        .catchError((_) {});
    await _saveCache();
  }

  static String _nameFromEmail(String? email) {
    if (email == null || email.isEmpty) return '사장님';
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  // ──────────────────────────────────────────────────────────
  // 회원가입 / 로그인
  // ──────────────────────────────────────────────────────────

  /// 이메일 회원가입. 약관 동의 이력을 함께 저장한다.
  Future<bool> signUp({
    required String email,
    required String name,
    required String password,
    bool agreeTerms = true,
    bool agreePrivacy = true,
    bool agreeMarketing = false,
  }) async {
    if (!agreeTerms || !agreePrivacy) {
      _error = '필수 약관에 동의해 주세요.';
      notifyListeners();
      return false;
    }

    _begin();
    try {
      final fbUser = await AuthService.instance.signUpWithEmail(
        email: email,
        password: password,
        displayName: name,
      );

      final consents = _buildConsents(
        terms: agreeTerms,
        privacy: agreePrivacy,
        marketing: agreeMarketing,
      );

      _currentUser = UserModel(
        id: fbUser.uid,
        email: fbUser.email ?? email.trim(),
        name: name.trim(),
        createdAt: DateTime.now(),
        provider: 'password',
        consents: consents,
      );

      // 🔴 타임아웃 필수. 규칙 미배포/네트워크 차단 시 이 await 가 영구히
      // 매달려서, 가입은 성공했는데 스피너만 돌고 다음 화면으로 못 넘어간다.
      // Firestore SDK 는 오프라인 큐를 갖고 있어 나중에 자동 반영된다.
      await UserRepository.instance
          .createIfAbsent(_currentUser!)
          .timeout(const Duration(seconds: 8), onTimeout: () {})
          .catchError((_) {});
      await UserRepository.instance
          .recordConsents(fbUser.uid, consents)
          .timeout(const Duration(seconds: 8), onTimeout: () {})
          .catchError((_) {});
      await _saveCache();

      _end();
      return true;
    } on AuthFailure catch (e) {
      _fail(e.message);
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider] signUp 오류: $e');
      _fail('회원가입 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// 이메일 로그인.
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _begin();
    try {
      final fbUser = await AuthService.instance.signInWithEmail(
        email: email,
        password: password,
      );
      await _hydrate(fbUser);
      _end();
      return true;
    } on AuthFailure catch (e) {
      _fail(e.message);
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider] signIn 오류: $e');
      _fail('로그인 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// 구글 로그인/가입.
  ///
  /// 첫 로그인이라면 약관 동의를 기록한다(구글 버튼 자체가 동의 안내를 포함).
  /// 사용자가 창을 닫으면 에러 없이 false 를 돌려준다.
  Future<bool> signInWithGoogle({bool agreeMarketing = false}) async {
    _begin();
    try {
      final fbUser = await AuthService.instance.signInWithGoogle();
      await _hydrate(fbUser);

      // 동의 이력이 없으면(=첫 로그인) 기록한다.
      if (!(_currentUser?.consents.hasRequired ?? false)) {
        final consents = _buildConsents(
          terms: true,
          privacy: true,
          marketing: agreeMarketing,
        );
        _currentUser = _currentUser!.copyWith(consents: consents);
        await UserRepository.instance
            .recordConsents(fbUser.uid, consents)
            .timeout(const Duration(seconds: 8), onTimeout: () {})
            .catchError((_) {});
        await _saveCache();
      }

      _end();
      return true;
    } on AuthCancelled {
      _isLoading = false;
      _error = null;
      notifyListeners();
      return false;
    } on AuthFailure catch (e) {
      _fail(e.message);
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider] google 오류: $e');
      // 원인 타입을 남겨서 사용자가 그대로 알려줄 수 있게 한다.
      _fail('구글 로그인 중 오류가 발생했습니다.\n(${e.runtimeType})');
      return false;
    }
  }

  /// 애플 계정으로 로그인/가입 (iOS 전용).
  ///
  /// 구글과 동일하게 첫 로그인 시 필수 동의 이력을 기록한다.
  /// (소셜 로그인 화면에 약관 안내를 표시하고 진행하는 방식)
  Future<bool> signInWithApple({bool agreeMarketing = false}) async {
    _begin();
    try {
      final fbUser = await AuthService.instance.signInWithApple();
      await _hydrate(fbUser);

      if (!(_currentUser?.consents.hasRequired ?? false)) {
        final consents = _buildConsents(
          terms: true,
          privacy: true,
          marketing: agreeMarketing,
        );
        _currentUser = _currentUser!.copyWith(consents: consents);
        await UserRepository.instance.recordConsents(fbUser.uid, consents);
        await _saveCache();
      }

      _end();
      return true;
    } on AuthCancelled {
      _isLoading = false;
      _error = null;
      notifyListeners();
      return false;
    } on AuthFailure catch (e) {
      _fail(e.message);
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider] apple 오류: $e');
      _fail('애플 로그인 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// 첫 로그인 시 필수 동의 이력을 남긴다.
  ///
  /// 🔴 카카오 로그인은 웹에서 **두 경로**로 들어온다.
  ///    ① 네이티브: `signInWithKakao()` 가 끝까지 처리
  ///    ② 웹: 페이지가 카카오로 이동했다 돌아오면서 `init()` 이 마무리
  ///    두 경로가 같은 동의 처리를 해야 하므로 함수로 빼뒀다.
  ///    (예전에는 ① 안에만 있어서, 웹 리다이렉트로 들어온 첫 사용자는
  ///     동의 이력이 남지 않을 수 있었다)
  Future<void> _ensureRequiredConsents(
    String uid, {
    bool agreeMarketing = false,
  }) async {
    if (_currentUser?.consents.hasRequired ?? false) return;
    if (_currentUser == null) return;

    final consents = _buildConsents(
      terms: true,
      privacy: true,
      marketing: agreeMarketing,
    );
    _currentUser = _currentUser!.copyWith(consents: consents);
    // 동의 기록 실패로 로그인을 막지 않는다(구글과 동일).
    await UserRepository.instance
        .recordConsents(uid, consents)
        .timeout(const Duration(seconds: 8), onTimeout: () {})
        .catchError((_) {});
    await _saveCache();
  }

  /// 카카오 계정으로 로그인/가입.
  ///
  /// 구글·애플과 같은 흐름이다. 첫 로그인 시 필수 동의 이력을 남긴다.
  Future<bool> signInWithKakao({bool agreeMarketing = false}) async {
    _begin();
    try {
      final fbUser = await AuthService.instance.signInWithKakao();
      await _hydrate(fbUser);
      await _ensureRequiredConsents(fbUser.uid,
          agreeMarketing: agreeMarketing);

      _end();
      return true;
    } on AuthCancelled {
      _isLoading = false;
      _error = null;
      notifyListeners();
      return false;
    } on AuthFailure catch (e) {
      _fail(e.message);
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider] kakao 오류: $e');
      _fail('카카오 로그인 중 오류가 발생했습니다.\n(${e.runtimeType})');
      return false;
    }
  }

  /// 현재 계정이 카카오 계정인지.
  bool get isKakaoAccount => AuthService.instance.isKakaoAccount;

  /// 이 기기에서 애플 로그인 버튼을 보여줄지 여부.
  bool get isAppleSignInSupported =>
      AuthService.instance.isAppleSignInSupported;

  /// 비밀번호 재설정 메일 발송.
  Future<bool> sendPasswordReset(String email) async {
    _begin();
    try {
      await AuthService.instance.sendPasswordReset(email);
      _end();
      return true;
    } on AuthFailure catch (e) {
      _fail(e.message);
      return false;
    } catch (_) {
      _fail('메일 발송 중 오류가 발생했습니다.');
      return false;
    }
  }

  Future<void> signOut() async {
    await AuthService.instance.signOut();
    _currentUser = null;
    await _clearCache();
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────
  // 회원 탈퇴
  // ──────────────────────────────────────────────────────────

  /// 회원 탈퇴. 클라우드 개인정보를 먼저 지우고 계정을 삭제한다.
  ///
  /// 재인증이 필요하면 [AuthReauthRequired] 를 그대로 던지므로
  /// 화면에서 비밀번호를 다시 받거나 구글 재로그인 후 재호출한다.
  Future<void> deleteAccount() async {
    final uid = _currentUser?.id;
    if (uid == null) return;

    _begin();
    try {
      await UserRepository.instance.deleteAllUserData(uid);
      await AuthService.instance.deleteAccount();
      _currentUser = null;
      await _clearCache();
      _end();
    } on AuthReauthRequired {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on AuthFailure catch (e) {
      _fail(e.message);
      rethrow;
    }
  }

  Future<void> reauthenticateWithPassword(String password) =>
      AuthService.instance.reauthenticateWithPassword(password);

  Future<void> reauthenticateWithGoogle() =>
      AuthService.instance.reauthenticateWithGoogle();

  Future<void> reauthenticateWithApple() =>
      AuthService.instance.reauthenticateWithApple();

  Future<void> reauthenticateWithKakao() =>
      AuthService.instance.reauthenticateWithKakao();

  bool get isGoogleAccount =>
      _currentUser?.isGoogleAccount ?? AuthService.instance.isGoogleAccount;

  /// 애플 계정으로 가입한 사용자인지 (탈퇴 시 비밀번호 대신 애플 재인증)
  bool get isAppleAccount => AuthService.instance.isAppleAccount;

  /// 비밀번호가 없는 소셜 계정인지 (구글 또는 애플)
  bool get isSocialAccount =>
      isGoogleAccount || isAppleAccount || isKakaoAccount;

  // ──────────────────────────────────────────────────────────
  // 사용자 정보 갱신
  // ──────────────────────────────────────────────────────────

  Future<void> incrementScanCount() async {
    if (_currentUser == null) return;
    _currentUser = _currentUser!.copyWith(
      scanCount: _currentUser!.scanCount + 1,
    );
    await _saveCache();
    await UserRepository.instance
        .update(_currentUser!.id, {'scanCount': _currentUser!.scanCount});
    notifyListeners();
  }

  Future<void> unlockUnlimited() async {
    if (_currentUser == null) return;
    _currentUser = _currentUser!.copyWith(isUnlimited: true);
    await _saveCache();
    await UserRepository.instance
        .update(_currentUser!.id, {'isUnlimited': true});
    notifyListeners();
  }

  /// 사업자 정보 저장 (온보딩 사업자등록증 인식 결과 포함)
  Future<void> updateBusinessInfo({
    required String businessName,
    required String businessNumber,
    required String ownerName,
    required String businessAddress,
    String phoneNumber = '',
  }) async {
    if (_currentUser == null) return;
    _currentUser = _currentUser!.copyWith(
      businessName: businessName,
      businessNumber: businessNumber,
      ownerName: ownerName,
      businessAddress: businessAddress,
      phoneNumber: phoneNumber,
    );
    await _saveCache();
    await UserRepository.instance.update(_currentUser!.id, {
      'businessName': businessName,
      'businessNumber': businessNumber,
      'ownerName': ownerName,
      'businessAddress': businessAddress,
      'phoneNumber': phoneNumber,
    });
    notifyListeners();
  }

  /// 마케팅 수신 동의 변경 (프로필에서 언제든 철회 가능)
  Future<void> setMarketingConsent(bool agreed) async {
    if (_currentUser == null) return;
    final consents = _currentUser!.consents.copyWith(
      marketing: ConsentRecord(
        agreed: agreed,
        version: LegalDocs.privacyVersion,
        at: DateTime.now(),
      ),
    );
    _currentUser = _currentUser!.copyWith(consents: consents);
    await _saveCache();
    await UserRepository.instance.recordConsents(_currentUser!.id, consents);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────
  // 내부 헬퍼
  // ──────────────────────────────────────────────────────────

  UserConsents _buildConsents({
    required bool terms,
    required bool privacy,
    required bool marketing,
  }) {
    final now = DateTime.now();
    return UserConsents(
      terms: ConsentRecord(
          agreed: terms, version: LegalDocs.termsVersion, at: now),
      privacy: ConsentRecord(
          agreed: privacy, version: LegalDocs.privacyVersion, at: now),
      marketing: ConsentRecord(
          agreed: marketing, version: LegalDocs.privacyVersion, at: now),
    );
  }

  void _begin() {
    _isLoading = true;
    _error = null;
    notifyListeners();
  }

  void _end() {
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      // 구버전 게스트 캐시는 폐기한다.
      if (map['id'] == 'guest_user') {
        await prefs.remove(_cacheKey);
        return;
      }
      _currentUser = UserModel.fromMap(map);
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    if (_currentUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_currentUser!.toMap()));
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      // 구버전에서 남긴 평문 비밀번호 / 사용자 목록 흔적 제거 (보안)
      final keys = prefs.getKeys().where((k) => k.startsWith('user_password_'));
      for (final k in keys.toList()) {
        await prefs.remove(k);
      }
      await prefs.remove('all_users');
    } catch (_) {}
  }
}
