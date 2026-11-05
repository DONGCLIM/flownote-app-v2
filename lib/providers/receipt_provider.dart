import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/receipt_model.dart';
import '../services/auth_service.dart';
import '../services/receipt_image_store.dart';
import '../services/user_repository.dart';

class ReceiptProvider extends ChangeNotifier {
  late Box<ReceiptModel> _box;
  bool _isLoading = false;
  String? _error;
  DateTime _selectedDay = DateTime.now();
  /// [allReceipts] 결과 캐시. 목록이 바뀌면 null 로 버린다.
  List<ReceiptModel>? _cache;
  DateTime _focusedDay = DateTime.now();

  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime get selectedDay => _selectedDay;
  DateTime get focusedDay => _focusedDay;

  /// 전체 영수증 (최신순)
  ///
  /// 🔴 결과를 캐시한다. 예전에는 getter 를 부를 때마다
  ///    `_box.values.toList()` + 전체 정렬을 다시 했다. 홈·구매내역·
  ///    캘린더 3개 탭이 각자 이 getter 를 여러 번 부르므로, 저장 한 번에
  ///    수십 번씩 정렬이 돌았다.
  ///
  ///    실측: 1000건에서 12회 호출 = 25ms / 600회 호출 = 95ms
  ///
  ///    캐시는 영수증이 실제로 바뀔 때만 [_invalidate] 로 버린다.
  ///    (날짜 선택 같은 UI 상태 변경으로는 버리지 않는다)
  List<ReceiptModel> get allReceipts {
    final cached = _cache;
    if (cached != null) return cached;
    // 🔴 상자를 갈아타는 찰나에 화면이 다시 그려질 수 있다. 그때 닫힌
    //    상자를 읽으면 앱이 죽는다. 아직 안 열렸으면 빈 목록을 준다.
    //    (전환이 끝나면 notifyListeners() 로 다시 그려진다)
    if (!_ready) return const <ReceiptModel>[];
    final list = _box.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return _cache = List<ReceiptModel>.unmodifiable(list);
  }

  /// 영수증 목록이 바뀌었으니 캐시를 버린다.
  void _invalidate() => _cache = null;

  /// 여러 건을 저장할 때 알림을 한 번으로 묶기 위한 잠금.
  bool _muted = false;

  @override
  void notifyListeners() {
    if (_muted) return;
    super.notifyListeners();
  }

  /// [body] 안에서 일어나는 알림을 모아 **끝에 한 번만** 보낸다.
  ///
  /// 🔴 왜 필요한가 — 영수증 4장을 저장하면 `addReceipt` 가 4번 돌면서
  ///    `notifyListeners()` 도 4번 났다. 그때마다 화면 전체가 다시
  ///    계산되니, 여러 장 스캔 후 뒤로 나올 때 특히 굼떴다.
  Future<T> batch<T>(Future<T> Function() body) async {
    if (_muted) return body();          // 중첩 호출 보호
    _muted = true;
    try {
      return await body();
    } finally {
      _muted = false;
      _invalidate();
      notifyListeners();
    }
  }

  // ── 계정별 상자 ────────────────────────────────────────────
  //
  // 🔴 예전에는 `receipts` 상자 **하나**만 썼다. 그래서 한 폰에서 계정을
  //    바꿔 로그인하면 **앞사람 영수증이 그대로 보였다.** 게다가 로그인
  //    직후 `pushAllToCloud()` 가 그 영수증을 지금 계정 것으로 클라우드에
  //    올려버려서, 섞인 상태가 서버까지 퍼졌다.
  //
  //    → 이제 **계정마다 상자를 따로** 쓴다. 로그아웃하면 그 상자를 닫고,
  //      다음 사람이 로그인하면 그 사람 상자를 연다. 서로 볼 수 없다.

  /// 옛 공용 상자. 섞여 있어서 더는 쓰지 않는다.
  static const String legacyBoxName = 'receipts';

  /// 로그인 전에 쓰는 상자. 로그인하면 자기 상자로 갈아탄다.
  static const String guestBoxName = 'receipts_guest';

