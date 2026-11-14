import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/purchase_list_model.dart';
import '../models/receipt_model.dart';
import 'auth_service.dart';
import 'cost_calc.dart';
import 'user_repository.dart';

/// 사입 리스트를 보관한다. (#179)
///
/// ## 어디에 담기나
///
/// ```
///   폰   Hive 상자 `plists_<uid 해시>`   ← 진실의 원천. 인터넷이 없어도 된다
///   서버 users/{uid}/purchase_lists/{id} ← 기기를 바꿔도 남게 하는 백업
/// ```
///
/// 🔴 영수증(`ReceiptProvider`)과 **같은 방식**으로 계정마다 상자를 나눈다.
///    한 폰을 여러 사람이 써도 서로 못 본다. 예전에 영수증이 섞여서
///    남의 것이 보였던 적이 있다(#179).
///
/// 🔴 서버 저장은 **글자를 칠 때마다 하지 않는다.** 사장님 지시:
///    "몇 초 모아서 한 번에 하거나 화면을 나갈 때 저장해줘."
///    → [touch] 를 부르면 폰에는 바로 쓰고, 서버는 [_syncDelay] 뒤에
///      한 번만 올린다. 화면을 나갈 때는 [flush] 로 즉시 올린다.
///    꽃시장은 인터넷이 자주 끊기므로 서버 저장은 실패해도 넘어간다.
class PurchaseListService extends ChangeNotifier {
  PurchaseListService._();
  static final PurchaseListService instance = PurchaseListService._();

  static const _uuid = Uuid();

  /// 서버로 올리기 전에 기다리는 시간. 타자를 치는 동안에는 안 올린다.
  static const Duration _syncDelay = Duration(seconds: 4);

  Box<PurchaseList>? _box;
  String? _openedFor;
  bool _ready = false;

  StreamSubscription<User?>? _authSub;
  Timer? _syncTimer;

  /// 아직 서버에 못 올린 리스트 id.
  final Set<String> _dirty = <String>{};

  /// 계정마다 다른 상자 이름.
  ///
  /// 🔴 uid 를 그대로 쓰지 않고 해시를 쓰는 이유는 영수증 쪽과 같다.
  ///    Hive 는 상자 이름 대소문자를 구분하지 않는데 Firebase uid 는
  ///    구분하고, 카카오 uid 에는 파일 이름에 못 쓰는 `:` 가 들어간다.
  static String boxNameFor(String? uid) {
    if (uid == null || uid.isEmpty) return 'plists_guest';
    final h = sha256.convert(utf8.encode(uid)).toString();
    return 'plists_${h.substring(0, 32)}';
  }

  Future<void> init() async {
    await _openFor(AuthService.instance.uid);
    _authSub?.cancel();
    _authSub = AuthService.instance.authStateChanges.listen((u) {
      switchAccount(u?.uid);
    });
    notifyListeners();
  }

  Future<void> switchAccount(String? uid) async {
    if (_ready && _openedFor == uid) return;
    // 계정을 바꾸기 전에 아직 못 올린 것을 올린다. 안 그러면 사라진다.
    await flush();
    await _openFor(uid);
    notifyListeners();
  }

