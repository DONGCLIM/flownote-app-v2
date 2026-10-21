import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/services/receipt_image_editor.dart';

/// 🔴 #101 — 카메라 화각(FOV) 불일치 회귀 방지
///
/// 사장님 리포트: "라인에 맞추라고 해놓고 찍으면 초광각? 혹은 광각처럼
/// 물체가 내가 카메라로 찍는 순간보다 작게 나와."
///
/// 원인은 프리뷰가 `BoxFit.cover` 였다는 것이다. cover 는 프리뷰를 확대해서
/// 슬롯을 꽉 채우고 넘치는 부분을 잘라낸다. 그런데 저장은
/// `controller.takePicture()` 가 하고, 이 함수는 잘라낸 프리뷰가 아니라
/// **센서 프레임 전체**를 파일에 쓴다.
///
///   화면에서 본 것   = 센서 프레임의 일부 (확대된 중앙 영역)
///   파일에 저장된 것 = 센서 프레임 전체
///
/// 그래서 저장된 사진에는 화면에서 본 것보다 넓은 범위가 담기고, 같은
/// 영수증이 더 넓은 그림 안에 들어가니 작아 보였다. 카메라가 렌즈를 바꾼
/// 것이 아니라 우리가 화면에서 확대해 보여주고 있었을 뿐이다.
///
/// 게다가 점선 가이드 프레임은 슬롯 바깥 경계에 그려져서, 잘린 프리뷰와
/// 아무 관계가 없었다. 즉 "라인에 맞추세요" 라는 안내가 거짓이었다.
///
/// 실제 카메라 하드웨어는 테스트에서 열 수 없으니
///   (1) 새로 쓴 비율 계산이 센서 비율을 정확히 지키는지
///   (2) 소스에 `BoxFit.cover` 가 다시 들어오지 않는지
/// 두 가지를 잠근다.

/// 현재 구현과 동일한 contain 계산.
/// (`scan_camera_ds_screen.dart` / `in_app_camera_screen.dart` 의 `_preview`)
({double w, double h}) _contain(double boxW, double boxH, double ar) {
  var w = boxW;
  var h = w / ar;
  if (h > boxH) {
    h = boxH;
    w = h * ar;
  }
  return (w: w, h: h);
}

/// cover 가 프리뷰를 얼마나 확대했는지 (1.0 초과면 잘라낸 것이다)
double _coverScale(double boxW, double boxH, double ar) {
  final byWidth = boxW / (boxH * ar);
  return byWidth > 1 ? byWidth : 1 / byWidth;
}

