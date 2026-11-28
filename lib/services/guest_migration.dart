import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'guest_service.dart';

/// 체험 데이터 옮기기 결과. 화면은 이 값만 보고 무엇을 보여줄지 정한다.
enum GuestMigrateStatus {
  /// 옮길 것이 없었다(체험 중이 아니었거나 맡겨 둔 토큰이 없다). 조용히 끝.
  none,

  /// 옮겼다. [GuestMigrateResult.receipts] 장.
  moved,

  /// **기존 회원**이라 옮기지 않았다. 체험 영수증은 그대로 남아 있다.
  skippedExisting,

  /// 실패했다. 로그인은 그대로 두고 다시 시도할 수 있다.
  failed,
}

/// 옮기기 결과 한 묶음.
@immutable
class GuestMigrateResult {
  const GuestMigrateResult(
    this.status, {
    this.receipts = 0,
    this.purchaseLists = 0,
    this.guestReceipts = 0,
    this.message = '',
  });

  final GuestMigrateStatus status;

  /// 실제로 옮긴 영수증 수.
  final int receipts;
  final int purchaseLists;

  /// 체험 계정에 있던 영수증 수. 안 옮겼을 때 안내 문구에 쓴다.
  final int guestReceipts;

  /// 실패 사유.
  final String message;

  bool get isMoved => status == GuestMigrateStatus.moved;
  bool get isSkipped => status == GuestMigrateStatus.skippedExisting;
  bool get isFailed => status == GuestMigrateStatus.failed;
}

/// 체험(익명) 데이터를 정식 계정으로 옮기는 일의 **앱 쪽 담당**. (#195 ⑤-d)
///
/// ## 왜 따로 두나
///
/// 카카오는 커스텀 토큰이라 `linkWithCredential` 로 붙일 수 없고 **uid 가
/// 바뀐다.** 그래서 로그인하고 나면 체험으로 찍어 둔 영수증이 옛 uid 아래
/// 남겨진 채 안 보인다. 서버 함수 `migrateGuestData` 가 그걸 옮기는데,
/// 그 함수는 **로그인하기 전에 받아 둔 체험 토큰**이 있어야 한다.
///
/// 그래서 순서가 이렇다.
///
/// ```
///   (체험 중) rememberGuest()   ← 로그인 **전에** 토큰을 맡아 둔다
///   카카오 로그인 (기존 흐름 그대로 — 한 줄도 고치지 않는다)
///   runIfPending()              ← 로그인 **뒤에** 서버에 옮겨 달라고 한다
/// ```
///
/// 🔴 **게스트가 아니면 `rememberGuest()` 가 아무것도 하지 않는다.** 맡긴
///    토큰이 없으면 `runIfPending()` 도 첫 줄에서 돌아간다. 그래서 가입하신
///    분의 로그인은 이 파일을 지나도 **아무 일도 일어나지 않는다.**
///
/// 🔴 토큰을 기기(SharedPreferences)에 적어 둔다. 웹 카카오 로그인은
///    **페이지가 통째로 카카오로 갔다 돌아오는** 방식이라, 메모리에만
///    들고 있으면 돌아왔을 때 사라진다. 다 쓰면 바로 지운다.
class GuestMigration {
  GuestMigration._();
  static final GuestMigration instance = GuestMigration._();

  /// 🔴 호출 가능(callable) 함수 주소. `kakaoCustomToken` 과 같은 지역이다.
  static const String _url =
      'https://asia-northeast3-flownote-404ef.cloudfunctions.net/migrateGuestData';

  static const String _kToken = 'fn_guest_migrate_token';
  static const String _kUid = 'fn_guest_migrate_uid';

  /// 테스트에서 실제 서버를 부르지 않도록 갈아끼우는 자리.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(String guestIdToken)? debugCall;

  String? _token;
  String? _guestUid;

  /// 맡아 둔 체험 계정의 uid. Hive 상자를 옮길 때 쓴다.
  String? get pendingGuestUid => _guestUid;

  /// 지금 옮길 것이 맡겨져 있는가.
  bool get hasPending => (_token ?? '').isNotEmpty;

  // ── 로그인 **전** ────────────────────────────────────────────

  /// 체험 중이면 ID 토큰을 받아 맡아 둔다.
  ///
  /// 🔴 **게스트일 때만 동작한다.** 회원이 부르면 아무 일도 하지 않는다.
  ///    돌려주는 값은 맡아 두었는가다.
  Future<bool> rememberGuest() async {
    if (!GuestService.instance.isGuest) return false;
    final u = AuthService.instance.currentUser;
    if (u == null) return false;
    try {
      final t = await u.getIdToken();
      if (t == null || t.isEmpty) return false;
      _token = t;
      _guestUid = u.uid;
      await _save();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[GuestMigration] 토큰 받기 실패: $e');
      return false;
    }
  }

