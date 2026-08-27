import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/receipt_model.dart';
import '../services/auth_service.dart';
import '../services/receipt_image_store.dart';
import '../services/user_repository.dart';
import 'dart:math';

class ReceiptProvider extends ChangeNotifier {
  late Box<ReceiptModel> _box;
  bool _isLoading = false;
  String? _error;
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();

  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime get selectedDay => _selectedDay;
  DateTime get focusedDay => _focusedDay;

  List<ReceiptModel> get allReceipts {
    final list = _box.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Future<void> init() async {
    _box = await Hive.openBox<ReceiptModel>('receipts');
    // Load sample data if empty
    if (_box.isEmpty) {
      await _loadSampleData();
    }
    notifyListeners();
  }

  Future<void> _loadSampleData() async {
    final rng = Random(42);

    final vendors = [
      {'name': '한국화훼 도매(주)', 'bizNo': '102-81-34567'},
      {'name': '서울꽃시장 도매', 'bizNo': '201-34-56789'},
      {'name': '강남 플라워 도매', 'bizNo': '305-12-98765'},
      {'name': '부산항 수입화훼', 'bizNo': '614-22-11234'},
      {'name': '경기도 화훼농장', 'bizNo': '131-45-88901'},
    ];

    // 업체별 품목 + 기준 단가
    final flowersByVendor = {
      '한국화훼 도매(주)': [
        ['장미(레드)', 1700.0], ['장미(핑크)', 1550.0], ['장미(화이트)', 1450.0],
        ['장미(오렌지)', 1650.0], ['프리미엄 장미(대)', 2100.0],
        ['작약(분홍)', 2300.0], ['작약(화이트)', 2100.0],
        ['스프레이장미', 1050.0], ['미니 장미', 850.0],
      ],
      '서울꽃시장 도매': [
        ['국화(백)', 750.0], ['국화(황)', 650.0], ['국화(분홍)', 700.0],
        ['거베라(레드)', 900.0], ['거베라(오렌지)', 850.0],
        ['카네이션(빨강)', 660.0], ['카네이션(핑크)', 610.0],
        ['수국(블루)', 2400.0], ['수국(핑크)', 2300.0],
        ['리시안셔스', 1200.0], ['알리움', 1000.0],
      ],
      '강남 플라워 도매': [
        ['라넌큘러스(분홍)', 1800.0], ['라넌큘러스(화이트)', 1700.0],
        ['아네모네', 1350.0], ['프리지아(황)', 980.0], ['프리지아(화이트)', 930.0],
        ['델피늄(블루)', 1100.0], ['스냅드래곤', 880.0],
        ['알스트로메리아', 800.0], ['튤립(레드)', 1200.0],
        ['튤립(핑크)', 1150.0], ['튤립(화이트)', 1100.0],
      ],
      '부산항 수입화훼': [
        ['수입 튤립(네덜란드)', 2100.0], ['수입 장미(에콰도르)', 2700.0],
        ['극락조화', 3400.0], ['안스리움(레드)', 3100.0], ['안스리움(핑크)', 3000.0],
        ['스카비오사', 1500.0], ['유칼립투스', 1850.0],
        ['수입 수국(그린)', 2700.0], ['목화솜가지', 1300.0],
      ],
      '경기도 화훼농장': [
        ['계절 혼합 야생화', 550.0], ['해바라기', 800.0],
        ['코스모스', 450.0], ['금잔화', 400.0],
        ['팬지', 320.0], ['라벤더', 1050.0],
        ['로즈마리 가지', 650.0], ['녹색 잎사귀(대엽)', 380.0],
        ['유카리 가지', 850.0],
      ],
    };

    // 월별 구매일 목록
    final purchaseDaysByMonth = <int, List<int>>{
      1: [3, 5, 7, 9, 11, 14, 16, 18, 20, 22, 25, 27, 29, 31],
      2: [2, 4, 6, 9, 11, 13, 16, 18, 20, 23, 25, 27],
      3: [2, 4, 6, 9, 11, 13, 16, 18, 20, 23, 25, 27, 29, 31],
      4: [1, 3, 5, 8, 10, 12, 15, 17, 19, 22, 24, 26, 28, 30],
    };

    // 월별 계절 단가 보정 계수
    // 봄(3~4월): 수요 증가로 단가 상승 / 겨울(1~2월): 비수기
    final seasonMultiplier = <int, double>{
      1: 0.95,   // 1월: 비수기, 단가 약간 낮음
      2: 1.00,   // 2월: 평월
      3: 1.12,   // 3월: 봄 성수기, 단가 상승
      4: 1.08,   // 4월: 봄 지속, 단가 높음
    };

    // 연도별 전반적인 단가 상승 (2026년은 2025년 대비 약 3~5% 상승)
    final yearMultiplier = <int, double>{
      2025: 1.00,
      2026: 1.04,
    };

    int sampleIdx = 0;

    // 2025년 1~4월 + 2026년 1~3월 생성
    final schedule = [
      {'year': 2025, 'months': [1, 2, 3, 4]},
      {'year': 2026, 'months': [1, 2, 3]},
    ];

    for (final s in schedule) {
      final year = s['year'] as int;
      final months = s['months'] as List<int>;
      final yMult = yearMultiplier[year]!;

      for (final month in months) {
        final days = purchaseDaysByMonth[month]!;
        final sMult = seasonMultiplier[month]!;

        for (final vendor in vendors) {
          final flowers = flowersByVendor[vendor['name']]!;
          final pickDays = List<int>.from(days)..shuffle(rng);
          final purchaseCount = rng.nextInt(2) + 5; // 5~6회/월
          final selectedDays = pickDays.take(purchaseCount).toList()..sort();

          for (final day in selectedDays) {
            final purchaseDate = DateTime(year, month, day);
            final itemCount = rng.nextInt(4) + 2; // 2~5가지 꽃
            final shuffled = List.from(flowers)..shuffle(rng);
            final selectedItems = shuffled.take(itemCount).toList();

            final items = selectedItems.map((f) {
              final qty = rng.nextInt(26) + 5; // 5~30단
              final basePrice = (f[1] as double);
              // 기준단가 × 연도 보정 × 계절 보정 + 소폭 랜덤 변동
              final adjustedBase = basePrice * yMult * sMult;
              final variation = (rng.nextInt(9) - 4) * 50.0; // ±200원
              final price = (adjustedBase + variation).clamp(300.0, 9999.0);
              return FlowerItem(
                name: f[0] as String,
                quantity: qty,
                unitPrice: price,
                unit: '단',
              );
            }).toList();

            final total = items.fold(0.0, (s, i) => s + i.totalPrice);

            final receipt = ReceiptModel(
              id: 'sample_$sampleIdx',
              date: purchaseDate,
              storeName: vendor['name']!,
              items: items,
              totalAmount: total,
              rawOcrText: '샘플 영수증 - ${vendor['name']} (${year}년 ${month}월 ${day}일)',
              createdAt: DateTime(year, month, day, 8 + rng.nextInt(10)),
            );
            await _box.put(receipt.id, receipt);
            sampleIdx++;
          }
        }
      }
    }
    if (kDebugMode) debugPrint('✓ 샘플 영수증 $sampleIdx건 생성 완료 (2025.1~4 + 2026.1~3)');
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
    if (uid == null) return 0;
    return UserRepository.instance.backupReceipts(uid, _box.values.toList());
  }

  /// 기기 변경 후 복원 — 로컬에 없는 영수증만 가져온다.
  Future<int> restoreFromCloud() async {
    final uid = _uid;
    if (uid == null) return 0;
    final remote = await UserRepository.instance.restoreReceipts(uid);
    var added = 0;
    for (final r in remote) {
      if (_box.containsKey(r.id)) continue;
      await _box.put(r.id, r);
      added++;
    }
    if (added > 0) notifyListeners();
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
    _syncUp(receipt);
    notifyListeners();
  }

  Future<void> updateReceipt(ReceiptModel receipt) async {
    // 수정 화면에서 사진을 새로 붙였을 수도 있다. 캐시 경로면 옮긴다.
    // (이미 영구 폴더면 persist 가 그대로 돌려준다)
    receipt.imagePath = await ReceiptImageStore.instance
        .persist(receipt.imagePath, receiptId: receipt.id);
    await _box.put(receipt.id, receipt);
    _syncUp(receipt);
    notifyListeners();
  }

  Future<void> deleteReceipt(String id) async {
    // 영수증을 지울 때 보관 사진도 같이 지운다. 안 지우면 저장공간만 먹는다.
    final r = _box.get(id);
    if (r != null) await ReceiptImageStore.instance.remove(r.imagePath);
    await _box.delete(id);
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
