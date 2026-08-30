// #112 회귀 테스트
//  (A) 핀치줌 없이도 사진 이동이 되는가
//  (B) 뒤로가기 후 느려짐 — 안 보이는 탭이 재build 되지 않는가
//
// 🔴 왜 이런 테스트가 필요한가
//    두 문제 모두 "눈으로 보면 그냥 느리다/안 된다" 라서, 고쳤는지
//    아닌지 코드만 봐서는 알 수 없었다. 그래서 숫자로 재는 테스트를
//    같이 넣는다. 나중에 누가 `constrained: false` 를 지우거나
//    `_LazyTabs` 를 다시 `IndexedStack` 으로 되돌리면 여기서 걸린다.
import 'dart:io' as io;

import 'package:flutter/foundation.dart'
    show SynchronousFuture, debugDefaultTargetPlatformOverride;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/theme/app_theme.dart';
import 'package:flow_note/widgets/lazy_tabs.dart';
import 'package:flow_note/widgets/pan_zoom_photo.dart';

// ══════════════════════════════════════════════════════════════
// 테스트용 이미지 provider — 원하는 픽셀 크기를 즉시 돌려준다.
// ══════════════════════════════════════════════════════════════
class _FakeProvider extends ImageProvider<_FakeProvider> {
  const _FakeProvider(this.w, this.h);
  final int w;
  final int h;

  @override
  Future<_FakeProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FakeProvider>(this);

  @override
  ImageStreamCompleter loadImage(_FakeProvider key, ImageDecoderCallback d) {
    return OneFrameImageStreamCompleter(_frame(w, h));
  }

  static Future<ImageInfo> _frame(int w, int h) async {
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint());
    final img = await rec.endRecording().toImage(w, h);
    return ImageInfo(image: img);
  }

  @override
  bool operator ==(Object other) =>
      other is _FakeProvider && other.w == w && other.h == h;
  @override
  int get hashCode => Object.hash(w, h);
}

Future<Offset> _drag(WidgetTester t,
    {Offset step = const Offset(0, -12), int n = 10}) async {
  final g = await t.startGesture(t.getCenter(find.byType(InteractiveViewer)));
  await t.pump(const Duration(milliseconds: 16));
  for (var i = 0; i < n; i++) {
    await g.moveBy(step);
    await t.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await t.pumpAndSettle();
  final m = t
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getTranslation();
  return Offset(m.x, m.y);
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SizedBox(width: 300, child: child),
          const Expanded(child: SizedBox()),
        ]),
      ),
    );