  /// 이 계정이 쓸 상자 이름.
  ///
  /// 🔴 uid 를 그대로 붙이지 않고 **해시**를 쓴다. 두 가지 이유다.
  ///    ① Hive 는 상자 이름의 **대소문자를 구분하지 않는다.** Firebase uid
  ///       는 구분한다(`aB…` 와 `Ab…` 는 다른 사람). 그대로 쓰면 두 사람이
  ///       같은 상자를 보게 된다.
  ///    ② 카카오 uid 에는 `:` 가 들어간다(`kakao:123`). 파일 이름에 쓸 수
  ///       없는 글자다.
  static String boxNameFor(String? uid) {
    if (uid == null || uid.isEmpty) return guestBoxName;
    final h = sha256.convert(utf8.encode(uid)).toString();
    return 'receipts_${h.substring(0, 32)}';
  }

  /// 지금 열려 있는 상자의 주인. 로그인 전이면 null.
  String? _openedFor;

  /// 상자가 열렸는가. 열리기 전에 [allReceipts] 를 부를 수 있어서 둔다.
  bool _ready = false;

  StreamSubscription<User?>? _authSub;

  Future<void> init() async {
    await _openFor(AuthService.instance.uid);

    // 옛 공용 상자를 지운다. 누구 것인지 알 수 없게 섞여 있어서, 남겨두면
    // 다음에 또 새어 나간다. 사장님 지시로 깨끗이 지우기로 했다.
    // 자기 영수증은 클라우드 백업에서 다시 내려받는다.
    await _dropLegacyBox();

    // 로그인·로그아웃을 따라 상자를 갈아탄다.
    // 구독하는 순간 현재 상태가 한 번 흘러오므로 첫 상자도 여기서 맞춰진다.
    _authSub?.cancel();
    _authSub = AuthService.instance.authStateChanges.listen((u) {
      switchAccount(u?.uid);
    });

    notifyListeners();
  }

  /// 계정이 바뀌었으니 상자를 갈아탄다.
  ///
  /// 🔴 로그아웃(`uid == null`)도 반드시 거쳐야 한다. 안 갈아타면 로그아웃
  ///    상태에서 앞사람 영수증이 그대로 보인다.
  Future<void> switchAccount(String? uid) async {
    if (_ready && _openedFor == uid) return;   // 이미 그 사람 상자다
    await _openFor(uid);
    notifyListeners();
  }

  Future<void> _openFor(String? uid) async {
    final name = boxNameFor(uid);
    if (_ready) {
      // 🔴 먼저 닫는다. 닫지 않으면 이전 상자가 메모리에 남아 다음 계정이
      //    쓰는 동안에도 살아 있다.
      try {
        await _box.close();
      } catch (_) {/* 이미 닫혔으면 넘어간다 */}
      _ready = false;
    }
    _box = await Hive.openBox<ReceiptModel>(name);
    _openedFor = uid;
    _ready = true;
    _invalidate();
    if (kDebugMode) {
      debugPrint('[Receipt] 상자 전환 → $name (${_box.length}건)');
    }
  }