  Future<void> _openFor(String? uid) async {
    if (_ready) {
      try {
        await _box?.close();
      } catch (_) {/* 이미 닫혔으면 넘어간다 */}
      _ready = false;
    }
    _box = await Hive.openBox<PurchaseList>(boxNameFor(uid));
    _openedFor = uid;
    _ready = true;
    _dirty.clear();
    if (kDebugMode) {
      debugPrint('[PList] 상자 전환 → ${boxNameFor(uid)} (${_box!.length}건)');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  // ── 읽기 ────────────────────────────────────────────────────

  /// 사입 날짜가 최근인 것부터.
  List<PurchaseList> get all {
    if (!_ready) return const <PurchaseList>[];
    final list = _box!.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return List<PurchaseList>.unmodifiable(list);
  }

  PurchaseList? byId(String id) => _ready ? _box!.get(id) : null;

  /// 아직 안 끝난 리스트 중 가장 가까운 것. 없으면 null.
  PurchaseList? get activeOne {
    for (final e in all) {
      if (e.status != PurchaseStatus.done) return e;
    }
    return null;
  }

  // ── 쓰기 ────────────────────────────────────────────────────

  /// 새 리스트를 만든다. 아직 저장하지는 않는다.
  ///
  /// [date] 를 안 주면 **내일**로 둔다. 보통 시장 전날 밤에 적기 때문이다.
  PurchaseList draft({DateTime? date, double budgetCap = 0}) {
    final now = DateTime.now();
    final d = date ?? DateTime(now.year, now.month, now.day + 1);
    return PurchaseList(
      id: _uuid.v4(),
      date: d,
      budgetCap: budgetCap,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 폰에 바로 쓰고, 서버는 조금 뒤에 한 번만 올린다.
  Future<void> touch(PurchaseList list, {bool notify = true}) async {
    if (!_ready) return;
    list.updatedAt = DateTime.now();
    await _box!.put(list.id, list);
    _dirty.add(list.id);
    _scheduleSync();
    if (notify) notifyListeners();
  }

  Future<void> remove(String id) async {
    if (!_ready) return;
    await _box!.delete(id);
    _dirty.remove(id);
    final uid = _openedFor;
    if (uid != null) {
      // 실패해도 폰에서는 이미 지워졌다. 서버는 다음에 맞춰진다.
      unawaited(UserRepository.instance.deletePurchaseList(uid, id));
    }
    notifyListeners();
  }

  /// 같은 품목으로 새 리스트를 만든다. (저장된 리스트 → "이 리스트로 새로 만들기")
  ///
  /// 🔴 체크 상태·메모·스케치는 **가져오지 않는다.** 지난번 장보기 기록이지
  ///    이번 계획이 아니다. 품목과 한도만 옮긴다.
  PurchaseList duplicate(PurchaseList src) {
    final now = DateTime.now();
    return PurchaseList(
      id: _uuid.v4(),
      date: DateTime(now.year, now.month, now.day + 1),
      purpose: src.purpose,
      items: src.items
          .map((e) => PurchaseItem(
                name: e.name,
                qty: e.qty,
                unitPrice: e.unitPrice,
                unit: e.unit,
                basisDate: e.basisDate,
              ))
          .toList(),
      budgetCap: src.budgetCap,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ── 서버 올리기 ──────────────────────────────────────────────

  void _scheduleSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(_syncDelay, () => unawaited(flush()));
  }

  /// 아직 못 올린 것을 지금 올린다. 화면을 나갈 때 부른다.
  ///
  /// 🔴 인터넷이 없으면 조용히 실패하고 `_dirty` 에 **그대로 남긴다.**
  ///    다음에 다시 올린다. 시장에서 신호가 약한 게 보통이다.
  Future<void> flush() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    if (!_ready || _dirty.isEmpty) return;
    final uid = _openedFor;
    if (uid == null) return;             // 로그인 전에는 폰에만 둔다

    final pending = _dirty.toList();
    for (final id in pending) {
      final item = _box!.get(id);
      if (item == null) {
        _dirty.remove(id);
        continue;
      }
      final ok = await UserRepository.instance.backupPurchaseList(uid, item);
      if (ok) _dirty.remove(id);
    }
  }

  /// 아직 서버에 못 올린 게 있는가. 화면에 "저장 안 됨" 을 보여줄 때 쓴다.
  bool get hasUnsynced => _dirty.isNotEmpty;

  /// 기기를 바꾼 뒤 서버에서 내려받는다. 폰에 없는 것만 더한다.
  Future<int> restoreFromCloud() async {
    if (!_ready) return 0;
    final uid = _openedFor;
    if (uid == null) return 0;
    final remote = await UserRepository.instance.restorePurchaseLists(uid);
    var added = 0;
    for (final r in remote) {
      if (_box!.containsKey(r.id)) continue;
      await _box!.put(r.id, r);
      added++;
    }
    if (added > 0) notifyListeners();
    return added;
  }

  // ── 자주 산 품목 ─────────────────────────────────────────────

  /// 최근 3개월 영수증에서 **산 횟수가 많은 순**으로 최대 [limit] 개.
  ///
  /// 사장님 확정(#179): "최근 3개월 영수증 중 산 횟수가 많은 순으로 6개".
  static List<PriceBookEntry> frequentItems(
    List<ReceiptModel> receipts, {
    int limit = 6,
    DateTime? now,
  }) {
    final base = now ?? DateTime.now();
    final from = DateTime(base.year, base.month - 3, base.day);

    final count = <String, int>{};
    final recent = <String, DateTime>{};
    for (final r in receipts) {
      if (r.date.isBefore(from)) continue;
      // 🔴 한 영수증에 같은 품목이 두 줄 있어도 **한 번 산 것**으로 센다.
      //    아니면 줄을 나눠 적은 날이 유난히 자주 산 것처럼 보인다.
      final seen = <String>{};
      for (final it in r.items) {
        final name = it.name.trim();
        if (name.isEmpty || seen.contains(name)) continue;
        seen.add(name);
        count[name] = (count[name] ?? 0) + 1;
        final old = recent[name];
        if (old == null || r.date.isAfter(old)) recent[name] = r.date;
      }
    }
    if (count.isEmpty) return const <PriceBookEntry>[];

    final names = count.keys.toList()
      ..sort((a, b) {
        final c = count[b]!.compareTo(count[a]!);
        if (c != 0) return c;
        // 횟수가 같으면 최근에 산 것을 앞에 둔다.
        return recent[b]!.compareTo(recent[a]!);
      });

    // 단가는 가장 최근 영수증 값을 쓴다. 장부가 이미 그렇게 만들어 준다.
    final book = PriceBook.fromReceipts(receipts);
    final out = <PriceBookEntry>[];
    for (final n in names) {
      final e = book.lookup(n);
      if (e != null) out.add(e);
      if (out.length >= limit) break;
    }
    return out;
  }
}
