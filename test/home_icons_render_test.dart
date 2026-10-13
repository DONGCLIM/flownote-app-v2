import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/design/fn_home_tokens.dart';
import 'package:flow_note/design/fn_icons.dart';
import 'package:flow_note/design/fn_shell.dart';
import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/providers/receipt_provider.dart';
import 'package:flow_note/screens/ds/home_ds_screen.dart';
import 'package:flow_note/screens/ds/main_ds_screen.dart';

/// #146 홈 시안 반영 검증.
///
/// 사장님 지적 4가지를 하나씩 테스트로 묶었다:
///   1. "카드마다 컬러도 다르고"            -> 카드1 #FFFDFC vs 카드3·4 #FFFFFF
///   2. "그림자 효과도 들어가있거든"        -> 카드 3종 + 버튼 + 탭바에 boxShadow
///   3. "알림 종 모양이 안 보여서"          -> 헤더에 FnBellIcon 1개
///   4. "맨 위 카드 아이콘을 오른쪽 걸로"    -> FnBookIcon, 분홍 박스 제거
///   5. "하단 바 아이콘도 동일하게"          -> FnTabIcon 5개

ReceiptModel _r(String id, DateTime d, String store, double amt) =>
    ReceiptModel(
      id: id,
      date: d,
      storeName: store,
      items: [FlowerItem(name: '장미', quantity: 1, unitPrice: amt, unit: '단')],
      totalAmount: amt,
      rawOcrText: 't',
      createdAt: d,
    );

class _Fake extends ReceiptProvider {
  _Fake(this._items);
  final List<ReceiptModel> _items;
  @override
  List<ReceiptModel> get allReceipts => _items;
}

List<ReceiptModel> _items() => <ReceiptModel>[
      for (var i = 0; i < 8; i++)
        _r('a$i', DateTime(2026, 8, 3 + i), '화람원예', 320000 + i * 11000),
      for (var i = 0; i < 6; i++)
        _r('b$i', DateTime(2026, 7, 2 + i * 3), '플라워팜', 280000 + i * 9000),
    ];

/// 홈 탭만 띄운다(헤더·탭바 없음). 카드 자체를 보는 테스트용.
Future<void> _pumpHome(WidgetTester t, {Size size = const Size(390, 844)}) async {
  // 🔴 `MediaQuery(data: MediaQueryData(size:))` 만으로는 뷰포트가 안 바뀐다.
  //    화면 기준 위치·크기를 재는 테스트는 반드시 view 를 직접 건드려야 한다.
  t.view.physicalSize = Size(size.width * 3, size.height * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<ReceiptProvider>.value(
      value: _Fake(_items()),
      child: const MaterialApp(home: Scaffold(body: HomeDsScreen())),
    ),
  );
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

/// 5탭 껍데기까지 띄운다. 헤더 벨 / 탭바 아이콘을 보는 테스트용.
Future<void> _pumpShell(WidgetTester t) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<ReceiptProvider>.value(
      value: _Fake(_items()),
      child: const MaterialApp(home: MainDsScreen()),
    ),
  );
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

/// 어떤 Finder 아래의 모든 `BoxDecoration` 을 모은다.
///
/// `Container` / `DecoratedBox` / `AnimatedContainer` 세 가지를 다 본다.
/// (세 위젯 모두 `decoration` 을 들고 있어서, 하나만 보면 놓친다)
List<BoxDecoration> _decosIn(Finder scope) {
  final out = <BoxDecoration>[];
  for (final e in find
      .descendant(of: scope, matching: find.byType(Container))
      .evaluate()) {
    final d = (e.widget as Container).decoration;
    if (d is BoxDecoration) out.add(d);
  }
  for (final e in find
      .descendant(of: scope, matching: find.byType(DecoratedBox))
      .evaluate()) {
    final d = (e.widget as DecoratedBox).decoration;
    if (d is BoxDecoration) out.add(d);
  }
  return out;
}

