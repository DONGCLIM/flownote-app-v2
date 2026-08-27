import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/services/flower_name_service.dart';

/// 꽃 이름 표준화 + 자동완성 검증.
///
/// 실제 자산(`assets/data/flower_names.json`, 150품목/1084품종)을 그대로 읽어서
/// 테스트한다. 가짜 픽스처로 하면 "라넌 치면 라넌큘러스 나오나" 같은
/// 진짜 궁금한 걸 못 잡는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = FlowerNameService.instance;

  setUpAll(() async {
    // SharedPreferences 는 이 테스트에서 안 쓰므로 asset 만 직접 주입한다.
    final raw = await rootBundle.loadString('assets/data/flower_names.json');
    svc.resetForTest();
    svc.loadFromJsonForTest(raw);
  });

  group('사전 로딩', () {
    test('자산이 로드되고 품목이 충분히 많다', () {
      expect(svc.isLoaded, isTrue);
      expect(svc.items.length, greaterThan(100));
    });

    test('경매 표준 표기가 들어있다 (우리 옛 표기가 아니라)', () {
      expect(svc.isStandard('리시안사스'), isTrue);
      expect(svc.isStandard('튜립'), isTrue);
      expect(svc.isStandard('안개'), isTrue);
      expect(svc.isStandard('히야신스'), isTrue);
      // 옛 사전 표기는 표준이 아니다
      expect(svc.isStandard('리시안셔스'), isFalse);
      expect(svc.isStandard('튤립'), isFalse);
    });

    test('거래량 내림차순이라 장미가 맨 앞이다', () {
      expect(svc.items.first.name, '장미');
      expect(svc.items.first.tradedQty, greaterThan(100000));
    });

    test('장미는 품종이 여러 개고 속당 평균가가 양수다', () {
      final rose = svc.itemOf('장미')!;
      expect(rose.varieties.length, greaterThan(50));
      expect(rose.avgPerBundle, greaterThan(0));
      // 1속 = 10송이 환산
      expect(rose.avgPerStem, closeTo(rose.avgPerBundle / 10, 0.001));
    });
  });

  group('표준화 (standardize)', () {
    test('옛 표기 → 경매 표준 표기', () {
      expect(svc.standardize('리시안셔스'), '리시안사스');
      expect(svc.standardize('튤립'), '튜립');
      expect(svc.standardize('안개꽃'), '안개');
      expect(svc.standardize('히아신스'), '히야신스');
    });

    test('약칭 → 표준', () {
      expect(svc.standardize('라넌'), '라넌큘러스');
      expect(svc.standardize('알스트로메리아'), '알스트메리아');
      expect(svc.standardize('유칼'), '유칼립투스');
    });

    test('영문 → 한글 표준', () {
      expect(svc.standardize('rose'), '장미');
      expect(svc.standardize('Gerbera'), '거베라');
      expect(svc.standardize('lisianthus'), '리시안사스');
    });

    test('오타 → 표준', () {
      expect(svc.standardize('장이'), '장미');
      expect(svc.standardize('안스리움'), '안시리움');
    });

    test('품종만 적혀 있으면 품목으로 승격하지 않고 `품목 품종` 으로 넓힌다', () {
      // Build 19 는 `쥬밀리아` → `장미` 로 승격시켰다. 사장님 지적:
      // `너무 상위카테고리로 잡히는데??` → 구체적인 정보를 우리가 지운 것이다.
      final rose = svc.itemOf('장미')!;
      final v = rose.varieties.first.name;
      expect(svc.standardize(v), '장미 $v');
    });

    test('소국/대국/스프레이국화를 국화로 뭉개지 않는다', () {
      // 세 개는 국화 품목 안의 서로 다른 물건이고 가격도 다르다.
      expect(svc.standardize('소국'), isNot('국화'));
      expect(svc.standardize('소국'), contains('소국'));
      expect(svc.standardize('대국'), isNot('국화'));
      expect(svc.standardize('스프레이국화'), isNot('국화'));
    });

    test('데이지를 마가렛으로 바꾸지 않는다', () {
      expect(svc.standardize('데이지'), isNot('마가렛'));
    });

    test('이미 `품목 품종` 형태면 그대로 둔다', () {
      final rose = svc.itemOf('장미')!;
      final v = rose.varieties.first.name;
      expect(svc.standardize('장미 $v'), '장미 $v');
    });

    test('모르는 이름은 억지로 바꾸지 않고 원문을 유지한다', () {
      // `컨트리B` 같은 실제 거래명을 엉뚱한 품목으로 바꿔버리면
      // 통계가 조용히 오염되고 사장님은 원인을 못 찾는다.
      expect(svc.standardize('컨트리B'), '컨트리B');
      expect(svc.standardize('zzzz알수없음'), 'zzzz알수없음');
    });

    test('빈 문자열/공백은 그대로', () {
      expect(svc.standardize(''), '');
      expect(svc.standardize('   '), '');
    });

    test('standardizedOrNull 은 변화가 있을 때만 값을 준다', () {
      expect(svc.standardizedOrNull('장미'), isNull);
      expect(svc.standardizedOrNull('리시안셔스'), '리시안사스');
    });
  });

  group('이름 분해 / 통계 키 (splitName · canonicalItem)', () {
    test('`품목 품종` 을 품목과 품종으로 분해한다', () {
      final rose = svc.itemOf('장미')!;
      final v = rose.varieties.first;
      final parts = svc.splitName('장미 ${v.name}')!;
      expect(parts.$1.name, '장미');
      expect(parts.$2!.name, v.name);
    });

    test('품목만 있으면 품종은 null', () {
      final parts = svc.splitName('장미')!;
      expect(parts.$1.name, '장미');
      expect(parts.$2, isNull);
    });

    test('모르는 이름은 분해되지 않는다 (null)', () {
      expect(svc.splitName('zzzz알수없음'), isNull);
    });

    test('통계 키는 품종을 상위 품목으로 묶는다', () {
      final rose = svc.itemOf('장미')!;
      final a = rose.varieties[0].name;
      final b = rose.varieties[1].name;
      // 저장값은 서로 다르지만 집계는 같은 `장미` 로 모인다.
      expect(svc.canonicalItem('장미 $a'), '장미');
      expect(svc.canonicalItem('장미 $b'), '장미');
      expect(svc.canonicalItem('장미'), '장미');
    });

    test('통계 키는 모르는 이름을 엉뚱한 품목에 합치지 않는다', () {
      expect(svc.canonicalItem('zzzz알수없음'), 'zzzz알수없음');
    });

    test('통계 키는 별칭도 표준 품목으로 모은다', () {
      expect(svc.canonicalItem('리시안셔스'), '리시안사스');
      expect(svc.canonicalItem('튤립'), '튜립');
    });

    test('isKnown 은 품목/품목+품종만 true', () {
      final rose = svc.itemOf('장미')!;
      expect(svc.isKnown('장미'), isTrue);
      expect(svc.isKnown('장미 ${rose.varieties.first.name}'), isTrue);
      expect(svc.isKnown('zzzz알수없음'), isFalse);
    });
  });

  group('초성 / 편집거리 유틸', () {
    test('초성 추출', () {
      expect(FlowerNameService.chosung('장미'), 'ㅈㅁ');
      expect(FlowerNameService.chosung('리시안사스'), 'ㄹㅅㅇㅅㅅ');
    });

    test('초성만 입력 판정', () {
      expect(FlowerNameService.isChosungOnly('ㅈㅁ'), isTrue);
      expect(FlowerNameService.isChosungOnly('장미'), isFalse);
      expect(FlowerNameService.isChosungOnly(''), isFalse);
    });

    test('정규화는 공백/기호를 없애되 sp 는 살린다', () {
      expect(FlowerNameService.normalize(' 장 미 '), '장미');
      expect(FlowerNameService.normalize('차밍레이스(sp)'), '차밍레이스sp');
    });

    test('편집거리', () {
      expect(FlowerNameService.editDistance('장미', '장미'), 0);
      expect(FlowerNameService.editDistance('장이', '장미'), 1);
      expect(FlowerNameService.editDistance('가나다라마바사', '장미'), greaterThan(3));
    });
  });

  group('자동완성 (suggest)', () {
    test('빈 입력이면 이번 달 제철 위주의 상위 품목이 나온다', () {
      // Build 22 부터 빈 입력 추천은 **거래량 × 이번 달 제철강도** 다.
      // 1년 내내 `장미` 로 고정되면 12월에 프리지아를 넣는 사장님에게
      // 아무 도움이 안 되므로, 여기서 `장미` 를 못 박지 않는다.
      final r = svc.suggest('');
      expect(r, isNotEmpty);
      // 뜬 후보는 모두 이번 달에 실제로 나오는 꽃이어야 한다.
      final mon = svc.currentMonth;
      for (final e in r) {
        expect(e.item.isOffSeason(mon), isFalse,
            reason: '${e.name} 은 $mon월에 안 나오는데 추천됐다');
      }
      // 그리고 상위는 거래량 상위권(장미/국화/리시안사스/거베라 등)에서 온다.
      final top = svc.items.take(25).map((e) => e.name).toSet();
      expect(top.contains(r.first.name), isTrue,
          reason: '첫 후보 ${r.first.name} 가 거래량 상위권이 아니다');
    });

    test('접두 일치: 리시안 → 리시안사스', () {
      final r = svc.suggest('리시안');
      expect(r.first.name, '리시안사스');
    });

    test('초성: ㅈㅁ → 장미', () {
      final r = svc.suggest('ㅈㅁ');
      expect(r.map((e) => e.name), contains('장미'));
    });

    test('별칭: 유스토마 → 리시안사스 (경로가 alias 로 표시된다)', () {
      final r = svc.suggest('유스토마');
      expect(r.first.name, '리시안사스');
      expect(r.first.kind, FlowerMatchKind.alias);
      expect(r.first.sub, contains('유스토마'));
    });

    test('오타: 리시안샤스 → 리시안사스', () {
      final r = svc.suggest('리시안샤스');
      expect(r.map((e) => e.name), contains('리시안사스'));
    });

    test('품종 검색은 품목이 아니라 `품목 품종` 을 저장값으로 준다', () {
      // Build 19 는 여기서 `장미` 만 저장했다. → `너무 상위카테고리로 잡히는데??`
      final rose = svc.itemOf('장미')!;
      final v = rose.varieties.first.name;
      final r = svc.suggest(v);
      expect(r.map((e) => e.value), contains('장미 $v'));
    });

    test('품목명을 정확히 쳐도 품종 후보가 함께 뜬다', () {
      // Build 19 는 `score < 8000` 조건 때문에 `장미` 를 정확히 치면
      // 품종이 하나도 안 떴다. 그래서 상위 카테고리밖에 안 보였다.
      final r = svc.suggest('장미', limit: 8);
      expect(r.first.value, '장미'); // 품목이 1순위
      final varieties = r.where((e) => e.variety != null);
      expect(varieties, isNotEmpty);
      expect(varieties.first.value, startsWith('장미 '));
    });

    test('`품목 + 나머지` 로 치면 그 품목 안에서 품종을 좁힌다', () {
      final rose = svc.itemOf('장미')!;
      final v = rose.varieties.first.name;
      // `장미 쥬` 처럼 앞 글자만 쳐도 최상단에 해당 품종이 온다.
      final head = v.substring(0, v.length < 2 ? 1 : 2);
      final r = svc.suggest('장미 $head', limit: 8);
      expect(r.first.name, '장미');
      expect(r.first.variety, isNotNull);
      expect(r.first.value, startsWith('장미 '));
    });

    test('소국을 치면 국화가 아니라 국화의 소국 품종이 온다', () {
      final r = svc.suggest('소국', limit: 8);
      // 상위 카테고리 `국화` 단독으로 끝나면 안 된다.
      expect(r.map((e) => e.value), contains('국화 소국'));
    });

    test('suggest 의 value 는 항상 품종을 보존한다', () {
      for (final q in ['장미', '국화', '소국', '리시안', 'ㅈㅁ']) {
        for (final e in svc.suggest(q, limit: 8)) {
          if (e.variety != null) {
            expect(e.value, '${e.name} ${e.variety!.name}', reason: q);
          } else {
            expect(e.value, e.name, reason: q);
          }
        }
      }
    });

    test('limit 을 넘지 않는다', () {
      expect(svc.suggest('ㅅ', limit: 5).length, lessThanOrEqualTo(5));
      expect(svc.suggest('', limit: 3).length, lessThanOrEqualTo(3));
    });

    test('같은 품목+품종 조합이 중복되지 않는다', () {
      final r = svc.suggest('장', limit: 8);
      final keys = r.map((e) => '${e.name}|${e.variety?.name ?? ''}').toList();
      expect(keys.length, keys.toSet().length);
    });

    test('sub 에 시세를 넣지 않는다 (고르는 중엔 볼 이유가 없다)', () {
      // 예전엔 드롭다운 2행이 `품목 · 품종 300종 · 제철 · 경매 10,815원/속
      // (≈1,082원/송이)` 였다. 한 줄에 사실이 5개라 복잡했고, 무엇보다
      // 그 시점은 이름을 **고치는 중**이라 시세를 볼 이유가 없다.
      // 시세는 이름이 확정된 뒤 항목 카드(`FlowerPriceLine`)에서 보여준다.
      for (final q in ['장미', 'ㅈㅁ', '리시안', '유스토마']) {
        for (final e in svc.suggest(q)) {
          expect(e.sub, isNot(contains('원')), reason: 'q=$q sub=${e.sub}');
          expect(e.sub, isNot(contains('경매')), reason: 'q=$q sub=${e.sub}');
          expect(e.sub, isNot(contains('/속')), reason: 'q=$q sub=${e.sub}');
          expect(e.sub, isNot(contains('송이')), reason: 'q=$q sub=${e.sub}');
        }
      }
    });

    test('sub 는 왜 떴는지만 알려준다', () {
      // 별칭 매칭이면 어떤 말에서 왔는지 밝힌다.
      final alias = svc.suggest('유스토마');
      expect(alias, isNotEmpty);
      expect(alias.first.sub, contains('유스토마'));
      expect(alias.first.sub, contains('리시안사스'));

      // 초성이면 초성이라고 밝힌다.
      final cho = svc.suggest('ㅈㅁ');
      expect(cho, isNotEmpty);
      expect(cho.any((e) => e.sub.contains('초성')), isTrue);
    });

    test('아무것도 안 맞으면 빈 목록 (억지 결과를 만들지 않는다)', () {
      expect(svc.suggest('zzzzqqqqxxxx'), isEmpty);
    });

    test('한 글자 입력도 죽지 않는다', () {
      for (final q in ['ㄱ', '장', 'a', '1', ' ']) {
        expect(() => svc.suggest(q), returnsNormally);
      }
    });
  });

  group('스프레이 계열 판정', () {
    test('(sp) 가 붙은 품종을 스프레이로 인식한다', () {
      const a = FlowerVariety(name: '차밍레이스(sp)', avgPerBundle: 10000);
      const b = FlowerVariety(name: '쥬밀리아', avgPerBundle: 8000);
      expect(a.isSpray, isTrue);
      expect(b.isSpray, isFalse);
    });
  });

  group('가격 신뢰성', () {
    test('모든 품목의 속당 평균가가 0보다 크다', () {
      for (final it in svc.items) {
        expect(it.avgPerBundle, greaterThan(0), reason: it.name);
      }
    });

    test('장미 품종 내 가격 스프레드가 실제로 크다 (2단 구조의 근거)', () {
      // 색상으로 묶으면 이 정보가 통째로 사라진다. 그래서 품목>품종 2단.
      final rose = svc.itemOf('장미')!;
      final prices = rose.varieties.map((v) => v.avgPerBundle).toList()..sort();
      expect(prices.last / prices.first, greaterThan(5));
    });
  });

  _build22Tests();
}