  /// 앱을 다시 켰을 때(웹 리다이렉트 복귀 포함) 맡겨 둔 것을 되살린다.
  Future<void> load() async {
    if (hasPending) return;
    try {
      final p = await SharedPreferences.getInstance();
      _token = p.getString(_kToken);
      _guestUid = p.getString(_kUid);
    } catch (_) {/* 못 읽으면 옮길 것이 없는 셈이다 */}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kToken, _token ?? '');
      await p.setString(_kUid, _guestUid ?? '');
    } catch (_) {}
  }

  /// 맡아 둔 것을 버린다. 다 옮겼거나, 더는 쓸 수 없을 때.
  Future<void> clear() async {
    _token = null;
    _guestUid = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kToken);
      await p.remove(_kUid);
    } catch (_) {}
  }

  // ── 로그인 **뒤** ────────────────────────────────────────────

  /// 맡겨 둔 체험 토큰이 있으면 서버에 옮겨 달라고 한다.
  ///
  /// 🔴 맡긴 것이 없으면 첫 줄에서 돌아간다 — 회원 로그인은 여기서 끝난다.
  /// 🔴 지금 로그인한 사람이 아직 익명이면 하지 않는다. 서버도 거절한다.
  ///
  /// 실패해도 **맡긴 것을 지우지 않는다.** 다시 시도할 수 있어야 한다.
  Future<GuestMigrateResult> runIfPending() async {
    await load();
    final token = _token;
    if (token == null || token.isEmpty) {
      return const GuestMigrateResult(GuestMigrateStatus.none);
    }
    final me = AuthService.instance.currentUser;
    if (me == null || me.isAnonymous) {
      return const GuestMigrateResult(GuestMigrateStatus.none);
    }

    try {
      final body = debugCall != null
          ? await debugCall!(token)
          : await _post(token, me);
      final out = parseResult(body);
      // 🔴 성공·건너뜀 둘 다 **끝난 것**이다. 맡긴 것을 지운다.
      //    실패만 남겨 두어 다시 시도할 수 있게 한다.
      if (!out.isFailed) await clear();
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('[GuestMigration] 옮기기 실패: $e');
      return GuestMigrateResult(
        GuestMigrateStatus.failed,
        message: '체험 영수증을 옮기지 못했어요.',
      );
    }
  }

  /// 호출 가능 함수 규약대로 보낸다.
  ///
  /// `cloud_functions` 패키지를 쓰지 않는 이유: 지금 `pubspec.yaml` 에 없고,
  /// 그 하나 때문에 의존성을 늘리는 것보다 `kakaoCustomToken` 과 **같은
  /// 방식**(http 직접 호출)이 읽기도 쉽다. 규약은 간단하다 —
  /// 본문은 `{"data": …}`, 답은 `{"result": …}`.
  Future<Map<String, dynamic>> _post(String guestIdToken, dynamic me) async {
    // 지금 로그인한 사람의 토큰. 서버는 이것으로 **받는 계정**을 정한다.
    final myToken = await me.getIdToken();
    final res = await http
        .post(
          Uri.parse(_url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $myToken',
          },
          body: jsonEncode({
            'data': {'guestIdToken': guestIdToken},
          }),
        )
        .timeout(const Duration(seconds: 120));

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) throw const FormatException('모양이 다릅니다');
    final map = Map<String, dynamic>.from(decoded);
    if (res.statusCode != 200) {
      final err = map['error'];
      final msg = err is Map ? (err['message']?.toString() ?? '') : '';
      throw Exception(msg.isEmpty ? 'HTTP ${res.statusCode}' : msg);
    }
    final result = map['result'];
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  /// 서버 답을 결과로 바꾼다.
  ///
  /// 🔴 순수 함수로 빼 두었다. 서버 없이 테스트할 수 있어야 한다.
  @visibleForTesting
  static GuestMigrateResult parseResult(Map<String, dynamic> m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;

    if (m['ok'] != true) {
      return const GuestMigrateResult(
        GuestMigrateStatus.failed,
        message: '체험 영수증을 옮기지 못했어요.',
      );
    }
    if (m['skipped'] == true) {
      return GuestMigrateResult(
        GuestMigrateStatus.skippedExisting,
        guestReceipts: n('guestReceipts'),
      );
    }
    return GuestMigrateResult(
      GuestMigrateStatus.moved,
      receipts: n('receipts'),
      purchaseLists: n('purchaseLists'),
      guestReceipts: n('guestReceipts'),
    );
  }
}
