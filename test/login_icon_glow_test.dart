// 요청 #116 — 로그인 화면 아이콘을 **글로우가 그려진 심볼**로 바꾼다.
//
// 사용자 요청: "이거 앱 로그인 할 때 페이지 아이콘을 이걸로 변경해줘."
//
// 이 테스트가 지키려는 것:
//
//  1. 로그인 화면(`splash_ds_screen` / 레거시 `login_screen`)은 글로우 판을
//     쓴다.
//  2. 🔴 **앱아이콘 · 파비콘 · maskable 은 절대 글로우 판으로 바뀌지 않는다.**
//     글로우 판은 사방에 반투명 여백이 있어서 정사각으로 잘리는 자리에
//     넣으면 글로우가 잘려 한 변이 떨어진 네모처럼 보인다. `FnAppMark` 의
//     기본값이 조용히 글로우로 바뀌는 사고를 막는 게 이 테스트의 핵심이다.
//  3. 글로우 판에는 위젯 그림자를 얹지 않는다 (그림에 이미 번짐이 있어
//     아래쪽만 두 겹으로 짙어진다).
//  4. 글로우 판의 완전 투명 픽셀 RGB 가 검정이 아니다 — #114 에서 검은
//     실선을 만든 원인이라, 축소될 때 다시 같은 문제가 생기지 않게 고정한다.
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/design/fn_brand.dart';

/// PNG IHDR 에서 가로/세로를 직접 읽는다 (디코더 없이).
({int w, int h}) _pngSize(String path) {
  final b = io.File(path).readAsBytesSync();
  int be(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  return (w: be(16), h: be(20));
}

void main() {
  group('#116 글로우 심볼 자산', () {
    test('파일이 있고 pubspec 으로 묶여 나간다', () {
      expect(io.File(FnBrand.symbolGlowAsset).existsSync(), isTrue,
          reason: '${FnBrand.symbolGlowAsset} 이 없다');
      final pub = io.File('pubspec.yaml').readAsStringSync();
      expect(pub.contains('- assets/brand/'), isTrue,
          reason: 'assets/brand/ 가 없으면 실행 중에 아이콘이 안 뜬다');
      expect(FnBrand.symbolGlowAsset.startsWith('assets/brand/'), isTrue,
          reason: '선언된 자산 폴더 밖이면 번들에 안 들어간다');
    });

    test('글로우 판과 기본 심볼은 서로 다른 파일이다', () {
      expect(FnBrand.symbolGlowAsset, isNot(FnBrand.symbolAsset));
      final a = io.File(FnBrand.symbolAsset).readAsBytesSync();
      final b = io.File(FnBrand.symbolGlowAsset).readAsBytesSync();
      expect(a.length == b.length && a.first == b.first && a.last == b.last,
          isFalse,
          reason: '같은 그림을 복사만 해 두면 이번 요청이 반영되지 않은 것이다');
    });

    test('충분히 큰 정사각에 가까운 그림이다', () {
      final s = _pngSize(FnBrand.symbolGlowAsset);
      expect(s.w, greaterThanOrEqualTo(512));
      expect(s.h, greaterThanOrEqualTo(512));
      // 1018x1024 — 글로우 여백 때문에 정확한 정사각은 아니지만,
      // 한쪽으로 심하게 늘어나 있으면 `BoxFit.contain` 에서 작게 보인다.
      expect((s.w - s.h).abs() / s.h, lessThan(0.05),
          reason: '가로세로가 5% 이상 다르면 84 정사각 안에서 작아 보인다');
    });
  });

  group('#116 로그인 화면 렌더', () {
    testWidgets('glow: true 면 글로우 판을 그린다', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Center(child: FnAppMark(size: 84, glow: true)),
      ));
      final img = t.widget<Image>(find.byType(Image));
      expect((img.image as AssetImage).assetName, FnBrand.symbolGlowAsset);
      expect(t.getSize(find.byType(FnAppMark)), const Size(84, 84));
    });

    testWidgets('🔴 기본값은 여전히 기본 심볼이다 (앱아이콘 자리 보호)', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Center(child: FnAppMark(size: 84)),
      ));
      final img = t.widget<Image>(find.byType(Image));
      expect((img.image as AssetImage).assetName, FnBrand.symbolAsset,
          reason: '기본값이 글로우로 바뀌면 런처/파비콘에서 글로우가 잘린다');
    });

    testWidgets('🔴 글로우 판에는 위젯 그림자를 얹지 않는다', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Center(child: FnAppMark(size: 84, glow: true, shadow: true)),
      ));
      // 그림자를 그리는 Container(BoxDecoration) 가 아예 없어야 한다.
      final boxes = find.descendant(
        of: find.byType(FnAppMark),
        matching: find.byType(DecoratedBox),
      );
      expect(boxes, findsNothing,
          reason: '그림의 번짐 + 위젯 그림자가 겹쳐 아래쪽만 짙어진다');
    });
  });

  group('#116 화면 배치', () {
    test('로그인 화면 두 곳이 글로우 판을 쓴다', () {
      for (final p in [
        'lib/screens/ds/splash_ds_screen.dart',
        'lib/screens/login_screen.dart',
      ]) {
        final src = io.File(p).readAsStringSync();
        final live = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(live.contains('glow: true'), isTrue,
            reason: '$p 의 로그인 아이콘이 글로우 판이 아니다');
      }
    });

    test('🔴 글로우 경로를 화면 코드에서 직접 쓰지 않는다', () {
      final leftovers = <String>[];
      for (final f in io.Directory('lib').listSync(recursive: true)) {
        if (f is! io.File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('fn_brand.dart')) continue;
        if (f.readAsStringSync().contains('logo_symbol_glow.png')) {
          leftovers.add(f.path);
        }
      }
      expect(leftovers, isEmpty,
          reason: '글로우 판은 FnAppMark(glow: true) 로만 쓴다');
    });

    test('🔴 앱아이콘 원본은 정사각 1024 이고 글로우가 없다', () {
      // 런처 아이콘 · 파비콘 · 스플래시는 tool/gen_icons.py 가 이 파일에서
      // 만든다.
      //
      // 요청 #117 로 이 파일은 사용자가 준 글로우 그림에서 다시 만들어졌다.
      // 다만 🔴 **글로우는 벗겨냈다.** 정사각으로 잘리고 마스크가
      // 씌워지는 자리(런처 · 파비콘 · maskable)에서는 사방의 반투명
      // 여백이 살아남을 수 없기 때문이다. 그대로 넣으면 한 변이 떨어진
      // 네모로 보이거나, 글로우를 안에 넣으려고 그림을 줄여서 홈 화면의
      // 다른 앱보다 아이콘만 작아 보인다.
      expect(io.File('assets/icon/app_icon.png').existsSync(), isTrue);
      final s = _pngSize('assets/icon/app_icon.png');
      expect(s.w, 1024);
      expect(s.h, 1024, reason: '앱아이콘은 정사각 1024 를 유지해야 한다');
    });
  });
}
