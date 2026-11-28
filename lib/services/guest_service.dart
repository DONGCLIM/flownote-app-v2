import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import 'auth_service.dart';
import 'legal_documents.dart';
import 'user_repository.dart';

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

  /// 🔴 **게스트 체험을 켰다.** (2026-11-28, 사장님 지시)
  ///
  ///    ①보안 규칙 ②게스트 계정 ③제한·잠금 ④프로필 ⑤가입 전환이
  ///    모두 끝났고, Firebase 콘솔에서 익명 로그인도 켜졌다.
  ///
  /// 🔴 **되돌리는 법:** 이 값을 `false` 로 바꾸고 웹만 다시 배포하면
  ///    된다(`./tool/build_web.sh --deploy`). 서버 함수와 규칙은 그대로
  ///    둬도 된다 — 아무도 부르지 않으면 아무 일도 하지 않는다.
  ///    이미 체험 중이던 분의 데이터도 지워지지 않는다.
  ///
  /// 🔴 이 값이 false 면 `enterAsGuest()` 가 첫 줄에서 돌아가므로,
  ///    예전처럼 인트로 → 로그인으로 간다. 회원 흐름은 어느 쪽이든
  ///    **똑같이** 돈다 — 회원은 이 값을 지나지 않는다.
  static const bool enabled = true;

  /// 체험 한도. **`firestore.rules` 의 `guestScanMax()` 와 같은 값**이어야
  /// 한다. 한쪽만 바꾸면 앱은 통과시키는데 서버가 거부한다.
  static const int scanMax = 5;

  /// 🔴 PDF 는 **세지 않는다**(#193). 사장님 지시가 바뀌었다 —
  ///    미리보기는 몇 번이든 열 수 있고, **저장·공유를 누르는 순간**
  ///    가입 안내를 띄운다. 셀 것이 없으니 칸도 두지 않았다.

  /// 🚫 **지금은 쓰지 않는다.** 체험 데이터를 며칠 보관하는가.
  ///
  /// 🔴 2026-11-28 사장님 지시로 **자동 정리를 하지 않기로** 했다. 정리
  ///    서버 함수(`functions/cleanup_guest_data.js`)는 만들어 두었지만
  ///    `index.js` 에서 내보내지 않아 **돌지 않는다.**
  ///
  /// 🔴 상수를 남겨 둔 이유: 나중에 게스트가 많이 쌓여 정리 정책을 다시
  ///    켤 때 앱과 서버가 같은 값을 봐야 한다. 없앴다 다시 만들면 두 값이
  ///    갈라진다. **이 값을 보고 무언가를 치우는 코드는 지금 없다.**
  static const int keepDays = 30;

  static const String _usageCol = 'usage';
  static const String _usageDoc = 'counters';

  /// 방문자 집계용 표시. `users/{uid}/meta/guest`
  ///
  /// 🔴 **기존 규칙으로 이미 저장된다.** `users/{uid}/{document=**}` 포괄
  ///    규칙이 주인에게 열려 있어서, 새 규칙을 더하지 않았다. 회원 흐름은
  ///    한 줄도 건드리지 않는다.
  static const String _metaCol = 'meta';
  static const String _metaDoc = 'guest';

  /// 이 **기기**에서 회원으로 로그인한 적이 있는가. (SharedPreferences)
  ///
  /// 🔴 왜 기기에 적나. 로그아웃하면 Firebase 쪽에는 아무 흔적이 없다.
  ///    그 상태로 다시 들어오시면 앱은 "처음 온 사람" 과 구별할 수 없어서
  ///    **회원인 사장님을 게스트로 밀어 넣는다.** 그러면 본인 영수증이
  ///    하나도 없는 화면을 보고 "데이터가 날아갔다" 고 느끼신다.
  ///    한 번이라도 회원으로 들어온 기기는 로그인 화면을 먼저 보여 준다.
  static const String _kMemberSeen = 'fn_member_signed_in_before';

  int _scans = 0;
  bool _loaded = false;

  /// 첫 스캔 전 안내에 동의했는가.
  bool _agreed = false;

  /// 첫 스캔 성공 안내를 이미 보여 줬는가. (#195)
  ///
  /// 🔴 서버에 안 적는다. 한 번 더 보여도 큰일이 아니고, 적으면 스캔마다
  ///    쓰기가 한 번씩 더 생긴다.
  bool _doneNoticeShown = false;

  int get scans => _scans;
  bool get isLoaded => _loaded;
  bool get agreedToTrial => _agreed;

  /// 🔴 **테스트에서만** 게스트 상태를 흉내 내는 스위치. (#195)
  ///
  /// 테스트에는 Firebase 가 없어 [AuthService.currentUser] 가 늘 null 이다.
  /// 그래서 테스트만으로는 게스트 갈래를 한 줄도 밟아 볼 수 없었다.
  ///
  /// 🔴 null 이면 **아무 일도 하지 않는다**. 실제 앱에서는 이 값을 건드리는
  ///    곳이 없으므로 회원 흐름은 예전 그대로 Firebase 만 본다.
  @visibleForTesting
  static bool? debugIsGuest;

  /// 지금 게스트로 들어와 있는가.
  ///
  /// 🔴 `isAnonymous` 를 Firebase 가 직접 알려 준다. 우리가 따로 기억하면
  ///    가입한 뒤에도 게스트로 남아 있는 사고가 난다.
  bool get isGuest =>
      debugIsGuest ??
      (AuthService.instance.currentUser?.isAnonymous ?? false);

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

  /// 첫 스캔이 **성공한 직후** 한 번만 띄울 안내를 지금 보여야 하는가. (#195)
  ///
  /// 저장이 끝나 [countScan] 이 1 이 된 직후에만 true 다. 두 장째부터는
  /// 뜨지 않는다.
  bool get shouldShowFirstScanDone =>
      isGuest && _scans == 1 && !_doneNoticeShown;

  /// 위 안내를 보여 줬다고 적는다.
  void markFirstScanDoneShown() {
    _doneNoticeShown = true;
  }

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
      // 방문자 집계용 표시. 실패해도 체험은 그대로 돈다.
      await markEnteredAsGuest();
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

  /// 첫 스캔 전 안내에 동의했다고 적는다. (#192 · #195)
  ///
  /// 두 군데에 남긴다.
  ///   1. `users/{uid}/usage/counters.trialAgreed` — "다시 묻지 않기" 표시
  ///   2. `users/{uid}/consent_log` — **감사용 동의 이력** (개인정보보호법은
  ///      동의 시점과 버전을 보관하라고 한다)
  ///
  /// 🔴 게스트일 때만 부른다. 회원은 가입할 때 이미 동의를 받았고 그
  ///    이력도 남아 있다 — 여기서 또 적으면 이력이 두 번 쌓인다.
  Future<void> markTrialAgreed() async {
    if (!isGuest) return;
    _agreed = true;
    notifyListeners();

    final ref = _usageRef();
    if (ref != null) {
      try {
        await ref.set({'trialAgreed': true}, SetOptions(merge: true));
      } catch (_) {/* 다음에 한 번 더 물어도 큰일은 아니다 */}
    }

    // 🔴 동의 이력. 실패해도 체험은 막지 않는다 — 인터넷이 없다고
    //    영수증을 못 찍게 하는 건 과하다. 다음 동의 때 다시 쌓인다.
    final uid = AuthService.instance.uid;
    if (uid == null) return;
    try {
      await UserRepository.instance.recordConsents(
        uid,
        UserConsents(
          privacy: ConsentRecord(
            agreed: true,
            version: LegalDocs.privacyVersion,
            at: DateTime.now(),
          ),
        ),
      );
    } catch (_) {/* 위와 같다 */}
  }

  // ── 게스트 표시 (방문자 집계용) ──────────────────────────────
  //
  // `users/{uid}/meta/guest` 한 문서에 세 시각을 적는다.
  //
  //   createdAt   체험으로 처음 들어온 때
  //   linkedAt    구글·애플·이메일로 **연결 가입**한 때 (uid 그대로)
  //   migratedAt  카카오로 가입해 **옮겨진** 때 (uid 가 바뀐다 — 서버가 적는다)
  //
  // 🔴 어느 것도 실패가 앱을 멈추게 하지 않는다. 집계용 표시일 뿐이고,
  //    이것 때문에 사장님이 영수증을 못 찍으면 본말이 뒤바뀐다.
  //
  // 🔴 **게스트일 때만** 적는다. 회원 계정에는 이 문서가 생기지 않는다.

  DocumentReference<Map<String, dynamic>>? _metaRef([String? uid]) {
    final id = uid ?? AuthService.instance.uid;
    if (id == null) return null;
    try {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .collection(_metaCol)
          .doc(_metaDoc);
    } catch (_) {
      return null;
    }
  }

  /// 체험으로 처음 들어왔다고 적는다.
  Future<void> markEnteredAsGuest() async {
    final ref = _metaRef();
    if (ref == null) return;
    try {
      // 🔴 `merge` 다. 이미 있으면 `createdAt` 을 덮어쓰지 않는다 —
      //    처음 들어온 때가 집계의 기준이다.
      await ref.set({
        'createdAt': FieldValue.serverTimestamp(),
        'guest': true,
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[Guest] 표시 남기기 실패: $e');
    }
  }

  /// 구글·애플·이메일로 **연결 가입**했다고 적는다.
  ///
  /// 🔴 uid 가 그대로이므로 같은 문서에 덧붙인다. 부르는 쪽은 연결이
  ///    **성공한 뒤**에 부른다 — 그 시점에는 이미 회원이라 `isGuest` 가
  ///    false 다. 그래서 여기서 게스트인지 묻지 않는다.
  Future<void> markLinked(String method) async {
    final ref = _metaRef();
    if (ref == null) return;
    try {
      await ref.set({
        'linkedAt': FieldValue.serverTimestamp(),
        'linkedWith': method,
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[Guest] 연결 표시 실패: $e');
    }
  }

  // ── "기존 계정이라 안 옮겼어요" 안내 줄 ───────────────────────

  /// 안내 줄을 지금 띄워야 하는가.
  ///
  /// 🔴 **새로 가입하신 분에게는 절대 켜지지 않는다.** 서버가 "기존
  ///    회원이라 옮기지 않았다"(`skipped`) 고 답했을 때만 켠다.
  ///    새 회원은 영수증이 그대로 옮겨졌으므로 알릴 것이 없다.
  bool _skipNotice = false;
  bool get pendingSkipNotice => _skipNotice;

  /// 이관이 건너뛰어졌다. 다음 화면에서 한 번 알린다.
  void raiseSkipNotice() {
    if (_skipNotice) return;
    _skipNotice = true;
    notifyListeners();
  }

  /// 사장님이 닫으셨다. 다시 띄우지 않는다.
  void dismissSkipNotice() {
    if (!_skipNotice) return;
    _skipNotice = false;
    notifyListeners();
  }

  // ── 이 기기에 회원 로그인 이력이 있는가 ──────────────────────

  /// 메모리 사본. `await` 없이 `build` 에서 읽을 수 있어야 한다.
  static bool _memberSeen = false;
  static bool get memberSeenOnThisDevice => _memberSeen;

  /// 앱 시작 때 한 번 읽어 둔다.
  static Future<bool> loadMemberSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      _memberSeen = p.getBool(_kMemberSeen) ?? false;
    } catch (_) {
      _memberSeen = false;      // 못 읽으면 "처음" 으로 본다
    }
    return _memberSeen;
  }

  /// 회원으로 로그인했다고 이 기기에 적는다.
  ///
  /// 🔴 **게스트(익명)는 적지 않는다.** 익명까지 적으면 체험만 해 본
  ///    기기도 다음부터 로그인 화면을 보게 된다 — 체험이 통째로 막힌다.
  static Future<void> markMemberSeen() async {
    if (_memberSeen) return;
    _memberSeen = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kMemberSeen, true);
    } catch (_) {/* 다음 로그인 때 다시 적는다 */}
  }

  /// 테스트에서만 되돌린다.
  @visibleForTesting
  static void resetMemberSeenForTest() => _memberSeen = false;

  /// 가입이 끝났다. 체험 숫자를 치운다.
  void clearAfterSignUp() {
    _scans = 0;
    _agreed = false;
    notifyListeners();
  }

  @visibleForTesting
  void setForTest({
    int scans = 0,
    bool agreed = false,
    bool doneNoticeShown = false,
    bool skipNotice = false,
  }) {
    _scans = scans;
    _agreed = agreed;
    _doneNoticeShown = doneNoticeShown;
    _skipNotice = skipNotice;
    _loaded = true;
  }
}
