import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 꽃 이름 표준화 + 자동완성 엔진
/// ═══════════════════════════════════════════════════════════════════════
///
/// ## 왜 필요한가
/// OCR(`gemini_ocr_service.dart`) 프롬프트는 **품목명을 의도적으로 5순위로
/// 낮춰놨다**. `- name 은 판독 불가 시 "" (지어내지 않음)` 이라고 못 박아둔 이유는
/// 사업자번호/합계 같은 "틀리면 안 되는 값"을 지키기 위해서다. 즉 품목명은
/// **사람이 고치는 게 정상 동작**이고, 그 고치는 행위를 최대한 편하게 만드는 게
/// 이 서비스의 존재 이유다.
///
/// ## 표준명의 출처
/// 국가표준식물목록 API는 폐기(`NO_OPENAPI_SERVICE_ERROR`)됐고, 살아있는
/// 농사로 API는 원예/조경 어휘라 도매 현장 용어와 다르다. 무엇보다
/// 국가표준은 `리시안셔스`를 `꽃도라지`로 바꿔 부르는데, 그건 꽃집 사장님이
/// 못 알아보는 이름이다.
///
/// → **표준명 = 화훼공판장 경매 데이터의 표기**를 그대로 쓴다.
///   (`flower.at.or.kr` returnData.api `kind=f001`, `flowerGubn=1` 절화)
///   우리 영수증은 결국 같은 도매 유통을 거쳐온 물건이므로 어휘가 일치한다.
///
/// 그래서 표준 표기는 `리시안사스`(X 리시안셔스), `튜립`(X 튤립),
/// `안개`(X 안개꽃), `히야신스`(X 히아신스) 다. 어색해 보여도 이게 현장 표기다.
///
/// ## 2단 구조 (품목 > 품종)
/// 처음엔 `장미(레드)` 처럼 "품목+색상"을 생각했지만 실제 데이터는 색이 아니라
/// **품종**으로 갈린다. 그리고 같은 장미 안에서 가격이 20배까지 벌어진다
/// (`싸나 상3` 2,490원 ↔ `나르샤(sp) 특2` 50,000원). 색상으로 묶으면 이 정보가
/// 통째로 사라지므로 `품목 > 품종` 2단으로 간다.
///
/// ## 검색 방식 (타이핑 보정)
/// 사장님이 실제로 치는 건 정확한 이름이 아니다. `라넌`, `리시안`, `ㅈㅁ`,
/// `장이` 처럼 친다. 그래서 5단계로 받아준다.
///   1. 별칭/오타 사전 직격 (`유스토마` → `리시안사스`)
///   2. 접두 일치 (`리시안` → `리시안사스`)
///   3. 부분 일치 (`핑크` → 품종 `졸리핑크`)
///   4. 초성 일치 (`ㅈㅁ` → `장미`)
///   5. 편집거리 (`리시안샤스` → `리시안사스`)
///
/// 모든 결과는 **거래량(q) 순**으로 가중치를 준다. 장미가 국화보다 먼저 나와야
/// 실제로 편하다.
class FlowerNameService {
  FlowerNameService._();
  static final FlowerNameService instance = FlowerNameService._();

  static const _assetPath = 'assets/data/flower_names.json';
  static const _prefsKeyMine = 'fn_flower_my_dict';

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// 표준 품목 목록 (거래량 내림차순)
  final List<FlowerItemName> _items = [];
  List<FlowerItemName> get items => List.unmodifiable(_items);

  /// 표준 품목명 집합 (O(1) 판정용)
  final Set<String> _standard = {};

  /// 정규화 키 → 표준 품목명
  final Map<String, String> _lookup = {};

  /// 사용자 개인 사전: 정규화 키 → 표준 품목명
  /// (사장님이 `컨트리B` 를 리시안사스로 고쳤으면 다음엔 바로 제안)
  final Map<String, String> _mine = {};

  /// 최근 사용한 표준명 (최신 우선, 최대 12개)
  final List<String> _recent = [];
  List<String> get recent => List.unmodifiable(_recent);

  /// [canonicalItem] 메모이제이션. 통계 집계는 영수증 수 × 품목 수만큼
  /// 호출되고, 내부는 150품목 × 최대 188품종 순회라 캐시가 없으면 느리다.
  final Map<String, String> _canonCache = {};

  // ─────────────────────────────────────────────────────────────────
  // 초기화
  // ─────────────────────────────────────────────────────────────────