  /// 옛 공용 상자를 디스크에서 없앤다. 한 번만 하면 된다.
  Future<void> _dropLegacyBox() async {
    try {
      if (!await Hive.boxExists(legacyBoxName)) return;
      await Hive.deleteBoxFromDisk(legacyBoxName);
      if (kDebugMode) debugPrint('[Receipt] 옛 공용 상자를 지웠습니다.');
    } catch (e) {
      if (kDebugMode) debugPrint('[Receipt] 옛 상자 삭제 실패: $e');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  List<ReceiptModel> getReceiptsForDay(DateTime day) {
    return allReceipts.where((r) =>
        r.date.year == day.year &&
        r.date.month == day.month &&
        r.date.day == day.day).toList();
  }

  Map<DateTime, List<ReceiptModel>> get receiptsByDay {
    final map = <DateTime, List<ReceiptModel>>{};
    for (final receipt in allReceipts) {
      final day = DateTime(receipt.date.year, receipt.date.month, receipt.date.day);
      map.putIfAbsent(day, () => []).add(receipt);
    }
    return map;
  }

  double getTotalForDay(DateTime day) {
    return getReceiptsForDay(day).fold(0.0, (sum, r) => sum + r.totalAmount);
  }

  double get monthlyTotal {
    return allReceipts
        .where((r) =>
            r.date.year == _focusedDay.year &&
            r.date.month == _focusedDay.month)
        .fold(0.0, (sum, r) => sum + r.totalAmount);
  }

  int get monthlyReceiptCount {
    return allReceipts
        .where((r) =>
            r.date.year == _focusedDay.year &&
            r.date.month == _focusedDay.month)
        .length;
  }

  void setSelectedDay(DateTime day) {
    _selectedDay = day;
    notifyListeners();
  }

  void setFocusedDay(DateTime day) {
    _focusedDay = day;
    notifyListeners();
  }

  // ── 분석용 메서드 ──

  /// 특정 연월 총지출
  double getMonthTotal(int year, int month) {
    return allReceipts
        .where((r) => r.date.year == year && r.date.month == month)
        .fold(0.0, (s, r) => s + r.totalAmount);
  }

  /// 특정 연월 영수증 건수
  int getMonthCount(int year, int month) {
    return allReceipts
        .where((r) => r.date.year == year && r.date.month == month)
        .length;
  }

  /// 보유 데이터의 연월 목록 (오름차순)
  List<DateTime> get availableMonths {
    final set = <String>{};
    final list = <DateTime>[];
    for (final r in allReceipts) {
      final key = '${r.date.year}-${r.date.month}';
      if (set.add(key)) {
        list.add(DateTime(r.date.year, r.date.month));
      }
    }
    list.sort();
    return list;
  }

  /// 품목별 월별 평균 단가 맵  { 품목명: { 'YYYY-MM': 평균단가 } }
  Map<String, Map<String, double>> get itemMonthlyCost {
    // { 품목명: { 'YYYY-MM': [단가 목록] } }
    final raw = <String, Map<String, List<double>>>{};
    for (final r in allReceipts) {
      final key = '${r.date.year}-${r.date.month.toString().padLeft(2,'0')}';
      for (final item in r.items) {
        raw.putIfAbsent(item.name, () => {});
        raw[item.name]!.putIfAbsent(key, () => []);
        raw[item.name]![key]!.add(item.unitPrice);
      }
    }
    final result = <String, Map<String, double>>{};
    for (final name in raw.keys) {
      result[name] = {};
      for (final ym in raw[name]!.keys) {
        final prices = raw[name]![ym]!;
        result[name]![ym] = prices.reduce((a, b) => a + b) / prices.length;
      }
    }
    return result;
  }

  /// 전체 구매 빈도 TOP N 품목
  List<MapEntry<String, int>> topItems(int n) {
    final count = <String, int>{};
    for (final r in allReceipts) {
      for (final item in r.items) {
        count[item.name] = (count[item.name] ?? 0) + 1;
      }
    }
    final sorted = count.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).toList();
  }

  /// 업체별 지출 비중 (전체 기간)
  Map<String, double> get vendorShare {
    final map = <String, double>{};
    for (final r in allReceipts) {
      map[r.storeName] = (map[r.storeName] ?? 0) + r.totalAmount;
    }
    return map;
  }

  // ────────────────────────────────────────────────────────────
  // 클라우드 백업 (오프라인 우선)
  //
  // 꽃시장에서는 인터넷이 불안정하므로 **Hive 가 항상 진실의 원천**이고
  // Firestore 는 기기 변경용 백업이다. 업로드는 실패해도 무시한다.
  // ────────────────────────────────────────────────────────────

  String? get _uid => AuthService.instance.uid;

  void _syncUp(ReceiptModel r) {
    final uid = _uid;
    if (uid == null) return;
    // await 하지 않는다 — 저장 UX 를 네트워크가 붙잡으면 안 된다.
    UserRepository.instance.backupReceipt(uid, r);
  }

  void _syncDelete(String id) {
    final uid = _uid;
    if (uid == null) return;
    UserRepository.instance.deleteReceiptBackup(uid, id);
  }

  /// 로그인 직후 전체 영수증을 클라우드로 밀어올린다.
  Future<int> pushAllToCloud() async {
    final uid = _uid;
    if (uid == null || !_ready) return 0;
    // 🔴 지금 열린 상자가 이 계정 것일 때만 올린다. 계정이 막 바뀐
    //    순간에 올리면 앞사람 영수증이 이 계정으로 올라간다.
    //    (예전에 클라우드가 섞인 바로 그 경로다)
    if (_openedFor != uid) return 0;
    return UserRepository.instance.backupReceipts(uid, _box.values.toList());
  }

  /// 기기 변경 후 복원 — 로컬에 없는 영수증만 가져온다.
  Future<int> restoreFromCloud() async {
    final uid = _uid;
    if (uid == null || !_ready) return 0;
    // 내려받은 영수증이 엉뚱한 상자에 들어가지 않게 한다.
    if (_openedFor != uid) return 0;
    final remote = await UserRepository.instance.restoreReceipts(uid);
    var added = 0;
    for (final r in remote) {
      if (_box.containsKey(r.id)) continue;
      await _box.put(r.id, r);
      added++;
    }
    if (added > 0) {
      _invalidate();
      notifyListeners();
    }
    return added;
  }

  /// 영수증을 저장한다.
  ///
  /// 🔴 저장 전에 사진을 **영구 폴더로 옮긴다.**
  ///    카메라/갤러리는 결과 파일을 캐시 폴더에 떨구는데, 캐시는 안드로이드가
  ///    예고 없이 비운다(저장공간 부족 · 캐시 삭제 · 앱 재설치).
  ///    경로를 그대로 저장하면 몇 주 뒤 상세 화면과 정산서 PDF 에서
  ///    '이미지를 불러올 수 없어요' 만 남는다.
  ///
  ///    저장 지점이 여러 곳(스캔·수동입력·캘린더)이라서 각 화면에서 처리하면
  ///    한 곳을 빠뜨린다. 모든 경로가 반드시 지나가는 여기서 한 번만 한다.
  Future<void> addReceipt(ReceiptModel receipt) async {
    receipt.imagePath = await ReceiptImageStore.instance
        .persist(receipt.imagePath, receiptId: receipt.id);
    await _box.put(receipt.id, receipt);
    _invalidate();
    _syncUp(receipt);
    notifyListeners();
  }

  Future<void> updateReceipt(ReceiptModel receipt) async {
    // 수정 화면에서 사진을 새로 붙였을 수도 있다. 캐시 경로면 옮긴다.
    // (이미 영구 폴더면 persist 가 그대로 돌려준다)
    receipt.imagePath = await ReceiptImageStore.instance
        .persist(receipt.imagePath, receiptId: receipt.id);
    await _box.put(receipt.id, receipt);
    _invalidate();
    _syncUp(receipt);
    notifyListeners();
  }

  Future<void> deleteReceipt(String id) async {
    // 영수증을 지울 때 보관 사진도 같이 지운다. 안 지우면 저장공간만 먹는다.
    final r = _box.get(id);
    if (r != null) await ReceiptImageStore.instance.remove(r.imagePath);
    await _box.delete(id);
    _invalidate();
    _syncDelete(id);
    notifyListeners();
  }

  Future<void> deleteReceipts(List<String> ids) async {
    for (final id in ids) {
      final r = _box.get(id);
      if (r != null) await ReceiptImageStore.instance.remove(r.imagePath);
      await _box.delete(id);
      _syncDelete(id);
    }
    _invalidate();
    notifyListeners();
  }

  Map<String, double> getFlowerSpending() {
    final map = <String, double>{};
    for (final receipt in allReceipts) {
      for (final item in receipt.items) {
        map[item.name] = (map[item.name] ?? 0.0) + item.totalPrice;
      }
    }
    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return sorted;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── 업체별 통계 ──

  /// 업체 목록 (총 지출 내림차순)
  List<_VendorStat> getVendorStats() {
    final map = <String, _VendorStat>{};
    for (final r in allReceipts) {
      final name = r.storeName.trim();
      if (!map.containsKey(name)) {
        map[name] = _VendorStat(name: name);
      }
      map[name]!.totalAmount += r.totalAmount;
      map[name]!.receiptCount++;
      map[name]!.receipts.add(r);
    }
    final list = map.values.toList();
    list.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return list;
  }

  /// 특정 업체의 월별 지출
  Map<String, double> getMonthlyByVendor(String vendorName) {
    final map = <String, double>{};
    for (final r in allReceipts) {
      if (r.storeName.trim() != vendorName) continue;
      final key = '${r.date.year}년 ${r.date.month}월';
      map[key] = (map[key] ?? 0.0) + r.totalAmount;
    }
    // 날짜순 정렬
    final entries = map.entries.toList()
      ..sort((a, b) {
        final pa = _parseMonthKey(a.key);
        final pb = _parseMonthKey(b.key);
        return pa.compareTo(pb);
      });
    return Map.fromEntries(entries);
  }

  DateTime _parseMonthKey(String key) {
    final parts = key.replaceAll('년 ', '-').replaceAll('월', '').split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }
}

class _VendorStat {
  final String name;
  double totalAmount = 0;
  int receiptCount = 0;
  List<ReceiptModel> receipts = [];
  _VendorStat({required this.name});
}
