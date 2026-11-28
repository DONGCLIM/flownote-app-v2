import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/services/flower_price_service.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 양재 경매 시세 표기 규칙 잠금
/// ═══════════════════════════════════════════════════════════════════════
///
/// 이 테스트가 지키는 건 **말투와 정직성**이다. 숫자 계산은 서버
/// (`functions/index.js`)가 하고, 여기서는 그 숫자를 사장님께 어떻게
/// 전달하는지를 고정한다. 규칙이 흔들리면 앱이 거짓말을 하게 된다.
void main() {
  FlowerPriceQuote q({
    int price = 11827,
    int? change = 41,
    String date = '2026-08-21',
  }) =>
      FlowerPriceQuote(
        market: '양재',
        itemName: '장미',
        pricePerBundle: price,
        changePercent: change,
        auctionDate: date,
      );

  group('시세 문구', () {
    test('금액은 양재 경매가임을 반드시 밝히고 단 기준이다', () {
      // 경매 낙찰가는 사장님이 도매상에서 실제로 지불하는 값과 수준이 다르다.
      // 출처를 숨기면 "내 매입가가 왜 이렇게 비싸냐"는 오해가 생긴다.
      expect(q().priceText, '양재 경매가 11,827원/단');
    });

    test('송이 환산은 하지 않는다', () {
      // 사장님이 "송이는 이제 정보를 안 줘도 될 거 같아" 라고 확정하셨다.
      // 애초에 경매 1단이 몇 송이인지는 품목마다 달라서 검증한 값이 아니었다.
      final line = q().lineText;
      expect(line, isNot(contains('송이')));
      expect(line, isNot(contains('≈')));
    });

    test('속이 아니라 단으로 말한다', () {
      // 사이트 표기가 `단(속)` 이라 1속 = 1단이고, 앱 단위 목록에는 속이 없다.
      expect(q().lineText, contains('/단'));
      expect(q().lineText, isNot(contains('/속')));
    });

    test('올랐으면 올랐다고, 내렸으면 내렸다고만 한다', () {
      expect(q(change: 41).changeText, '지난주보다 41% 올랐어요');
      expect(q(change: -12).changeText, '지난주보다 12% 내렸어요');
    });

    test('위아래 5% 안이면 비슷하다고 한다', () {
      // 처음엔 문턱을 두지 않았더니 `해바라기 · 1% 올랐어요` 가 나왔다.
      // 꽃값 주간 변동 중간값이 품목별로 9.5~19.6% 라서 1~2% 는 제자리다.
      // 사장님이 "위아래 5프로면 그냥 비슷하다고 하자" 로 확정하셨다.
      for (final c in [0, 1, 3, 5, -1, -3, -5]) {
        expect(q(change: c).changeText, '지난주와 비슷해요', reason: 'c=$c');
        expect(q(change: c).isFlat, isTrue, reason: 'c=$c');
      }
      // 밴드 경계 바로 밖은 다시 방향을 말한다.
      expect(q(change: 6).changeText, '지난주보다 6% 올랐어요');
      expect(q(change: -6).changeText, '지난주보다 6% 내렸어요');
    });

    test('비슷할 때는 화살표·강조색의 근거가 되는 방향이 없다', () {
      // 위젯이 `isUp || isDown` 으로 화살표를 그린다. 밴드 안에서 방향이
      // 참이 되면 제자리인데 화살표가 뜬다.
      for (final c in [0, 1, 5, -1, -5]) {
        expect(q(change: c).isUp, isFalse, reason: 'c=$c');
        expect(q(change: c).isDown, isFalse, reason: 'c=$c');
      }
    });

    test('계산 불가와 비슷함을 구분한다 (모르는 걸 비슷하다고 하지 않는다)', () {
      // `null` = 관측 경매일이 부족해 계산 자체가 안 된 것.
      // 이걸 "비슷해요" 로 뭉개면 없는 사실을 만들어내는 것이다.
      expect(q(change: null).changeText, isEmpty);
      expect(q(change: null).isFlat, isFalse);
      expect(q(change: null).lineText, isNot(contains('비슷')));
      expect(q(change: 0).isFlat, isTrue);
    });

    test('변화를 계산할 수 없으면 그 조각을 뺀다 (지어내지 않는다)', () {
      // 실측: 247품목 중 최근 6경매일이 다 있는 건 33%, 4일 이상은 40%.
      // 철 지난 꽃은 말할 게 없는 게 정상이다.
      final n = q(change: null);
      expect(n.changeText, isEmpty);
      expect(n.hasChange, isFalse);
      // 금액과 날짜는 남는다.
      expect(n.lineText, contains('11,827원/단'));
      expect(n.lineText, contains('8/21 경매'));
    });

    test('예측하는 말은 절대 쓰지 않는다', () {
      // 2년치 실측에서 오름/내림 판정이 다음 기간에도 유지될 확률은
      // 51~53%(동전 던지기)였다. 문턱을 5%~25%로 바꿔도 같았다.
      // 즉 `오를 것 같아요` 는 반이 틀리는 거짓말이다.
      for (final c in [80, 41, 6, 3, 0, -3, -6, -41, -80, null]) {
        final line = q(change: c).lineText;
        for (final banned in ['오를', '내릴', '전망', '예상', '같아요', '듯']) {
          expect(line, isNot(contains(banned)), reason: 'c=$c line=$line');
        }
      }
    });

    test('언제 기준인지 항상 밝힌다', () {
      // 경매는 월·수·금만 열려서 오늘 값이 아닐 수 있다. 날짜를 숨기면
      // 사장님이 오늘 시세로 오해한다.
      expect(q(date: '2026-08-21').dateText, '8/21 경매');
      expect(q(date: '2026-01-05').dateText, '1/5 경매');
      expect(q().lineText, contains('경매'));
    });

    test('한 줄 전체 형태', () {
      expect(
        q().lineText,
        '양재 경매가 11,827원/단 · 지난주보다 41% 올랐어요 · 8/21 경매',
      );
      expect(
        q(change: -12, price: 3476).lineText,
        '양재 경매가 3,476원/단 · 지난주보다 12% 내렸어요 · 8/21 경매',
      );
      expect(
        q(change: null, price: 19027).lineText,
        '양재 경매가 19,027원/단 · 8/21 경매',
      );
      expect(
        q(change: 1, price: 3791).lineText,
        '양재 경매가 3,791원/단 · 지난주와 비슷해요 · 8/21 경매',
      );
    });

    test('방향 판정', () {
      expect(q(change: 41).isUp, isTrue);
      expect(q(change: 41).isDown, isFalse);
      expect(q(change: -12).isDown, isTrue);
      expect(q(change: 0).isUp, isFalse);
      expect(q(change: 0).isDown, isFalse);
      expect(q(change: null).isUp, isFalse);
      expect(q(change: null).isDown, isFalse);
      // 밴드 크기가 바뀌면 이 테스트가 먼저 깨져야 한다.
      expect(FlowerPriceQuote.changeBand, 5);
    });

    test('금액에 천단위 쉼표가 들어간다', () {
      expect(q(price: 999).priceText, contains('999원'));
      expect(q(price: 1000).priceText, contains('1,000원'));
      expect(q(price: 35155).priceText, contains('35,155원'));
    });
  });

  group('서비스', () {
    test('요약이 없으면 아무것도 내주지 않는다', () {
      // Firestore 를 붙이지 않은 상태. 시세는 부가 정보라서 없으면 조용히
      // 사라져야 하고, 예외를 던져 영수증 입력을 막아선 안 된다.
      final s = FlowerPriceService.instance;
      expect(s.isReady, isFalse);
      expect(s.lookup('장미'), isNull);
      expect(s.lookup('장미 하젤'), isNull);
      expect(s.lookup(''), isNull);
      expect(s.lookup('   '), isNull);
    });
  });
}
