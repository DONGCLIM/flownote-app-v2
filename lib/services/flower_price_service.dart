import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 양재 화훼공판장 경매 시세 (읽기 전용)
/// ═══════════════════════════════════════════════════════════════════════
///
/// ## 앱은 경매 API 를 직접 부르지 않는다
/// 원본은 하루치가 **185KB / 989행**이고 응답이 1.7~2.5초 걸린다. 영수증을
/// 열 때마다 부르면 100장 찍으면 18MB다. 그래서 서버(`functions/index.js`)가
/// **하루 한 번** 불러서 요약해두고, 앱은 그 요약 **약 6KB** 만 읽는다.
/// 영수증을 몇 장 찍든 추가 통신은 0이다.
///
/// ## 왜 `단` 인가
/// `flower.at.or.kr` 는 물량 단위를 `단(속)` 으로 표기한다. 즉 1속 = 1단이고
/// `속` 은 경매장 표기, `단` 은 일반 표기다. 앱 단위 목록에도 `속` 이 없으므로
/// 표시는 `단` 으로 통일한다. (송이 환산은 하지 않는다 — 경매 물량이 실제로
/// 몇 송이인지는 품목마다 다르고, 우리가 검증한 값이 아니다.)
///
/// ## 왜 `양재` 라고 쓸 수 있나
/// 이 API 응답에는 시장 구분 필드가 없다. 그래서 직접 대조했다. 사이트 메인의
/// "양재 거래동향" 집계와 API 합계가 3일 모두 **물량 오차 0단**으로 일치했다
/// (08-21: 96,033단 / 08-20: 1,056단 / 08-22: 1,097단).
/// → 양재 단독 데이터가 맞다.
///
/// ## 왜 `올랐어요` 만 말하고 `오를 것 같아요` 는 안 하나
/// 2년치(경매일 303일, 상위 30품목)로 검증했다. 오름/내림 판정 후 **다음
/// 기간에도 같은 방향일 확률이 51~53%** — 동전 던지기였다. 문턱을 5%로 낮추든
/// 25%로 올리든 똑같았다. 즉 **단기 예측력은 없다.**
/// 그래서 이 서비스는 과거 사실(`지난주보다 41% 올랐어요`)만 내보낸다.
class FlowerPriceService {
  FlowerPriceService._();
  static final FlowerPriceService instance = FlowerPriceService._();

  static const _docPath = 'market/yangjae_latest';
  static const _prefsKey = 'flower_price_summary_v1';

  /// 하루 한 번 갱신이 방침이므로, 이 시간 안에는 네트워크를 다시 타지 않는다.
  static const _refreshAfter = Duration(hours: 6);

  _Summary? _summary;
  DateTime? _fetchedAt;
  bool _loading = false;

  /// 시세를 쓸 수 있는가. 이게 `false` 면 UI 는 아무것도 안 보여준다.
  bool get isReady => _summary != null;

  /// 이 요약의 기준 경매일 (`2026-08-21`). 화면에 날짜를 밝히기 위해 필요하다.
  String? get baseDate => _summary?.base;

  // ───────────────────────────────────────────────────────────────────
  //  적재
  // ───────────────────────────────────────────────────────────────────

  /// 캐시를 먼저 붙이고, 필요하면 조용히 갱신한다.
  ///
  /// 실패해도 예외를 던지지 않는다. 시세는 **부가 정보**이고, 이것 때문에
  /// 영수증 입력이 막히면 안 된다. 못 받으면 그냥 안 보여주면 된다.
  Future<void> init() async {
    await _loadCache();
    // await 하지 않는다 — 화면이 시세를 기다릴 이유가 없다.
    refresh();
  }

