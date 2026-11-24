import 'package:flutter/material.dart';
import 'dart:io' as io;
import 'package:provider/provider.dart';
import 'package:flow_note/design/fn_home_tokens.dart';
import 'package:flow_note/providers/receipt_provider.dart';
import 'package:flow_note/screens/ds/home_ds_screen.dart';
import 'package:flow_note/services/subscription_service.dart';
import 'package:flow_note/services/home_tips.dart';
import 'package:flow_note/screens/ds/insight_ds_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/screens/ds/fn_data.dart';

/// 회귀 방지 — 홈 화면 회색 버그(28-A)
///
/// 원인: `home_ds_screen.dart` 의 `_priceCard` 가 `priceData['장미(레드)']!`
/// 로 시안 품목명을 하드코딩 역참조했다. 실데이터에서는 품목명이 실제 매입한
/// 꽃 이름(상위 8개)이라 '장미(레드)' 가 없으면 build() 가 throw 하고,
/// 릴리즈 빌드에서는 화면 전체가 회색 ErrorWidget 으로 덮였다.
String _read(String p) => io.File(p).readAsStringSync();

ReceiptModel _r(String id, String store, DateTime date,
    List<({String name, int qty, double price})> items) {
  final flowers = items
      .map((e) => FlowerItem(
          name: e.name, quantity: e.qty, unitPrice: e.price, unit: '단'))
      .toList();
  return ReceiptModel(
    id: id,
    date: date,
    storeName: store,
    items: flowers,
    totalAmount: flowers.fold<double>(0, (s, i) => s + i.totalPrice),
    rawOcrText: 'test',
    createdAt: date,
  );
}

void main() {
  final now = DateTime.now();
  DateTime monthsAgo(int n) => DateTime(now.year, now.month - n, 10);

  group('28-A 회귀 — 시안 품목명이 없어도 홈 데이터가 안전하다', () {
    test("실데이터에 '장미(레드)' 가 없어도 priceData 가 비어있지 않다", () {
      final receipts = [
        _r('a', '대한꽃도매', monthsAgo(1), [
          (name: '작약', qty: 10, price: 2000),
          (name: '수국', qty: 5, price: 3000),
        ]),
        _r('b', '화람원예', monthsAgo(0), [
          (name: '작약', qty: 10, price: 2400),
        ]),
      ];
      final d = FnDemo.resolveFrom(receipts);

      expect(d.isDemo, isFalse);
      // 시안 하드코딩 키는 존재하지 않는다 → `!` 역참조는 반드시 크래시였다.
      expect(d.priceData.containsKey('장미(레드)'), isFalse);
      // 하지만 화면이 쓸 수 있는 첫 품목은 항상 존재한다.
      expect(d.priceData, isNotEmpty);
      final first = d.priceData.keys.first;
      expect(d.priceData[first], isNotNull);
      expect(d.priceData[first]!.locked, isFalse);
    });

    test('빈 데이터에서도 첫 품목 접근이 안전하다', () {
      final d = FnDemo.resolveFrom(const []);
      expect(d.isDemo, isTrue);
      expect(d.priceData, isNotEmpty);
      expect(d.priceData[d.priceData.keys.first], isNotNull);
      expect(d.insights, isNotEmpty);
    });

    test('금액이 0인 영수증만 있어도 차트 데이터가 깨지지 않는다', () {
      final d = FnDemo.resolveFrom([
        _r('z', '무료증정', monthsAgo(0), [(name: '샘플', qty: 1, price: 0)]),
      ]);
      expect(d.months.length, 12);
      expect(d.spend.length, 12);
      // 전월이 0원이면 나눗셈이 무한대가 되지 않아야 한다.
      expect(d.pctUp, 0);
      expect(d.taxData, isNotEmpty);
    });

    test('months/spend 길이가 항상 같아 인덱스 초과가 없다', () {
      for (final receipts in [
        <ReceiptModel>[],
        [_r('a', '대한꽃도매', monthsAgo(0), [(name: '작약', qty: 1, price: 100)])],
      ]) {
        final d = FnDemo.resolveFrom(receipts);
        expect(d.months.length, d.spend.length);
        expect(d.months.length, greaterThanOrEqualTo(6));
      }
    });
  });

  group('28-A 회귀 — ErrorWidget 회색 박스가 아니라 안내가 보인다', () {
    testWidgets('build 예외 시 사유 문구가 화면에 남는다', (tester) async {
      // main() 이 설치하는 것과 동일한 동작을 검증한다.
      // flutter_test 는 테스트 종료 시점에 ErrorWidget.builder 가 원복돼
      // 있는지 검사하므로, 테스트 본문 안에서 되돌려 놓아야 한다.
      final original = ErrorWidget.builder;
      ErrorWidget.builder = (details) => Directionality(
            textDirection: TextDirection.ltr,
            child: Text('이 화면을 표시하는 중 문제가 발생했어요\n${details.exception}'),
          );

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (_) => throw StateError('의도된 실패')),
      ));

      expect(tester.takeException(), isA<StateError>());
      expect(find.textContaining('이 화면을 표시하는 중 문제가 발생했어요'),
          findsOneWidget);
      // 회색 박스가 아니라 원인 문구까지 화면에 남는다.
      expect(find.textContaining('의도된 실패'), findsOneWidget);

      ErrorWidget.builder = original;
    });
  });

  _k135();
}


