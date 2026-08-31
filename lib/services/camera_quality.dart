import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// 촬영 화질과 화각을 정하는 **단 하나의 자리**.
///
/// ## 왜 따로 뺐나
///
/// 예전에는 두 카메라 화면이 각자 `ResolutionPreset.high` 를 적어 뒀다.
/// 그래서 한쪽만 고치면 다른 쪽은 그대로 남는 사고가 반복됐다.
/// 이제 두 화면 모두 [open] 만 부른다.
///
/// ## `ResolutionPreset.high` 가 왜 문제였나 (직접 확인한 내용)
///
/// `camera_android_camerax` 는 프리셋 하나로 만든 `ResolutionSelector` 를
/// **프리뷰와 사진 촬영에 똑같이** 물려 준다.
/// (`android_camera_camerax.dart` — `Preview(resolutionSelector: …)` 와
///  `ImageCapture(resolutionSelector: …)` 가 같은 값을 받는다.)
///
/// 그리고 `high` 의 정의는 이렇다.
/// ```dart
/// case ResolutionPreset.high:
///   boundSize = CameraSize(width: 1280, height: 720);
///   aspectRatio = AspectRatio.ratio16To9;   // ← 16:9 로 강제
/// ```
///
/// 여기서 두 가지 손해가 동시에 났다.
///
/// 1) **화각이 좁아진다(= 확대돼 보인다).**
///    휴대폰 뒷면 카메라의 센서는 4:3(세로로 0.75)이다.
///    이걸 16:9(세로로 0.5625)로 만들려면 좌우를 잘라내야 한다.
///    남는 가로 폭은 `0.5625 / 0.75 = 0.75`, 즉 **가로 25% 가 사라진다.**
///    배율로는 `1 / 0.75 = 1.333배` 확대다.
///    기본 카메라 앱은 4:3 전체를 보여 주니까, 우리 화면만 확대돼 보였다.
///    사장님이 말한 "찍을 때 약간 확대되어서" 가 정확히 이거다.
///
/// 2) **해상도가 0.92MP 로 묶인다.**
///    1280 × 720 = 92만 화소. 요즘 휴대폰 센서는 1200만 화소가 넘는다.
///    영수증 글씨는 원래 작은데, 센서가 이미 92만 화소로 뭉갠 뒤에
///    프레임(0.62)까지 잘라내니 저장본이 720 × 1161 밖에 안 됐다.
///    저장 상한으로 정한 1200px 에도 못 미쳐서, 줄이는 단계가 아예
///    동작하지 않았다(줄일 게 없으니까). 화질 손실이 전부 촬영 단계였다.
///
/// ## 그래서 `max` 를 쓴다
///
/// ```dart
/// case ResolutionPreset.max:
///   resolutionStrategy = ResolutionStrategy.highestAvailableStrategy;
///   return ResolutionSelector(resolutionStrategy: resolutionStrategy);
/// ```
///
/// `max` 는 **`aspectRatioStrategy` 를 아예 넘기지 않는다.**
/// 그래서 CameraX 가 센서 고유 비율(4:3)을 그대로 쓴다.
///   * 좌우를 잘라내지 않으니 **기본 카메라 앱과 같은 화각**이 된다.
///   * 가장 높은 해상도를 고르니 **센서 화소를 다 쓴다.**
///   * 프리뷰와 사진이 같은 비율이 되어, 두 화면의 배율이 어긋날 여지도 줄어든다.
///
/// ## 그래도 실패할 기기가 있다
///
/// 아주 오래된 기기나 브라우저에서는 최고 해상도 프리뷰를 못 열 수 있다.
/// 그때 화면 전체가 "카메라를 열 수 없어요" 가 되면 안 된다.
/// 그래서 [presets] 순서대로 내려가며 시도한다.
class CameraQuality {
  const CameraQuality._();

  /// 위에서부터 시도한다. 앞이 실패하면 다음으로 내려간다.
  ///
  /// `max` 가 목표고, 뒤 두 개는 오래된 기기용 안전망이다.
  /// 순서를 바꾸면 화각이 다시 좁아진다. 바꾸지 말 것.
  static const List<ResolutionPreset> presets = <ResolutionPreset>[
    ResolutionPreset.max,
    ResolutionPreset.veryHigh,
    ResolutionPreset.high,
  ];

  /// 카메라를 열고 **초기화까지 끝낸** 컨트롤러를 준다.
  ///
  /// 실패한 컨트롤러는 여기서 정리하니, 부르는 쪽은 성공한 것만 받는다.
  /// 전부 실패하면 마지막 예외를 그대로 던진다(원인을 삼키지 않는다).
  static Future<CameraController> open(CameraDescription description) async {
    Object? lastError;
    StackTrace? lastStack;

    for (final preset in presets) {
      final controller = CameraController(
        description,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      try {
        await controller.initialize();
        if (kDebugMode) {
          debugPrint('[CameraQuality] $preset 로 열었습니다 — '
              '프리뷰 ${controller.value.previewSize}');
        }
        return controller;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (kDebugMode) {
          debugPrint('[CameraQuality] $preset 실패 — 다음 단계로 내려갑니다: $e');
        }
        try {
          await controller.dispose();
        } catch (_) {
          // 이미 망가진 컨트롤러다. 정리 실패는 무시해도 된다.
        }
      }
    }

    Error.throwWithStackTrace(
      lastError ?? StateError('카메라를 열 수 없습니다'),
      lastStack ?? StackTrace.current,
    );
  }
}
