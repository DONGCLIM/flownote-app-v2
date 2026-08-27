import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 꽃 계절 시세 패턴 (인사이트 탭)
/// ═══════════════════════════════════════════════════════════════════════
///
/// ## 이게 왜 영수증 카드가 아니라 인사이트에 있나
/// 영수증 카드에 붙는 `FlowerPriceLine` 은 **지금 사실**을 말한다
/// (`양재 경매가 11,827원/단 · 지난주보다 41% 올랐어요`). 반면 계절 패턴은
/// **평소 어떤가**를 말한다. 성격이 다르고, 영수증 찍는 중에 필요한 정보도
/// 아니다. 그래서 인사이트 탭으로 분리했다.
///
/// ## 단기 추세와 달리 계절은 실제로 반복된다
/// 같은 2년치 데이터(경매일 303일)로 두 가지를 따로 검증했다.
///
/// | 주장 | 검증 방법 | 결과 |
/// |---|---|---|
/// | "요즘 오르는 중" (단기) | 판정 후 다음 기간에도 같은 방향인가 | **51~53%** |
/// | "이 달은 비싼 편" (계절) | 1년차 판정이 2년차에도 같은 방향인가 | **73%** |
///
/// 단기는 동전 던지기라서 예측 문구를 전부 금지했지만(`FlowerPriceQuote`
/// 참고), 계절은 재현된다. 그래서 계절만 말한다.
///
/// ## 그래도 품목을 골라서 말한다
/// 전체 평균이 73%여도 품목별 편차가 크다. 실측 재현율:
/// 카네이션·델피니움·마가렛 100% · 리시안사스 92% · 거베라 91% · 장미 88% ·
/// **국화 62% · 백합 56% · 엽란 30% · 호접란 12%.**
///
/// 그래서 자산(`flower_season.json`)에는 아래를 **모두** 통과한 품목만 넣었다.
///   - 두 해 모두 10개월 이상 관측 (그 달 경매 3일 이상)
///   - 두 해 월별지수 상관 ≥ 0.6
///   - 검증 가능한 주장 6건 이상, 그 중 재현 ≥ 70%
///
/// 247품목 중 **32품목**만 남았다. 나머지는 아무 말도 하지 않는다 —
/// 국화·백합·유칼립투스처럼 흔한 꽃도 여기서 빠졌다. 흔한 것과 예측
/// 가능한 것은 다르다.
///
/// ## 문턱 ±10%
/// 연평균 대비 ±10% 안이면 "비싼/싼 편"이라고 하지 않는다. 문턱별 재현율은
/// ±5% 76% / ±10% 73% / ±15% 72% / ±25% 68% 로 큰 차이가 없어서, 말할 게
/// 있을 때만 말하도록 중간값을 골랐다.
class FlowerSeasonService {
  FlowerSeasonService._();
  static final FlowerSeasonService instance = FlowerSeasonService._();

  static const _assetPath = 'assets/data/flower_season.json';

  final Map<String, _Season> _items = {};
  int _band = 10;
  String _range = '';
  bool _loaded = false;

  bool get isReady => _loaded && _items.isNotEmpty;

  /// 수록 품목 수 (실측 32)
  int get itemCount => _items.length;

  /// `2024-08-26~2026-08-21` — 근거 기간을 화면에 밝히기 위해 필요하다.
  String get range => _range;

  /// 연평균 대비 이 폭 안이면 비싸다/싸다고 말하지 않는다.
  int get band => _band;

  int _monthOverride = 0;

  int get currentMonth =>
      _monthOverride > 0 ? _monthOverride : DateTime.now().month;

  @visibleForTesting
  void setMonthForTest(int m) => _monthOverride = (m >= 1 && m <= 12) ? m : 0;