  /// 자산 + 개인 사전 로드. 두 번 호출해도 안전하다.
  ///
  /// 실패해도 **절대 throw 하지 않는다.** 사전이 없으면 자동완성만 조용히
  /// 비활성화되고 기존 자유 입력이 그대로 동작해야 한다. (사전 로딩 실패로
  /// 영수증 편집 화면이 회색이 되면 안 된다 — 홈 회색화면 사건의 교훈)
  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      _parse(raw);
    } catch (e) {
      debugPrint('[FlowerNameService] asset load failed: $e');
    }
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString(_prefsKeyMine);
      if (s != null && s.isNotEmpty) {
        final m = jsonDecode(s) as Map<String, dynamic>;
        final alias = m['alias'];
        if (alias is Map) {
          alias.forEach((k, v) => _mine['$k'] = '$v');
        }
        for (final r in (m['recent'] as List?) ?? const []) {
          final v = '$r';
          if (v.isNotEmpty && !_recent.contains(v)) _recent.add(v);
        }
      }
    } catch (e) {
      debugPrint('[FlowerNameService] my-dict load failed: $e');
    }
    _loaded = true;
  }

  void _parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['items'] as List?) ?? const [];
    _items.clear();
    _standard.clear();
    _lookup.clear();
    _canonCache.clear();
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      final name = '${m['n']}'.trim();
      if (name.isEmpty) continue;
      final varieties = <FlowerVariety>[];
      for (final g in (m['g'] as List?) ?? const []) {
        final gm = g as Map<String, dynamic>;
        final gn = '${gm['n']}'.trim();
        if (gn.isEmpty) continue;
        varieties.add(
          FlowerVariety(
            name: gn,
            avgPerBundle: _num(gm['a']),
            tradedQty: _num(gm['q']).round(),
            monthly: _months(gm['m']),
          ),
        );
      }
      final item = FlowerItemName(
        name: name,
        avgPerBundle: _num(m['a']),
        tradedQty: _num(m['q']).round(),
        varieties: varieties,
        monthly: _months(m['m']),
      );
      _items.add(item);
      _standard.add(name);
      _lookup[normalize(name)] = name;
      _lookup[chosung(name)] = name;
    }
    // 별칭 사전을 표준 위에 덮는다 (별칭이 표준을 가리면 안 되므로 putIfAbsent)
    for (final e in aliases.entries) {
      _lookup.putIfAbsent(normalize(e.key), () => e.value);
    }
  }

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  // ─────────────────────────────────────────────────────────────────
  // 별칭 / 오타 사전
  // ─────────────────────────────────────────────────────────────────

  /// 별칭 → 표준(경매 표기).
  ///
  /// 기존 `ReceiptParser._flowerDict` 는 교과서 이름(`물망초`,`봄맞이`,`팬지`,
  /// `포인세티아`)을 담고 있었는데 46일치 실제 경매 데이터에 **0회** 등장한다.
  /// 반면 실제로 거래되는 `옥시페탈륨`,`쿠루쿠마`,`노무라`,`보리사초` 같은 이름은
  /// 사전에 아예 없었다. 그래서 사전 자체를 경매 데이터로 갈아끼우고, 여기에는
  /// **표기 차이·약칭·영문·오타만** 남긴다.
  static const Map<String, String> aliases = {
    // ── 표기 차이 (우리가 틀렸던 것들) ──
    '리시안셔스': '리시안사스',
    '리시안샤스': '리시안사스',
    '리시안서스': '리시안사스',
    '리시안': '리시안사스',
    '유스토마': '리시안사스',
    'lisianthus': '리시안사스',
    '튤립': '튜립',
    'tulip': '튜립',
    'tulips': '튜립',
    '안개꽃': '안개',
    'babysbreath': '안개',
    '히아신스': '히야신스',
    'hyacinth': '히야신스',
    // ── 약칭 (현장에서 줄여 부르는 말) ──
    '라넌': '라넌큘러스',
    '라난큘러스': '라넌큘러스',
    '라넌큐러스': '라넌큘러스',
    'ranunculus': '라넌큘러스',
    '알스트로메리아': '알스트메리아',
    '알스트로': '알스트메리아',
    '알스트': '알스트메리아',
    '유칼': '유칼립투스',
    '유카리': '유칼립투스',
    'eucalyptus': '유칼립투스',
    '글라디올라스': '글라디올러스',
    '글라디': '글라디올러스',
    'gladiolus': '글라디올러스',
    '스카비오싸': '스카비오사',
    '스카비': '스카비오사',
    '하이페리쿰': '하이페리콤',
    '하이페리컴': '하이페리콤',
    '하이페리': '하이페리콤',
    '아스틸베': '아스틸베',
    '옥시': '옥시페탈륨',
    '옥시페탈륨': '옥시페탈륨',
    '쿠루쿠마': '쿠루쿠마',
    '큐루쿠마': '쿠루쿠마',
    '클레마': '클레마티스',
    '델피늄': '델피니움',
    '델피니엄': '델피니움',
    // '데이지': '마가렛' 은 제거했다. 데이지와 마가렛은 다른 꽃이고,
    // 현장에서 섞어 부른다는 이유로 우리가 이름을 바꿔버릴 권리는 없다.
    '마가렛트': '마가렛',
    '스토크': '스톡크',
    '스톡': '스톡크',
    'stock': '스톡크',
    '아스파라': '아스파라거스',
    '루스커스': '루스커스',
    '몬스테': '몬스테라',
    '심비': '심비디움',
    '덴파': '덴파레',
    '호접': '호접란',
    '팔레놉시스': '호접란',
    // ── 영문 ──
    'rose': '장미',
    'roses': '장미',
    '로즈': '장미',
    'chrysanthemum': '국화',
    'gerbera': '거베라',
    'carnation': '카네이션',
    'carnations': '카네이션',
    'hydrangea': '수국',
    'sunflower': '해바라기',
    'sunflowers': '해바라기',
    'lily': '백합',
    'lilies': '백합',
    '릴리': '백합',
    'peony': '작약',
    'peonies': '작약',
    '모란': '작약',
    'calla': '칼라',
    'anemone': '아네모네',
    'statice': '스타티스',
    'freesia': '프리지아',
    'eustoma': '리시안사스',
    // ── 오타 (자주 나오는 자모 실수) ──
    '장이': '장미',
    '자미': '장미',
    '거배라': '거베라',
    '겨베라': '거베라',
    '카네이숀': '카네이션',
    '해바래기': '해바라기',
    '수구': '수국',
    '벡합': '백합',
    '안시륨': '안시리움',
    '안스리움': '안시리움',
    '안슬리움': '안시리움',
    '멘드라미': '맨드라미',
    '다알리아': '다알리아',
    '달리아': '다알리아',
    'dahlia': '다알리아',
    '천일홍': '천일홍',
    '메리골드': '메리골드',
    '마리골드': '메리골드',
    'marigold': '메리골드',
    // ── 여기에 있던 `소국`/`대국`/`스프레이국화`/`스프국` → `국화` 는 삭제했다 ──
    // 소국·대국·스프레이국화는 국화라는 **품목 안의 서로 다른 물건**이고
    // 가격도 다르다. 실제 경매 데이터에도 `소국`,`화이트소국`,`옐로우소국`,
    // `핑퐁(소국)`,`장미소국` 이 국화의 **품종**으로 따로 존재한다.
    // 이걸 `국화` 로 뭉개면 사장님이 신경 쓰는 차이가 통째로 사라진다.
    // → 별칭이 아니라 품종 매칭으로 처리한다. (`소국` 입력 → `국화 소국` 제안)

    // ── Build 22: 2년치(576 경매일) 로 사전을 다시 만들면서 추가 ──
    // Build 19 사전은 46일(한여름)치라 봄·겨울 꽃이 통째로 빠져 있었다.
    // 그래서 아래 `라넌큘러스`,`프리지아` 별칭은 **존재하지 않는 표준명을
    // 가리키는 죽은 별칭**이었다. 이제 실제로 존재한다.
    '후리지아': '프리지아',
    '후리지어': '프리지아',
    '프리지어': '프리지아',
    '프리자아': '프리지아',
    '프리': '프리지아',
    '라넌큐라스': '라넌큘러스',
    '라넌쿨러스': '라넌큘러스',
    '라난쿨루스': '라넌큘러스',
    '라넌큐': '라넌큘러스',
    '금어': '금어초',
    '스냅드래곤': '금어초',
    'snapdragon': '금어초',
    '왁스': '왁스플라워',
    '왁스플라': '왁스플라워',
    'waxflower': '왁스플라워',
    '아이리스': '아이리스',
    '붓꽃': '아이리스',
    'iris': '아이리스',
    '헬레보루스': '헬레보루스',
    '헬레보러스': '헬레보루스',
    '크리스마스로즈': '헬레보루스',
    '골든볼': '골든볼',
    '크라스페디아': '골든볼',
    '꽃양배추': '꽃양배추',
    '엽모란': '꽃양배추',
    '니겔라': '니겔라',
    '흑종초': '니겔라',
    '라일락': '라일락',
    'lilac': '라일락',
    '스위트피': '스위트피',
    '스윗피': '스위트피',
    'sweetpea': '스위트피',
    '시네라리아': '시네라리아',
    '카랑코에': '카랑코에',
    '칼랑코에': '카랑코에',
    '카란코에': '카랑코에',
    '뽀삐': '뽀삐',
    '포피': '뽀삐',
    '양귀비': '뽀삐',
    'poppy': '뽀삐',
    '루피너스': '루피너스',
    '루피나스': '루피너스',
    '매발톱': '매발톱',
    '아퀼레지아': '매발톱',
    '백묘국': '백묘국',
    '더스티밀러': '백묘국',
    '엉겅퀴': '엉겅퀴',
    '아티쵸크': '아티쵸크',
    '아티초크': '아티쵸크',
    '아티쵹': '아티쵸크',
    '라이스플라워': '라이스플라워',
    '라이스': '라이스플라워',
    '금잔화': '금잔화',
    '칼렌듈라': '금잔화',
    '물망초': '물망초',
    '포겟미낫': '물망초',
    '이베리스': '이베리스',
    '사포나리아': '사포나리아',
    '아스트란시아': '아스트란시아',
    '밥티시아': '밥티시아',
    '홍가시': '홍가시',
    '말채': '말채나무',
    '말채나무': '말채나무',
    '시레네': '시레네',
    '천조초': '천조초',
    '개나리': '개나리',
    '매화': '매화',
    '동백': '동백',
    '목화': '목화',
    '보리': '보리',
    '유채': '유채',
    '비단향': '비단향',
    '담쟁이': '담쟁이',
    '돈나무': '돈나무',
  };

  // ─────────────────────────────────────────────────────────────────
  // 문자열 정규화 유틸
  // ─────────────────────────────────────────────────────────────────

  /// 검색 비교용 정규화: 소문자, 공백/기호 제거.
  ///
  /// 경매 품종명에는 `차밍레이스(sp)` 처럼 `(sp)`(스프레이 계열) 표기가 붙는다.
  /// 괄호는 제거하지 않고 **기호만** 없애서 `차밍레이스sp` 로 만든다.
  /// (`sp` 자체가 의미 있는 식별자이므로 버리면 안 된다)
  static String normalize(String s) {
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      final c = String.fromCharCode(r);
      if (c == ' ' ||
          c == '\t' ||
          c == '_' ||
          c == '-' ||
          c == '.' ||
          c == ',' ||
          c == '/' ||
          c == '(' ||
          c == ')' ||
          c == '[' ||
          c == ']' ||
          c == '·') {
        continue;
      }
      b.write(c);
    }
    return b.toString();
  }

  static const _cho = [
    'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
    'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
  ];

  /// 한글 초성 추출. `장미` → `ㅈㅁ`
  ///
  /// 사장님이 `ㅈㅁ` 만 쳐도 장미가 나오게 하려는 것. 한글이 아닌 문자는
  /// 그대로 통과시켜서 `ㅈㅁ2` 같은 혼합 입력도 깨지지 않게 한다.
  static String chosung(String s) {
    final b = StringBuffer();
    for (final r in normalize(s).runes) {
      if (r >= 0xAC00 && r <= 0xD7A3) {
        b.write(_cho[((r - 0xAC00) ~/ 28) ~/ 21]);
      } else {
        b.write(String.fromCharCode(r));
      }
    }
    return b.toString();
  }

  /// 입력이 초성만으로 이뤄졌는지 (`ㅈㅁ` 처럼)
  static bool isChosungOnly(String s) {
    final n = normalize(s);
    if (n.isEmpty) return false;
    for (final r in n.runes) {
      if (!_cho.contains(String.fromCharCode(r))) return false;
    }
    return true;
  }

  /// 편집거리 (Levenshtein). 오타 한두 글자를 잡기 위한 것이므로
  /// [cutoff] 를 넘으면 즉시 포기해서 비용을 줄인다.
  static int editDistance(String a, String b, {int cutoff = 3}) {
    if (a == b) return 0;
    if ((a.length - b.length).abs() > cutoff) return cutoff + 1;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    final cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j - 1] + cost;
        final del = prev[j] + 1;
        final ins = cur[j - 1] + 1;
        if (del < v) v = del;
        if (ins < v) v = ins;
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > cutoff) return cutoff + 1;
      prev = List<int>.from(cur);
    }
    return prev[b.length];
  }

  // ─────────────────────────────────────────────────────────────────
  // 표준화
  // ─────────────────────────────────────────────────────────────────

  bool isStandard(String name) => _standard.contains(name.trim());

  /// 저장된 이름이 우리가 아는 이름인지 (품목 또는 `품목 품종` 조합).
  bool isKnown(String name) => splitName(name) != null;

  /// ## ⚠️ 이 함수를 저장 경로에서 쓰지 마라
  ///
  /// Build 19 에서 저장 3경로가 전부 이 함수를 태웠고, 그 결과
  /// **사장님이 드롭다운을 건드리지 않아도 입력한 글자가 조용히 바뀌었다.**
  /// `너무 상위카테고리로 잡히는데?? 그리고 그거 강요되는 구조야` 라는
  /// 지적이 정확히 이것이다. 지금은 저장 경로에서 전부 제거했다.
  ///
  /// 이 함수의 용도는 **제안(suggestion)과 조회(lookup)뿐**이다.
  /// 즉 "이렇게 쓰는 게 표준입니다" 를 보여주기 위한 계산이고,
  /// 실제 저장값을 바꾸는 결정은 언제나 사장님의 탭이 한다.
  ///
  /// 그리고 더 이상 **품종을 품목으로 승격시키지 않는다.** `졸리핑크` 를
  /// `리시안사스` 로 바꿔버리면 사장님이 적은 정보를 우리가 지우는 것이다.
  /// 품종→품목 승격이 필요한 곳은 통계 집계뿐이고, 그건 [canonicalItem] 이
  /// 저장값을 건드리지 않고 따로 계산한다.
  String standardize(String input) {
    final t = input.trim();
    if (t.isEmpty) return t;
    if (_standard.contains(t)) return t;
    // `국화 국화` 처럼 품목명이 두 번 적힌 건 한 번으로 접는다.
    // 경매 데이터에 `goodName == pumName` 인 (품종 무구분) 물량이 있어서
    // 242개 품목이 이 형태를 만들 수 있다. 사장님 영수증에 그렇게 남으면 안 된다.
    final dup = _collapseSelfDup(t);
    if (dup != null) return dup;
    // 이미 `품목 품종` 형태면 그대로 둔다 (`국화 소국`).
    if (splitName(t) != null) return t;
    final n = normalize(t);
    final mine = _mine[n];
    if (mine != null) return mine;
    final hit = _lookup[n];
    if (hit != null) return hit;

    // 품종명만 적혀 있으면 **품목으로 승격하지 않고** `품목 품종` 으로 넓힌다.
    // (`쥬밀리아` → `장미` ✗ / `장미 쥬밀리아` ○)
    final v = _findVariety(n);
    if (v != null) return '${v.$1.name} ${v.$2.name}';
    return t;
  }

  /// `장미 장미` → `장미`. 그 외에는 null (건드리지 않는다).
  String? _collapseSelfDup(String t) {
    final sp = t.indexOf(' ');
    if (sp <= 0) return null;
    final head = t.substring(0, sp);
    final rest = t.substring(sp + 1).trim();
    if (head != rest) return null;
    return _standard.contains(head) ? head : null;
  }

  /// 표준화 결과가 원문과 달라졌는지 (UI에서 "이렇게 쓰는 게 표준" 안내용)
  String? standardizedOrNull(String input) {
    final s = standardize(input);
    return s == input.trim() ? null : s;
  }

  // ─────────────────────────────────────────────────────────────────
  // 이름 분해 / 통계용 정규 키
  // ─────────────────────────────────────────────────────────────────

  /// 저장된 이름을 `(품목, 품종?)` 으로 분해한다.
  ///
  /// 저장 포맷은 **`품목` 또는 `품목 품종`** 이다 (공백 하나로 이어붙임).
  /// 품종명 단독 저장을 쓰지 않는 이유: 실제 경매 데이터의 921개 품종명 중
  /// 38개가 여러 품목에 겹쳐 있고, 그중 `핑크`/`화이트`/`혼합` 같은 이름은
  /// 30개 품목이 공유한다. `핑크` 만 저장하면 무슨 꽃인지 알 수 없다.
  ///
  /// 우리가 모르는 이름이면 `null`. (그래도 저장은 된다 — 판정용일 뿐)
  (FlowerItemName, FlowerVariety?)? splitName(String stored) {
    final t = stored.trim();
    if (t.isEmpty) return null;
    for (final it in _items) {
      if (it.name == t) return (it, null);
      if (!t.startsWith(it.name)) continue;
      final rest = t.substring(it.name.length).trim();
      if (rest.isEmpty) return (it, null);
      final rn = normalize(rest);
      for (final v in it.varieties) {
        if (normalize(v.name) == rn) return (it, v);
      }
    }
    return null;
  }

  /// 통계 집계용 **상위 품목 키**. 저장값은 절대 건드리지 않는다.
  ///
  /// `InsightService` 가 `장미 쥬밀리아` 와 `장미 하젤` 을 "장미"로 묶어
  /// 보고 싶을 때만 쓴다. 화면에 뿌리는 이름은 언제나 저장된 원문이다.
  /// 모르는 이름은 원문을 그대로 키로 쓴다 (엉뚱한 품목에 합치지 않는다).
  String canonicalItem(String stored) {
    final cached = _canonCache[stored];
    if (cached != null) return cached;
    final r = _canonicalItem(stored);
    if (_canonCache.length < 4000) _canonCache[stored] = r;
    return r;
  }

  String _canonicalItem(String stored) {
    final parts = splitName(stored);
    if (parts != null) return parts.$1.name;
    final t = stored.trim();
    final n = normalize(t);
    final hit = _mine[n] ?? _lookup[n];
    if (hit != null) {
      final p = splitName(hit);
      return p != null ? p.$1.name : hit;
    }
    final v = _findVariety(n);
    if (v != null) return v.$1.name;
    return t;
  }

  /// 정규화된 품종명으로 `(품목, 품종)` 찾기. 거래량 상위 품목이 먼저 걸린다
  /// (`_items` 가 거래량 내림차순이므로 `핑크` 는 가장 큰 품목으로 붙는다).
  (FlowerItemName, FlowerVariety)? _findVariety(String normalized) {
    for (final it in _items) {
      for (final v in it.varieties) {
        if (normalize(v.name) == normalized) return (it, v);
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────
  // 자동완성 검색
  // ─────────────────────────────────────────────────────────────────

  /// [query] 에 대한 자동완성 후보. 점수 내림차순.
  ///
  /// [limit] 개까지만 돌려준다. `FnAutoComplete` 는 표시 전용이므로
  /// **필터링은 전부 여기서** 끝낸다.
  List<FlowerSuggestion> suggest(String query, {int limit = 8}) {
    final q = normalize(query);
    if (!_loaded || _items.isEmpty) return const [];

    // 이번 달. 계절 가중치의 기준이다.
    final mon = currentMonth;

    // 빈 입력 → 최근 사용 + **이번 달 제철** 상위
    if (q.isEmpty) {
      final out = <FlowerSuggestion>[];
      for (final r in _recent) {
        // 최근 사용값은 `장미 쥬밀리아` 처럼 품종까지 포함될 수 있다.
        // itemOf() 로만 찾으면 품종이 날아가므로 splitName() 으로 분해한다.
        final parts = splitName(r);
        if (parts != null) {
          out.add(FlowerSuggestion(
            name: parts.$1.name,
            item: parts.$1,
            variety: parts.$2,
            score: 1000,
            kind: FlowerMatchKind.recent,
          ));
        }
        if (out.length >= 4) break;
      }
      // 아무것도 안 쳤을 때 뜨는 목록이 1년 내내 `장미·국화·거베라` 로
      // 고정되면 12월에 프리지아를 넣는 사장님한테 아무 도움이 안 된다.
      //
      // 다만 `_popBoost` 를 쓰면 안 된다. 그건 999 에서 천장을 치기 때문에
      // 장미(557만속)와 시레네(14만속)가 똑같은 999 가 되고, 그러면 순위가
      // 계절 점수만으로 결정돼서 **1월 목록에서 장미와 국화가 사라졌다.**
      // 1월에도 사장님이 가장 많이 사는 꽃은 장미다. 그건 거짓말이다.
      //
      // 그래서 여기선 `monthlyQty` = 2년 거래량 × 이번달 강도 를 쓴다.
      // 포화가 없으니 물량 규모가 그대로 반영되고, 동시에 제철이 아닌 달엔
      // 값이 내려간다. 즉 `이번 달에 실제로 얼마나 나오는가` 의 근사값이다.
      final pool = [..._items]..sort((a, b) {
        final qa = a.monthlyQty(mon), qb = b.monthlyQty(mon);
        if (qa != qb) return qb.compareTo(qa);
        return b.tradedQty.compareTo(a.tradedQty);
      });
      for (final it in pool) {
        if (out.length >= limit) break;
        if (out.any((e) => e.name == it.name)) continue;
        out.add(FlowerSuggestion(
          name: it.name,
          item: it,
          score: 500,
          kind: FlowerMatchKind.popular,
        ));
      }
      return out;
    }

    final chosungQuery = isChosungOnly(query);
    final qCho = chosung(query);
    final scored = <FlowerSuggestion>[];

    for (final it in _items) {
      final n = normalize(it.name);
      final cho = chosung(it.name);
      // 거래량 가중치: 장미(35만속)가 남천(수십속)보다 먼저 떠야 한다.
      final pop = _popBoost(it.tradedQty);
      // 이번 달 제철 보정. 폭이 ±420 이라 매칭 스테이지를 넘나들지 않고
      // 같은 품질 안에서만 순서를 바꾼다.
      final seas = seasonBoost(it.seasonAt(mon));

      int? score;
      FlowerMatchKind kind = FlowerMatchKind.item;
      String? via;

      if (n == q) {
        score = 10000 + pop;
      } else if (chosungQuery && cho.startsWith(qCho)) {
        score = 7000 + pop;
        kind = FlowerMatchKind.chosung;
      } else if (n.startsWith(q)) {
        score = 8000 + pop - (n.length - q.length);
      } else if (n.contains(q)) {
        score = 6000 + pop - n.indexOf(q) * 10;
      } else if (!chosungQuery && cho.contains(qCho) && qCho.length >= 2) {
        score = 4500 + pop;
        kind = FlowerMatchKind.chosung;
      } else if (q.length >= 2) {
        final d = editDistance(q, n, cutoff: q.length <= 3 ? 1 : 2);
        if (d <= (q.length <= 3 ? 1 : 2)) {
          score = 3000 + pop - d * 300;
          kind = FlowerMatchKind.typo;
        }
      }

      // 별칭 경유 매칭 (`유스토마` 로 쳤는데 표준은 `리시안사스`)
      for (final a in aliases.entries) {
        if (a.value != it.name) continue;
        final an = normalize(a.key);
        if (an == q) {
          final s = 9000 + pop;
          if (score == null || s > score) {
            score = s;
            kind = FlowerMatchKind.alias;
            via = a.key;
          }
        } else if (an.startsWith(q) && q.length >= 2) {
          final s = 6500 + pop;
          if (score == null || s > score) {
            score = s;
            kind = FlowerMatchKind.alias;
            via = a.key;
          }
        }
      }

      if (score != null) {
        scored.add(FlowerSuggestion(
          name: it.name,
          item: it,
          score: score + seas,
          kind: kind,
          via: via,
        ));
      }

      // ── 품종 매칭 ────────────────────────────────────────────────
      // Build 19 에서는 `score < 8000` 조건 때문에 `장미` 를 정확히 치면
      // 품종이 **하나도** 안 떴다. 그래서 사장님 눈에는 상위 카테고리밖에
      // 안 보였다. 이제 세 경우 모두 품종을 내려준다.
      //
      //  (1) 품목명을 정확히 쳤다 (`장미`)        → 거래량 상위 품종을 이어서 제안
      //  (2) `품목 + 나머지` 를 쳤다 (`장미 쥬`)  → 나머지로 품종을 좁힘
      //  (3) 품종명만 쳤다 (`쥬밀리아`,`소국`)    → 그 품종을 그대로 제안
      final exactItem = n == q;

      // (2) `장미 쥬` / `국화소` 처럼 품목명을 앞에 붙여 치는 경우의 나머지
      String? tail;
      if (!exactItem && q.length > n.length && q.startsWith(n)) {
        final r = q.substring(n.length);
        if (r.isNotEmpty) tail = r;
      }

      if (tail != null) {
        // 품목이 확정됐으니 그 안에서만 품종을 찾는다. 점수를 품목 정확일치보다
        // 높게 줘서 `장미 쥬` 를 쳤을 때 `장미 쥬밀리아` 가 최상단에 온다.
        for (final v in it.varieties) {
          final vn = normalize(v.name);
          int? vs;
          if (vn == tail) {
            vs = 12000;
          } else if (vn.startsWith(tail)) {
            vs = 10500 - (vn.length - tail.length);
          } else if (vn.contains(tail)) {
            vs = 9800;
          }
          if (vs != null) {
            scored.add(FlowerSuggestion(
              name: it.name,
              item: it,
              variety: v,
              score: vs + pop + seasonBoost(v.seasonAt(mon)),
              kind: FlowerMatchKind.variety,
            ));
          }
        }
      } else if (exactItem) {
        // (1) 품목만 확정된 상태. 품목 행(10000+pop) 바로 아래에
        // 거래량 상위 품종을 붙여서 "더 좁힐 수 있다"는 걸 눈으로 보여준다.
        // varieties 는 거래량 내림차순이므로 앞에서부터 자른다.
        // 이번 달에 실제로 나오는 품종을 먼저 보여준다. 12월에 장미를 치면
        // 겨울에 안 들어오는 품종이 상위 6개를 차지하는 걸 막는다.
        final ranked = [...it.varieties]..sort((a, b) {
          final sa = a.seasonAt(mon), sb = b.seasonAt(mon);
          // 이번 달 0(미출하)은 무조건 뒤로
          if ((sa == 0) != (sb == 0)) return sa == 0 ? 1 : -1;
          // 품목 추천과 같은 잣대(이번 달 예상 물량)를 쓴다.
          final qa = a.monthlyQty(mon), qb = b.monthlyQty(mon);
          if (qa != qb) return qb.compareTo(qa);
          return b.tradedQty.compareTo(a.tradedQty);
        });
        final take = ranked.length < 6 ? ranked.length : 6;
        for (var vi = 0; vi < take; vi++) {
          scored.add(FlowerSuggestion(
            name: it.name,
            item: it,
            variety: ranked[vi],
            // 품목 행보다 확실히 낮게(9900 이하) 두되 다른 품목보다는 위로.
            score: 9900 + pop - vi,
            kind: FlowerMatchKind.variety,
          ));
        }
      } else if (q.length >= 2) {
        // (3) 품종명만 쳤다. 품목이 이미 강하게 걸린 경우에도 품종을 지우지
        // 않는다 — 지웠던 게 바로 `상위카테고리로 잡힌다` 의 원인이었다.
        for (final v in it.varieties) {
          final vn = normalize(v.name);
          int? vs;
          if (vn == q) {
            vs = 10200; // 품종 정확일치는 다른 품목의 접두일치보다 우선
          } else if (vn.startsWith(q)) {
            vs = 7500 - (vn.length - q.length);
          } else if (vn.contains(q)) {
            vs = 5000;
          } else if (chosungQuery && chosung(v.name).startsWith(qCho)) {
            vs = 4000;
          }
          if (vs != null) {
            scored.add(FlowerSuggestion(
              name: it.name,
              item: it,
              variety: v,
              // `핑크`/`화이트` 같은 이름은 30개 품목이 공유한다. 거래량
              // 가중치를 줘서 장미·국화 쪽이 먼저 뜨게 한다.
              score: vs + pop + seasonBoost(v.seasonAt(mon)),
              kind: FlowerMatchKind.variety,
            ));
          }
        }
      }
    }

    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.name.length.compareTo(b.name.length);
    });

    // 중복 제거. 키는 **저장될 값**(`value`)이다. `variety?.name` 으로 잡으면
    // `국화`(품목) 와 `국화 · 국화`(품종=품목명) 가 서로 다른 키가 돼서
    // 화면에 같은 이름 두 줄이 나란히 떴다. 눈에 보이는 대로 합쳐야 한다.
    final seen = <String>{};
    final out = <FlowerSuggestion>[];
    for (final s in scored) {
      final k = s.value;
      if (!seen.add(k)) continue;
      out.add(s);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 거래량 → 0~999 보정치. 로그 스케일이라 상위 품목이 과도하게 독식하지 않는다.
  /// `"149611000011"` 같은 12자리 문자열을 월별 강도 리스트로.
  ///
  /// 문자열로 저장한 이유는 용량이다. `[1,4,9,...]` JSON 배열로 두면
  /// 품목+품종 2,978개 × 12칸에 콤마/공백이 붙어서 33KB 가 더 붙는다.
  static List<int> _months(Object? v) {
    if (v is List) {
      if (v.length != 12) return const <int>[];
      return [for (final e in v) (_num(e).round()).clamp(0, 9)];
    }
    final s = v == null ? '' : '$v';
    if (s.length != 12) return const <int>[];
    final out = <int>[];
    for (var i = 0; i < 12; i++) {
      final c = s.codeUnitAt(i) - 0x30;
      if (c < 0 || c > 9) return const <int>[];
      out.add(c);
    }
    return out;
  }

  /// 계절 가중치의 기준이 되는 달. 보통은 오늘이지만 테스트에서 고정한다.
  int _monthOverride = 0;

  /// 지금 기준월 (1~12)
  int get currentMonth =>
      _monthOverride > 0 ? _monthOverride : DateTime.now().month;

  /// 테스트/디버그용. 0 을 주면 실제 달로 되돌린다.
  @visibleForTesting
  void setMonthForTest(int m) => _monthOverride = (m >= 1 && m <= 12) ? m : 0;

  /// 계절 보정 점수. 검색 점수에 더한다.
  ///
  /// 사장님이 12월에 `ㅌ` 을 치면 **튜립**(12월 강도 3, 2월 피크)이
  /// **토마토**(연중)보다 위로 와야 한다. 반대로 8월에 `프` 를 치면
  /// 프리지아(8월 0)는 뒤로 밀려야 한다.
  ///
  /// 폭은 ±420 으로 잡았다. 스테이지 간 간격(1000~2000)보다 작아서
  /// **매칭 품질 순서는 절대 뒤집지 않고**, 같은 스테이지 안에서만
  /// 순서를 바꾼다. 오타교정 결과가 정확일치를 앞지르면 안 되기 때문이다.
  static int seasonBoost(int strength) {
    switch (strength) {
      case 9:
      case 8:
        return 420; // 한창 제철
      case 7:
        return 330;
      case 6:
        return 220;
      case 5:
        return 120;
      case 4:
        return 40;
      case 3:
        return -40;
      case 2:
        return -140;
      case 1:
        return -240;
      default:
        return -420; // 이번 달엔 아예 안 나오는 꽃
    }
  }

  static int _popBoost(int qty) {
    if (qty <= 0) return 0;
    var v = 0;
    var q = qty;
    while (q > 1 && v < 999) {
      q ~/= 2;
      v += 55;
    }
    return v > 999 ? 999 : v;
  }

  FlowerItemName? itemOf(String name) {
    final t = name.trim();
    for (final it in _items) {
      if (it.name == t) return it;
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────
  // 학습 (개인 사전 / 최근 사용)
  // ─────────────────────────────────────────────────────────────────

  /// 사장님이 [typed] 를 [chosen] 으로 확정했음을 기억한다.
  ///
  /// 다음부터 같은 오타를 치면 1순위로 제안된다. 저장 실패는 무시한다
  /// (학습이 안 되는 건 불편이지만, 여기서 throw 하면 저장 자체가 실패한다).
  Future<void> learn(String typed, String chosen) async {
    final c = chosen.trim();
    if (c.isEmpty) return;
    _recent.remove(c);
    _recent.insert(0, c);
    while (_recent.length > 12) {
      _recent.removeLast();
    }
    final t = normalize(typed);
    // 개인 별칭은 **우리가 모르는 입력**에 대해서만 학습한다.
    // 예를 들어 `장미` 라고 정확히 치고 `장미 쥬밀리아` 를 한 번 골랐다고
    // 해서 다음부터 `장미` 를 쥬밀리아로 바꿔주면, 그게 또 강요다.
    if (t.isNotEmpty &&
        t != normalize(c) &&
        !_standard.contains(typed.trim()) &&
        splitName(typed) == null &&
        _lookup[t] == null) {
      _mine[t] = c;
    }
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _prefsKeyMine,
        jsonEncode({'alias': _mine, 'recent': _recent}),
      );
    } catch (e) {
      debugPrint('[FlowerNameService] persist failed: $e');
    }
  }

  /// 테스트용 리셋
  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    _items.clear();
    _standard.clear();
    _lookup.clear();
    _mine.clear();
    _recent.clear();
    _canonCache.clear();
  }

  /// 테스트용 직접 주입 (asset 없이 검색 로직만 검증)
  @visibleForTesting
  void loadFromJsonForTest(String raw) {
    _parse(raw);
    _loaded = true;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 모델
// ═══════════════════════════════════════════════════════════════════════

/// 표준 품목 (예: `장미`)
class FlowerItemName {
  const FlowerItemName({
    required this.name,
    required this.avgPerBundle,
    required this.tradedQty,
    required this.varieties,
    this.monthly = const <int>[],
  });

  /// 표준 품목명 (경매 `pumName`)
  final String name;

  /// 속당 평균 단가. `Σ totAmt / Σ totQty` 로 계산한 **가중평균**이다.
  ///
  /// `avgAmt` 를 단순 평균하면 소량 거래된 특1이 전체를 끌어올려서 실제보다
  /// 비싸게 보인다. 반드시 금액합÷수량합.
  final double avgPerBundle;

  /// 집계 기간 총 거래 속수 (검색 랭킹 가중치)
  final int tradedQty;

  /// 품종 목록 (거래량 내림차순)
  final List<FlowerVariety> varieties;

  /// 절화 경매 단위는 **1속(≈10송이)**. 우리 영수증은 송이 단위이므로
  /// 그냥 비교하면 10배 틀린다. 화면에는 속당을 주로, 송이 환산은 보조로.
  static const stemsPerBundle = 10;

  double get avgPerStem => avgPerBundle / stemsPerBundle;

  /// 1~12월 출하 강도 0~9. 그 품목이 **가장 많이 나오는 달을 9** 로 두고
  /// 나머지 달을 상대 비율로 환산했다. 0 이면 2년간 그 달에 거래가 없었다.
  ///
  /// 예) 프리지아 `149611000011` → 3월 피크, 7~9월은 아예 안 나옴.
  ///     해바라기 `111248889852` → 9월 피크.
  /// 절대 거래량이 아니라 **품목 내부의 상대값**이다. 그래야 장미(연중 대량)와
  /// 튜립(2월 소량) 을 같은 잣대로 "지금이 제철인가" 판단할 수 있다.
  final List<int> monthly;

  /// [month] (1~12) 의 출하 강도. 데이터가 없으면 중립값 5.
  int seasonAt(int month) {
    if (monthly.length != 12) return 5;
    final i = month - 1;
    if (i < 0 || i > 11) return 5;
    return monthly[i];
  }

  /// 지금이 제철인가 (강도 7 이상)
  bool isInSeason(int month) => seasonAt(month) >= 7;

  /// 이번 달에 아예 안 나오는 꽃인가
  bool isOffSeason(int month) => monthly.length == 12 && seasonAt(month) == 0;

  /// **이번 달 예상 물량**. `2년 총 거래량 × 이번달 강도(0~9)`.
  ///
  /// 이게 필요한 이유: 추천 목록을 상대강도만으로 세우면 장미(557만속, 1월 강도 6)가
  /// 시레네(14만속, 1월 강도 7) 에게 밀린다. 1월에도 사장님이 제일 많이 사는 건
  /// 장미다. 반대로 절대 거래량만 쓰면 12월에 프리지아가 안 뜬다.
  /// 두 값을 곱하면 `이번 달에 실제로 몇 속 나오는지` 에 비례하는 값이 나온다.
  int monthlyQty(int month) => tradedQty * seasonAt(month);

  /// 제철 표기용 문자열. 연중 품목은 null (굳이 안 보여준다).
  String? peakLabel() {
    if (monthly.length != 12) return null;
    final hot = <int>[];
    for (var i = 0; i < 12; i++) {
      if (monthly[i] >= 7) hot.add(i + 1);
    }
    // hot 이 7개월 이상이면 사실상 연중 품목이다. 장미는 12개월 전부 6~9라
    // `3~7월, 9~10월, 12월` 같은 무의미한 라벨이 나왔다. 그건 정보가 아니다.
    if (hot.isEmpty || hot.length >= 7) return null; // 연중
    // 12월-1월처럼 해를 넘기는 구간을 사람이 읽는 형태로 뭉친다.
    final runs = <List<int>>[];
    for (final m in hot) {
      if (runs.isNotEmpty && runs.last.last + 1 == m) {
        runs.last.add(m);
      } else {
        runs.add([m]);
      }
    }
    if (runs.length >= 2 && runs.first.first == 1 && runs.last.last == 12) {
      final merged = [...runs.last, ...runs.first];
      runs.removeLast();
      runs.removeAt(0);
      runs.add(merged);
    }
    return runs
        .map((r) => r.length == 1 ? '${r.first}월' : '${r.first}~${r.last}월')
        .join(', ');
  }
}

/// 품종 (예: `쥬밀리아`)
class FlowerVariety {
  const FlowerVariety({
    required this.name,
    required this.avgPerBundle,
    this.tradedQty = 0,
    this.monthly = const <int>[],
  });
  final String name;
  final double avgPerBundle;

  /// 집계 기간 총 거래 속수
  final int tradedQty;

  /// 1~12월 출하 강도 0~9 (품목의 [FlowerItemName.monthly] 와 동일 규칙)
  final List<int> monthly;

  int seasonAt(int month) {
    if (monthly.length != 12) return 5;
    final i = month - 1;
    if (i < 0 || i > 11) return 5;
    return monthly[i];
  }

  /// 이번 달 예상 물량 (품목의 [FlowerItemName.monthlyQty] 와 동일 규칙)
  int monthlyQty(int month) => tradedQty * seasonAt(month);

  double get avgPerStem => avgPerBundle / FlowerItemName.stemsPerBundle;

  /// `차밍레이스(sp)` 처럼 `(sp)` 가 붙으면 스프레이 계열이고 대체로 더 비싸다.
  bool get isSpray => name.contains('(sp)');
}

/// 매칭 경로. UI에서 왜 이 후보가 떴는지 사장님에게 알려주기 위한 것.
enum FlowerMatchKind {
  /// 품목명 직접 매칭
  item,

  /// 품종명 매칭 (`졸리핑크` → 리시안사스)
  variety,

  /// 별칭/영문 (`유스토마` → 리시안사스)
  alias,

  /// 초성 (`ㅈㅁ` → 장미)
  chosung,

  /// 오타 교정 (`리시안샤스` → 리시안사스)
  typo,

  /// 최근 사용
  recent,

  /// 거래량 상위 (빈 입력)
  popular,
}

/// 자동완성 후보 1건
class FlowerSuggestion {
  const FlowerSuggestion({
    required this.name,
    required this.item,
    required this.score,
    required this.kind,
    this.variety,
    this.via,
  });

  /// 매칭된 **품목**명. 저장값이 아니다. 저장값은 [value] 를 쓴다.
  final String name;
  final FlowerItemName item;

  /// 품종 매칭이면 해당 품종
  final FlowerVariety? variety;
  final int score;
  final FlowerMatchKind kind;

  /// 별칭 경유 시 원래 별칭 (`유스토마`)
  final String? via;

  /// 품종이 사실상 `품목 그대로` 인가.
  ///
  /// 경매 데이터에는 품종 구분 없이 올라온 물량이 `goodName == pumName` 으로
  /// 들어온다 (242개 품목에 존재). 그대로 두면 `ㄱㅎ` 를 쳤을 때 드롭다운에
  /// `국화` 와 `국화 · 국화` 가 나란히 떠서 사장님 눈엔 그냥 버그로 보이고,
  /// 확정하면 `국화 국화` 라는 이름이 저장된다. 이 경우는 품종을 안 붙인다.
  bool get _varietyIsItself {
    final v = variety;
    return v == null || v.name == name;
  }

  /// 드롭다운 1행 (`label`) — 사람이 읽기 좋게 가운뎃점으로 끊는다.
  String get label => _varietyIsItself ? name : '$name · ${variety!.name}';

  /// **확정 시 실제로 저장되는 값.**
  ///
  /// Build 19 의 버그: 여기가 없어서 호출부가 전부 [name](=품목)을 저장했고,
  /// `장미 · 쥬밀리아` 를 눌러도 `장미` 만 남았다. 품종을 고르면 품종이
  /// 저장돼야 한다. 포맷은 `품목 품종` (공백 하나) — 품종명 단독은
  /// `핑크`/`화이트`/`혼합` 처럼 30개 품목이 공유해서 식별이 안 된다.
  String get value => _varietyIsItself ? name : '$name ${variety!.name}';

  /// 이번 달 제철 뱃지. 제철이면 `제철`, 이번 달 미출하면 `비수기`.
  /// 연중 품목은 빈 문자열 (없는 정보를 억지로 붙이지 않는다).
  String get seasonTag {
    final mon = FlowerNameService.instance.currentMonth;
    final v = variety;
    // 품종 데이터가 얇으면(거래 소량) 품목 계절값으로 판단한다.
    final st = (v != null && v.monthly.length == 12 && v.tradedQty >= 300)
        ? v.seasonAt(mon)
        : item.seasonAt(mon);
    if (item.monthly.length != 12) return '';
    if (st == 0) return '비수기';
    if (st >= 8) return '제철';
    if (st <= 2) return '끝물';
    return '';
  }

  /// 드롭다운 2행 (`sub`) — 디자인 시스템 AutoComplete 의 `sub` 슬롯.
  ///
  /// **여기엔 시세를 넣지 않는다.** 예전엔 `품목 · 품종 300종 · 제철 ·
  /// 경매 10,815원/속 (≈1,082원/송이)` 처럼 한 줄에 사실 5개를 밀어넣었는데,
  /// 사장님이 "복잡하다"고 하셨고 맞는 지적이었다. 게다가 그 시점은 아직
  /// 이름을 **고치는 중**이라 시세를 볼 이유가 없다.
  ///
  /// 시세는 이름이 **확정된 뒤** 항목 카드에서 보여준다
  /// (`FlowerPriceLine` + `FlowerPriceService`).
  /// 여기 남는 건 `왜 이 후보가 떴는지` 와 제철 여부뿐이다.
  String get sub {
    final tag = seasonTag;
    switch (kind) {
      case FlowerMatchKind.alias:
        return _join(['$via → $name', tag]);
      case FlowerMatchKind.typo:
        return _join(['이거 찾으셨나요?', tag]);
      case FlowerMatchKind.variety:
        return _join(['${item.name} 품종', tag]);
      case FlowerMatchKind.chosung:
        return _join(['초성 검색', tag]);
      case FlowerMatchKind.recent:
        return _join(['최근 사용', tag]);
      case FlowerMatchKind.item:
      case FlowerMatchKind.popular:
        final n = item.varieties.length;
        // 품종이 여러 개면 이 행을 고른 뒤 품종을 더 좁힐 수 있다.
        return _join([if (n > 1) '품목 · 품종 $n종', tag]);
    }
  }

  static String _join(List<String> parts) =>
      parts.where((e) => e.isNotEmpty).join(' · ');

}