  Future<void> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final at = m['_fetchedAt'] as int?;
      _summary = _Summary.fromMap(m);
      _fetchedAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    } catch (e) {
      debugPrint('[price] 캐시 복원 실패: $e');
    }
  }

  /// Firestore 에서 요약을 받아온다. 이미 최근에 받았으면 아무것도 안 한다.
  Future<void> refresh({bool force = false}) async {
    if (_loading) return;
    if (!force && _fetchedAt != null) {
      if (DateTime.now().difference(_fetchedAt!) < _refreshAfter) return;
    }
    _loading = true;
    try {
      final snap = await FirebaseFirestore.instance
          .doc(_docPath)
          .get()
          .timeout(const Duration(seconds: 12));
      final data = snap.data();
      if (data == null) {
        debugPrint('[price] 요약 문서가 없습니다 ($_docPath)');
        return;
      }
      final s = _Summary.fromMap(data);
      if (s.items.isEmpty) return;

      _summary = s;
      _fetchedAt = DateTime.now();

      final p = await SharedPreferences.getInstance();
      await p.setString(
        _prefsKey,
        jsonEncode({...s.toMap(), '_fetchedAt': _fetchedAt!.millisecondsSinceEpoch}),
      );
      debugPrint('[price] 갱신 완료: ${s.base} 기준 ${s.items.length}품목');
    } catch (e) {
      // 오프라인이면 정상적인 상황이다. 캐시가 있으면 그걸 계속 쓴다.
      debugPrint('[price] 갱신 실패(캐시 유지): $e');
    } finally {
      _loading = false;
    }
  }

  // ───────────────────────────────────────────────────────────────────
  //  조회
  // ───────────────────────────────────────────────────────────────────

  /// 저장된 꽃 이름으로 시세를 찾는다.
  ///
  /// 입력은 `장미 하젤` 처럼 `품목 품종` 일 수 있다. 경매 요약은 **품목 단위**
  /// 라서 품종을 떼고 앞머리로 찾는다. 품종별로 나누지 않은 이유는, 품종까지
  /// 내려가면 최근 6경매일을 다 채우는 품종이 거의 없어서 대부분 침묵하게
  /// 되기 때문이다 (품목 기준으로도 63%만 계산된다).
  FlowerPriceQuote? lookup(String flowerName) {
    final s = _summary;
    if (s == null) return null;

    final name = flowerName.trim();
    if (name.isEmpty) return null;

    // 1) 이름 전체로 (품목만 적은 경우)
    var e = s.items[name];
    // 2) 첫 낱말로 (`장미 하젤` → `장미`)
    if (e == null) {
      final sp = name.indexOf(' ');
      if (sp > 0) e = s.items[name.substring(0, sp)];
    }
    if (e == null) return null;

    // 너무 묵은 값은 내보내지 않는다.
    //
    // 실측: 요약이 1경매일(약 2일) 묵으면 오름/내림 판정이 29% 뒤집히고,
    // 2경매일이면 46%, 3경매일이면 56% 다. 즉 낡은 추세는 거짓말에 가깝다.
    // 경매는 월·수·금만 열리므로 `maxStale` 경매일 ≈ 그 두 배의 날수로 본다.
    final age = _daysSince(e.date);
    if (age != null && age > s.maxStale * 2 + 1) return null;

    return FlowerPriceQuote(
      market: s.market,
      itemName: e.name,
      pricePerBundle: e.price,
      changePercent: e.change,
      auctionDate: e.date,
    );
  }

  /// `2026-08-21` 로부터 오늘까지 며칠 지났나. 파싱 실패 시 `null`.
  int? _daysSince(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).difference(d).inDays;
  }
}

/// ═══════════════════════════════════════════════════════════════════════
/// 화면에 바로 쓸 수 있게 다듬은 시세 한 건
/// ═══════════════════════════════════════════════════════════════════════
@immutable
class FlowerPriceQuote {
  const FlowerPriceQuote({
    required this.market,
    required this.itemName,
    required this.pricePerBundle,
    required this.changePercent,
    required this.auctionDate,
  });

  /// `양재`
  final String market;

  /// 요약에서 실제로 찾아낸 품목명 (`장미 하젤` 을 넣으면 `장미`)
  final String itemName;

  /// 원/단 (1속 = 1단)
  final int pricePerBundle;

  /// 지난주(최근 3경매일 vs 이전 3경매일) 대비 %. 계산 불가면 `null`.
  final int? changePercent;

  /// 이 시세가 찍힌 경매일 (`2026-08-21`)
  final String auctionDate;

  /// `양재 경매가 11,827원/단`
  String get priceText => '$market 경매가 ${_won(pricePerBundle)}/단';