  /// 자산 로드. 두 번 호출해도 안전하고, **실패해도 throw 하지 않는다.**
  /// 계절 정보는 부가 정보라서 없으면 인사이트 카드만 조용히 사라진다.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      _parse(raw);
    } catch (e) {
      debugPrint('[FlowerSeasonService] asset load failed: $e');
    }
    _loaded = true;
  }

  void _parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    _band = (json['band'] as num?)?.toInt() ?? 10;
    _range = '${json['range'] ?? ''}';
    final items = json['items'];
    if (items is! Map) return;
    _items.clear();
    // 자산은 2년 경매 물량 내림차순으로 정렬돼 있다. 그 순서를 그대로
    // 순위로 쓴다 — 사장님이 실제로 만질 확률의 대리 지표다.
    var rank = 0;
    items.forEach((name, v) {
      if (v is! Map) return;
      final m = v['m'];
      if (m is! Map) return;
      final idx = <int, int>{};
      m.forEach((k, val) {
        final mm = int.tryParse('$k');
        final vv = (val as num?)?.toInt();
        if (mm != null && mm >= 1 && mm <= 12 && vv != null) idx[mm] = vv;
      });
      if (idx.length < 10) return;
      _items['$name'] = _Season(
        name: '$name',
        index: idx,
        yearAvg: (v['b'] as num?)?.toInt() ?? 0,
        corr: (v['c'] as num?)?.toDouble() ?? 0,
        repeatRate: (v['r'] as num?)?.toDouble() ?? 0,
        rank: rank++,
      );
    });
  }

  /// 품목 하나의 계절 소견. 검증을 통과하지 못한 품목은 `null`.
  ///
  /// `장미 하젤` 처럼 품종까지 들어와도 품목(`장미`)으로 되돌려 찾는다 —
  /// 품종별 계절 패턴은 표본이 얇아서 검증하지 않았다.
  FlowerSeasonNote? lookup(String flowerName, {int? month}) {
    final name = flowerName.trim();
    if (name.isEmpty) return null;
    var e = _items[name];
    if (e == null) {
      final sp = name.indexOf(' ');
      if (sp > 0) e = _items[name.substring(0, sp)];
    }
    if (e == null) return null;
    final m = month ?? currentMonth;
    if (!e.index.containsKey(m)) return null;
    return FlowerSeasonNote(
      itemName: e.name,
      month: m,
      monthIndex: e.index[m]!,
      yearAvg: e.yearAvg,
      cheapestMonth: e.cheapest,
      priciestMonth: e.priciest,
      monthlyIndex: Map.unmodifiable(e.index),
      band: _band,
      repeatRate: e.repeatRate,
      isMajor: e.rank < majorRank,
    );
  }

  /// 이 순위 안쪽을 "많이 쓰는 꽃"으로 본다.
  ///
  /// 편차만으로 줄을 세우면 8월 목록 1·2위가 알스트메리아·캐모마일이 된다.
  /// 숫자로는 맞지만 대부분의 꽃집이 만지지 않는 품목이고, 정작 장미·거베라가
  /// 화면 밖으로 밀린다. 물량 상위 품목을 먼저 보여주는 게 실제로 쓸모 있다.
  static const majorRank = 12;

  /// 이번 달 소견을 화면에 올릴 순서로 정렬해 돌려준다.
  ///
  /// 1순위 **많이 쓰는 꽃**(물량 상위 12), 2순위 **연평균에서 많이 벗어난 것**.
  /// 밴드(±10%) 안이라 말할 게 없는 품목은 아예 제외한다.
  List<FlowerSeasonNote> notesForMonth({int? month, int limit = 6}) {
    final m = month ?? currentMonth;
    final out = <FlowerSeasonNote>[];
    for (final e in _items.values) {
      if (!e.index.containsKey(m)) continue;
      final n = lookup(e.name, month: m);
      if (n == null || !n.hasVerdict) continue;
      out.add(n);
    }
    out.sort((a, b) {
      if (a.isMajor != b.isMajor) return a.isMajor ? -1 : 1;
      return b.deviation.abs().compareTo(a.deviation.abs());
    });
    return out.length <= limit ? out : out.sublist(0, limit);
  }
}