// ─────────────────────────────────────────────────────────────────────
// Build 22: 2년치 사전 + 계절(월별) 가중치
// ─────────────────────────────────────────────────────────────────────
void _build22Tests() {
  group('2년치 사전 커버리지', () {
    test('Build 19 에서 통째로 빠졌던 봄/겨울 품목이 들어있다', () {
      final svc = FlowerNameService.instance;
      // 46일(한여름)치로 만들었던 사전에는 이들이 아예 없었다.
      for (final n in [
        '프리지아',
        '라넌큘러스',
        '금어초',
        '왁스플라워',
        '아이리스',
        '헬레보루스',
        '꽃양배추',
        '스위트피',
        '라일락',
        '물망초',
      ]) {
        expect(svc.isStandard(n), isTrue, reason: '$n 이 사전에 없다');
      }
    });

    test('품목 200개 이상 / 품종 2000개 이상', () {
      final svc = FlowerNameService.instance;
      expect(svc.items.length, greaterThanOrEqualTo(200));
      final g = svc.items.fold<int>(0, (a, b) => a + b.varieties.length);
      expect(g, greaterThanOrEqualTo(2000));
    });

    test('죽은 별칭이 없다 (별칭 타깃은 모두 실제 표준명)', () {
      final svc = FlowerNameService.instance;
      final dead = <String>[];
      for (final e in FlowerNameService.aliases.entries) {
        if (!svc.isStandard(e.value)) dead.add('${e.key}->${e.value}');
      }
      expect(dead, isEmpty, reason: '존재하지 않는 표준명을 가리킴: $dead');
    });

    test('모든 품목이 12개월 데이터를 갖는다', () {
      final svc = FlowerNameService.instance;
      final bad = svc.items.where((e) => e.monthly.length != 12).toList();
      expect(bad, isEmpty);
    });
  });

  group('계절 가중치', () {
    tearDown(() => FlowerNameService.instance.setMonthForTest(0));

    test('프리지아는 3월 피크, 8월엔 출하 없음', () {
      final f = FlowerNameService.instance.itemOf('프리지아')!;
      expect(f.seasonAt(3), greaterThanOrEqualTo(8));
      expect(f.seasonAt(8), 0);
      expect(f.isInSeason(3), isTrue);
      expect(f.isOffSeason(8), isTrue);
    });

    test('해바라기는 여름~초가을이 제철', () {
      final f = FlowerNameService.instance.itemOf('해바라기')!;
      expect(f.seasonAt(9), greaterThanOrEqualTo(8));
      expect(f.seasonAt(1), lessThanOrEqualTo(3));
    });

    test('장미는 연중 품목이라 제철 라벨을 강조하지 않는다', () {
      // 장미는 12개월 전부 강도 6~9 라서 "제철"이라는 말 자체가 무의미하다.
      // peakLabel 은 hot(>=7) 이 8개월 이상이면 null 을 준다.
      final f = FlowerNameService.instance.itemOf('장미')!;
      expect(f.peakLabel(), isNull, reason: '연중 품목에 제철 라벨이 붙었다');
      // 반대로 어느 달에도 비수기가 아니다.
      for (var m = 1; m <= 12; m++) {
        expect(f.isOffSeason(m), isFalse);
      }
    });

    test('프리지아 peakLabel 은 봄 구간을 가리킨다', () {
      final f = FlowerNameService.instance.itemOf('프리지아')!;
      final l = f.peakLabel();
      expect(l, isNotNull);
      expect(l, contains('3월'));
    });

    test('3월엔 프리지아가 8월보다 훨씬 앞선다', () {
      final svc = FlowerNameService.instance;

      svc.setMonthForTest(3);
      final marIdx = svc
          .suggest('프', limit: 12)
          .indexWhere((e) => e.name == '프리지아' && e.variety == null);

      svc.setMonthForTest(8);
      final augIdx = svc
          .suggest('프', limit: 12)
          .indexWhere((e) => e.name == '프리지아' && e.variety == null);

      expect(marIdx, greaterThanOrEqualTo(0));
      // 3월 순위가 8월 순위보다 앞이거나 같아야 한다 (8월엔 아예 빠질 수도 있음)
      if (augIdx >= 0) {
        expect(marIdx, lessThanOrEqualTo(augIdx));
      }
    });

    test('빈 입력 추천 목록이 달마다 달라진다', () {
      final svc = FlowerNameService.instance;
      svc.setMonthForTest(2);
      final feb = svc.suggest('', limit: 8).map((e) => e.name).toList();
      svc.setMonthForTest(8);
      final aug = svc.suggest('', limit: 8).map((e) => e.name).toList();
      expect(feb, isNot(equals(aug)), reason: '계절 추천이 작동하지 않는다');
    });

    test('2월 추천엔 봄꽃이, 8월 추천엔 여름꽃이 들어간다', () {
      final svc = FlowerNameService.instance;
      svc.setMonthForTest(2);
      final feb = svc.suggest('', limit: 10).map((e) => e.name).toSet();
      svc.setMonthForTest(8);
      final aug = svc.suggest('', limit: 10).map((e) => e.name).toSet();

      // 프리지아/튜립/라넌큘러스 중 하나라도 2월 목록에 있어야 한다
      expect(
        feb.intersection({'프리지아', '튜립', '라넌큘러스', '스톡크', '금어초'}),
        isNotEmpty,
        reason: '2월 추천에 봄꽃이 없다: $feb',
      );
      // 8월 목록에는 봄꽃이 없어야 한다
      expect(aug.contains('프리지아'), isFalse, reason: '8월에 프리지아가 추천됨');
    });

    test('계절 보정 폭이 매칭 스테이지를 뒤집지 않는다', () {
      // 정확일치(10000) 가 오타교정(3000) 보다 항상 위여야 한다.
      // seasonBoost 최대 폭 420*2=840 < 스테이지 간격
      expect(FlowerNameService.seasonBoost(9), lessThan(1000));
      expect(FlowerNameService.seasonBoost(0), greaterThan(-1000));
    });

    test('제철 태그가 sub 에 노출된다', () {
      final svc = FlowerNameService.instance;
      svc.setMonthForTest(3);
      final s = svc.suggest('프리지아', limit: 5).firstWhere(
            (e) => e.name == '프리지아',
          );
      expect(s.sub, contains('제철'));
    });
  });

  // ── Build 22 추가: 달별 추천 순위가 `이번 달 예상 물량` 이어야 한다 ──
  //
  // 처음 구현은 `_popBoost + seasonBoost*2` 였는데, `_popBoost` 가 999 에서
  // 천장을 쳐서 장미(557만속)와 시레네(14만속)가 동점이 되고 결국 계절 점수만
  // 남았다. 그 결과 **1월 추천 목록에서 장미와 국화가 통째로 사라졌다.**
  // 1월에도 사장님이 가장 많이 사는 건 장미다. 아래 테스트가 그 재발을 막는다.
  group('달별 추천 순위', () {
    final svc = FlowerNameService.instance;
    tearDown(() => svc.setMonthForTest(0));

    test('열두 달 모두 장미와 국화가 상위 5위 안에 남는다', () {
      for (var m = 1; m <= 12; m++) {
        svc.setMonthForTest(m);
        final top5 = svc.suggest('', limit: 5).map((e) => e.name).toList();
        expect(top5, contains('장미'), reason: '$m월 목록: $top5');
        expect(top5, contains('국화'), reason: '$m월 목록: $top5');
      }
    });

    test('겨울엔 겨울꽃이, 여름엔 여름꽃이 올라온다', () {
      svc.setMonthForTest(12);
      final dec = svc.suggest('', limit: 12).map((e) => e.name).toSet();
      svc.setMonthForTest(7);
      final jul = svc.suggest('', limit: 12).map((e) => e.name).toSet();

      // 12월엔 있고 7월엔 없어야 하는 것
      expect(dec.contains('프리지아'), isTrue, reason: '12월: $dec');
      expect(jul.contains('프리지아'), isFalse, reason: '7월: $jul');
      // 7월엔 있고 12월엔 없어야 하는 것
      expect(jul.contains('수국'), isTrue, reason: '7월: $jul');
      expect(dec.contains('수국'), isFalse, reason: '12월: $dec');
    });

    test('monthlyQty 는 거래량과 이번달 강도를 모두 반영한다', () {
      final rose = svc.itemOf('장미')!;
      final freesia = svc.itemOf('프리지아')!;
      // 3월엔 프리지아가 제철(9)이지만 장미(연중 대량)를 못 넘는다
      expect(rose.monthlyQty(3), greaterThan(freesia.monthlyQty(3)));
      // 같은 프리지아라도 3월 예상물량이 8월보다 훨씬 크다
      expect(freesia.monthlyQty(3), greaterThan(freesia.monthlyQty(8)));
      // 8월엔 아예 0 (2년간 거래 없음)
      expect(freesia.monthlyQty(8), 0);
    });

    test('같은 이름이 두 줄로 뜨지 않는다 (품종명 == 품목명)', () {
      // `국화` 품목 안에는 품종명이 그대로 `국화` 인 항목이 있다.
      // 이게 `국화` 와 `국화 · 국화` 로 나란히 떠서 버그처럼 보였다.
      for (final m in [1, 3, 7, 12]) {
        svc.setMonthForTest(m);
        for (final q in ['ㄱㅎ', '국화', '장미', '거베라', '루스커스']) {
          final r = svc.suggest(q, limit: 8);
          final labels = r.map((e) => e.label).toList();
          expect(labels.toSet().length, labels.length,
              reason: '$m월 "$q" 에서 중복 라벨: $labels');
          for (final e in r) {
            // `루스커스 루스커스(열매)` 는 정당하다 — 품종명이 `루스커스(열매)` 다.
            // 금지 대상은 품목명이 정확히 두 번 반복된 `루스커스 루스커스` 뿐이다.
            expect(e.value, isNot('${e.name} ${e.name}'),
                reason: '저장값이 이름을 두 번 담았다: ${e.value}');
          }
        }
      }
    });

    test('`품목 품목` 은 한 번으로 접힌다', () {
      expect(svc.standardize('국화 국화'), '국화');
      expect(svc.standardize('장미 장미'), '장미');
      expect(svc.standardize('루스커스 루스커스'), '루스커스');
      // 진짜 품종은 건드리지 않는다
      expect(svc.standardize('장미 하젤'), '장미 하젤');
      // 모르는 이름끼리 겹친 건 손대지 않는다
      expect(svc.standardize('머시기 머시기'), '머시기 머시기');
    });
  });
}
