import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PlanTier { free, pro }

/// 요금제 정책 (프로토타입 구독 안내 화면 기준)
class PlanPolicy {
  /// 무료 체험 기간
  static const int trialDays = 30;

  /// 월 구독료
  static const int monthlyPrice = 49000;

  /// 연 구독료 (2개월 무료)
  static const int yearlyPrice = 490000;

  /// FREE: 월 스캔 100장
  static const int freeMonthlyScans = 100;

  /// FREE: 연속 촬영 최대 5장
  static const int freeBurstLimit = 5;

  /// FREE: 정산서 발송 3회
  static const int freeExports = 3;

  /// PRO: 연속 촬영 최대 20장
  static const int proBurstLimit = 20;

  static const List<String> proFeatures = [
    '무제한 영수증 스캔 · OCR',
    '연속 촬영 최대 20장',
    '정산서 무제한 발송',
    '월간 매입 리포트 자동 생성',
    '시세 트래커 · 단가 비교',
    '면세 / 과세 자동 분류',
  ];
}

/// 구독 상태 관리
class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  static const _kTier = 'fn_plan_tier';
  static const _kStart = 'fn_plan_start';
  static const _kScans = 'fn_scan_count';
  static const _kScanMonth = 'fn_scan_month';
  static const _kExports = 'fn_export_count';

  PlanTier _tier = PlanTier.free;
  DateTime _startedAt = DateTime.now();
  int _scansThisMonth = 0;
  String _scanMonth = '';
  int _exports = 0;
  bool _loaded = false;

  /// 🔴 지금은 모든 기능을 전부 열어둔다.
  ///
  /// 아직 결제(인앱결제)를 붙이지 않았다. 결제 수단이 없는 상태에서
  /// 기능을 잠그면, 사장님은 돈을 낼 방법도 없이 "PRO 전용입니다" 만
  /// 보게 된다. 그건 제품이 아니라 막힌 길이다.
  ///
  /// 그래서 잠금 판단을 이 한 곳으로 모아 전부 통과시킨다.
  /// 화면마다 흩어진 `if (isPro)` 를 지우지 않은 이유는, 결제가 붙는 날
  /// **이 상수 하나만 false 로 바꾸면** 원래 정책이 그대로 살아나기
  /// 때문이다. 조건문을 다 뜯어내면 그때 다시 심어야 한다.
  static const bool unlockEverything = true;

  PlanTier get tier => _tier;

  /// 잠금 해제 기간에는 항상 PRO 로 취급한다.
  /// (실제 결제 상태는 [purchasedPro] 로 따로 본다)
  bool get isPro => unlockEverything || _tier == PlanTier.pro;
  bool get isFree => !isPro;

  /// 사용자가 **실제로** 결제해서 PRO 인지. 요금제 안내 화면에서만 쓴다.
  /// 전체 잠금 해제 상태를 결제 완료로 착각해 보여주면 안 된다.
  bool get purchasedPro => _tier == PlanTier.pro;
  DateTime get startedAt => _startedAt;
  int get scansThisMonth => _scansThisMonth;
  int get exportsUsed => _exports;
  bool get isLoaded => _loaded;

  /// 무료 체험 남은 일수 (PRO 는 null)
  int get trialDaysLeft {
    if (isPro) return 0;
    final used = DateTime.now().difference(_startedAt).inDays;
    final left = PlanPolicy.trialDays - used;
    return left < 0 ? 0 : left;
  }

  bool get trialExpired => isFree && trialDaysLeft <= 0;

  /// 남은 스캔 횟수 (PRO 는 -1 = 무제한)
  int get scansLeft =>
      isPro ? -1 : (PlanPolicy.freeMonthlyScans - _scansThisMonth).clamp(0, 999999);

  int get burstLimit =>
      isPro ? PlanPolicy.proBurstLimit : PlanPolicy.freeBurstLimit;

  int get exportsLeft =>
      isPro ? -1 : (PlanPolicy.freeExports - _exports).clamp(0, 999);

  bool get canScan => isPro || scansLeft > 0;
  bool get canExport => isPro || exportsLeft > 0;

  Future<void> init() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _tier = p.getString(_kTier) == 'pro' ? PlanTier.pro : PlanTier.free;
      final s = p.getInt(_kStart);
      _startedAt =
          s != null ? DateTime.fromMillisecondsSinceEpoch(s) : DateTime.now();
      if (s == null) await p.setInt(_kStart, _startedAt.millisecondsSinceEpoch);
      _scanMonth = p.getString(_kScanMonth) ?? _currentMonth;
      _scansThisMonth =
          _scanMonth == _currentMonth ? (p.getInt(_kScans) ?? 0) : 0;
      _exports = p.getInt(_kExports) ?? 0;
    } catch (e) {
      if (kDebugMode) debugPrint('[Subscription] load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  static String get _currentMonth {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  Future<void> recordScan([int count = 1]) async {
    if (isPro) return;
    final p = await SharedPreferences.getInstance();
    if (_scanMonth != _currentMonth) {
      _scanMonth = _currentMonth;
      _scansThisMonth = 0;
      await p.setString(_kScanMonth, _scanMonth);
    }
    _scansThisMonth += count;
    await p.setInt(_kScans, _scansThisMonth);
    notifyListeners();
  }

  Future<void> recordExport() async {
    if (isPro) return;
    _exports++;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kExports, _exports);
    notifyListeners();
  }

  Future<void> upgradeToPro() async {
    _tier = PlanTier.pro;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTier, 'pro');
    notifyListeners();
  }

  Future<void> downgradeToFree() async {
    _tier = PlanTier.free;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTier, 'free');
    notifyListeners();
  }
}