void main() {
  group('#112(A) 핀치줌 없이도 영수증을 밀어서 볼 수 있다', () {
    testWidgets('🔴 배율 1 에서 세로로 긴 영수증이 이동한다', (t) async {
      await t.pumpWidget(_host(const PanZoomPhoto(
        height: 260,
        imageProvider: _FakeProvider(1200, 1600),
        image: SizedBox.expand(),
      )));
      await t.pumpAndSettle();

      final d = await _drag(t);
      expect(d.dy, lessThan(0),
          reason: '배율 1 에서 위로 끌었는데 이동량이 0 이다. '
              'constrained: false 가 빠졌거나 원본 비율을 못 읽은 것이다');
    });

    testWidgets('🔴 사진 끝을 넘어서 빈 배경이 끌려오지 않는다', (t) async {
      await t.pumpWidget(_host(const PanZoomPhoto(
        height: 260,
        imageProvider: _FakeProvider(1200, 1600),
        image: SizedBox.expand(),
      )));
      await t.pumpAndSettle();

      await _drag(t, step: const Offset(0, -40), n: 100);
      final m = t
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getTranslation();
      // 폭 300 * (1600/1200) = 400 높이. 뷰포트 260 -> 140 만큼만 이동 가능.
      expect(m.y, closeTo(-140, 1.5),
          reason: '경계를 벗어났다. boundaryMargin 을 무한으로 준 것 아닌가');
    });

    testWidgets('🔴 원본 비율을 모르면 예전과 동일하게(이동 없이) 동작한다', (t) async {
      // provider 를 주지 않은 경우 = 웹에서 앱 사진을 열었을 때 등
      await t.pumpWidget(_host(const PanZoomPhoto(
        height: 260,
        image: SizedBox.expand(),
      )));
      await t.pumpAndSettle();

      final d = await _drag(t);
      expect(d, Offset.zero,
          reason: '비율을 모르는데 이동이 된다면 빈 배경이 끌려다닌다');
    });

    testWidgets('🔴 세로가 짧은 영수증은 억지로 늘리지 않는다', (t) async {
      await t.pumpWidget(_host(const PanZoomPhoto(
        height: 260,
        imageProvider: _FakeProvider(1600, 400), // 폭300 -> 높이 75
        image: SizedBox.expand(),
      )));
      await t.pumpAndSettle();

      final d = await _drag(t);
      expect(d.dy, 0,
          reason: '넘칠 게 없는데 이동하면 사진이 화면에서 사라진다');
    });

    testWidgets('🔴 InteractiveViewer 는 constrained: false 여야 한다', (t) async {
      await t.pumpWidget(_host(const PanZoomPhoto(
        height: 260,
        imageProvider: _FakeProvider(1200, 1600),
        image: SizedBox.expand(),
      )));
      await t.pumpAndSettle();

      final iv = t.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(iv.constrained, isFalse,
          reason: 'true(기본값)면 배율1 이동 여유가 0 이 된다');
      expect(iv.minScale, 1);
      expect(iv.maxScale, 5, reason: '기존 확대 배율을 유지해야 한다');
      expect(iv.panEnabled, isTrue);
    });

    testWidgets('🔴 탭(전체화면 열기)은 여전히 동작한다', (t) async {
      var tapped = 0;
      await t.pumpWidget(_host(PanZoomPhoto(
        height: 260,
        imageProvider: const _FakeProvider(1200, 1600),
        onTap: () => tapped++,
        image: const SizedBox.expand(),
      )));
      await t.pumpAndSettle();

      await t.tap(find.byType(InteractiveViewer));
      await t.pumpAndSettle();
      expect(tapped, 1, reason: '드래그를 넣으면서 탭을 잡아먹었다');
    });
  });

  group('#112(B) 뒤로가기 후 반응 — 안 보이는 탭은 다시 그리지 않는다', () {
    testWidgets('🔴 provider 가 바뀌어도 숨은 탭은 재build 되지 않는다', (t) async {
      final counts = <int, int>{};
      final notifier = ValueNotifier<int>(0);
      addTearDown(notifier.dispose);

      Widget tab(int i) => AnimatedBuilder(
            animation: notifier,
            builder: (_, __) {
              counts[i] = (counts[i] ?? 0) + 1;
              return Text('탭$i');
            },
          );

      await t.pumpWidget(MaterialApp(
        home: LazyTabs(index: 0, builders: [
          () => tab(0),
          () => tab(1),
          () => tab(2),
        ]),
      ));
      // 처음엔 0번만 만들어졌어야 한다 (지연 생성)
      expect(counts.keys.toSet(), {0},
          reason: '열어 본 적 없는 탭까지 미리 build 했다');

      counts.clear();
      notifier.value++; // = 영수증 저장 후 notifyListeners()
      await t.pump();

      expect(counts[1], isNull, reason: '숨은 탭1이 다시 build 됐다');
      expect(counts[2], isNull, reason: '숨은 탭2가 다시 build 됐다');
    });

    testWidgets('🔴 탭을 다시 열면 최신 데이터로 갱신된다', (t) async {
      var value = 0;
      Widget build(int idx) => MaterialApp(
            home: LazyTabs(index: idx, builders: [
              () => Text('홈 v$value'),
              () => Text('내역 v$value'),
            ]),
          );

      await t.pumpWidget(build(1)); // 내역 탭을 먼저 본다
      expect(find.text('내역 v0'), findsOneWidget);

      await t.pumpWidget(build(0)); // 홈으로 이동
      value = 7; // 숨어 있는 동안 데이터가 바뀌었다
      await t.pumpWidget(build(1)); // 내역으로 돌아온다

      expect(find.text('내역 v7'), findsOneWidget,
          reason: '숨어 있던 탭이 옛 데이터를 그대로 들고 있다');
    });

    testWidgets('🔴 탭을 옮겨도 상태(스크롤/입력)가 살아있다', (t) async {
      final ctl = TextEditingController();
      addTearDown(ctl.dispose);

      // TextField 는 Material 조상이 필요하다.
      Widget build(int idx) => MaterialApp(
            home: Scaffold(
              body: LazyTabs(index: idx, builders: [
                () => TextField(controller: ctl),
                () => const Text('다른 탭'),
              ]),
            ),
          );

      await t.pumpWidget(build(0));
      await t.enterText(find.byType(TextField), '장미 20단');
      await t.pumpWidget(build(1)); // 다른 탭
      await t.pumpWidget(build(0)); // 돌아옴

      expect(ctl.text, '장미 20단',
          reason: '탭을 옮겼다가 돌아오니 입력이 날아갔다');
    });

    testWidgets('🔴 안 보이는 탭에서는 애니메이션이 멈춘다', (t) async {
      await t.pumpWidget(MaterialApp(
        home: LazyTabs(index: 0, builders: [
          () => const Text('홈'),
          () => const Text('내역'),
        ]),
      ));
      await t.pumpWidget(MaterialApp(
        home: LazyTabs(index: 1, builders: [
          () => const Text('홈'),
          () => const Text('내역'),
        ]),
      ));
      // 숨은 탭(0)의 TickerMode 가 꺼져 있어야 한다
      final offstages = t.widgetList<Offstage>(find.byType(Offstage)).toList();
      expect(offstages.where((o) => o.offstage).length, 1,
          reason: '숨긴 탭이 정확히 1개여야 한다');
    });

    testWidgets('🔴 main_ds_screen 이 IndexedStack 으로 되돌아가지 않았다', (t) async {
      const p = 'lib/screens/ds/main_ds_screen.dart';
      final src = _read(p);
      final live = src
          .split('\n')
          .where((l) =>
              l.contains('IndexedStack') && !l.trimLeft().startsWith('//'))
          .toList();
      expect(live, isEmpty,
          reason: 'IndexedStack 이 살아 있다. 5탭 전체 재build 가 돌아온다: $live');
      // _LazyTabs 는 테스트에서 import 할 수 있도록
      // lib/widgets/lazy_tabs.dart 의 public LazyTabs 로 빼냈다.
      expect(src.contains('LazyTabs('), isTrue,
          reason: 'LazyTabs 로 그리지 않고 있다');
      expect(src.contains("import '../../widgets/lazy_tabs.dart'"), isTrue,
          reason: 'lazy_tabs.dart import 가 사라졌다');
    });
  });

  group('#112 세 화면 모두 적용됐다', () {
    const screens = [
      'lib/screens/ds/scan_review_ds_screen.dart',
      'lib/screens/receipt_detail_screen.dart',
      'lib/screens/receipt_edit_screen.dart',
    ];

    testWidgets('🔴 사진 뷰어에 InteractiveViewer 를 직접 쓰지 않는다', (t) async {
      for (final p in screens) {
        final src = _read(p);
        expect(src.contains('PanZoomPhoto('), isTrue,
            reason: '$p 에 PanZoomPhoto 가 없다');
        // 전체화면 뷰어(_showFull)의 InteractiveViewer 는 남아도 된다.
        // 문제였던 건 260px 인라인 뷰어다 -> maxHeight: 260 조합이 없어야 한다.
        expect(src.contains('constraints: const BoxConstraints(maxHeight: 260)'),
            isFalse,
            reason: '$p 에 옛 260px 고정 뷰어가 남아 있다');
      }
    });

    testWidgets('🔴 인라인 뷰어 사진은 BoxFit.fill 로 그린다', (t) async {
      // 바깥에서 원본 비율대로 크기를 잡으므로, 안에서 또 맞추면 여백이 생긴다.
      for (final p in screens) {
        final src = _read(p);
        final i = src.indexOf('PanZoomPhoto(');
        final seg = src.substring(i, i + 900);
        expect(seg.contains('BoxFit.fill'), isTrue,
            reason: '$p 의 PanZoomPhoto 안이 fill 이 아니다');
      }
    });
  });

  group('#112(B) 뒤로가기 화면 전환이 짧아졌다', () {
    Future<int> measurePop(WidgetTester t, ThemeData theme) async {
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(
        navigatorKey: nav,
        theme: theme,
        home: const Scaffold(body: Center(child: Text('탭 화면'))),
      ));
      await t.pumpAndSettle();
      nav.currentState!.push(MaterialPageRoute(
          builder: (_) => const Scaffold(body: Center(child: Text('상세')))));
      await t.pumpAndSettle();

      var ms = 0;
      var n = 0;
      nav.currentState!.pop();
      while (t.binding.hasScheduledFrame && n < 400) {
        await t.pump(const Duration(milliseconds: 8));
        ms += 8;
        n++;
      }
      return ms;
    }

    testWidgets('🔴 뒤로가기 애니메이션이 200ms 안에 끝난다', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ms = await measurePop(t, AppTheme.lightTheme);
      expect(ms, lessThan(200),
          reason: '뒤로가기가 ${ms}ms 걸린다. 기본값(약 312ms)으로 '
              '되돌아갔는지 pageTransitionsTheme 을 확인하라');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('🔴 테마에 FnFastPageTransitions 가 걸려 있다', (t) async {
      final theme = AppTheme.lightTheme;
      final b = theme.pageTransitionsTheme.builders[TargetPlatform.android];
      expect(b, isA<FnFastPageTransitions>(),
          reason: '안드로이드 전환이 기본값으로 되돌아갔다');
      expect(b!.reverseTransitionDuration.inMilliseconds, 160);
      // 앞으로 가는 전환은 너무 빠르면 뚝 끊긴 느낌이 난다 — 240ms 유지.
      expect(b.transitionDuration.inMilliseconds, 240);
    });
  });
}

String _read(String p) => io.File(p).readAsStringSync();
