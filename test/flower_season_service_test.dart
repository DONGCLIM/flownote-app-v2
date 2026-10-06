import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/services/flower_season_service.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 계절 시세 표기 규칙 잠금
/// ═══════════════════════════════════════════════════════════════════════
///
/// 여기서 지키는 건 **정직성**이다.
///
/// 단기 추세는 실측 재현율이 51~53%(동전 던지기)라서 예측 문구를 전부
/// 금지했다(`flower_price_service_test.dart`). 계절은 73%로 재현되므로
/// 말해도 되지만, 그렇다고 **약속**이 되는 건 아니다. `보통 …한 편`
/// 이라는 과거형 표현을 벗어나는 순간 거짓말이 된다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final svc = FlowerSeasonService.instance;

  setUpAll(() async {
    await svc.load();
  });

  tearDown(() => svc.setMonthForTest(0));

  group('자산', () {
    test('검증을 통과한 품목만 실려 있다', () {
      // 247품목 중 재현율 70% · 상관 0.6 문턱을 넘은 것만 남겼다.
      expect(svc.isReady, isTrue);
      expect(svc.itemCount, greaterThanOrEqualTo(20));
      expect(svc.itemCount, lessThan(60),
          reason: '문턱이 느슨해지면 못 믿을 품목이 섞인다');
    });

    test('근거 기간을 밝힐 수 있다', () {
      expect(svc.range, contains('2024'));
      expect(svc.range, contains('2026'));
    });

    test('재현율이 낮았던 품목은 침묵한다', () {
      // 실측 재현율: 국화 62% · 백합 56% · 유칼립투스 60% · 엽란 30% ·
      // 호접란 12%. 흔한 꽃이라도 해마다 들쭉날쭉하면 말하지 않는다.
      for (final n in ['국화', '백합', '유칼립투스', '엽란', '호접란', '메리골드']) {
        expect(svc.lookup(n, month: 3), isNull, reason: n);
      }
    });

    test('통과한 품목은 12달 중 최소 10달을 안다', () {
      final n = svc.lookup('장미', month: 8);
      expect(n, isNotNull);
      expect(n!.monthlyIndex.length, greaterThanOrEqualTo(10));
    });
  });

  group('조회', () {
    test('품종을 넣어도 품목으로 되돌려 찾는다', () {
      // 품종별 계절 패턴은 표본이 얇아서 검증하지 않았다.
      final a = svc.lookup('장미', month: 12);
      final b = svc.lookup('장미 하젤', month: 12);
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(b!.itemName, '장미');
      expect(b.monthIndex, a!.monthIndex);
    });

    test('없는 꽃과 빈 입력은 null', () {
      expect(svc.lookup('없는꽃'), isNull);
      expect(svc.lookup(''), isNull);
      expect(svc.lookup('   '), isNull);
    });
  });

  group('문구', () {
    test('연평균 대비 ±10% 안이면 비싸다 싸다고 하지 않는다', () {
      const n = FlowerSeasonNote(
        itemName: '장미',
        month: 5,
        monthIndex: 108,
        yearAvg: 9621,
        cheapestMonth: 7,
        priciestMonth: 12,
        monthlyIndex: {5: 108},
        band: 10,
        repeatRate: 0.88,
        isMajor: true,
      );
      expect(n.hasVerdict, isFalse);
      expect(n.isPricey, isFalse);
      expect(n.isCheap, isFalse);
      expect(n.verdictText, '5월엔 평소와 비슷한 편이에요');
    });

    test('비싼 달·싼 달 문구', () {
      FlowerSeasonNote mk(int idx) => FlowerSeasonNote(
            itemName: '장미',
            month: 7,
            monthIndex: idx,
            yearAvg: 9621,
            cheapestMonth: 7,
            priciestMonth: 12,
            monthlyIndex: const {7: 58, 12: 147},
            band: 10,
            repeatRate: 0.88,
            isMajor: true,
          );
      expect(mk(147).verdictText, '7월엔 보통 47% 비싼 편이에요');
      expect(mk(58).verdictText, '7월엔 보통 42% 싼 편이에요');
      expect(mk(147).isPricey, isTrue);
      expect(mk(58).isCheap, isTrue);
    });

    test('예측하는 말은 절대 쓰지 않는다', () {
      // 계절이 반복된다는 건 과거 사실이다. 올해를 약속하면 거짓말이 된다.
      const banned = ['오를', '내릴', '오릅', '내립', '전망', '예상', '될 거', '겁니다'];
      for (final item in ['장미', '거베라', '리시안사스', '카네이션', '수국']) {
        for (var m = 1; m <= 12; m++) {
          final n = svc.lookup(item, month: m);
          if (n == null) continue;
          for (final b in banned) {
            expect(n.verdictText, isNot(contains(b)),
                reason: '$item $m월 → ${n.verdictText}');
            expect(n.lineText, isNot(contains(b)));
          }
        }
      }
    });

    test('반복된 사실임을 `보통` 으로 못 박는다', () {
      // 이 단어가 빠지면 단정이 되어버린다.
      for (var m = 1; m <= 12; m++) {
        final n = svc.lookup('장미', month: m);
        if (n == null || !n.hasVerdict) continue;
        expect(n.verdictText, contains('보통'), reason: '$m월');
        expect(n.verdictText, contains('편이에요'), reason: '$m월');
      }
    });

    test('금액은 단 기준이고 천단위 쉼표가 들어간다', () {
      final n = svc.lookup('장미', month: 12)!;
      expect(n.yearAvgText, contains('/단'));
      expect(n.yearAvgText, isNot(contains('송이')));
      expect(n.yearAvgText, matches(RegExp(r'\d,\d{3}원')));
    });

    test('최저월·최고월을 함께 밝힌다', () {
      final n = svc.lookup('장미', month: 8)!;
      expect(n.rangeText, contains('${n.cheapestMonth}월'));
      expect(n.rangeText, contains('${n.priciestMonth}월'));
      expect(n.cheapestMonth, isNot(n.priciestMonth));
    });
  });

  group('실데이터 위성 검증', () {
    test('장미는 7월이 가장 싸고 12월이 가장 비싸다', () {
      // 2년 실측 지수: 120 142 95 86 111 69 58 80 94 104 115 147
      final n = svc.lookup('장미', month: 1)!;
      expect(n.cheapestMonth, 7);
      expect(n.priciestMonth, 12);
      // 최고월이 최저월의 2.5배 — 이게 계절을 알려줄 가치가 있는 이유다.
      expect(n.spreadText, '2.5배');
    });

    test('카네이션은 어버이날 앞이 비싸고 늦여름이 싸다', () {
      // 실측 재현율 100%. 8월 지수 31 vs 4월 119.
      final n = svc.lookup('카네이션', month: 8);
      expect(n, isNotNull);
      expect(n!.isCheap, isTrue);
      expect(n.monthlyIndex[4]! > n.monthlyIndex[8]!, isTrue);
    });

    test('이번 달 목록은 편차 큰 순서이고 밴드 안은 빠진다', () {
      svc.setMonthForTest(12);
      final list = svc.notesForMonth(limit: 5);
      expect(list, isNotEmpty);
      expect(list.length, lessThanOrEqualTo(5));
      for (final n in list) {
        expect(n.hasVerdict, isTrue, reason: '${n.itemName} 밴드 안인데 목록에 있다');
        expect(n.month, 12);
      }
      // 많이 쓰는 꽃이 먼저, 그 다음 편차 큰 순. 편차만으로 세우면 8월
      // 1·2위가 알스트메리아·캐모마일이 되어 장미가 화면 밖으로 밀린다.
      for (var i = 1; i < list.length; i++) {
        final prev = list[i - 1];
        final cur = list[i];
        if (prev.isMajor == cur.isMajor) {
          expect(prev.deviation.abs(), greaterThanOrEqualTo(cur.deviation.abs()));
        } else {
          expect(prev.isMajor, isTrue, reason: '많이 쓰는 꽃이 뒤로 밀렸다');
        }
      }
    });

    test('많이 쓰는 꽃이 목록 앞에 온다', () {
      // 물량 상위 12품목(장미·거베라·리시안사스 …)을 먼저 보여준다.
      for (var m = 1; m <= 12; m++) {
        svc.setMonthForTest(m);
        final list = svc.notesForMonth(limit: 3);
        expect(list, isNotEmpty, reason: '$m월');
        expect(list.first.isMajor, isTrue,
            reason: '$m월 첫 항목이 ${list.first.itemName}');
      }
    });

    test('12개월 모두 최소 한 품목은 말할 게 있다', () {
      // 특정 달에 목록이 텅 비면 화면이 빈다. 실제로 그런 달이 없는지 확인.
      for (var m = 1; m <= 12; m++) {
        svc.setMonthForTest(m);
        expect(svc.notesForMonth().isNotEmpty, isTrue, reason: '$m월이 비었다');
      }
    });
  });
}
