import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 매입처 과세 유형
enum TaxType {
  /// 면세 - 생화(농산물) 매입
  exempt,

  /// 과세 - 부자재/포장재 매입 (부가세 10%)
  taxable,
}

extension TaxTypeX on TaxType {
  String get label => this == TaxType.exempt ? '면세' : '과세';
  String get key => this == TaxType.exempt ? 'exempt' : 'taxable';
  String get description =>
      this == TaxType.exempt ? '생화 · 부가세 없음' : '부자재 · 부가세 10%';

  static TaxType fromKey(String? k) =>
      k == 'taxable' ? TaxType.taxable : TaxType.exempt;
}

/// 매입처별 과세 유형을 저장/조회한다.
///
/// 프로토타입의 `localStorage['fn_vendor_tax']` 와 동일한 역할.
class VendorTaxService extends ChangeNotifier {
  VendorTaxService._();
  static final VendorTaxService instance = VendorTaxService._();

  static const _prefsKey = 'fn_vendor_tax';

  /// 프로토타입 기본값
  static const Map<String, TaxType> defaults = {
    '대한꽃도매': TaxType.exempt,
    '화람원예': TaxType.taxable,
    '미림화훼': TaxType.exempt,
    '그린플러스': TaxType.taxable,
  };

  final Map<String, TaxType> _map = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  Map<String, TaxType> get all => Map.unmodifiable(_map);

  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          _map[k] = TaxTypeX.fromKey(v as String?);
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VendorTax] load failed: $e');
    }
    // 기본값 병합 (사용자 설정이 우선)
    defaults.forEach((k, v) => _map.putIfAbsent(k, () => v));
    _loaded = true;
    notifyListeners();
  }

  /// 매입처의 과세 유형. 미등록 매입처는 이름으로 추론한다.
  TaxType typeOf(String vendor) {
    final v = vendor.trim();
    if (_map.containsKey(v)) return _map[v]!;
    return _guess(v);
  }

  bool isExempt(String vendor) => typeOf(vendor) == TaxType.exempt;
  bool isTaxable(String vendor) => typeOf(vendor) == TaxType.taxable;

  Future<void> setType(String vendor, TaxType type) async {
    _map[vendor.trim()] = type;
    notifyListeners();
    await _persist();
  }

  Future<void> toggle(String vendor) => setType(
        vendor,
        isExempt(vendor) ? TaxType.taxable : TaxType.exempt,
      );

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_map.map((k, v) => MapEntry(k, v.key))),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[VendorTax] save failed: $e');
    }
  }

  /// 등록되지 않은 매입처 이름으로 과세 유형 추론
  static TaxType _guess(String vendor) {
    const taxableHints = [
      '자재',
      '부자재',
      '포장',
      '리본',
      '자재상',
      '플러스',
      '원예',
      '가든',
      '데코',
      '패키지',
    ];
    for (final h in taxableHints) {
      if (vendor.contains(h)) return TaxType.taxable;
    }
    return TaxType.exempt; // 화훼 도매는 대부분 면세
  }

  /// 금액을 공급가액 / 부가세로 분리한다.
  ///
  /// 과세 매입처의 금액은 부가세 포함가로 간주 -> 공급가액 = 금액 / 1.1
  TaxSplit split(String vendor, double amount) {
    if (isExempt(vendor)) {
      return TaxSplit(supply: amount, vat: 0, total: amount, exempt: true);
    }
    final supply = (amount / 1.1).roundToDouble();
    return TaxSplit(
      supply: supply,
      vat: amount - supply,
      total: amount,
      exempt: false,
    );
  }
}

class TaxSplit {
  final double supply; // 공급가액
  final double vat; // 부가세
  final double total; // 합계
  final bool exempt;

  const TaxSplit({
    required this.supply,
    required this.vat,
    required this.total,
    required this.exempt,
  });

  static const zero =
      TaxSplit(supply: 0, vat: 0, total: 0, exempt: true);

  TaxSplit operator +(TaxSplit o) => TaxSplit(
        supply: supply + o.supply,
        vat: vat + o.vat,
        total: total + o.total,
        exempt: exempt && o.exempt,
      );
}
