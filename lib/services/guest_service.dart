import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// 게스트 체험 모드. (#192)
///
/// ## 왜 만들었나
///
/// 지금은 첫 화면이 로그인이라, 앱이 뭘 해 주는지 보기도 전에 가입을
/// 해야 한다. 사장님 지시(#192): 로그인 없이 들어와 영수증 몇 장을
/// 찍어 보고, 마음에 들면 가입하게 한다.
///
/// ## 어떻게 도나
///
/// ```
///   앱 시작 → 로그인 안 돼 있음 → signInAnonymously()
///           → Firebase 가 진짜 uid 를 준다 (익명 계정)
///           → 영수증·사입 리스트가 users/{그 uid} 아래 담긴다
///   가입     → linkWithCredential() 로 **같은 uid** 에 구글을 붙인다
///           → uid 가 안 바뀌므로 찍어 둔 영수증이 그대로 남는다
/// ```
///
/// 🔴 익명 계정도 `request.auth != null` 이다. 그래서 보안 규칙에서
///    `sign_in_provider == 'anonymous'` 로 따로 가려 막았다. 안 그러면
///    "로그인했으면 통과" 규칙을 게스트가 전부 통과한다.
///
/// 🔴 체험 횟수는 **서버**(`users/{uid}/usage/counters`)에 적는다.
///    기기(SharedPreferences)에 적으면 앱을 지웠다 깔 때 0 으로 돌아가고
///    고칠 수도 있다. 규칙이 1씩·한도까지만 올리도록 지킨다.
class GuestService extends ChangeNotifier {
  GuestService._();
  static final GuestService instance = GuestService._();

  /// 🔴 **게스트 체험을 아직 켜지 않았다.** (#192 — 2·5단계만 끝남)
  ///
  ///    ①②단계(보안 규칙·게스트 계정)는 됐지만 ③제한·잠금 ④프로필
  ///    ⑤가입 전환이 아직 없다. 이대로 켜면 처음 오신 분이 **게스트로
  ///    들어와 가입할 길이 없는 채로 갇힌다.** 지금 상태보다 나쁘다.
  ///
  ///    ③④⑤ 가 끝나는 날 이 값을 `true` 로 바꾸면 켜진다. 그 전까지는
  ///    예전처럼 인트로 → 로그인으로 간다.
  static const bool enabled = false;

  /// 체험 한도. **`firestore.rules` 의 `guestScanMax()` 와 같은 값**이어야
  /// 한다. 한쪽만 바꾸면 앱은 통과시키는데 서버가 거부한다.
  static const int scanMax = 5;

  /// 🔴 PDF 는 **세지 않는다**(#193). 사장님 지시가 바뀌었다 —
  ///    미리보기는 몇 번이든 열 수 있고, **저장·공유를 누르는 순간**
  ///    가입 안내를 띄운다. 셀 것이 없으니 칸도 두지 않았다.

  /// 체험 영수증을 며칠 뒤에 지우는가. 안내 문구와 2차 작업이 같이 쓴다.
  static const int keepDays = 30;

  static const String _usageCol = 'usage';
  static const String _usageDoc = 'counters';

  int _scans = 0;
  bool _loaded = false;

  /// 첫 스캔 전 안내에 동의했는가.
  bool _agreed = false;

  int get scans => _scans;
  bool get isLoaded => _loaded;
  bool get agreedToTrial => _agreed;

  /// 지금 게스트로 들어와 있는가.
  ///
  /// 🔴 `isAnonymous` 를 Firebase 가 직접 알려 준다. 우리가 따로 기억하면
  ///    가입한 뒤에도 게스트로 남아 있는 사고가 난다.
  bool get isGuest => AuthService.instance.currentUser?.isAnonymous ?? false;

  int get scansLeft => (scanMax - _scans).clamp(0, scanMax);

  /// 영수증을 더 찍을 수 있는가. 가입자는 늘 true.
  bool get canScan => !isGuest || _scans < scanMax;

  /// PDF 를 **저장·공유**할 수 있는가. 게스트는 못 한다(#193).
  ///
  /// 🔴 미리보기는 막지 않는다. 뭘 받게 되는지 봐야 가입할 마음이 든다.
  ///    버튼을 누르는 순간에만 가입 안내를 띄운다.
  bool get canExportPdf => !isGuest;

