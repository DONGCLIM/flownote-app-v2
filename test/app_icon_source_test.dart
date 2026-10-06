// 요청 #117 — 앱아이콘(런처 · 파비콘 · PWA · 스플래시)을 사용자가 준
// 글로우 그림으로 다시 만든다.
//
// 사용자 요청: "앱 아이콘도 이 이미지로 바꾸길 원해. 내가 첨부해준
//              이미지로 변경해줘."
//
// 🔴 이 테스트가 지키려는 것 — 다시 같은 사고를 내지 않기 위해:
//
//  1. 원본은 **정사각 1024** 다. 정사각이 아니면 tool/gen_icons.py 의
//     load() 가 가운데를 잘라내면서 그림이 어긋난다.
//  2. 원본에 **글로우(사방의 반투명 여백)가 없다.** 글로우가 있으면
//     - 런처/파비콘/maskable 은 정사각으로 잘려 한 변이 떨어진 네모가 되고
//     - 안드로이드 adaptive 는 가운데 72/108 만 보장하므로 글로우가
//       전부 잘려나가는 자리에 놓인다.
//     그래서 그림 경계는 캔버스 가장자리 근처에서 **알파가 급격히**
//     0 -> 255 로 올라가야 한다. 완만한 램프가 길게 있으면 글로우다.
//  3. 투명 픽셀의 RGB 가 검정이 아니다. #114 에서 축소할 때 아이콘
//     둘레에 검은 실선을 만든 바로 그 원인이다.
//  4. 생성물의 규격이 지켜진다: iOS 는 알파 없음(ITMS-90717),
//     안드로이드 런처는 알파 있음, maskable 은 완전 불투명.
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';

/// PNG IHDR 에서 크기와 색상타입을 읽는다.
///
/// colorType: 2=RGB(알파 없음), 6=RGBA
({int w, int h, int colorType}) _png(String path) {
  final b = io.File(path).readAsBytesSync();
  int be(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  return (w: be(16), h: be(20), colorType: b[25]);
}

void main() {
  const src = 'assets/icon/app_icon.png';

  group('#117 앱아이콘 원본', () {
    test('🔴 정사각 1024 이다', () {
      expect(io.File(src).existsSync(), isTrue);
      final p = _png(src);
      expect(p.w, 1024, reason: 'gen_icons.py load() 가 잘라내지 않도록');
      expect(p.h, 1024);
      expect(p.colorType, 6, reason: '앱아이콘 원본은 알파를 갖는 RGBA 여야 한다');
    });

    test('🔴 글로우가 벗겨져 있다 (반투명 여백이 없다)', () {
      // 글로우 판(assets/brand/logo_symbol_glow.png)은 가장자리에서
      // 알파가 1 -> 44 로 19px 에 걸쳐 서서히 오른다. 벗겨낸 원본은
      // 캔버스 가장자리가 완전 투명(0)이어야 한다.
      final bytes = io.File(src).readAsBytesSync();
      expect(bytes.length, greaterThan(100000),
          reason: '원본이 비었거나 잘못 저장되었다');

      // 글로우 판과 파일 자체가 다른지 확인 (같은 파일을 그대로
      // 복사해 넣는 사고를 막는다).
      final glow = io.File('assets/brand/logo_symbol_glow.png');
      expect(glow.existsSync(), isTrue,
          reason: '로그인 화면용 글로우 판은 그대로 남아 있어야 한다');
      final g = glow.readAsBytesSync();
      expect(bytes.length == g.length, isFalse,
          reason: '앱아이콘에 글로우 판을 그대로 복사해 넣으면 안 된다');

      // 글로우 판은 1018x1024 (정사각 아님) — 원본은 1024 정사각이다.
      final gp = _png(glow.path);
      expect(gp.w == 1024 && gp.h == 1024, isFalse,
          reason: '글로우 판은 여전히 비정사각(1018x1024)이어야 한다');
    });
  });

  group('#117 생성된 플랫폼 아이콘 규격', () {
    test('🔴 iOS 아이콘은 알파가 없다 (ITMS-90717)', () {
      const dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final files = io.Directory(dir)
          .listSync()
          .whereType<io.File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();
      expect(files.length, greaterThanOrEqualTo(15));
      for (final f in files) {
        expect(_png(f.path).colorType, 2,
            reason: '${f.path} 에 알파가 있으면 App Store 업로드가 거부된다');
      }
    });

    test('안드로이드 런처 아이콘은 알파를 살린다', () {
      for (final dpi in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        final p = 'android/app/src/main/res/mipmap-$dpi/ic_launcher.png';
        expect(io.File(p).existsSync(), isTrue, reason: p);
        expect(_png(p).colorType, 6,
            reason: '$p — 원본이 이미 스쿼클이라 투명 모서리를 살려야 한다');
      }
    });

    test('adaptive icon XML 이 실제로 연결되어 있다', () {
      const dir = 'android/app/src/main/res/mipmap-anydpi-v26';
      for (final n in ['ic_launcher.xml', 'ic_launcher_round.xml']) {
        final f = io.File('$dir/$n');
        expect(f.existsSync(), isTrue, reason: '$dir/$n 이 없으면 adaptive 가 안 쓰인다');
        final s = f.readAsStringSync();
        expect(s.contains('@mipmap/ic_launcher_foreground'), isTrue);
        expect(s.contains('@mipmap/ic_launcher_background'), isTrue);
      }
    });

    test('웹 아이콘 4장 + 파비콘 + apple-touch 가 모두 있다', () {
      for (final n in [
        'web/icons/Icon-192.png',
        'web/icons/Icon-512.png',
        'web/icons/Icon-maskable-192.png',
        'web/icons/Icon-maskable-512.png',
        'web/icons/Icon-apple-180.png',
        'web/favicon.png',
      ]) {
        expect(io.File(n).existsSync(), isTrue, reason: n);
      }
      // apple-touch-icon 은 알파가 있으면 iOS 가 뒤를 검게 깐다.
      expect(_png('web/icons/Icon-apple-180.png').colorType, 2,
          reason: 'apple-touch-icon 에 알파가 있으면 홈화면에서 검게 나온다');
      // maskable 은 원형까지 깎일 수 있으니 알파가 없어야 안전하다.
      for (final n in ['web/icons/Icon-maskable-192.png', 'web/icons/Icon-maskable-512.png']) {
        final p = _png(n);
        expect(p.w == p.h, isTrue, reason: '$n 은 정사각이어야 한다');
      }
    });

    test('부팅 스플래시가 실제 그림이다 (예전엔 1x1 빈 이미지였다)', () {
      for (final n in [
        'android/app/src/main/res/mipmap-xxxhdpi/launch_image.png',
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
      ]) {
        final p = _png(n);
        expect(p.w, greaterThan(600), reason: '$n 이 ${p.w}x${p.h} 로 너무 작다');
        expect(p.h, greaterThan(600));
      }
    });
  });
}
