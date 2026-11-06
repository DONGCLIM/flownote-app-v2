// #114 브랜드 자산(텍스트로고 · 앱로고) 반영 검증.
//
// 핵심 규칙은 하나다: **워드마크와 심볼은 서로 바꿔 쓸 수 없다.**
//   - 심볼  = 정사각 스쿼클 + 흰 책  -> 앱아이콘 / 파비콘 / 정사각 자리
//   - 워드마크 = 가로로 긴 글자      -> 화면 안 브랜드 표기 (정사각 금지)
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/design/fn_brand.dart';

void main() {
  group('#114 브랜드 자산 파일', () {
    test('워드마크 파일이 있고 pubspec 에 선언되어 있다', () {
      expect(io.File('assets/brand/logo_wordmark.png').existsSync(), isTrue);
      final pub = io.File('pubspec.yaml').readAsStringSync();
      expect(pub.contains('- assets/brand/'), isTrue,
          reason: 'assets/brand/ 가 없으면 실행 중에 워드마크가 안 뜬다');
    });

    test('워드마크 비율이 FnBrand.wordmarkRatio 와 맞는다', () {
      final b = io.File('assets/brand/logo_wordmark.png').readAsBytesSync();
      // PNG IHDR: 폭/높이는 16바이트 뒤 빅엔디안 4바이트씩.
      int be(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
      final w = be(16), h = be(20);
      expect(h, 300);
      expect(w / h, closeTo(FnBrand.wordmarkRatio, 0.01));
      // 워드마크는 반드시 가로로 길다 -> 정사각 슬롯에 넣으면 글자가 잘린다.
      expect(w / h, greaterThan(3));
    });

    test('심볼 파일은 정사각이다', () {
      final b = io.File('assets/icon/app_icon.png').readAsBytesSync();
      int be(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
      expect(be(16), 1024);
      expect(be(20), 1024);
    });

    test('생성된 플랫폼 아이콘이 다 있다', () {
      for (final p in [
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png',
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png',
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_background.png',
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
        'web/icons/Icon-192.png',
        'web/icons/Icon-512.png',
        'web/icons/Icon-maskable-192.png',
        'web/icons/Icon-maskable-512.png',
        'web/icons/Icon-apple-180.png',
        'web/favicon.png',
      ]) {
        expect(io.File(p).existsSync(), isTrue, reason: '$p 가 없다');
      }
    });

    test('web/index.html 은 알파 없는 apple-touch-icon 을 쓴다', () {
      final html = io.File('web/index.html').readAsStringSync();
      expect(html.contains('icons/Icon-apple-180.png'), isTrue);
      expect(html.contains('apple-touch-icon" href="icons/Icon-192.png"'), isFalse);
    });
  });

  group('#114 브랜드 위젯 렌더', () {
    testWidgets('FnAppMark 는 심볼을 정사각으로 그린다', (t) async {
      await t.pumpWidget(const MaterialApp(home: Center(child: FnAppMark(size: 84))));
      final img = t.widget<Image>(find.byType(Image));
      expect((img.image as AssetImage).assetName, FnBrand.symbolAsset);
      expect(t.getSize(find.byType(FnAppMark)), const Size(84, 84));
      // 🔴 그림에 스쿼클이 이미 있으므로 위젯이 또 자르면 안 된다.
      final box = t.widget<Container>(find.descendant(
          of: find.byType(FnAppMark), matching: find.byType(Container)));
      expect(box.clipBehavior, Clip.none);
    });

    testWidgets('FnWordmark 는 비율대로 넓어진다', (t) async {
      await t.pumpWidget(const MaterialApp(home: Center(child: FnWordmark(height: 33))));
      final img = t.widget<Image>(find.byType(Image));
      expect((img.image as AssetImage).assetName, FnBrand.wordmarkAsset);
      final s = t.getSize(find.byType(FnWordmark));
      expect(s.height, 33);
      expect(s.width / s.height, closeTo(FnBrand.wordmarkRatio, 0.01));
    });
  });

  group('#114 화면 배치 (워드마크 vs 심볼)', () {
    test('심볼 경로를 직접 쓰는 화면 코드가 남아 있지 않다', () {
      final leftovers = <String>[];
      for (final f in io.Directory('lib').listSync(recursive: true)) {
        if (f is! io.File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('fn_brand.dart')) continue;
        if (f.readAsStringSync().contains('assets/icon/app_icon.png')) {
          leftovers.add(f.path);
        }
      }
      expect(leftovers, isEmpty,
          reason: '심볼은 FnAppMark 로만 쓴다 (직접 경로 금지)');
    });

    test('스플래시/로그인에 Text(\'FlowNote\') 브랜드 표기가 남아 있지 않다', () {
      for (final p in [
        'lib/screens/ds/splash_ds_screen.dart',
        'lib/screens/login_screen.dart',
      ]) {
        final src = io.File(p).readAsStringSync();
        // 주석에 적힌 설명 문구까지 걸리면 안 되니 주석 줄은 뺀다.
        final live = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(live.contains("Text('FlowNote'"), isFalse,
            reason: '$p 의 브랜드 글자는 워드마크 그림으로 바뀌어야 한다');
        expect(src.contains('FnWordmark'), isTrue, reason: '$p 에 워드마크가 없다');
        expect(src.contains('FnAppMark'), isTrue, reason: '$p 에 심볼이 없다');
      }
    });
  });
}