  /// 체험에서 첫 영수증인가. 첫 스캔 안내를 한 번만 띄우는 데 쓴다.
  bool get isFirstScan => isGuest && _scans == 0;

  // ── 게스트 계정 ──────────────────────────────────────────────

  /// 로그인 안 돼 있으면 게스트로 들어간다.
  ///
  /// 돌려주는 값은 **게스트로 들어갔는가**다. 이미 로그인돼 있거나
  /// Firebase 를 못 쓰면 false 를 주고 아무것도 하지 않는다.
  Future<bool> enterAsGuest() async {
    if (!enabled) return false;           // 아직 안 켰다 (위 주석 참고)
    final auth = AuthService.instance;
    if (!auth.isAvailable) return false;
    if (auth.currentUser != null) return false;   // 이미 들어와 있다
    try {
      await FirebaseAuth.instance.signInAnonymously();
      await load();
      return true;
    } catch (e) {
      // 콘솔에서 익명 로그인을 꺼 두면 여기로 온다. 로그인 화면으로 보낸다.
      if (kDebugMode) debugPrint('[Guest] 익명 로그인 실패: $e');
      return false;
    }
  }

  // ── 사용 횟수 ────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>>? _usageRef() {
    final uid = AuthService.instance.uid;
    if (uid == null) return null;
    try {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(_usageCol)
          .doc(_usageDoc);
    } catch (_) {
      return null;
    }
  }

  /// 서버에서 지금까지 쓴 횟수를 읽는다.
  Future<void> load() async {
    final ref = _usageRef();
    if (ref == null) return;
    try {
      final snap = await ref.get();
      final m = snap.data();
      _scans = (m?['scans'] as num?)?.toInt() ?? 0;
      _agreed = m?['trialAgreed'] as bool? ?? false;
      _loaded = true;
      notifyListeners();
    } catch (e) {
      // 인터넷이 없다. 0 으로 두고 앱은 계속 돈다.
      if (kDebugMode) debugPrint('[Guest] 사용 횟수 읽기 실패: $e');
      _loaded = true;
    }
  }

  /// 영수증 한 장을 썼다고 올린다.
  ///
  /// 🔴 **인식에 성공해 저장된 영수증만** 부른다. 사장님 지시(#192):
  ///    "실패·다시 찍기는 세지 않음". 연속 촬영도 장당으로 한 번씩.
  ///
  /// 돌려주는 값은 올렸는가다. 한도를 넘었으면 false.
  Future<bool> countScan() async {
    if (!isGuest) return true;              // 가입자는 안 센다
    if (_scans >= scanMax) return false;

    // 화면이 바로 반응하게 먼저 올린다.
    _scans = _scans + 1;
    notifyListeners();

    final ref = _usageRef();
    if (ref == null) return true;
    try {
      // 🔴 `set(merge)` 가 아니라 **증가**를 쓴다. 두 화면에서 동시에
      //    올려도 하나가 묻히지 않는다. 규칙이 +1 만 통과시킨다.
      await ref.set({'scans': FieldValue.increment(1)},
          SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[Guest] 횟수 올리기 실패: $e');
    }
    return true;
  }

  /// 첫 스캔 전 안내에 동의했다고 적는다. (#192)
  ///
  /// 🔴 동의 이력은 `UserRepository.recordConsents` 가 `consent_log` 에
  ///    남긴다. 여기서는 "다시 묻지 않기" 용 표시만 둔다.
  Future<void> markTrialAgreed() async {
    _agreed = true;
    notifyListeners();
    final ref = _usageRef();
    if (ref == null) return;
    try {
      await ref.set({'trialAgreed': true}, SetOptions(merge: true));
    } catch (_) {/* 다음에 한 번 더 물어도 큰일은 아니다 */}
  }

  /// 가입이 끝났다. 체험 숫자를 치운다.
  void clearAfterSignUp() {
    _scans = 0;
    _agreed = false;
    notifyListeners();
  }

  @visibleForTesting
  void setForTest({int scans = 0, bool agreed = false}) {
    _scans = scans;
    _agreed = agreed;
    _loaded = true;
  }
}