/// ═══════════════════════════════════════════════════════════════════════
/// 화면에 바로 쓸 수 있게 다듬은 계절 소견 한 건
/// ═══════════════════════════════════════════════════════════════════════
@immutable
class FlowerSeasonNote {
  const FlowerSeasonNote({
    required this.itemName,
    required this.month,
    required this.monthIndex,
    required this.yearAvg,
    required this.cheapestMonth,
    required this.priciestMonth,
    required this.monthlyIndex,
    required this.band,
    required this.repeatRate,
    required this.isMajor,
  });

  final String itemName;

  /// 기준월 (1~12)
  final int month;

  /// 그 달 지수. 연평균 = 100.
  final int monthIndex;

  /// 2년 물량가중 연평균 (원/단)
  final int yearAvg;

  final int cheapestMonth;
  final int priciestMonth;

  /// 1~12월 지수 전체. 막대그래프용.
  final Map<int, int> monthlyIndex;

  /// 이 폭 안이면 비싸다/싸다고 말하지 않는다.
  final int band;

  /// 2년 재현율 (0.7~1.0). 근거의 세기를 밝히는 데 쓴다.
  final double repeatRate;

  /// 경매 물량 상위 품목인가. 목록 정렬에만 쓰고 화면에 노출하지 않는다 —
  /// "이 꽃은 마이너입니다" 같은 말을 사장님께 할 이유가 없다.
  final bool isMajor;

  /// 연평균 대비 몇 %인가. `+47` = 47% 비싼 달.
  int get deviation => monthIndex - 100;

  bool get isPricey => deviation > band;
  bool get isCheap => deviation < -band;

  /// 말할 게 있는가. 밴드 안이면 `false` — 카드에서 아예 빼버린다.
  bool get hasVerdict => isPricey || isCheap;

  /// `8월엔 보통 20% 싼 편이에요` · `12월엔 보통 47% 비싼 편이에요`
  ///
  /// **`보통`** 이 핵심이다. 이건 지난 2년이 그랬다는 말이고 올해를 약속하는
  /// 게 아니다. `오를 거예요` 같은 예측형은 쓰지 않는다.
  String get verdictText {
    if (!hasVerdict) return '$month월엔 평소와 비슷한 편이에요';
    final d = deviation.abs();
    return isPricey ? '$month월엔 보통 $d% 비싼 편이에요' : '$month월엔 보통 $d% 싼 편이에요';
  }

  /// `가장 싼 달은 7월, 가장 비싼 달은 12월`
  String get rangeText => '가장 싼 달은 $cheapestMonth월, 가장 비싼 달은 $priciestMonth월';

  /// `연평균 9,621원/단` — 지수만 보여주면 감이 안 오므로 기준을 같이 준다.
  String get yearAvgText => '연평균 ${_won(yearAvg)}/단';

  /// 최고월이 최저월의 몇 배인가. `2.5배`
  String get spreadText {
    final lo = monthlyIndex[cheapestMonth];
    final hi = monthlyIndex[priciestMonth];
    if (lo == null || hi == null || lo <= 0) return '';
    return '${(hi / lo).toStringAsFixed(1)}배';
  }

  /// `장미 · 12월엔 보통 47% 비싼 편이에요`
  String get lineText => '$itemName · $verdictText';

  static String _won(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    b.write('원');
    return b.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  내부 모델 — 자산 그대로
// ═══════════════════════════════════════════════════════════════════════

@immutable
class _Season {
  _Season({
    required this.name,
    required this.index,
    required this.yearAvg,
    required this.corr,
    required this.repeatRate,
    required this.rank,
  })  : cheapest = _pick(index, min: true),
        priciest = _pick(index, min: false);

  final String name;
  final Map<int, int> index;
  final int yearAvg;
  final double corr;
  final double repeatRate;

  /// 2년 경매 물량 내림차순 순위 (0 = 장미)
  final int rank;
  final int cheapest;
  final int priciest;

  static int _pick(Map<int, int> idx, {required bool min}) {
    var best = idx.keys.first;
    for (final e in idx.entries) {
      if (min ? e.value < idx[best]! : e.value > idx[best]!) best = e.key;
    }
    return best;
  }
}