  /// 이 폭 안이면 "올랐다/내렸다"고 말하지 않는다.
  ///
  /// 꽃값은 **원래** 주 단위로 크게 흔들린다. 2년치로 재본 품목별 주간 변동
  /// 중간값이 유칼립투스 9.5% · 국화 10.9% · 장미 13.5% · 거베라 16.9% ·
  /// 스톡크 19.6% 다. 즉 1~2% 는 아무 일도 안 일어난 상태의 잡음이다.
  /// 그걸 "올랐어요" 라고 말하면 사장님이 없는 신호를 보게 된다.
  static const changeBand = 5;

  /// `지난주보다 41% 올랐어요` · `지난주보다 12% 내렸어요` ·
  /// `지난주와 비슷해요`
  ///
  /// 계산 자체가 불가능하면(관측 경매일이 부족) 빈 문자열 — 그때는 아예
  /// 아무 말도 하지 않는다. **모르는 것과 비슷한 것은 다르다.**
  String get changeText {
    final c = changePercent;
    if (c == null) return '';
    if (c.abs() <= changeBand) return '지난주와 비슷해요';
    return c > 0 ? '지난주보다 $c% 올랐어요' : '지난주보다 ${-c}% 내렸어요';
  }

  /// 밴드 밖으로 오른 경우만 `true`. 색·화살표가 이걸 따라가므로,
  /// `changePercent > 0` 을 그대로 쓰면 1% 에도 화살표가 뜬다.
  bool get isUp => (changePercent ?? 0) > changeBand;
  bool get isDown => (changePercent ?? 0) < -changeBand;

  /// 밴드 안(= `비슷해요`)인지. 계산 불가와 구분된다.
  bool get isFlat =>
      changePercent != null && changePercent!.abs() <= changeBand;

  bool get hasChange => changeText.isNotEmpty;

  /// `8/21 경매` — 언제 기준인지 반드시 밝힌다. 경매는 월·수·금만 열려서
  /// 오늘 값이 아닐 수 있고, 날짜를 숨기면 사장님이 오늘 시세로 오해한다.
  String get dateText {
    final p = auctionDate.split('-');
    if (p.length != 3) return auctionDate;
    return '${int.tryParse(p[1]) ?? p[1]}/${int.tryParse(p[2]) ?? p[2]} 경매';
  }

  /// 한 줄 전체. `양재 경매가 11,827원/단 · 지난주보다 41% 올랐어요 · 8/21 경매`
  String get lineText {
    final parts = [priceText, if (hasChange) changeText, dateText];
    return parts.join(' · ');
  }

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
//  내부 모델 — 서버 요약 문서 그대로
// ═══════════════════════════════════════════════════════════════════════

/// 키를 한 글자로 줄인 이유: 247품목 × 3필드라서 이름을 길게 쓰면 문서가
/// 몇 배로 커진다. 서버(`functions/index.js` `buildSummary`)와 짝이다.
@immutable
class _Entry {
  const _Entry({
    required this.name,
    required this.date,
    required this.price,
    required this.change,
  });

  final String name;
  final String date; // d
  final int price;   // p — 원/단
  final int? change; // c — 지난주 대비 %

  Map<String, dynamic> toMap() => {'d': date, 'p': price, 'c': change};
}

@immutable
class _Summary {
  const _Summary({
    required this.market,
    required this.base,
    required this.maxStale,
    required this.items,
  });

  final String market;
  final String base;
  final int maxStale;
  final Map<String, _Entry> items;

  static _Summary fromMap(Map<String, dynamic> m) {
    final raw = (m['items'] as Map?) ?? const {};
    final items = <String, _Entry>{};
    raw.forEach((k, v) {
      if (v is! Map) return;
      final price = (v['p'] as num?)?.round();
      final date = v['d'] as String?;
      if (price == null || date == null) return;
      final name = k.toString();
      items[name] = _Entry(
        name: name,
        date: date,
        price: price,
        change: (v['c'] as num?)?.round(),
      );
    });
    return _Summary(
      market: (m['market'] as String?) ?? '양재',
      base: (m['base'] as String?) ?? '',
      maxStale: (m['maxStale'] as num?)?.toInt() ?? 3,
      items: items,
    );
  }

  Map<String, dynamic> toMap() => {
        'market': market,
        'base': base,
        'maxStale': maxStale,
        'items': {for (final e in items.entries) e.key: e.value.toMap()},
      };
}
