import 'package:flutter/material.dart';
import 'dart:io' as io;
import 'package:provider/provider.dart';
import 'package:flow_note/design/fn_home_tokens.dart';
import 'package:flow_note/providers/receipt_provider.dart';
import 'package:flow_note/screens/ds/home_ds_screen.dart';
import 'package:flow_note/services/subscription_service.dart';
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
      await _pumpHome(tester);
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
      await _pumpHome(tester);
      expect(find.text('이번 달 총 지출'), findsOneWidget);
      expect(find.text('지출 추이'), findsOneWidget);
      expect(find.text('품목 비중'), findsOneWidget);
      expect(find.text('스마트 사입 가이드'), findsOneWidget);
      expect(find.text('권장 사입 주기'), findsOneWidget);
      expect(find.text('권장 절화 비중'), findsOneWidget);
      expect(find.text('여름철 절화 수명 관리 팁'), findsOneWidget);
      expect(find.text('상세 분석 보기 >'), findsOneWidget);
      expect(find.textContaining('맞춤 사입 리포트 보기'), findsOneWidget);
    });

    testWidgets('막대가 6개이고 마지막만 넓게 강조된다', (tester) async {
      await _pumpHome(tester);
      // 데모 데이터는 12개월 -> 꼬리 6개만 그린다.
      final labels = ['2월', '3월', '4월', '5월', '6월', '7월'];
      for (final m in labels) {
        expect(find.text(m), findsWidgets, reason: '$m 막대 라벨이 없다');
      }
      // 강조 막대 폭(42) > 일반 막대 폭(27)
      expect(FnHome.barActiveW, greaterThan(FnHome.barW));
    });

    testWidgets('총 지출 금액과 전월/영수증/변동폭이 함께 보인다',
        (tester) async {
      await _pumpHome(tester);
      // 데모: 이번 달 305만, 전월 262만, 영수증 8매
      expect(find.text('₩3,050,000'), findsOneWidget);
      expect(find.text('₩2,620,000'), findsOneWidget);
      expect(find.text('8매'), findsOneWidget);
      expect(find.text('전월 지출'), findsOneWidget);
      expect(find.text('변동폭'), findsOneWidget);
    });

    testWidgets('카드 좌우 여백이 좌우 대칭이다(시안 19.7dp)', (tester) async {
      await _pumpHome(tester);
      final screen = tester.getSize(find.byType(HomeDsScreen));
      // 코랄 카드는 화면 가로 전체를 쓰고 처음부터 보이므로 여백 측정에 좋다.
      // 조상 Container 는 3개다:
      //   [0] 칩(38..163.8)  [1] 코랄 카드(20..370)  [2] 화면 전체(0..390)
      // `.last` 를 쓰면 화면 전체를 집어 여백이 늘 0 으로 나온다.
      final coral = find.ancestor(
        of: find.text('이번 달 총 지출'),
        matching: find.byType(Container),
      );
      final box = tester.getRect(coral.at(1));
      final left = box.left;
      final right = screen.width - box.right;
      expect((left - right).abs(), lessThan(1.0),
          reason: '좌 $left / 우 $right — 좌우가 어긋났다');
      expect(left, closeTo(FnHome.pagePad, 1.0));
    });

    testWidgets('🔴 통계 금액이 구분선에 달라붙지 않는다', (tester) async {
      // 처음 만들 때 `_stat` 에 가로 패딩이 없어서, 긴 금액(₩2,620,000)의
      // 오른쪽 끝이 구분선에 **정확히 0.0px** 로 붙었다. 320/360/390
      // 세 폭 전부에서 그랬다. 320dp 렌더 스크린샷에서 눈으로 먼저 보였고,
      // 픽셀로 재서 확인한 뒤 좌우 7dp 를 넣었다.
      for (final w in [320.0, 360.0, 390.0]) {
        await _pumpHome(tester, size: Size(w, 900));
        final amount = tester.getRect(find.text('₩2,620,000'));

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
      await _pumpHome(tester);
      await tester.tap(find.text('₩3,050,000'));
      // 🔴 라우트 전환에는 pump 가 **두 번** 필요하다.
      //    첫 pump 가 새 라우트를 트리에 끼워 넣고, 두 번째가 전환을 끝낸다.
      //    한 번만 하면 화면이 아직 안 바뀌어 findsNothing 이 된다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(TrendDsScreen), findsOneWidget);
    });

    testWidgets('상세 분석 보기를 누르면 과세/면세 상세가 열린다', (tester) async {
      // `SubscriptionService.unlockEverything == true` 라 모든 기능이 열려
      // 있다. (사장님 지시: "프로 어쩌고 이런거는 다 빼기로 했잖아")
      // 따라서 Pro 모달이 아니라 실제 화면이 뜨는 게 맞는 동작이다.
      expect(SubscriptionService.instance.isPro, isTrue,
          reason: '구독 정책이 바뀌었다면 이 테스트의 기대값도 같이 바꿔야 한다');
      await _pumpHome(tester);
      await tester.tap(find.text('상세 분석 보기 >'));
      // 🔴 라우트 전환에는 pump 가 **두 번** 필요하다.
      //    첫 pump 가 새 라우트를 트리에 끼워 넣고, 두 번째가 전환을 끝낸다.
      //    한 번만 하면 화면이 아직 안 바뀌어 findsNothing 이 된다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(DonutDsScreen), findsOneWidget);
    });

    testWidgets('CTA 를 누르면 전체 인사이트가 열린다', (tester) async {
      await _pumpHome(tester);
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
      expect(find.text('₩3,050,000'), findsNothing);
      expect(find.text('₩50,000'), findsOneWidget);
    });

    testWidgets('영수증이 하나도 없어도 깨지지 않는다', (tester) async {
      await _pumpHome(tester, items: const []);
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeDsScreen), findsOneWidget);
    });
  });
}