// ─────────────────────────────────────────────────────────────────────
//  #135 — 홈 화면을 시안 PNG 기준으로 다시 그린 뒤의 회귀 방지
//
//  시안 실측(316x1009 crop, 환산비 1.2342):
//    페이지 배경 #FFF9F6 / 카드 #FFFFFF / 코랄 #FF6E78 -> #FFAC92
//    살구 막대 #FFD4C2 / 강조 글자 #E8555E / 본문 #545454
//    카드 좌우 여백 19.7dp (좌우 대칭)
// ─────────────────────────────────────────────────────────────────────

class _FakeReceiptProvider extends ReceiptProvider {
  _FakeReceiptProvider(this._items);
  final List<ReceiptModel> _items;

  @override
  List<ReceiptModel> get allReceipts => _items;
}

/// 주석 줄을 걷어낸 소스.
///
/// 🔴 주석에 적어 둔 숫자/문구 때문에 `contains` 검사가 거짓 통과한 사고가
/// 지난 작업에서 두 번 있었다. 검사 전에 주석을 먼저 지운다.
String _codeOf(String path) => io.File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) {
      final t = l.trim();
      return !t.startsWith('//') && !t.startsWith('///');
    })
    .join('\n');

/// 홈 숫자를 확인할 때 쓰는 영수증. (#183)
///
/// 🔴 이번 달 50만 / 전월 30만 으로 **일부러 딱 떨어지게** 잡았다.
///    화면에 `500,000원`·`300,000원` 이 그대로 떠야 하므로, 품목 금액의
///    합이 곧 총액이 되도록 수량 1 로 맞춘다.
List<ReceiptModel> _sample() {
  final now = DateTime.now();
  return [
    _r('cur', '대한꽃도매', DateTime(now.year, now.month, 3), [
      (name: '장미', qty: 1, price: 400000),
      (name: '포장지', qty: 1, price: 100000),
    ]),
    _r('prev', '대한꽃도매', DateTime(now.year, now.month - 1, 12), [
      (name: '장미', qty: 1, price: 300000),
    ]),
  ];
}

Widget _home(List<ReceiptModel> items) =>
    ChangeNotifierProvider<ReceiptProvider>.value(
      // 🔴 Provider 를 MaterialApp **바깥**에 둬야 한다. 안쪽(home:)에 두면
      //    Navigator.push 로 열린 화면은 Provider 를 못 찾고
      //    ProviderNotFoundException 이 난다.
      value: _FakeReceiptProvider(items),
      child: const MaterialApp(home: Scaffold(body: HomeDsScreen())),
    );

Future<void> _pumpHome(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  List<ReceiptModel> items = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_home(items));
  // Image.asset 은 테스트 바인딩에서 resolve 되지 않아 pumpAndSettle() 이
  // 멈추지 않는다. 고정 시간만 돌린다.
  await tester.pump(const Duration(milliseconds: 300));
}

/// 위젯 트리 전체를 훑어 쓰인 색을 모은다.
Set<int> _paintedColors(WidgetTester tester) {
  final out = <int>{};
  void addColor(Color? c) {
    if (c != null) out.add(c.toARGB32());
  }

  for (final e in find.byType(Container).evaluate()) {
    final w = e.widget as Container;
    addColor(w.color);
    final dec = w.decoration;
    if (dec is BoxDecoration) {
      addColor(dec.color);
      final g = dec.gradient;
      if (g is LinearGradient) {
        for (final c in g.colors) {
          addColor(c);
        }
      }
      final b = dec.border;
      if (b is Border) addColor(b.top.color);
    }
  }
  for (final e in find.byType(Text).evaluate()) {
    addColor((e.widget as Text).style?.color);
  }
  for (final e in find.byType(Icon).evaluate()) {
    addColor((e.widget as Icon).color);
  }
  return out;
}