void main() {
  group('🔴 #101 화각 — 프리뷰가 센서 비율을 그대로 지킨다', () {
    // 흔한 조합: 4:3 센서 → 세로 화면 비율 3/4, 슬롯 362x600
    const boxW = 362.0;
    const boxH = 600.0;
    const ar = 3 / 4;

    test('contain 결과의 비율이 센서 비율과 정확히 같다', () {
      final r = _contain(boxW, boxH, ar);
      expect(r.w / r.h, closeTo(ar, 1e-9),
          reason: '프리뷰 비율이 센서와 달라지면 본 것과 찍힌 것이 달라진다');
      expect(r.w, lessThanOrEqualTo(boxW + 1e-9));
      expect(r.h, lessThanOrEqualTo(boxH + 1e-9));
    });

    test('예전 cover 방식은 반드시 프레임 일부를 잘라냈다', () {
      // 이 값이 1보다 크다는 것이 "확대해서 잘라냈다" 는 증거다.
      expect(_coverScale(boxW, boxH, ar), greaterThan(1.0),
          reason: 'cover 가 확대·크롭을 하지 않았다면 화각 불일치도 없었다');
    });

    test('세로로 긴 슬롯은 폭 기준, 가로로 넓은 슬롯은 높이 기준으로 맞춘다', () {
      final tall = _contain(300, 900, ar);
      expect(tall.w, closeTo(300, 1e-9));
      expect(tall.h, closeTo(400, 1e-9));

      final wide = _contain(900, 300, ar);
      expect(wide.h, closeTo(300, 1e-9));
      expect(wide.w, closeTo(225, 1e-9));
    });

    test('16:9 센서에서도 비율이 지켜진다', () {
      const ar169 = 9 / 16;
      final r = _contain(boxW, boxH, ar169);
      expect(r.w / r.h, closeTo(ar169, 1e-9));
      expect(r.h, lessThanOrEqualTo(boxH + 1e-9));
    });
  });

  // 🔴 #103 에서 화각 계약이 바뀌었다. 기록을 남긴다.
  //
  // #101 은 "cover 금지" 를 못박았다. 이유는 정당했다 — cover 로 늘리면
  // 프리뷰가 잘려서 사장님이 프레임에 맞춘 것과 저장된 사진이 달라졌다
  // (초광각 문제). 그래서 프레임을 센서 비율(0.75)로 줄였다.
  //
  // 그런데 그게 #103 의 "왜 갑자기 작아졌어?" 다. 시안은 프레임이 세로로
  // 꽉 차야 한다(`flex: 1`, 비율 약 0.62).
  //
  // 두 요구를 동시에 만족시키는 방법은 하나뿐이다.
  //   프리뷰는 cover 로 프레임을 꽉 채우고,
  //   **찍은 JPEG 을 같은 비율로 잘라서** 저장한다.
  // 그래서 cover 는 이제 허용하되, **자르기가 반드시 함께 있어야 한다.**
  test('🔴 cover 로 채우면 찍은 사진도 같은 비율로 잘라야 한다', () {
    for (final path in const [
      'lib/screens/ds/scan_camera_ds_screen.dart',
      'lib/screens/in_app_camera_screen.dart',
    ]) {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: '$path 가 없다');
      final src = f.readAsStringSync();
      final code = f
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => !l.startsWith('//'))
          .join('\n');

      if (!code.contains('BoxFit.cover')) continue;

      // cover 를 쓴다면 자르기가 반드시 있어야 한다.
      expect(code.contains('_cropToFrame'), isTrue,
          reason: '$path 가 cover 로 프리뷰를 채우는데 _cropToFrame 이 없다 — '
              '프레임에 맞춘 것과 저장된 사진이 달라진다(초광각 문제 재발)');
      expect(code.contains('coverCropRect'), isTrue,
          reason: '$path 의 자르기가 프리뷰와 같은 계산(coverCropRect)을 써야 한다');
      // 잘린 사진이 프레임 밖으로 새지 않게 clip 이 있어야 한다.
      expect(code.contains('Clip.hardEdge'), isTrue,
          reason: '$path 의 cover 프리뷰에 clipBehavior 가 없다');
      // 가이드 비율 상수가 살아있는지
      expect(src.contains('0.62'), isTrue,
          reason: '$path 에 가이드 프레임 비율(0.62)이 없다');
    }
  });

  test('🔴 #148 프레임 비율은 어떤 슬롯에서도 정확히 frameAspect 다', () {
    // 🔴 예전에는 "폭이 슬롯의 78% 아래로 내려가면 78% 로 되돌린다"
    //    라는 보정이 있었다. 그게 걸리면 비율이 frameAspect 가 아니게
    //    돼서, 화면에서 본 사각형과 저장되는 사각형이 달라진다.
    //    (아이폰 SE 슬롯에서 0.62 대신 0.668 로 계산됐다)
    //    보정을 지웠으니 어떤 슬롯에서도 비율이 정확해야 한다.
    const frameAspect = 0.75;
    const slots = [
      (380.0, 520.0), // 세로가 모자란 슬롯
      (335.0, 391.0), // 아이폰 SE
      (350.0, 900.0), // 세로가 남는 슬롯
      (280.0, 292.0), // 아주 작은 슬롯
      (372.0, 496.0), // 갤럭시
    ];
    for (final (boxW, boxH) in slots) {
      var w = boxW;
      var h = w / frameAspect;
      if (h > boxH) {
        h = boxH;
        w = h * frameAspect;
      }
      expect(w / h, closeTo(frameAspect, 1e-9),
          reason: '슬롯 $boxW x $boxH 에서 비율이 ${w / h} 가 됐다 — '
              '화면과 저장 사진이 달라진다');
      expect(w, lessThanOrEqualTo(boxW + 1e-9));
      expect(h, lessThanOrEqualTo(boxH + 1e-9));
      // 슬롯 한 변은 꽉 채운다 (작아 보이면 안 된다)
      final fills = (w - boxW).abs() < 1e-9 || (h - boxH).abs() < 1e-9;
      expect(fills, isTrue, reason: '슬롯 $boxW x $boxH 를 꽉 채우지 못했다');
    }
  });

  test('🔴 #148 보정 상수 0.78 이 되살아나면 안 된다', () {
    for (final path in const [
      'lib/screens/ds/scan_camera_ds_screen.dart',
      'lib/screens/in_app_camera_screen.dart',
    ]) {
      final code = File(path)
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => !l.startsWith('//') && !l.startsWith('///'))
          .join('\n');
      expect(code.contains('0.78'), isFalse,
          reason: '$path 에 폭 78% 보정이 되살아났다 — 프레임 비율이 깨진다');
    }
  });

  test('🔴 프레임 가이드는 프리뷰 사각형에만 그린다', () {
    // 예전에는 build() 쪽 Expanded 슬롯 경계에 CustomPaint 를 뒀다.
    // 지금은 `_framed()` 헬퍼 하나로 모아서, 프리뷰 사각형에만 씌운다.
    final src =
        File('lib/screens/ds/scan_camera_ds_screen.dart').readAsStringSync();
    expect(src.contains('Widget _framed('), isTrue,
        reason: '_framed 헬퍼가 사라지면 가이드가 다시 어긋날 수 있다');
    // 시안 요소들이 살아있는지 (모서리 브래킷 / 스캔 라인)
    expect(src.contains('_Bracket'), isTrue, reason: '모서리 브래킷이 사라졌다');
    expect(src.contains('0.46'), isTrue, reason: '스캔 라인 위치(46%)가 사라졌다');
    // 🔴 좌상단 안내문은 브래킷(x 10~44)을 피해야 한다.
    //    left: 18 이면 브래킷 세로선에 닿는다 — E2E 스크린샷으로 확인했다.
    expect(src.contains('left: 52,'), isTrue,
        reason: '좌상단 안내문 여백이 브래킷을 침범한다');
    // 프리뷰 비율 계산이 살아있는지(#150 은 _liveAspect getter 로 옮겼다)
    expect(src.contains('_liveAspect'), isTrue,
        reason: '프리뷰 비율 계산이 사라졌다');
  });

  // ─────────────────────────────────────────────────────────────
  // 🔴 #105 "찍을 때랑 찍고나서 배율이 달라진다" 회귀 방어
  //
  // 원인: 화각이 어긋나는 지점이 두 곳인데 한 곳만 계산했다.
  //   ① 촬영본 → 프리뷰 표면 : 카메라 플러그인이 잘라준다
  //        (안드로이드 ResolutionPreset.high 는 프리뷰를 16:9 로 요청,
  //         사진은 4:3 으로 찍힐 수 있다)
  //   ② 프리뷰 표면 → 화면 프레임 : 위젯의 BoxFit.cover 가 잘라낸다
  // 예전 코드는 ②만 계산해서 실제 상황에서 가로 화각이 1.1022배 어긋났다.
  // ─────────────────────────────────────────────────────────────

  test('🔴 프리뷰가 16:9, 사진이 4:3 일 때 화면과 저장이 같아야 한다', () {
    const frame = 0.62;
    const imgW = 3000, imgH = 4000; // 4:3 세로 → 0.75
    const previewAspect = 720 / 1280; // 16:9 세로 → 0.5625

    final rect = ReceiptImageEditor.coverCropRect(
      imageWidth: imgW,
      imageHeight: imgH,
      previewAspect: frame,
      cameraAspect: previewAspect,
    );

    // 화면이 실제로 보여준 화각:
    //   프리뷰 표면은 촬영본 가로의 (0.5625/0.75)=75% 만 담고 있고,
    //   거기서 cover 가 세로를 (0.5625/0.62)=90.7% 로 잘라 보여줬다.
    expect(rect.width, closeTo(0.75, 1e-9),
        reason: '가로는 촬영본의 75% 여야 한다 (프리뷰가 이미 잘라 준 몫)');
    expect(rect.height, closeTo(0.5625 / 0.62, 1e-9),
        reason: '세로는 cover 가 잘라낸 몫이어야 한다');

    // 잘라낸 결과 비율이 화면 프레임과 정확히 같아야 한다.
    final outAspect = (imgW * rect.width) / (imgH * rect.height);
    expect(outAspect, closeTo(frame, 1e-9),
        reason: '저장 비율이 화면 프레임(0.62)과 달라지면 배율이 어긋난다');

    // 중앙 정렬이어야 한다.
    expect(rect.left, closeTo((1 - rect.width) / 2, 1e-9));
    expect(rect.top, closeTo((1 - rect.height) / 2, 1e-9));
  });

  test('🔴 예전 계산은 이 상황에서 1.10배 어긋났다 (되돌리지 말 것)', () {
    // 예전 코드: cameraAspect 를 안 넘겼다 = 프리뷰와 촬영본 비율이 같다고 가정
    final wrong = ReceiptImageEditor.coverCropRect(
      imageWidth: 3000,
      imageHeight: 4000,
      previewAspect: 0.62,
    );
    final right = ReceiptImageEditor.coverCropRect(
      imageWidth: 3000,
      imageHeight: 4000,
      previewAspect: 0.62,
      cameraAspect: 720 / 1280,
    );
    expect(wrong.width, closeTo(0.62 / 0.75, 1e-9)); // 0.8267
    expect(right.width, closeTo(0.75, 1e-9));
    expect(wrong.width / right.width, closeTo(1.1022, 1e-3),
        reason: '이 차이가 사장님이 본 "약간 확대돼서 찍힌다" 였다');
  });

  test('🔴 프리뷰와 촬영본 비율이 같으면 예전 계산과 결과가 같다', () {
    final a = ReceiptImageEditor.coverCropRect(
      imageWidth: 3000, imageHeight: 4000, previewAspect: 0.62);
    final b = ReceiptImageEditor.coverCropRect(
      imageWidth: 3000, imageHeight: 4000, previewAspect: 0.62,
      cameraAspect: 0.75);
    expect(b.width, closeTo(a.width, 1e-9));
    expect(b.height, closeTo(a.height, 1e-9));
  });

  test('🔴 어떤 프리뷰/촬영본 조합에서도 저장 비율은 프레임 비율이 된다', () {
    const frame = 0.62;
    const combos = [
      (3000, 4000, 0.5625), // 4:3 사진 + 16:9 프리뷰
      (3000, 4000, 0.75), // 4:3 + 4:3
      (1080, 1920, 0.75), // 16:9 사진 + 4:3 프리뷰
      (1080, 1920, 0.5625), // 16:9 + 16:9
      (3000, 4000, 0.5), // 아주 긴 프리뷰
      (4000, 3000, 0.75), // 가로 사진(방향 처리 실패 대비)
    ];
    for (final (w, h, cam) in combos) {
      final r = ReceiptImageEditor.coverCropRect(
        imageWidth: w, imageHeight: h, previewAspect: frame, cameraAspect: cam);
      final out = (w * r.width) / (h * r.height);
      expect(out, closeTo(frame, 1e-9),
          reason: '$w x $h / 프리뷰 $cam 에서 저장 비율이 $out 이 됐다');
      expect(r.width, inInclusiveRange(0.0, 1.0));
      expect(r.height, inInclusiveRange(0.0, 1.0));
    }
  });

  test('🔴 두 카메라 화면이 프리뷰 비율(cameraAspect)을 반드시 넘긴다', () {
    for (final path in const [
      'lib/screens/ds/scan_camera_ds_screen.dart',
      'lib/screens/in_app_camera_screen.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('cameraAspect: cameraAspect,'), isTrue,
          reason: '$path 가 coverCropRect 에 프리뷰 비율을 안 넘긴다 — '
              '찍을 때와 저장될 때 배율이 어긋난다(#105 재발)');
      expect(src.contains('1 / c.value.aspectRatio'), isTrue,
          reason: '$path 가 컨트롤러의 프리뷰 비율을 읽지 않는다');
    }
  });

  test('🔴 리사이즈는 1200px 자동이다 — 고르는 UI 가 없어야 한다', () {
    final eng = File('lib/services/receipt_image_editor.dart').readAsStringSync();
    expect(eng.contains('static const int defaultMaxDimension = 1200;'), isTrue,
        reason: '자동 저장 크기 기준이 1200px 이어야 한다');
    expect(eng.contains('resizeChoices'), isFalse,
        reason: '리사이즈 선택 목록이 되살아났다');

    final crop = File('lib/screens/ds/receipt_crop_ds_screen.dart').readAsStringSync();
    for (final gone in const ['_resizeRow', 'Widget _chip(', "'원본'", "'높음'", "'보통'", "'작게'"]) {
      expect(crop.contains(gone), isFalse, reason: '크롭 화면에 $gone 이 남았다');
    }
    expect(crop.contains('_maxDim = ReceiptImageEditor.defaultMaxDimension'), isTrue,
        reason: '크롭 화면이 고정 저장 크기를 쓰지 않는다');
  });

  // ────────────────────────────────────────────────────────────────
  // #106 촬영 화질 · 화각 회귀 방지
  // ────────────────────────────────────────────────────────────────

  test('🔴 두 카메라 화면은 CameraQuality.open 으로만 카메라를 연다', () {
    for (final path in const [
      'lib/screens/ds/scan_camera_ds_screen.dart',
      'lib/screens/in_app_camera_screen.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('CameraQuality.open('), isTrue,
          reason: '$path 가 CameraQuality.open 을 쓰지 않는다');
      expect(src.contains('CameraController('), isFalse,
          reason: '$path 에서 CameraController 를 직접 만들면 '
              '프리셋이 화면마다 갈라진다(한쪽만 고치는 사고의 원인)');
      expect(src.contains('ResolutionPreset.high,'), isFalse,
          reason: '$path 에 ResolutionPreset.high 가 되살아났다. '
              '센서 4:3 을 16:9 로 잘라서 가로 25% 를 버리고 '
              '해상도도 1280x720 으로 묶는다');
    }
  });

  test('🔴 #152 CameraQuality 는 veryHigh(16:9) 를 첫 후보로 둔다', () {
    // 🔴 #152 에서 방침이 바뀌었다.
    //    예전(#105)에는 "max 가 센서 비율(4:3)을 그대로 쓰니 첫 후보"
    //    였다. 그런데 4:3 은 휴대폰 화면보다 납작해서, 확대 없이는
    //    세로를 67% 밖에 못 채운다(사장님: "화면에 꽉 차게").
    //    16:9 는 4:3 의 위아래만 잘라낸 것이라 **가로 화각이 같다**
    //    = 폰을 드는 거리가 같다 = 확대가 아니다. 그래서 16:9 를 쓴다.
    final src = File('lib/services/camera_quality.dart').readAsStringSync();

    final i = src.indexOf('presets = <ResolutionPreset>[');
    expect(i, greaterThan(0), reason: 'presets 목록이 없어졌다');
    final list = src.substring(i, src.indexOf('];', i));

    final max = list.indexOf('ResolutionPreset.max');
    final very = list.indexOf('ResolutionPreset.veryHigh');
    final high = list.indexOf('ResolutionPreset.high');

    expect(very, greaterThanOrEqualTo(0), reason: 'veryHigh 가 목록에 없다');
    expect(max, greaterThanOrEqualTo(0),
        reason: 'max 안전망이 사라졌다 — 16:9 를 못 여는 기기가 있다');
    expect(very, lessThan(high),
        reason: 'veryHigh(1920x1080) 가 high(1280x720) 보다 앞이어야 한다. '
            'high 는 짧은 변 720 이 저장 상한 1200 보다 작아 글씨가 뭉갠다');
    expect(very, lessThan(max),
        reason: 'max 가 먼저면 기기가 4:3 을 줘서 화면이 다시 납작해진다');

    // 오래된 기기에서 첫 후보가 실패해도 화면이 죽지 않아야 한다.
    expect(src.contains('await controller.dispose()'), isTrue,
        reason: '실패한 컨트롤러를 정리하지 않으면 카메라가 잠긴다');
  });

  test('🔴 리사이즈는 cubic 이어야 한다 (기본값 nearest 는 글자를 깎는다)', () {
    final src = File('lib/services/receipt_image_editor.dart').readAsStringSync();

    // copyResize 호출 개수 = cubic 지정 개수. 하나라도 빠지면 실패.
    final calls = 'img.copyResize('.allMatches(src).length;
    final cubic = 'img.Interpolation.cubic'.allMatches(src).length;
    expect(calls, greaterThan(0), reason: 'copyResize 호출이 사라졌다');
    expect(cubic, calls,
        reason: 'copyResize $calls 개 중 cubic 지정은 $cubic 개다. '
            'interpolation 을 안 적으면 image 패키지 기본값인 '
            'Interpolation.nearest 가 쓰여서 얇은 글자 획이 사라진다');

    // #105 에서 사장님이 못박은 값. 조용히 올리지 말 것.
    expect(src.contains('static const int defaultMaxDimension = 1200;'), isTrue,
        reason: '저장 상한 1200px 은 #105 에서 정한 값이다');
  });

  // ─────────────────────────────────────────────────────────────
  // 🔴 #151 "가이드 안에 들어오지만 너무 확대돼서 또 폰을 눈까지
  //          올려야 한다. 편한 자세에서 찍게 해달라"
  //
  // #150 은 "세로 우선" 이라며 세로를 슬롯에 꽉 채우고 넘치는 좌우를
  // 화면 밖으로 버렸다. 4:3 기기에서 좌우 18.6% 를 잘라냈는데,
  // **자르는 것이 곧 확대다** (배율 1.228).
  //
  // 네 번의 실패를 관통하는 교훈:
  //   프레임을 크게 보이려고 화각을 깎으면 그게 바로 확대다.
  //   #147 cover(21%) / #148 cover(33%) / #150 좌우잘라냄(23%)
  //
  // #151: 센서 화면을 통째로 보여준다(contain, 화각 100%, 배율 1.0).
  //       프레임 크기는 **여백을 줄여서** 확보한다.
  // ─────────────────────────────────────────────────────────────

  /// #151 배치. 센서 전체가 슬롯 안에 들어가도록만 한다(자르지 않음).
  ({double pw, double ph}) layout151(double boxW, double boxH, double ar) {
    var pw = boxW;
    var ph = pw / ar;
    if (ph > boxH) {
      ph = boxH;
      pw = ph * ar;
    }
    return (pw: pw, ph: ph);
  }

  test('🔴 #151 센서 화각을 100% 보여준다 — 한 픽셀도 자르지 않는다', () {
    const boxW = 412.0, boxH = 669.0;
    for (final ar in const [0.75, 0.6667, 0.5625, 0.4615]) {
      final r = layout151(boxW, boxH, ar);
      // 프리뷰가 슬롯을 넘으면 그만큼 화면 밖으로 잘린다 = 확대.
      expect(r.pw, lessThanOrEqualTo(boxW + 1e-6),
          reason: '센서 $ar 에서 프리뷰 폭 ${r.pw} 가 슬롯($boxW)을 넘었다 — '
              '좌우가 잘리고 그만큼 확대돼 보인다');
      expect(r.ph, lessThanOrEqualTo(boxH + 1e-6),
          reason: '센서 $ar 에서 프리뷰 높이 ${r.ph} 가 슬롯($boxH)을 넘었다');
      // 비율은 센서 그대로 (찌그러지지 않는다)
      expect(r.pw / r.ph, closeTo(ar, 1e-9));
    }
  });

  test('🔴 #151 #150 의 세로우선은 4:3 에서 1.23배 확대였다 (되돌리지 말 것)', () {
    const boxW = 372.0, boxH = 609.0;
    // #150 방식: 세로를 꽉 채우고 폭이 넘치게 둔다.
    const ar = 0.75;
    final ph = boxH;
    final pw = ph * ar; // 456.75
    expect(pw, greaterThan(boxW)); // 슬롯 폭을 넘는다
    final zoom = pw / boxW;
    expect(zoom, closeTo(1.2278, 1e-3),
        reason: '이 1.23배가 사장님이 느낀 "또 확대됐다" 였다');
    expect(boxW / pw, closeTo(0.8145, 1e-3),
        reason: '가로 화각이 81.4% 로 줄었다');
  });

  test('🔴 #151 실제 코드가 자르지 않는다 (ClipRect/OverflowBox 금지)', () {
    for (final path in const [
      'lib/screens/ds/scan_camera_ds_screen.dart',
      'lib/screens/in_app_camera_screen.dart',
    ]) {
      final code = File(path)
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => !l.startsWith('//') && !l.startsWith('///'))
          .join('\n');

      // 프리뷰를 늘리는 cover 금지
      expect(code.contains('BoxFit.cover'), isFalse,
          reason: '$path 에 BoxFit.cover 가 되살아났다 — 프리뷰가 확대된다');

      // 슬롯 밖으로 넘겨 자르는 OverflowBox 금지
      expect(code.contains('OverflowBox'), isFalse,
          reason: '$path 가 OverflowBox 로 화면 밖까지 그린다 — '
              '잘리는 만큼 확대돼 보인다(#150 재발)');

      // 가로 기준으로 담고(contain), 넘치면 줄인다
      final containsW =
          RegExp(r'var pw = (?:box|constraints)\.maxWidth;').hasMatch(code);
      final containsH = RegExp(r'var ph = pw / ar;').hasMatch(code);
      expect(containsW && containsH, isTrue,
          reason: '$path 가 contain 배치가 아니다 — 센서 일부가 잘릴 수 있다');

      // 세로 우선(= 좌우를 버리는) 패턴이 없어야 한다
      final heightFirst =
          RegExp(r'var ph = (?:box|constraints)\.maxHeight;').hasMatch(code) &&
              RegExp(r'var pw = ph \* ar;').hasMatch(code);
      expect(heightFirst, isFalse,
          reason: '$path 에 세로 우선 배치가 되살아났다 — 좌우가 잘려 확대된다');
    }
  });

  test('🔴 #152 센서에 16:9 를 먼저 요청한다 (꽉 찬 화면 + 확대 0)', () {
    // 휴대폰 화면(0.45)은 4:3(0.75)보다 훨씬 세로로 길다.
    // 4:3 로는 확대 없이 세로를 67% 밖에 못 채운다.
    // 16:9 는 4:3 의 위아래를 잘라낸 것이라 **가로 화각이 같다**
    // = 폰을 드는 거리가 같다 = 확대가 아니다.
    final src = File('lib/services/camera_quality.dart').readAsStringSync();
    final code = src
        .split('\n')
        .map((l) => l.trim())
        .where((l) => !l.startsWith('//') && !l.startsWith('///'))
        .join('\n');

    final iVeryHigh = code.indexOf('ResolutionPreset.veryHigh');
    final iMax = code.indexOf('ResolutionPreset.max');
    expect(iVeryHigh, greaterThanOrEqualTo(0),
        reason: 'veryHigh(16:9) 후보가 사라졌다');
    expect(iMax, greaterThanOrEqualTo(0), reason: 'max 안전망이 사라졌다');
    expect(iVeryHigh, lessThan(iMax),
        reason: 'max 가 먼저면 기기가 4:3 을 줘서 화면이 다시 납작해진다');
  });

  test('🔴 #152 16:9 는 가로 화각을 깎지 않는다 (= 확대 아님)', () {
    // 같은 가로를 유지할 때 16:9 는 4:3 의 위아래만 잘라낸다.
    const fourThree = 3 / 4; // 0.75
    const sixteenNine = 9 / 16; // 0.5625

    // 세로 화각 비율 = 75%  (위아래 25% 잘림)
    expect(sixteenNine / fourThree, closeTo(0.75, 1e-9),
        reason: '16:9 의 세로 화각은 4:3 의 75% 다');

    // 🔴 가로는 그대로이므로 피사체까지의 거리가 같다.
    //    영수증은 세로로 길어서 가로 폭이 담기는지가 거리를 결정한다.
    const screenW = 412.0, usableH = 825.0;
    for (final (name, ar, fill) in const [
      ('4:3', 0.75, 0.666),
      ('16:9', 0.5625, 0.888),
    ]) {
      final pw = screenW;
      final ph = pw / ar;
      // 어느 쪽도 가로를 자르지 않는다 (확대 0)
      expect(pw, closeTo(screenW, 1e-9),
          reason: '$name 에서 가로가 깎였다 — 그러면 확대다');
      expect(ph / usableH, closeTo(fill, 0.01),
          reason: '$name 의 세로 채움이 예상과 다르다');
    }
  });

  test('🔴 #152 컨트롤을 영상 위에 겹쳐 세로 공간을 영상에 준다', () {
    final ds =
        File('lib/screens/ds/scan_camera_ds_screen.dart').readAsStringSync();
    final code = ds
        .split('\n')
        .map((l) => l.trim())
        .where((l) => !l.startsWith('//') && !l.startsWith('///'))
        .join('\n');

    // 영상이 화면 전체를 슬롯으로 받아야 한다.
    expect(code.contains('Positioned.fill(child: _previewSlot())'), isTrue,
        reason: '영상이 화면 전체를 쓰지 않는다 — Column 으로 되돌아가면 '
            '뱃지/셔터가 영상 공간을 깎아 다시 납작해진다');

    // 셔터가 영상 위에 떠 있어야 한다.
    expect(RegExp(r'bottom: 24,\s*child: _shutterRow\(\),').hasMatch(code),
        isTrue,
        reason: '셔터가 영상 위에 겹쳐 있지 않다');
  });

  test('🔴 #152 저장 상한(1200px)보다 큰 해상도를 받는다', () {
    // veryHigh = 1920x1080. 상한 1200 보다 크므로 글씨가 뭉개지지 않는다.
    // (예전 high = 1280x720 은 720 이 상한보다 작아 문제였다)
    const veryHighShortSide = 1080;
    const highShortSide = 720;
    final src =
        File('lib/services/receipt_image_editor.dart').readAsStringSync();
    expect(src.contains('static const int defaultMaxDimension = 1200;'), isTrue,
        reason: '저장 상한 1200px 은 #105 에서 정한 값이다');
    expect(veryHighShortSide, lessThan(1200),
        reason: '짧은 변은 상한보다 작은 게 정상(긴 변 1920 이 상한을 넘는다)');
    expect(highShortSide, lessThan(veryHighShortSide),
        reason: 'high 로 떨어지면 해상도가 더 낮아진다');
  });

  test('🔴 #151 저장은 화면에 보인 영역과 같다', () {
    for (final path in const [
      'lib/screens/ds/scan_camera_ds_screen.dart',
      'lib/screens/in_app_camera_screen.dart',
    ]) {
      final code = File(path)
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => !l.startsWith('//') && !l.startsWith('///'))
          .join('\n');
      expect(code.contains('_shownAspect'), isTrue,
          reason: '$path 가 보이는 영역을 기록하지 않는다');
      // 가이드 비율로 자르면 영수증이 가이드를 넘겼을 때 글자가 날아간다.
      expect(RegExp(r'previewAspect: _?frameAspect').hasMatch(code), isFalse,
          reason: '$path 가 가이드 비율로 사진을 자른다');
    }
  });

  test('🔴 #151 contain 이면 저장 때 아무것도 안 깎인다', () {
    // 화면에 센서 전체가 보였으니 저장본도 전체여야 한다.
    for (final (w, h, cam) in const [
      (3000, 4000, 0.75),
      (1080, 1920, 0.5625),
      (1440, 3120, 0.4615),
    ]) {
      final r = ReceiptImageEditor.coverCropRect(
        imageWidth: w,
        imageHeight: h,
        previewAspect: cam, // contain 이라 보인 비율 == 센서 비율
        cameraAspect: cam,
      );
      expect(r.isFull, isTrue,
          reason: '$w x $h / 센서 $cam 인데 ${r.width} x ${r.height} 로 잘렸다');
    }
  });

  test('🔴 #151 가이드는 세로로 긴 영수증 모양을 유지한다', () {
    final ds =
        File('lib/screens/ds/scan_camera_ds_screen.dart').readAsStringSync();
    final iac =
        File('lib/screens/in_app_camera_screen.dart').readAsStringSync();
    expect(ds.contains('static const double frameAspect = 0.62;'), isTrue);
    expect(iac.contains('static const double _frameAspect = 0.62;'), isTrue);
    expect(0.62, lessThan(1.0), reason: '세로가 가로보다 길어야 영수증 모양이다');
  });

  // ─────────────────────────────────────────────────────────────
  // 🔴 #154 "프레임이 가로로 나온다"
  //
  // camera 패키지의 정의:
  //   double get aspectRatio => previewSize!.width / previewSize!.height;
  //
  // previewSize 는 기기/플러그인에 따라 가로형으로도 세로형으로도 온다.
  // 내 예전 코드 `1 / aspectRatio` 는 "항상 가로형" 이라는 검증 안 된
  // 가정이었고, 세로형으로 오는 기기에서 비율이 뒤집혔다.
  //
  //   previewSize 1920x1080 -> aspectRatio 1.778 -> 1/a = 0.562  세로 ✅
  //   previewSize 1080x1920 -> aspectRatio 0.562 -> 1/a = 1.778  가로 ❌
  //
  // 고침: 짧은변/긴변 으로 정규화해 방향에 의존하지 않게 한다.
  // ─────────────────────────────────────────────────────────────

  /// #154 의 정규화를 그대로 재현한다.
  double liveAspect(double w, double h) {
    final shortSide = w < h ? w : h;
    final longSide = w < h ? h : w;
    return shortSide / longSide;
  }

  test('🔴 #154 previewSize 방향이 어느 쪽이든 세로로 긴 비율이 나온다', () {
    // 같은 센서를 가로형/세로형으로 보고해도 결과가 같아야 한다.
    expect(liveAspect(1920, 1080), closeTo(0.5625, 1e-9));
    expect(liveAspect(1080, 1920), closeTo(0.5625, 1e-9));
    expect(liveAspect(4000, 3000), closeTo(0.75, 1e-9));
    expect(liveAspect(3000, 4000), closeTo(0.75, 1e-9));

    // 전부 1 보다 작아야 한다 = 세로로 길다.
    for (final (w, h) in const [
      (1920.0, 1080.0),
      (1080.0, 1920.0),
      (4000.0, 3000.0),
      (3000.0, 4000.0),
    ]) {
      expect(liveAspect(w, h), lessThan(1.0),
          reason: '$w x $h 에서 비율이 1 이상이면 프레임이 가로로 눕는다');
    }
  });

  test('🔴 #154 예전 계산은 세로형 입력에서 가로로 뒤집혔다 (되돌리지 말 것)', () {
    // 되돌렸을 때 무슨 일이 벌어지는지 숫자로 박아 둔다.
    double old(double w, double h) => 1 / (w / h);
    expect(old(1920, 1080), closeTo(0.5625, 1e-9)); // 가로형 입력 -> 정상
    expect(old(1080, 1920), closeTo(1.7778, 1e-3)); // 세로형 입력 -> 가로로 누움
    expect(old(1080, 1920), greaterThan(1.0),
        reason: '이 1.78 이 사장님이 본 가로 프레임이었다');
  });

  test('🔴 #154 두 카메라 화면이 방향에 의존하지 않게 계산한다', () {
    for (final path in const [
      'lib/screens/ds/scan_camera_ds_screen.dart',
      'lib/screens/in_app_camera_screen.dart',
    ]) {
      final code = File(path)
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => !l.startsWith('//') && !l.startsWith('///'))
          .join('\n');

      // 짧은변/긴변 정규화가 있어야 한다.
      expect(code.contains('return shortSide / longSide;'), isTrue,
          reason: '$path 가 세로 기준으로 정규화하지 않는다 — '
              'previewSize 가 세로형인 기기에서 프레임이 가로로 눕는다');

      // 방향 가정에 기대는 예전 식이 남아 있으면 안 된다.
      expect(code.contains('1 / a;'), isFalse,
          reason: '$path 에 방향 뒤집힘 버그가 되살아났다');
      expect(code.contains('1 / c.value.aspectRatio'), isFalse,
          reason: '$path 의 자르기가 방향 가정에 기대고 있다');
    }
  });

  test('🔴 #154 어느 방향으로 와도 화면 폭을 꽉 채운다 (확대 0)', () {
    // 세로로 긴 비율이므로 폭 기준으로 담으면 화면 폭을 꽉 쓴다.
    const screenW = 412.0, usableH = 825.0;
    for (final (w, h) in const [(1920.0, 1080.0), (1080.0, 1920.0)]) {
      final ar = liveAspect(w, h);
      var pw = screenW;
      var ph = pw / ar;
      if (ph > usableH) {
        ph = usableH;
        pw = ph * ar;
      }
      // 가로를 자르지 않으므로 확대가 없다.
      expect(pw, closeTo(screenW, 1e-6),
          reason: '\$w x \$h 에서 폭이 \$pw 로 깎였다 — 그러면 확대다');
      // 세로는 화면의 80% 이상 채운다.
      expect(ph / usableH, greaterThan(0.8),
          reason: '$w x $h 에서 세로를 ${(ph / usableH * 100).round()}% 밖에 못 채웠다');
    }
  });

  // ───────────────────────────────────────────────────────────────────
  // 🔴 #154-b  플러그인 CameraPreview 내부의 같은 버그를 무력화해 둔다
  //
  // `camera-0.11.1/lib/src/camera_preview.dart:28-31` 에는 우리가 #154 에서
  // 고친 것과 **똑같은 방향 뒤집힘 버그**가 들어 있다.
  //
  //   return AspectRatio(
  //     aspectRatio: _isLandscape()
  //         ? controller.value.aspectRatio
  //         : (1 / controller.value.aspectRatio),   // ← 세로형 previewSize 에서 1.778
  //
  // 즉 우리 쪽 `_liveAspect` 만 고쳐도, CameraPreview 가 스스로 가로 비율을
  // 적용해 버리면 프레임이 다시 눕는다.
  //
  // 다행히 `RenderAspectRatio._applyAspectRatio` 는 이렇게 시작한다
  // (`flutter/lib/src/rendering/proxy_box.dart`):
  //
  //   if (constraints.isTight) {
  //     return constraints.smallest;     // ← aspectRatio 를 통째로 무시
  //   }
  //
  // 그래서 CameraPreview 에게 **타이트한 제약**을 주면 내부 AspectRatio 가
  // 무력화되고, 우리가 계산한 pw x ph 가 그대로 쓰인다.
  //
  // ⚠️ 아래 래핑을 느슨하게(예: `Align`, `Center`, 제약 없는 `Column` 자식)
  //    바꾸면 플러그인의 1/a 가 되살아나 프레임이 가로로 눕는다.
  // ───────────────────────────────────────────────────────────────────

  test('🔴 #154-b 타이트 제약이면 AspectRatio 는 무시된다 (플러그인 1/a 무력화 근거)',
      () {
    final f = File('/home/user/flutter/packages/flutter/lib/src/'
        'rendering/proxy_box.dart');
    if (!f.existsSync()) return; // SDK 경로가 다른 환경에서는 건너뛴다
    final code = f.readAsStringSync();
    final i = code.indexOf('Size _applyAspectRatio(');
    expect(i, greaterThan(0), reason: 'RenderAspectRatio 구현을 못 찾았다');
    final body = code.substring(i, i + 1200);
    expect(body.contains('constraints.isTight'), isTrue,
        reason: 'AspectRatio 가 더이상 타이트 제약을 그냥 통과시키지 않는다 — '
            'CameraPreview 래핑 전략을 다시 검토해야 한다');
    expect(body.contains('return constraints.smallest;'), isTrue,
        reason: '타이트 제약에서 aspectRatio 를 무시한다는 보장이 사라졌다');
  });

  test('🔴 #154-b 플러그인 CameraPreview 에 방향 뒤집힘 식이 실제로 들어 있다', () {
    final dirs = Directory('/home/user/.pub-cache/hosted/pub.dev')
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.split('/').last.startsWith('camera-'))
        .toList();
    if (dirs.isEmpty) return; // pub-cache 가 없는 환경에서는 건너뛴다
    final f = File('${dirs.first.path}/lib/src/camera_preview.dart');
    if (!f.existsSync()) return;
    final code = f.readAsStringSync();
    // 이 식이 사라졌다면(플러그인이 고쳐졌다면) 우리 래핑 주석을 갱신해야 한다.
    expect(code.contains('1 / controller.value.aspectRatio'), isTrue,
        reason: '플러그인이 방향 버그를 고쳤다 — 우리 쪽 주석/래핑을 재검토할 것');
  });

  test('🔴 #154-b 두 카메라 화면 모두 CameraPreview 를 타이트하게 감싼다', () {
    // scan 쪽: SizedBox.expand 가 자식에게 타이트 제약을 준다.
    final scan = File('lib/screens/ds/scan_camera_ds_screen.dart')
        .readAsStringSync();
    expect(
        RegExp(r'SizedBox\.expand\(\s*child:\s*CameraPreview\(')
            .hasMatch(scan),
        isTrue,
        reason: 'scan 화면이 CameraPreview 를 느슨하게 감쌌다 — '
            '플러그인의 1/a 가 되살아나 프레임이 가로로 눕는다');

    // in_app 쪽: SizedBox(width/height) -> Stack(fit: StackFit.expand) 체인.
    final inApp =
        File('lib/screens/in_app_camera_screen.dart').readAsStringSync();
    final j = inApp.indexOf('CameraPreview(_controller!)');
    expect(j, greaterThan(0), reason: 'in_app 화면의 CameraPreview 를 못 찾았다');
    final before = inApp.substring(0, j);
    expect(before.contains('fit: StackFit.expand'), isTrue,
        reason: 'in_app 화면의 CameraPreview 상위에 타이트 제약이 사라졌다');
    expect(RegExp(r'width:\s*pw,\s*\n\s*height:\s*ph,').hasMatch(before),
        isTrue,
        reason: 'in_app 화면이 계산한 pw x ph 를 더이상 고정하지 않는다');
  });
}