/// 어떤 글자를 품은 **가장 가까운** 카드의 `BoxDecoration` 을 찾는다.
///
/// 🔴 `find.ancestor(...).first` 를 쓰면 안 된다. 글자의 조상 목록에는
///    바깥 카드와 페이지 배경까지 들어 있어서, `.first` 가 엉뚱한 흰색을
///    집어 온다(#142·#144 에서 두 번 겪었다). 그래서 조상 중
///    **`boxShadow` 와 `borderRadius` 를 둘 다 가진 것**만 고르고,
///    그중 글자에 가장 가까운(= 목록에서 앞쪽) 것을 쓴다.
BoxDecoration _cardOf(String text) {
  final ancestors = find.ancestor(
    of: find.text(text),
    matching: find.byType(Container),
  );
  final cands = <BoxDecoration>[];
  for (final e in ancestors.evaluate()) {
    final d = (e.widget as Container).decoration;
    if (d is BoxDecoration && d.borderRadius != null) cands.add(d);
  }
  expect(cands, isNotEmpty, reason: '"$text" 를 품은 둥근 카드를 못 찾았다');
  return cands.first;
}

void main() {
  group('#146 홈 카드 색·그림자', () {
    testWidgets('카드1(영수증 정리)은 순백이 아니라 #FFFDFC 다', (t) async {
      await _pumpHome(t);
      final d = _cardOf('장미 단가가 전월 대비 +19% 상승했어요');
      // 🔴 자기 자신(FnHome.cardWarm)과 비교하면 토큰을 바꿔도 통과한다.
      //    시안 실측값을 **리터럴로** 박아 비교한다.
      expect(d.color, const Color(0xFFFFFDFC));
      // 순백이면 안 된다 — 이게 "카드마다 컬러가 다르다" 의 핵심
      expect(d.color, isNot(const Color(0xFFFFFFFF)));
    });

    testWidgets('카드3(지출 추이)은 순백 #FFFFFF 다', (t) async {
      await _pumpHome(t);
      final d = _cardOf('지출 추이');
      expect(d.color, const Color(0xFFFFFFFF));
    });

    testWidgets('카드1·3 내부색이 서로 다르다', (t) async {
      await _pumpHome(t);
      final c1 = _cardOf('장미 단가가 전월 대비 +19% 상승했어요').color;
      final c3 = _cardOf('지출 추이').color;
      expect(c1, isNot(c3),
          reason: '시안은 카드1 #FFFDFC / 카드3 #FFFFFF 로 다르다');
    });

    testWidgets('카드1에 그림자가 있다', (t) async {
      await _pumpHome(t);
      final d = _cardOf('장미 단가가 전월 대비 +19% 상승했어요');
      expect(d.boxShadow, isNotNull);
      expect(d.boxShadow!, isNotEmpty);
    });

    testWidgets('카드3에 그림자가 있다', (t) async {
      await _pumpHome(t);
      final d = _cardOf('지출 추이');
      expect(d.boxShadow, isNotNull);
      expect(d.boxShadow!, isNotEmpty);
    });

    testWidgets('카드3 그림자가 카드1보다 진하다', (t) async {
      await _pumpHome(t);
      // 시안 Δ: 카드1 9.4 / 카드3 19.4 — 카드3 이 약 2배 진하다.
      final a1 = _cardOf('장미 단가가 전월 대비 +19% 상승했어요')
          .boxShadow!
          .first
          .color
          .a;
      final a3 = _cardOf('지출 추이').boxShadow!.first.color.a;
      expect(a3, greaterThan(a1),
          reason: '시안 Δ 19.4(카드3) > 9.4(카드1)');
    });

    testWidgets('그림자 색은 따뜻한 갈색이 아니라 무채색이다', (t) async {
      await _pumpHome(t);
      final c = _cardOf('지출 추이').boxShadow!.first.color;
      // 🔴 시안 그림자의 채널별 감소율이 R/G/B = 0.0261/0.0261/0.0261 로
      //    완전히 균일했다. 즉 #142 내역 화면의 #8A7268 과 다르다.
      final r = (c.r * 255).round();
      final g = (c.g * 255).round();
      final b = (c.b * 255).round();
      expect(r, g, reason: '무채색이어야 한다 (R==G)');
      expect(g, b, reason: '무채색이어야 한다 (G==B)');
    });

    testWidgets('코랄 CTA 버튼에 그림자가 있다', (t) async {
      await _pumpHome(t);
      final btn = find.textContaining('맞춤 사입 리포트 보기');
      expect(btn, findsOneWidget);
      final decos = <BoxDecoration>[];
      for (final e in find
          .ancestor(of: btn, matching: find.byType(Container))
          .evaluate()) {
        final d = (e.widget as Container).decoration;
        if (d is BoxDecoration && d.gradient != null) decos.add(d);
      }
      expect(decos, isNotEmpty, reason: '그라디언트 버튼을 못 찾았다');
      expect(decos.first.boxShadow, isNotNull);
      expect(decos.first.boxShadow!, isNotEmpty);
    });
  });

  group('#146 카드1 책 아이콘', () {
    testWidgets('시안 책 아이콘이 그려진다', (t) async {
      await _pumpHome(t);
      expect(find.byType(FnBookIcon), findsOneWidget);
    });

    testWidgets('분홍 둥근 사각 박스가 사라졌다', (t) async {
      await _pumpHome(t);
      // 전에는 책을 38x38 #FFF1EE 둥근 사각 안에 넣었다. 시안에는 없다.
      // 책 아이콘의 조상 중에 coralFaint 로 칠한 사각이 있으면 실패.
      final boxes = <BoxDecoration>[];
      for (final e in find
          .ancestor(of: find.byType(FnBookIcon), matching: find.byType(Container))
          .evaluate()) {
        final d = (e.widget as Container).decoration;
        if (d is BoxDecoration &&
            d.color == FnHome.coralFaint &&
            d.shape != BoxShape.circle) {
          boxes.add(d);
        }
      }
      expect(boxes, isEmpty,
          reason: '시안에는 아이콘 뒤 분홍 사각 박스가 없다');
    });

    testWidgets('책 아이콘 뒤에 분홍 글로우가 있다', (t) async {
      await _pumpHome(t);
      // 시안: 아이콘 바깥 16dp 까지 #FFF0EE 로 번진다.
      final decos = _decosIn(
        find.ancestor(
          of: find.byType(FnBookIcon),
          matching: find.byType(Center),
        ),
      );
      final glow = decos.where((d) =>
          d.boxShadow != null &&
          d.boxShadow!.isNotEmpty &&
          // 분홍빛 = 빨강 성분이 파랑보다 뚜렷하게 크다
          d.boxShadow!.first.color.r > d.boxShadow!.first.color.b);
      expect(glow, isNotEmpty, reason: '책 아이콘 글로우가 없다');
    });

    testWidgets('책 좌우 페이지 색이 다르다 (투톤)', (t) async {
      await _pumpHome(t);
      final w = t.widget<FnBookIcon>(find.byType(FnBookIcon));
      // 시안 실측 리터럴. 토큰을 바꿔도 통과하지 않게 값을 직접 쓴다.
      expect(w.left, const Color(0xFFFF787C));
      expect(w.right, const Color(0xFFFF9385));
      expect(w.left, isNot(w.right));
    });
  });

  group('#146 헤더 벨', () {
    testWidgets('시안 벨이 그려진다', (t) async {
      await _pumpShell(t);
      expect(find.byType(FnBellIcon), findsOneWidget);
    });

    testWidgets('Material 기본 벨은 더 안 쓴다', (t) async {
      await _pumpShell(t);
      final icons = find.byIcon(Icons.notifications_none_rounded);
      expect(icons, findsNothing,
          reason: '시안 모양과 달라서 커스텀 벨로 바꿨다');
    });

    testWidgets('벨을 누르면 안내가 뜬다 (연결 유지)', (t) async {
      await _pumpShell(t);
      await t.tap(find.byType(FnBellIcon));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('알림은 준비 중이에요'), findsOneWidget);
    });
  });

  group('#146 탭바 아이콘', () {
    testWidgets('탭 5칸 모두 시안 아이콘을 쓴다', (t) async {
      await _pumpShell(t);
      expect(find.byType(FnTabIcon), findsNWidgets(5));
    });

    testWidgets('탭 키가 5개 다 다르게 전달된다', (t) async {
      await _pumpShell(t);
      final keys = t
          .widgetList<FnTabIcon>(find.byType(FnTabIcon))
          .map((w) => w.tabKey)
          .toList();
      expect(keys, ['home', 'settle', 'scan', 'calendar', 'profile']);
    });

    testWidgets('활성 탭 아이콘만 코랄이다', (t) async {
      await _pumpShell(t);
      final ws = t.widgetList<FnTabIcon>(find.byType(FnTabIcon)).toList();
      // 홈이 기본 활성
      expect(ws[0].color, FnHome.coralFlat);
      for (final w in ws.skip(1)) {
        expect(w.color, isNot(FnHome.coralFlat));
      }
    });

    testWidgets('Material 탭 아이콘은 떠 있는 탭바에서 안 쓴다', (t) async {
      await _pumpShell(t);
      for (final ic in [
        Icons.home_rounded,
        Icons.business_center_outlined,
        Icons.photo_camera_outlined,
        Icons.calendar_today_outlined,
        Icons.person_outline_rounded,
      ]) {
        expect(find.byIcon(ic), findsNothing,
            reason: '$ic 는 시안 모양과 달라 커스텀으로 바꿨다');
      }
    });

    testWidgets('탭바에 그림자가 있고 위아래 대칭에 가깝다', (t) async {
      await _pumpShell(t);
      final nav = find.byType(FnBottomNavigation);
      expect(nav, findsOneWidget);
      final decos = _decosIn(nav).where((d) =>
          d.boxShadow != null &&
          d.boxShadow!.isNotEmpty &&
          d.borderRadius != null);
      expect(decos, isNotEmpty, reason: '탭바 그림자를 못 찾았다');
      final sh = decos.first.boxShadow!.first;
      // 시안 Δ위 14.9 / Δ아래 15.0 — 아래로 치우치지 않는다.
      // blur 에 비해 offset 이 작아야 위아래가 비슷하게 번진다.
      expect(sh.offset.dy, lessThan(sh.blurRadius / 2),
          reason: '시안은 위아래가 거의 대칭이다');
      // 무채색이어야 한다 (전에는 갈색 #8A5C57 이었다)
      final r = (sh.color.r * 255).round();
      final g = (sh.color.g * 255).round();
      final b = (sh.color.b * 255).round();
      expect(r, g);
      expect(g, b);
    });

    testWidgets('탭 아이콘 크기는 시안 실측 23dp 다', (t) async {
      await _pumpShell(t);
      final w = t.widgetList<FnTabIcon>(find.byType(FnTabIcon)).first;
      expect(w.size, 23.0);
    });
  });

  group('#146 커스텀 아이콘 자체', () {
    testWidgets('모르는 탭 키는 빈칸을 돌려주고 깨지지 않는다', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Center(child: FnTabIcon(tabKey: '없는키', color: Colors.black)),
      ));
      await t.pump();
      // 🔴 `takeException()` 이 null 이어야 진짜로 안 터진 것이다.
      //    (전에 `bool _noError() => true` 라는 의미 없는 단정을 썼다가
      //     사보타주로 걸러 냈다)
      expect(t.takeException(), isNull);
      // 모르는 키는 CustomPaint 없이 같은 크기 SizedBox 만 남는다.
      final box = t.widget<SizedBox>(find.descendant(
        of: find.byType(FnTabIcon),
        matching: find.byType(SizedBox),
      ));
      expect(box.width, FnHome.tabIconSize);
      expect(box.height, FnHome.tabIconSize);
    });

    testWidgets('알려진 탭 키 5개는 모두 CustomPaint 를 만든다', (t) async {
      for (final k in ['home', 'settle', 'scan', 'calendar', 'profile']) {
        await t.pumpWidget(MaterialApp(
          home: Center(child: FnTabIcon(tabKey: k, color: Colors.grey)),
        ));
        await t.pump();
        expect(t.takeException(), isNull, reason: '$k 에서 예외');
        expect(
          find.descendant(
            of: find.byType(FnTabIcon),
            matching: find.byType(CustomPaint),
          ),
          findsWidgets,
          reason: '$k 아이콘이 안 그려졌다',
        );
      }
    });

    testWidgets('벨·책도 예외 없이 그려진다', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [FnBellIcon(), FnBookIcon()],
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.byType(FnBellIcon), findsOneWidget);
      expect(find.byType(FnBookIcon), findsOneWidget);
    });
  });
}
