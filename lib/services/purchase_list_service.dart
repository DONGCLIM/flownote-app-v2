import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    // 🔴 임시 메모장 id 를 **여기서** 읽어 둔다(#189). 그래야 메모장 화면이
    //    `initState` 에서 기다리지 않고 바로 펼칠 수 있다. 화면이 await 하면
    //    한 박자 빈 화면이 보였다가 글이 튀어나와 깜빡인다.
    await _loadDraftId();
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

  /// 저장된 사입 리스트 화면 위쪽 요약. (#187)
  ///
  /// 🔴 평균을 **전체 건수**로 나누지 않는다. 메모만 적은 리스트는
  ///    금액이 0 이라, 그걸 분모에 넣으면 평균이 확 내려간다.
  static PurchaseSummary summarize(List<PurchaseList> lists) {
    if (lists.isEmpty) return PurchaseSummary.zero;
    var total = 0.0;
    var priced = 0;
    for (final e in lists) {
      if (e.isMemoOnly) continue;
      total += e.plannedTotal;
      priced++;
    }
    return PurchaseSummary(
      count: lists.length,
      total: total,
      average: priced == 0 ? 0 : total / priced,
    );
  }

  /// 지금 저장된 것들의 요약.
  PurchaseSummary get summary => summarize(all);

  /// 아직 저장하지 않은 **임시 메모장**의 id. (#189)
  ///
  /// 🔴 왜 따로 두나 — 예전에는 가이드·칩으로 메모장을 열면
  ///    [activeOne](아직 안 끝난 리스트 중 가장 최근 것)을 집어 왔다.
  ///    그래서 예산 검토에서 저장해 둔 **남의 리스트에 메모가 덮어써졌다.**
  ///    이제 새 메모장은 자기만의 임시 리스트를 쓰고, 그 id 를 여기 적어
  ///    둔다. 앱을 꺼도 남아 있어서 쓰던 메모가 그대로 돌아온다.
  ///
  /// 🔴 저장 구조를 새로 만들지 않았다. 담기는 곳은 1단계와 같은
  ///    `PurchaseList` 상자다. 여기엔 **어느 것이 임시인지** 만 적어 둔다.
  static const String _draftKey = 'fn_memo_draft_id';

  String? _draftId;
  bool _draftLoaded = false;

  /// 쓰던 임시 메모장을 가져온다. 없으면 새로 만든다. (저장은 아직 안 한다)
  ///
  /// 🔴 **기다리지 않는다.** id 는 [init] 에서 이미 읽어 뒀다. 새로 만들
  ///    때만 적어 두는데, 그건 뒤에서 조용히 한다. 메모장을 여는 순간
  ///    바로 글이 보여야 해서다.
  PurchaseList memoDraft() {
    final id = _draftId;
    if (id != null) {
      final found = byId(id);
      if (found != null) return found;
    }
    final made = draft();
    _draftId = made.id;
    unawaited(_writeDraftId(made.id));
    return made;
  }

  /// 이 리스트가 아직 저장 안 한 임시 메모장인가.
  bool isMemoDraft(String id) => _draftId == id;

  /// 임시 메모장을 **진짜 리스트로 굳힌다.** 저장이 끝나면 부른다.
  ///
  /// 🔴 굳힌 뒤에는 임시 표시를 지운다. 그래야 다음에 메모장을 열면
  ///    빈 메모장·빈 스케치로 시작한다. 사장님 지시(#189).
  Future<void> clearMemoDraft() async {
    _draftId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {/* 못 지워도 다음에 덮어쓴다 */}
  }

  Future<void> _loadDraftId() async {
    if (_draftLoaded) return;
    _draftLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_draftKey);
      if (v != null && v.isNotEmpty) _draftId = v;
    } catch (_) {/* 처음 쓰는 폰 */}
  }

  Future<void> _writeDraftId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, id);
    } catch (_) {/* 못 적어도 이번 화면에서는 돌아간다 */}
  }

  /// 저장된 목록 — **임시 메모장은 뺀다.** (#189)
  ///
  /// 🔴 저장된 사입 리스트 화면은 이걸 본다. 아직 "저장" 을 안 누른
  ///    임시 작성분이 목록에 섞이면, 사장님은 저장한 적도 없는 빈
  ///    리스트가 왜 있는지 알 수 없다.
  List<PurchaseList> get saved =>
      List<PurchaseList>.unmodifiable(all.where((e) => !isMemoDraft(e.id)));

  /// 저장된 것만으로 센 요약.
  PurchaseSummary get savedSummary => summarize(saved);

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

  /// 폰에 바로 쓰고, 올릴 것으로 표시해 둔다.
  ///
  /// 🔴 [sync] 를 켤 때만 서버 올리기를 예약한다(#191). 사장님 지시:
  ///    "저장 횟수 줄이기: 입력할 때마다 말고 저장 버튼·화면 나갈 때·
  ///    체크할 때만". 예전에는 글자 하나마다 4초 타이머를 다시 걸어서,
  ///    긴 메모를 적으면 타이머가 수백 번 섰다 없어졌다.
  ///    표시(`_dirty`)는 늘 남기므로 나갈 때 [flush] 가 한 번에 올린다.
  Future<void> touch(
    PurchaseList list, {
    bool notify = true,
    bool sync = false,
  }) async {
    if (!_ready) return;
    list.updatedAt = DateTime.now();
    await _box!.put(list.id, list);
    _dirty.add(list.id);
    if (sync) _scheduleSync();
    if (notify) notifyListeners();
  }

  /// **지금 바로** 저장한다. 자동 저장(4초)을 기다리지 않는다. (#188)
  ///
  /// 🔴 왜 [touch] 를 안 쓰나 — `touch` 는 상자가 안 열려 있으면 첫 줄
  ///    `if (!_ready) return;` 에서 **조용히 아무것도 안 하고 끝난다.**
  ///    저장 버튼은 성공한 줄 알고 넘어갔고, 저장된 사입 리스트는
  ///    늘 비어 있었다(#188 버그). 여기서는
  ///    1) 상자가 닫혀 있으면 열어 보고,
  ///    2) 그래도 안 되면 **false 를 돌려준다.**
  ///    화면이 그걸 보고 "저장하지 못했어요" 라고 알린다.
  ///
  /// 서버 올리기는 기다리지 않는다. 폰(Hive)에 들어갔으면 저장된 것이다.
  /// 꽃시장은 인터넷이 자주 끊기는데, 그때마다 저장을 막으면 안 된다.
  Future<bool> saveNow(PurchaseList list) async {
    if (!_ready) {
      try {
        await _openFor(AuthService.instance.uid);
      } catch (_) {
        return false;
      }
    }
    if (!_ready || _box == null) return false;
    try {
      list.updatedAt = DateTime.now();
      await _box!.put(list.id, list);
      _dirty.add(list.id);
    } catch (_) {
      return false;
    }
    notifyListeners();
    unawaited(flush());
    return true;
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
      // 🔴 아직 "저장" 을 안 누른 임시 메모장은 **올리지 않는다**(#191).
      //    사장님 지시: "새 메모장 임시 작성분은 기기에만 두고 올리지 않기".
      //    올려 버리면 PC 에서 열었을 때 적다 만 메모가 리스트에 뜬다.
      if (isMemoDraft(id)) continue;
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

  /// 어느 쪽을 남길지 고른다 — **나중에 저장한 쪽이 이긴다.** (#191)
  ///
  /// 🔴 사장님 지시(#191): "같은 리스트를 두 기기에서 고쳤으면 나중에
  ///    저장한 쪽이 이김". 시각이 같으면 폰 것을 남긴다. 눈앞의 기기에서
  ///    방금 본 내용이 갑자기 바뀌면 고장으로 보인다.
  @visibleForTesting
  static bool remoteWins(PurchaseList? local, PurchaseList remote) {
    if (local == null) return true;
    return remote.updatedAt.isAfter(local.updatedAt);
  }

  /// 클라우드와 맞춘다. 내려받고, 폰에만 있던 것은 올린다. (#191)
  ///
  /// ```
  ///   서버에만 있다        → 폰에 넣는다          (다른 기기에서 적은 것)
  ///   양쪽에 있다          → updatedAt 늦은 쪽    (나중에 저장한 쪽이 이김)
  ///   폰에만 있다          → 서버에 올린다        (옛 리스트 챙기기)
  ///   임시 작성분          → 건드리지 않는다      (기기에만 둔다)
  /// ```
  ///
  /// 🔴 인터넷이 없으면 [UserRepository] 가 빈 목록을 주고, 올리기는
  ///    조용히 실패해 `_dirty` 에 남는다. 앱은 폰 저장만으로 그대로 돈다.
  ///
  /// 돌려주는 값은 **새로 받아 온 건수**다.
  Future<int> syncWithCloud() async {
    if (!_ready) return 0;
    final uid = _openedFor;
    if (uid == null) return 0;            // 로그인 전에는 폰에만 둔다

    var pulled = 0;
    final seen = <String>{};
    try {
      final remote = await UserRepository.instance.restorePurchaseLists(uid);
      for (final r in remote) {
        seen.add(r.id);
        // 임시 작성분 id 와 겹치면 손대지 않는다. 적다 만 글이 날아간다.
        if (isMemoDraft(r.id)) continue;
        final local = _box!.get(r.id);
        if (!remoteWins(local, r)) continue;
        await _box!.put(r.id, r);
        pulled++;
      }
    } catch (_) {
      // 인터넷이 없다. 폰 것만으로 돈다.
    }

    // 🔴 폰에만 있던 리스트를 올린다(#191). 사장님 지시: "기존에 폰에만
    //    있던 리스트도 처음 열 때 클라우드로 올라가게".
    for (final e in saved) {
      if (seen.contains(e.id)) continue;
      _dirty.add(e.id);
    }
    await flush();

    if (pulled > 0) notifyListeners();
    return pulled;
  }

  /// 예전 이름. 부르는 곳이 남아 있을 수 있어 남겨 둔다.
  Future<int> restoreFromCloud() => syncWithCloud();

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

/// 저장된 사입 리스트 화면이 쓰는 요약. (#187)
///
/// 🔴 **예산을 적은 리스트만** 금액에 넣는다. 사장님 지시(#187):
///    "예산 없는 메모 리스트는 금액 계산에서 제외". 메모만 적어 둔
///    리스트까지 평균에 넣으면 1회 평균이 실제보다 낮게 나온다.
@immutable
class PurchaseSummary {
  const PurchaseSummary({
    required this.count,
    required this.total,
    required this.average,
  });

  /// 저장된 리스트 **전체** 건수. 메모 리스트도 센다.
  final int count;

  /// 예상 예산 합계. 품목이 있는 리스트만 더한다.
  final double total;

  /// 1회 평균 = 합계 ÷ **품목이 있는 리스트 수**.
  final double average;

  static const PurchaseSummary zero =
      PurchaseSummary(count: 0, total: 0, average: 0);
}

/// 메모 한 줄 — 글과 체크 상태. (#185)
@immutable
class MemoLine {
  const MemoLine({required this.text, this.checked = false});

  final String text;
  final bool checked;

  MemoLine copyWith({String? text, bool? checked}) =>
      MemoLine(text: text ?? this.text, checked: checked ?? this.checked);

  @override
  bool operator ==(Object other) =>
      other is MemoLine && other.text == text && other.checked == checked;

  @override
  int get hashCode => Object.hash(text, checked);
}

/// 체크할 수 있는 메모를 [PurchaseList.memo] **한 칸에** 담는 방법. (#185)
///
/// 🔴 사장님 지시: "새 저장 구조는 만들지 마." 그래서 체크 상태를 담을
///    필드를 새로 만들지 않고, 글 앞에 표시를 붙여 **한 줄에 같이** 적는다.
///
/// ```
///   [ ] 금요일 웨딩 부케 3개 — 화이트 위주     ← 아직 안 샀다
///   [x] 장미(레드) 단가 오르면 소국으로 대체   ← 샀다
/// ```
///
/// 🔴 표시가 없는 줄도 그냥 읽는다. 1단계에서 적어 둔 메모(표시가 없다)가
///    이미 있을 수 있는데, 그걸 못 읽으면 사장님 글이 사라진다.
class MemoText {
  MemoText._();

  static const String doneMark = '[x] ';
  static const String openMark = '[ ] ';

  /// 글자를 줄 목록으로 푼다.
  static List<MemoLine> parse(String raw) {
    if (raw.isEmpty) return const <MemoLine>[];
    return [
      for (final line in raw.split('\n'))
        if (line.startsWith(doneMark))
          MemoLine(text: line.substring(doneMark.length), checked: true)
        else if (line.startsWith(openMark))
          MemoLine(text: line.substring(openMark.length))
        else
          // 표시가 없는 옛 메모. 아직 안 산 줄로 본다.
          MemoLine(text: line),
    ];
  }

  /// 줄 목록을 저장할 글자로 되돌린다.
  ///
  /// 🔴 맨 끝의 빈 줄은 버린다. 엔터만 치고 나가면 빈 줄이 쌓여서,
  ///    다시 열 때마다 메모가 아래로 밀려 내려간다.
  static String encode(List<MemoLine> lines) {
    final kept = List<MemoLine>.from(lines);
    while (kept.isNotEmpty && kept.last.text.trim().isEmpty) {
      kept.removeLast();
    }
    return kept
        .map((e) => '${e.checked ? doneMark : openMark}${e.text}')
        .join('\n');
  }

  /// 글이 있는 줄 수. 빈 줄은 세지 않는다.
  static int total(List<MemoLine> lines) =>
      lines.where((e) => e.text.trim().isNotEmpty).length;

  /// 산 줄 수.
  static int done(List<MemoLine> lines) =>
      lines.where((e) => e.checked && e.text.trim().isNotEmpty).length;

  /// 탭에 적는 `3/5`. 글이 하나도 없으면 빈 글자.
  static String counter(List<MemoLine> lines) {
    final t = total(lines);
    if (t == 0) return '';
    return '${done(lines)}/$t';
  }
}
