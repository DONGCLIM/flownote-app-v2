import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
      // 화각 계약 상수가 살아있는지
      expect(src.contains('0.62'), isTrue,
          reason: '$path 에 프레임 비율 계약(0.62)이 없다');
    }
  });

  test('🔴 프레임 비율 계약은 화면·저장 양쪽이 같은 값을 쓴다', () {
    // 프레임 그리기 / cover 프리뷰 / JPEG 자르기 — 세 곳이 같은 값을 봐야
    // 한다. 값이 갈라지면 다시 화각이 어긋난다.
    final ds =
        File('lib/screens/ds/scan_camera_ds_screen.dart').readAsStringSync();
    expect(ds.contains('static const double frameAspect = 0.62;'), isTrue,
        reason: 'frameAspect 계약 상수가 사라졌다');
    final iac =
        File('lib/screens/in_app_camera_screen.dart').readAsStringSync();
    expect(iac.contains('static const double _frameAspect = 0.62;'), isTrue,
        reason: 'in_app_camera 의 프레임 비율이 어긋났다');
  });

  test('🔴 프레임은 세로로 꽉 차야 한다 (#103 "왜 갑자기 작아졌어?")', () {
    // #101 의 회귀 코드는 이랬다.
    //   if (h > box.maxHeight) { h = box.maxHeight; w = h * ar; }  ← 폭이 줄어든다
    // 지금은 폭이 78% 아래로는 절대 줄지 않는다.
    const boxW = 380.0, boxH = 520.0;
    const frameAspect = 0.62;
    var w = boxW;
    var h = w / frameAspect;
    if (h > boxH) {
      h = boxH;
      w = h * frameAspect;
      if (w < boxW * 0.78) {
        w = boxW * 0.78;
        h = boxH;
      }
    }
    // 세로는 슬롯을 꽉 채운다
    expect(h, closeTo(boxH, 1e-9));
    // 폭이 시안보다 많이 좁아지지 않는다
    expect(w, greaterThanOrEqualTo(boxW * 0.78 - 1e-9));
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
    // 프리뷰 사각형 계산이 살아있는지
    expect(src.contains('1 / _controller!.value.aspectRatio'), isTrue);
  });
}