void _k135() {
  group('#135 홈 — 시안 색이 실제로 칠해진다', () {
    testWidgets('예외 없이 그려진다', (tester) async {
      await _pumpHome(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeDsScreen), findsOneWidget);
    });

    testWidgets('페이지 배경이 시안의 따뜻한 크림(#FFF9F6)이다', (tester) async {
      await _pumpHome(tester);
      expect(_paintedColors(tester), contains(0xFFFFF9F6));
    });

    testWidgets('코랄 그라디언트 두 끝(#FF6E78 -> #FFAC92)이 둘 다 쓰인다',
        (tester) async {
      await _pumpHome(tester);
      final used = _paintedColors(tester);
      expect(used, contains(0xFFFF6E78));
      expect(used, contains(0xFFFFAC92));
    });

    testWidgets('연한 살구 막대(#FFD4C2)와 강조 글자(#E8555E)가 보인다',
        (tester) async {
      // 🔴 #183 부터 영수증이 0건이면 막대를 아예 그리지 않는다(빈 안내).
      //    색을 보려면 실데이터가 있어야 한다.
      await _pumpHome(tester, items: _sample());
      final used = _paintedColors(tester);
      expect(used, contains(0xFFFFD4C2));
      expect(used, contains(0xFFE8555E));
    });

    testWidgets('예전 로즈 계열 주조색(#EE7686)으로 되돌아가지 않았다',
        (tester) async {
      await _pumpHome(tester);
      // 시안의 코랄(#FF6E78)과 DS 기본 rose50(#EE7686)은 다른 색이다.
      // 큰 면적(그라디언트/CTA)이 rose50 으로 칠해지면 시안과 톤이 어긋난다.
      final src = _codeOf('lib/screens/ds/home_ds_screen.dart');
      expect(src.contains('FnColors.primaryNormal'), isFalse,
          reason: '홈 본문은 시안 코랄(FnHome.coral)을 써야 한다');
    });

    testWidgets('토큰 파일이 실측값을 그대로 들고 있다', (tester) async {
      final src = _codeOf('lib/design/fn_home_tokens.dart');
      for (final hex in [
        '0xFFFFF9F6', // 페이지 배경
        '0xFFFF6E78', // 코랄 시작
        '0xFFFFAC92', // 코랄 끝
        '0xFFFFD4C2', // 살구 막대
        '0xFFE8555E', // 강조 글자
        '0xFF545454', // 본문
        '0xFFA3A3A3', // 보조
      ]) {
        expect(src, contains(hex), reason: '$hex 가 토큰에서 사라졌다');
      }
    });
  });

  group('#135 홈 — 시안 구조가 보인다', () {
    testWidgets('시안의 글귀가 실제로 화면에 있다', (tester) async {
      // 🔴 #186 부터 팁 글자가 날마다 바뀐다. 고정 문구로 집으면 달이
      //    바뀔 때마다 깨진다. 화면과 **같은 곳**에 물어본다.
      //    띄우기 **전에** 물어야 한다 — 화면이 뜨면서 "봤다" 를 적어
      //    다음 팁으로 넘어가기 때문이다.
      final tip = HomeTipStore.instance.today();
      expect(tip, isNotNull);

      await _pumpHome(tester);
      expect(find.text('이번 달 총 지출'), findsOneWidget);
      expect(find.text('지출 추이'), findsOneWidget);
      expect(find.text('품목 비중'), findsOneWidget);
      expect(find.text('스마트 사입 가이드'), findsOneWidget);
      expect(find.text('권장 사입 주기'), findsOneWidget);
      expect(find.text('권장 절화 비중'), findsOneWidget);
      expect(find.text(tip!.title), findsOneWidget);
      expect(find.text('상세 분석 보기 >'), findsOneWidget);
      expect(find.textContaining('맞춤 사입 리포트 보기'), findsOneWidget);
    });

    testWidgets('막대가 6개이고 마지막만 넓게 강조된다', (tester) async {
      // 🔴 #183 부터 달 라벨은 **오늘 기준 최근 6개월**이다. 예전에는
      //    시안 고정값(2~7월)이었는데, 그건 데모 숫자라 지웠다.
      await _pumpHome(tester, items: _sample());
      final now = DateTime.now();
      for (var i = 5; i >= 0; i--) {
        final m = DateTime(now.year, now.month - i);
        expect(find.text('${m.month}월'), findsWidgets,
            reason: '${m.month}월 막대 라벨이 없다');
      }
      // 강조 막대 폭(42) > 일반 막대 폭(27)
      expect(FnHome.barActiveW, greaterThan(FnHome.barW));
    });

    testWidgets('총 지출 금액과 전월/영수증/변동폭이 함께 보인다',
        (tester) async {
      // 🔴 #183 금액 표기에서 ₩ 를 빼고 `3,050,000원` 꼴로 바꿨다.
      //    숫자도 데모가 아니라 **이 사용자의 영수증**에서 나온다.
      await _pumpHome(tester, items: _sample());
      expect(find.text('500,000원'), findsOneWidget); // 이번 달
      expect(find.text('300,000원'), findsOneWidget); // 전월
      expect(find.text('1매'), findsOneWidget);
      expect(find.text('전월 지출'), findsOneWidget);
      expect(find.text('변동폭'), findsOneWidget);
      // ₩ 기호가 홈에 남아 있으면 안 된다.
      expect(find.textContaining('₩'), findsNothing);
    });

    testWidgets('카드 좌우 여백이 좌우 대칭이다(시안 19.7dp)', (tester) async {
      await _pumpHome(tester);
      final screen = tester.getSize(find.byType(HomeDsScreen));
      // 코랄 카드는 화면 가로 전체를 쓰고 처음부터 보이므로 여백 측정에 좋다.
      //
      // 🔴 예전에는 조상 Container 를 `.at(1)` 로 집었다. #147 에서 코랄
      //    카드를 ClipRRect > DecoratedBox > Stack 구조로 바꾸면서
      //    Container 조상이 **0개**가 됐고(배지만 Container 로 남음)
      //    이 테스트가 깨졌다. 인덱스/타입 하나에 기대지 않도록,
      //    카드를 감싼 ClipRRect 중 **폭으로** 카드인 것을 고른다.
      final clips = find.ancestor(
        of: find.text('이번 달 총 지출'),
        matching: find.byType(ClipRRect),
      );
      Rect? found;
      for (final e in clips.evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        // 화면 전체(여백 0)도 아니고, 배지처럼 좁지도 않은 것.
        if (r.width < screen.width - 1 && r.width > screen.width * 0.7) {
          found = r;
          break;
        }
      }
      expect(found, isNotNull,
          reason: '코랄 카드를 못 찾았다 — 카드 래퍼 구조가 또 바뀌었다');
      final box = found!;
      final left = box.left;
      final right = screen.width - box.right;
      expect((left - right).abs(), lessThan(1.0),
          reason: '좌 $left / 우 $right — 좌우가 어긋났다');
      // 🔴 토큰(FnHome.pagePad)과 비교하면 토큰을 바꿔도 테스트가 따라가서
      //    아무것도 못 잡는다(자기참조). 시안 실측값을 **리터럴**로 박는다.
      //    시안 19.7dp -> 앱 20dp.
      expect(left, closeTo(20.0, 1.0),
          reason: '카드 좌우 여백이 시안(19.7dp)과 다르다: $left');
      expect(FnHome.pagePad, closeTo(20.0, 1e-9),
          reason: 'pagePad 토큰이 시안값에서 벗어났다');
    });

    testWidgets('🔴 통계 금액이 구분선에 달라붙지 않는다', (tester) async {
      // 처음 만들 때 `_stat` 에 가로 패딩이 없어서, 긴 금액(₩2,620,000)의
      // 오른쪽 끝이 구분선에 **정확히 0.0px** 로 붙었다. 320/360/390
      // 세 폭 전부에서 그랬다. 320dp 렌더 스크린샷에서 눈으로 먼저 보였고,
      // 픽셀로 재서 확인한 뒤 좌우 7dp 를 넣었다.
      for (final w in [320.0, 360.0, 390.0]) {
        await _pumpHome(tester, items: _sample(), size: Size(w, 900));
        final amount = tester.getRect(find.text('300,000원'));

        // 구분선은 폭이 정확히 1 인 박스다.
        final lines = <Rect>[];
        for (final e in find.byType(Container).evaluate()) {
          final r = tester.getRect(find.byWidget(e.widget));
          if (r.width == 1.0 && r.height > 10) lines.add(r);
        }
        expect(lines, isNotEmpty, reason: '구분선을 못 찾았다 (@$w)');

        // 금액 바로 오른쪽 구분선과의 간격
        final right = lines
            .where((r) => r.left >= amount.right)
            .fold<double?>(null, (m, r) => m == null || r.left < m ? r.left : m);
        expect(right, isNotNull, reason: '금액 오른쪽 구분선이 없다 (@$w)');
        expect(right! - amount.right, greaterThanOrEqualTo(4.0),
            reason: '폭 $w: 금액이 구분선에 ${right - amount.right}px 로 붙었다');
      }
    });

    testWidgets('좁은 화면(320x568)에서도 넘치지 않는다', (tester) async {
      await _pumpHome(tester, size: const Size(320, 568));
      expect(tester.takeException(), isNull);
    });

    testWidgets('넓은 화면(430x932)에서도 넘치지 않는다', (tester) async {
      await _pumpHome(tester, size: const Size(430, 932));
      expect(tester.takeException(), isNull);
    });
  });

  group('#135 홈 — 기능이 하나도 사라지지 않았다', () {
    test('예전에 있던 메서드/화면 연결이 소스에 그대로 있다', () {
      final src = _codeOf('lib/screens/ds/home_ds_screen.dart');
      for (final name in [
        '_proModal',          // Pro 안내 모달
        '_openInsight',       // 인사이트 -> 해당 화면
        '_push',              // 공통 네비게이션
        '_activeSlice',       // 비중 조각 선택 상태
        '_isPro',             // 구독 분기
        'FnDemo.resolve',     // 실데이터 연결
        'TrendDsScreen',      // 지출 추이
        'DonutDsScreen',      // 과세/면세 상세
        'PriceDsScreen',      // 품목 시세
        'CompareDsScreen',    // 거래처 비교
        'InsightsDsScreen',   // 전체 인사이트
        'GuideDsScreen',      // 스마트 사입 가이드
        'class _ProModal',    // 모달 위젯 자체
      ]) {
        expect(src, contains(name), reason: '$name 이(가) 사라졌다');
      }
      // 네 갈래 인사이트 분기가 전부 남아 있어야 한다.
      for (final t in ['price', 'compare', 'donut', 'trend']) {
        expect(src, contains('FnInsightTarget.$t'));
      }
    });

    testWidgets('총 지출 카드를 누르면 지출 추이 화면이 열린다', (tester) async {
      await _pumpHome(tester, items: _sample());
      await tester.tap(find.text('500,000원'));
      // 🔴 라우트 전환에는 pump 가 **두 번** 필요하다.
      //    첫 pump 가 새 라우트를 트리에 끼워 넣고, 두 번째가 전환을 끝낸다.
      //    한 번만 하면 화면이 아직 안 바뀌어 findsNothing 이 된다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(TrendDsScreen), findsOneWidget);
    });

    testWidgets('🔴 품목 비중 카드를 누르면 품목별 지출 분석이 열린다 (#184)',
        (tester) async {
      // `SubscriptionService.unlockEverything == true` 라 모든 기능이 열려
      // 있다. (사장님 지시: "프로 어쩌고 이런거는 다 빼기로 했잖아")
      expect(SubscriptionService.instance.isPro, isTrue,
          reason: '구독 정책이 바뀌었다면 이 테스트의 기대값도 같이 바꿔야 한다');
      await _pumpHome(tester, items: _sample());
      // 🔴 #183 에서는 그 화면이 없어 월별 인사이트로 임시 연결했었다.
      //    #184 에서 제 화면을 만들었으니 이제 그리로 가야 한다.
      await tester.tap(find.text('상세 분석 보기 >'));
      // 🔴 라우트 전환에는 pump 가 **두 번** 필요하다.
      //    첫 pump 가 새 라우트를 트리에 끼워 넣고, 두 번째가 전환을 끝낸다.
      //    한 번만 하면 화면이 아직 안 바뀌어 findsNothing 이 된다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(ItemSpendDsScreen), findsOneWidget);
      expect(find.byType(InsightsDsScreen), findsNothing);
    });

    testWidgets('🔴 지출 추이 카드를 누르면 시즌 매입 비교가 열린다 (#183)',
        (tester) async {
      await _pumpHome(tester, items: _sample());
      await tester.tap(find.text('자세히 보기 >'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(GuideSeasonDsScreen), findsOneWidget);
    });

    testWidgets('CTA 를 누르면 전체 인사이트가 열린다', (tester) async {
      await _pumpHome(tester, items: _sample());
      // CTA 는 접힌 화면 기준 y≈938 — 844 뷰포트 밖이다. 먼저 끌어올린다.
      await tester.drag(find.byType(SingleChildScrollView).first,
          const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('맞춤 사입 리포트 보기'));
      // 🔴 라우트 전환에는 pump 가 **두 번** 필요하다.
      //    첫 pump 가 새 라우트를 트리에 끼워 넣고, 두 번째가 전환을 끝낸다.
      //    한 번만 하면 화면이 아직 안 바뀌어 findsNothing 이 된다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(InsightsDsScreen), findsOneWidget);
    });

    testWidgets('실데이터가 있으면 데모 수치가 아니라 실값을 보여준다',
        (tester) async {
      final now = DateTime.now();
      final items = [
        _r('x', '대한꽃도매', DateTime(now.year, now.month, 3), [
          (name: '작약', qty: 10, price: 5000),
        ]),
      ];
      await _pumpHome(tester, items: items);
      expect(tester.takeException(), isNull);
      // 데모 고정값(305만)이 더 이상 보이면 안 된다.
      expect(find.text('3,050,000원'), findsNothing);
      expect(find.text('50,000원'), findsOneWidget);
    });

    testWidgets('영수증이 하나도 없어도 깨지지 않는다', (tester) async {
      await _pumpHome(tester, items: const []);
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeDsScreen), findsOneWidget);
    });
  });

  // 🔴 #153 (#136 후속) "영수증 0건이면 홈 차트가 빈칸"
  //
  // 실제로 재현되는지 직접 확인했다. months/spend 는 어떤 경우에도
  // 12개로 채워지므로 bars 가 비는 일은 없고, 0원인 달도 clamp(6.0)
  // 덕에 6dp 막대가 보인다. 즉 빈칸은 나오지 않는다.
  // 다만 bars 가 비는 분기가 94dp 빈칸을 돌려주고 있어서, 혹시라도
  // 그 경로를 타면 고장처럼 보인다. 안내문으로 바꾸고 고정한다.
  group('#153 홈 차트 — 0건에서도 빈칸이 아니다', () {
    test('🔴 영수증이 0건이어도 months/spend 가 12개로 채워진다', () {
      final d = FnDemo.resolveFrom(const <ReceiptModel>[]);
      expect(d.months.length, 12,
          reason: 'months 가 비면 차트가 통째로 사라진다');
      expect(d.spend.length, 12,
          reason: 'spend 가 비면 차트가 통째로 사라진다');
      expect(d.isDemo, isTrue, reason: '0건이면 데모 데이터를 보여준다');
    });

    test('🔴 영수증 1건이어도 12개월이 유지되고 막대가 그려진다', () {
      final r = ReceiptModel(
        id: 'x',
        date: DateTime.now(),
        storeName: '가게',
        items: const [],
        totalAmount: 1000,
        rawOcrText: '',
        createdAt: DateTime.now(),
      );
      final d = FnDemo.resolveFrom([r]);
      expect(d.months.length, 12);
      expect(d.spend.length, 12);
      expect(d.isDemo, isFalse, reason: '실데이터가 있으면 데모가 아니다');

      // 0원인 달도 최소 높이 6dp 로 보인다 (clamp).
      // 실제 계산을 그대로 재현해 확인한다.
      const barFull = 94.0;
      const topPct = 76.0;
      final tail = d.spend.sublist(d.spend.length - 6);
      final mx = tail.reduce((a, b) => a > b ? a : b);
      for (final v in tail) {
        final pct = mx <= 0 ? 0.0 : v / mx * topPct;
        final h = (pct / 100 * barFull).clamp(6.0, barFull);
        expect(h, greaterThanOrEqualTo(6.0),
            reason: '막대 높이가 0 이면 그 자리가 빈칸으로 보인다');
      }
    });

    testWidgets('🔴 영수증 0건이면 빈칸이 아니라 안내와 스캔 버튼이 보인다 (#183)',
        (tester) async {
      await _pumpHome(tester);
      expect(tester.takeException(), isNull);

      // 두 카드가 다 있고
      expect(find.text('지출 추이'), findsOneWidget);
      expect(find.text('품목 비중'), findsOneWidget);

      // 🔴 #183 부터 영수증이 0건이면 시안 데모 막대를 그리지 않는다.
      //    예전에는 305만 짜리 가짜 막대가 떠서 자기 매입으로 오해하셨다.
      //    두 카드 모두 같은 안내 + 스캔 버튼을 보여준다.
      expect(find.text('영수증을 찍으면 여기에 정리돼요'), findsNWidgets(2));
      expect(find.text('영수증 스캔하기'), findsNWidgets(2));

      // 코랄 카드도 데모 숫자(305만) 대신 0원이어야 한다.
      expect(find.text('3,050,000원'), findsNothing);
      expect(find.text('0원'), findsOneWidget);
    });

    test('🔴 bars 가 비면 빈칸 대신 안내문을 보여준다', () {
      // 지금 데이터 경로로는 타지 않는 분기지만, 타더라도 빈칸이면 안 된다.
      final code = io.File('lib/screens/ds/home_ds_screen.dart')
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => !l.startsWith('//') && !l.startsWith('///'))
          .join('\n');
      expect(code.contains('아직 지출 기록이 없어요'), isTrue,
          reason: 'bars 가 비었을 때 94dp 빈칸만 남으면 고장처럼 보인다');
      // 🔴 #183 영수증이 0건일 때 카드가 보여줄 안내.
      expect(code.contains('영수증을 찍으면 여기에 정리돼요'), isTrue,
          reason: '0건일 때 빈 카드만 남으면 고장처럼 보인다');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 홈 팁 자동 변경 (#186)
  // ═══════════════════════════════════════════════════════════════════

  /// 셈만 확인할 때 쓰는 작은 팁 목록. 진짜 목록과 떼어 둔다.
  ///
  /// 🔴 `kHomeTips` 로 규칙을 확인하면, 나중에 팁을 한 줄 더할 때마다
  ///    엉뚱한 테스트가 깨진다. 규칙은 작은 목록으로, 진짜 목록은
  ///    "모양이 맞는지" 만 본다.
  const sample = <HomeTip>[
    HomeTip(
      id: 'M1',
      group: '시즌',
      when: TipWhen.month,
      month: 9,
      title: '9월 팁 하나',
      body: '9월에만 보여요.',
    ),
    HomeTip(
      id: 'M2',
      group: '시즌',
      when: TipWhen.month,
      month: 9,
      title: '9월 팁 둘',
      body: '9월에만 보여요.',
    ),
    HomeTip(
      id: 'Y1',
      group: '관리',
      when: TipWhen.allYear,
      title: '연중 팁',
      body: '아무 때나 보여요.',
    ),
    HomeTip(
      id: 'T1',
      group: '세무',
      when: TipWhen.month,
      month: 7,
      title: '기한 있는 팁',
      body: '7월 25일까지 신고가 있어요.',
      deadline: (7, 25),
    ),
    HomeTip(
      id: 'K1',
      group: '시즌',
      when: TipWhen.chuseok,
      title: '추석 팁',
      body: '추석 전에만 보여요.',
    ),
  ];

  group('홈 팁 — 고르는 규칙 (#186)', () {
    test('🔴 오늘 보여줄 수 있는 팁 = 이번 달 팁 + 연중 팁', () {
      final list = HomeTipPicker.candidates(DateTime(2026, 9, 1), all: sample);
      final ids = list.map((e) => e.id).toList();
      expect(ids, contains('M1'));
      expect(ids, contains('M2'));
      expect(ids, contains('Y1'));
      // 7월 팁은 9월에 안 나온다.
      expect(ids, isNot(contains('T1')));
    });

    test('🔴 이번 달 팁을 연중 팁보다 먼저 보여준다', () {
      final list = HomeTipPicker.candidates(DateTime(2026, 9, 1), all: sample);
      final yearIdx = list.indexWhere((e) => e.when == TipWhen.allYear);
      final monthIdx = list.lastIndexWhere((e) => e.when == TipWhen.month);
      expect(monthIdx, lessThan(yearIdx),
          reason: '연중 팁이 이번 달 팁보다 앞에 왔다');
    });

    test('🔴 날짜가 바뀌면 다음 팁으로 넘어간다', () {
      final seen = <String>{};
      for (var i = 0; i < 3; i++) {
        final t = HomeTipPicker.pick(DateTime(2026, 9, 1 + i), all: sample);
        seen.add(t!.id);
      }
      expect(seen.length, greaterThan(1), reason: '며칠이 지나도 같은 팁만 나온다');
    });

    test('🔴 같은 날 두 번 물어도 같은 팁이다', () {
      final a = HomeTipPicker.pick(DateTime(2026, 9, 7), all: sample);
      final b = HomeTipPicker.pick(DateTime(2026, 9, 7), all: sample);
      expect(a!.id, b!.id, reason: '화면을 두 번 열면 팁이 달라진다');
    });

    test('🔴 한 번 본 팁은 30일 동안 다시 안 나온다', () {
      // 🔴 9월 4일부터는 추석 팁(K1)도 후보라 답이 둘이 된다.
      //    추석 기간 **밖**의 날을 골라 M1·M2·Y1 만 남긴다.
      final today = DateTime(2026, 9, 1);
      // M1·M2 를 어제 봤다. 남은 건 연중 팁뿐이다.
      final seen = {
        'M1': today.subtract(const Duration(days: 1)),
        'M2': today.subtract(const Duration(days: 2)),
      };
      final t = HomeTipPicker.pick(today, seen: seen, all: sample);
      expect(t!.id, 'Y1');
    });

    test('30일이 지난 팁은 다시 나올 수 있다', () {
      final today = DateTime(2026, 9, 1);
      final seen = {'M1': today.subtract(const Duration(days: 31))};
      final ids = <String>{};
      for (var i = 0; i < 5; i++) {
        final t = HomeTipPicker.pick(
            today.add(Duration(days: i)), seen: seen, all: sample);
        ids.add(t!.id);
      }
      expect(ids, contains('M1'));
    });

    test('🔴 다 봤으면 빈칸 대신 가장 오래전에 본 것을 다시 보여준다', () {
      // 추석 기간 밖. 후보는 M1·M2·Y1 셋뿐이고 셋 다 봤다.
      final today = DateTime(2026, 9, 1);
      final seen = {
        'M1': today.subtract(const Duration(days: 3)),
        'M2': today.subtract(const Duration(days: 1)),
        'Y1': today.subtract(const Duration(days: 2)),
      };
      final t = HomeTipPicker.pick(today, seen: seen, all: sample);
      expect(t, isNotNull, reason: '빈칸이 되면 카드가 비어 보인다');
      expect(t!.id, 'M1', reason: '가장 오래전에 본 것부터 다시 돌아야 한다');
    });

    test('🔴 세무 팁은 신고 기한이 지나면 안 보인다', () {
      // 7월 25일까지. 당일은 보이고, 다음 날은 안 보인다.
      expect(sample[3].showsOn(DateTime(2026, 7, 25)), isTrue);
      expect(sample[3].showsOn(DateTime(2026, 7, 26)), isFalse);
      expect(sample[3].showsOn(DateTime(2026, 7, 1)), isTrue);
    });

    test('🔴 추석 팁은 3주 전부터 추석 당일까지만', () {
      // 2026년 추석은 9월 25일. 3주 전은 9월 4일.
      final chuseok = KoreanDates.chuseok(2026)!;
      const tip = HomeTip(
        id: 'K1',
        group: '시즌',
        when: TipWhen.chuseok,
        title: '추석 팁',
        body: '',
      );
      expect(tip.showsOn(DateTime(2026, 9, 3), chuseok: chuseok), isFalse);
      expect(tip.showsOn(DateTime(2026, 9, 4), chuseok: chuseok), isTrue);
      expect(tip.showsOn(DateTime(2026, 9, 25), chuseok: chuseok), isTrue);
      expect(tip.showsOn(DateTime(2026, 9, 26), chuseok: chuseok), isFalse);
    });

    test('🔴 추석 날짜를 모르는 해에는 추석 팁이 안 보인다', () {
      // 2029년은 표에 없다. 틀린 날짜로 보여주느니 숨긴다.
      expect(KoreanDates.chuseok(2029), isNull);
      final ids = HomeTipPicker.candidates(DateTime(2029, 9, 10), all: sample)
          .map((e) => e.id);
      expect(ids, isNot(contains('K1')));
    });

    test('보여줄 팁이 하나도 없으면 null', () {
      expect(HomeTipPicker.pick(DateTime(2026, 9, 1), all: const []), isNull);
    });
  });

  group('홈 팁 — 추석·수능 날짜 (사장님 확인 #186)', () {
    test('🔴 추석 2026~2028', () {
      expect(KoreanDates.chuseok(2026), DateTime(2026, 9, 25));
      expect(KoreanDates.chuseok(2027), DateTime(2027, 9, 15));
      expect(KoreanDates.chuseok(2028), DateTime(2028, 10, 3));
    });

    test('🔴 수능 2026~2028', () {
      expect(KoreanDates.suneung(2026), DateTime(2026, 11, 19));
      expect(KoreanDates.suneung(2027), DateTime(2027, 11, 18));
      expect(KoreanDates.suneung(2028), DateTime(2028, 11, 16));
    });
  });

  group('홈 팁 — 목록 (#186)', () {
    test('🔴 S·C·O 팁만 넣었다. 데이터 팁(D)은 아직 없다', () {
      expect(kHomeTips.length, 58);
      for (final t in kHomeTips) {
        expect('SCO'.contains(t.id[0]), isTrue, reason: '${t.id} 가 섞여 있다');
      }
      expect(kHomeTips.any((e) => e.id.startsWith('D')), isFalse);
    });

    test('🔴 ID 가 겹치지 않는다', () {
      final ids = kHomeTips.map((e) => e.id).toSet();
      expect(ids.length, kHomeTips.length, reason: 'ID 가 겹치면 본 기록이 엉킨다');
    });

    test('🔴 달 팁은 1~12월이 다 있고, 달이 빠진 줄이 없다', () {
      final months = <int>{};
      for (final t in kHomeTips) {
        if (t.when != TipWhen.month) continue;
        expect(t.month, inInclusiveRange(1, 12), reason: '${t.id} 의 달이 이상하다');
        months.add(t.month);
      }
      expect(months.length, 12, reason: '팁이 없는 달이 있으면 그 달엔 연중 팁만 돈다');
    });

    test('🔴 제목·본문이 빈 줄이 없다', () {
      for (final t in kHomeTips) {
        expect(t.title.trim(), isNotEmpty, reason: '${t.id} 제목이 비었다');
        expect(t.body.trim(), isNotEmpty, reason: '${t.id} 본문이 비었다');
      }
    });

    test('🔴 세무 팁 S02·S04·S19 에 신고 기한이 달려 있다', () {
      HomeTip byId(String id) => kHomeTips.firstWhere((e) => e.id == id);
      expect(byId('S02').deadline, (1, 25));
      expect(byId('S04').deadline, (2, 10));
      expect(byId('S19').deadline, (7, 25));
      // 기한이 지나면 안 보인다.
      expect(byId('S19').showsOn(DateTime(2026, 7, 26)), isFalse);
    });

    test('🔴 추석 팁 S23 은 추석 기간에만 보인다', () {
      final s23 = kHomeTips.firstWhere((e) => e.id == 'S23');
      expect(s23.when, TipWhen.chuseok);
      final chuseok = KoreanDates.chuseok(2026)!;
      expect(s23.showsOn(DateTime(2026, 9, 10), chuseok: chuseok), isTrue);
      expect(s23.showsOn(DateTime(2026, 8, 1), chuseok: chuseok), isFalse);
    });

    test('어느 달에 열어도 보여줄 팁이 있다', () {
      for (var m = 1; m <= 12; m++) {
        final t = HomeTipPicker.pick(DateTime(2026, m, 15));
        expect(t, isNotNull, reason: '$m월에 보여줄 팁이 없다');
      }
    });
  });

  group('홈 팁 — 소스 계약 (#186)', () {
    test('🔴 팁을 앱 안 목록에 담았다 (Firestore 아님)', () {
      final src = _read('lib/services/home_tips.dart');
      expect(src.contains('const List<HomeTip> kHomeTips'), isTrue);
      // 🔴 글자만 세면 "Firestore 가 아니다" 라고 적은 **주석**에 걸린다.
      //    실제로 쓰는지 보려면 import 를 본다.
      for (final banned in [
        'cloud_firestore',
        'package:http',
        'FirebaseFirestore.instance',
      ]) {
        expect(src.contains(banned), isFalse, reason: '$banned 를 쓰고 있다');
      }
    });

    test('🔴 본 기록을 이 기기에만 남긴다 (클라우드 저장 안 함)', () {
      final src = _read('lib/services/home_tips.dart');
      expect(src.contains('SharedPreferences'), isTrue);
      expect(src.contains('UserRepository'), isFalse);
      expect(src.contains('backup'), isFalse);
    });

    test('🔴 팁 카드 모양과 이동이 그대로다', () {
      final home = _read('lib/screens/ds/home_ds_screen.dart');
      // 코랄 제목 + 본문, 누르면 품목 시세로.
      expect(home.contains('FnHome.coralText'), isTrue);
      expect(home.contains('PriceDsScreen()'), isTrue);
      // 옛 고정 문구는 사라졌다.
      expect(home.contains('여름철 절화 수명 관리 팁'), isFalse);
    });

    test('🔴 팁을 build() 안에서 고르지 않는다', () {
      final home = _read('lib/screens/ds/home_ds_screen.dart');
      // build 마다 고르면 "봤다" 기록이 하루 만에 다 소모된다.
      expect(home.contains('HomeTipStore.instance.today()'), isTrue);
      expect(home.contains('_tip = HomeTipStore'), isTrue);
    });

    test('🔴 데이터 팁(D01~D10)이 다음 할 일로 문서에 적혀 있다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('D01'), isTrue);
      expect(doc.contains('데이터 팁'), isTrue);
    });
  });
}
