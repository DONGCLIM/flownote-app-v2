import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// 영수증 사진을 **자르고 · 줄이고 · 회전**하는 엔진.
///
/// ## 왜 이 파일이 새로 생겼나
///
/// 세 가지 요구가 한 지점에서 만난다.
///
/// 1. **촬영 화면 프레임을 영수증 모양(세로로 긴 사각형)으로 꽉 채워야 한다.**
///    프레임을 꽉 채우려면 프리뷰를 `BoxFit.cover` 로 확대해 잘라 보여줘야
///    한다. 그런데 `takePicture()` 는 화면에 보이는 영역이 아니라 **센서
///    프레임 전체**를 파일에 쓴다. 그대로 두면 "라인에 맞췄는데 찍힌 사진은
///    더 넓다"(= 초광각처럼 작게 나온다) 는 문제가 되돌아온다.
///    → 찍힌 JPEG 를 **보이던 사각형만큼 잘라내면** 화면과 파일이 같아진다.
///
/// 2. **영수증만 크롭하는 기능.** 사용자가 네 변을 끌어 영역을 정하면
///    그 영역만 남긴다.
///
/// 3. **리사이즈해서 저장.** 카메라 원본은 3~8MB 다. 업로드·백업·PDF 모두
///    느려진다. 긴 변 기준으로 줄인다.
///
/// 세 가지 전부 "JPEG 를 디코딩해서 다시 인코딩" 이 필요하다.
/// `package:image` 는 순수 Dart 라서 **웹과 앱에서 같은 코드**로 돈다.
/// (기존 `image_shrink` 는 웹에서만 canvas 로 축소하고 네이티브에서는
///  항상 `null` 을 돌려줬다. 즉 앱에는 축소 수단이 아예 없었다.)
///
/// ## 성능
///
/// 3000×4000 JPEG 디코딩+인코딩은 기기에서 0.3~1.5초쯤 걸린다.
/// UI 를 멈추지 않으려고 [compute] (별 isolate) 로 돌린다.
/// 웹에서는 `compute` 가 같은 스레드에서 실행되지만, 프레임 하나 정도
/// 끊기는 수준이고 촬영 직후 한 번뿐이라 감당할 수 있다.
class ReceiptImageEditor {
  ReceiptImageEditor._();

  /// 저장할 때 쓰는 긴 변 길이(px). **모든 저장 경로가 이 값을 쓴다.**
  ///
  /// 예전에는 원본/높음/보통/작게 네 단계를 사장님이 직접 고르게 했다.
  /// 실제로 쓸 때 매번 고르는 게 번거롭고, 잘못 고르면 용량만 커졌다.
  /// 그래서 선택을 없애고 **1200px 로 자동 변환**하기로 정했다.
  ///
  /// 긴 변 1200px 이면 감열지 영수증 한 장이 세로로 다 들어가고,
  /// 파일은 200~400KB 로 떨어져서 업로드·백업·PDF 가 모두 빨라진다.
  static const int defaultMaxDimension = 1200;

  /// JPEG 저장 품질.
  static const int quality = 88;

  /// [bytes] 를 [rect] (0~1 비율) 만큼 자르고, 긴 변을 [maxDimension] 으로
  /// 줄여서 **새 JPEG 바이트**를 돌려준다.
  ///
  /// - [rect] 가 `null` 이면 자르지 않는다.
  /// - [maxDimension] 이 `null` 이거나 원본이 더 작으면 줄이지 않는다.
  /// - [quarterTurns] 는 시계방향 90도 회전 횟수.
  /// - 어떤 단계든 실패하면 `null` — 호출부는 원본을 그대로 쓴다.
  ///   사진 한 장 편집 실패로 영수증 저장 자체를 막지 않는다.
  static Future<Uint8List?> transform(
    Uint8List bytes, {
    Rel? rect,
    int? maxDimension,
    int quarterTurns = 0,
  }) async {
    if (bytes.isEmpty) return null;
    // 아무 변화도 요청하지 않았다면 디코딩 비용을 쓰지 않는다.
    if (rect == null && maxDimension == null && quarterTurns % 4 == 0) {
      return null;
    }
    try {
      return await compute(
        _work,
        _Job(
          bytes: bytes,
          left: rect?.left ?? 0,
          top: rect?.top ?? 0,
          width: rect?.width ?? 1,
          height: rect?.height ?? 1,
          maxDimension: maxDimension ?? 0,
          quarterTurns: quarterTurns % 4,
        ),
      );
    } catch (e) {
      debugPrint('[receiptEdit] 편집 실패(원본 유지): $e');
      return null;
    }
  }

  /// 원본의 픽셀 크기를 읽는다. 실패하면 `null`.
  ///
  /// 크롭 UI 에서 "몇 px 로 저장됩니다" 를 보여주는 데 쓴다.
  static Future<({int width, int height})?> measure(Uint8List bytes) async {
    try {
      return await compute(_measure, bytes);
    } catch (_) {
      return null;
    }
  }

  /// 촬영 직후, **화면에서 실제로 보였던 사각형**만 남긴다.
  ///
  /// ## 🔴 여기가 "찍을 때랑 찍고 나서 배율이 다르다" 의 정답이다
  ///
  /// 화각이 어긋나는 지점이 **두 곳**인데, 예전 코드는 한 곳만 계산했다.
  ///
  /// ```
  ///  ① 센서/촬영본  ─(카메라 플러그인이 프리뷰용으로 잘라줌)─▶  ② 프리뷰 표면
  ///                                                              │
  ///                                     ③ 위젯이 BoxFit.cover 로 잘라 보여줌
  ///                                                              ▼
  ///                                                        화면 프레임(0.62)
  /// ```
  ///
  /// 안드로이드에서 `ResolutionPreset.high` 는 **프리뷰를 16:9 로** 요청한다
  /// (`camera_android_camerax` 의 `_getResolutionSelectorFromPreset` 에서
  ///  `aspectRatio = AspectRatio.ratio16To9`). 그런데 사진 촬영은 기기가
  /// 16:9 를 못 주면 4:3 센서 모드로 떨어진다. 즉 **②와 ①의 비율이 다르다.**
  ///
  /// 실제 숫자로 보면 (프리뷰 16:9 = 세로 0.5625, 촬영본 4:3 = 세로 0.75):
  ///
  /// | | 가로로 보이는 화각 |
  /// |---|---|
  /// | 화면에서 본 것 (②→③) | 촬영본 가로의 **75%** |
  /// | 예전 코드가 저장한 것 | 촬영본 가로의 **82.7%** |
  ///
  /// 예전 코드는 ①의 비율만 보고 0.62 로 중앙을 잘랐다. 비율(0.62)은 맞지만
  /// **영역이 다르다.** 그래서 프리뷰가 파일보다 약 1.10배 확대돼 보였다.
  /// 화면에서 라인에 딱 맞췄는데 저장된 사진은 더 넓게 나오는 것이다.
  ///
  /// ## 고친 방식
  ///
  /// ①→②→③ 두 단계를 **곱해서** 한 번에 잘라낸다.
  ///
  /// - ①→② : 프리뷰는 촬영본의 중앙 일부다.
  ///   [cameraAspect] 가 더 좁으면 가로를, 더 넓으면 세로를 잘라낸 것이다.
  /// - ②→③ : 위젯의 `BoxFit.cover` 가 다시 [previewAspect] 로 잘라낸다.
  ///
  /// 두 비율을 곱한 사각형은 어떤 조합에서든 최종 비율이 정확히
  /// [previewAspect] 가 된다(네 경우 모두 대수적으로 증명되고,
  /// `test/camera_fov_test.dart` 가 숫자로 검증한다).
  ///
  /// - [previewAspect] : 화면 프레임의 `가로/세로` (시안 계약값 0.62)
  /// - [cameraAspect]  : 프리뷰 표면의 `가로/세로` (세로 기준).
  ///   `1 / controller.value.aspectRatio` 를 넘긴다.
  ///   `null` 이면 프리뷰와 촬영본 비율이 같다고 보고 예전 계산을 쓴다.
  static Rel coverCropRect({
    required int imageWidth,
    required int imageHeight,
    required double previewAspect,
    double? cameraAspect,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0 || previewAspect <= 0) {
      return const Rel(0, 0, 1, 1);
    }
    final imageAspect = imageWidth / imageHeight;

    // 프리뷰 표면 비율을 모르면 촬영본과 같다고 본다(예전 동작).
    final camera =
        (cameraAspect == null || cameraAspect <= 0 || !cameraAspect.isFinite)
            ? imageAspect
            : cameraAspect;

    // ① 촬영본 → 프리뷰 표면. 플러그인이 중앙에서 잘라준다고 본다.
    var w = 1.0;
    var h = 1.0;
    if (camera < imageAspect) {
      // 프리뷰가 더 좁다 → 촬영본의 좌우가 잘려 있었다.
      w = camera / imageAspect;
    } else if (camera > imageAspect) {
      // 프리뷰가 더 넓다 → 촬영본의 위아래가 잘려 있었다.
      h = imageAspect / camera;
    }

    // ② 프리뷰 표면 → 화면 프레임. 위젯의 BoxFit.cover 가 잘라낸 몫.
    if (camera < previewAspect) {
      h *= camera / previewAspect;
    } else if (camera > previewAspect) {
      w *= previewAspect / camera;
    }

    w = w.clamp(0.0, 1.0);
    h = h.clamp(0.0, 1.0);
    if (w >= 0.999 && h >= 0.999) return const Rel(0, 0, 1, 1);
    return Rel((1 - w) / 2, (1 - h) / 2, w, h);
  }

  /// 편집 결과 바이트를 `XFile` 로 감싼다.
  ///
  /// 이후 파이프라인(`ScanDraft` → `ReceiptImageStore.persist`) 이 전부
  /// `XFile` 을 받으므로 모양을 맞춰준다.
  ///
  /// 🔴 웹에서 `XFile.fromData` 는 `path` 를 `blob:` URL 로 만든다.
  ///    네이티브에서는 `path` 가 우리가 넘긴 문자열 그대로다. 그래서
  ///    네이티브는 [savedPath] 에 **실제로 쓴 파일 경로**를 넘겨야 한다.
  static XFile wrap(
    Uint8List bytes, {
    required String name,
    String? savedPath,
  }) {
    return XFile.fromData(
      bytes,
      mimeType: 'image/jpeg',
      name: name,
      path: savedPath,
      length: bytes.length,
    );
  }
}

/// 0~1 비율 사각형. (`Rect` 를 쓰면 dart:ui 가 isolate 로 못 넘어간다)
@immutable
class Rel {
  const Rel(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  /// 전체 영역인가 (자를 필요가 없는가).
  bool get isFull =>
      left <= 0.0005 &&
      top <= 0.0005 &&
      width >= 0.999 &&
      height >= 0.999;

  Rel clampToUnit() {
    final l = left.clamp(0.0, 1.0);
    final t = top.clamp(0.0, 1.0);
    return Rel(
      l,
      t,
      width.clamp(0.0, 1.0 - l),
      height.clamp(0.0, 1.0 - t),
    );
  }

  @override
  String toString() => 'Rel($left, $top, $width, $height)';

  @override
  bool operator ==(Object other) =>
      other is Rel &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// isolate 로 넘기는 작업 묶음. 원시 타입만 담는다.
@immutable
class _Job {
  const _Job({
    required this.bytes,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.maxDimension,
    required this.quarterTurns,
  });

  final Uint8List bytes;
  final double left;
  final double top;
  final double width;
  final double height;
  final int maxDimension;
  final int quarterTurns;
}

/// 별 isolate 에서 도는 실제 작업. 최상위 함수여야 한다.
Uint8List? _work(_Job job) {
  var im = img.decodeImage(job.bytes);
  if (im == null) return null;

  // EXIF 회전을 먼저 굽는다. 안 하면 잘라낼 좌표가 어긋난다.
  im = img.bakeOrientation(im);

  // 1) 자르기
  final needCrop = job.left > 0.0005 ||
      job.top > 0.0005 ||
      job.width < 0.999 ||
      job.height < 0.999;
  if (needCrop) {
    final x = (im.width * job.left).round().clamp(0, im.width - 1);
    final y = (im.height * job.top).round().clamp(0, im.height - 1);
    final w = (im.width * job.width).round().clamp(1, im.width - x);
    final h = (im.height * job.height).round().clamp(1, im.height - y);
    im = img.copyCrop(im, x: x, y: y, width: w, height: h);
  }

  // 2) 회전
  if (job.quarterTurns != 0) {
    im = img.copyRotate(im, angle: job.quarterTurns * 90);
  }

  // 3) 줄이기 — 긴 변 기준. 원본이 더 작으면 키우지 않는다.
  final maxDim = job.maxDimension;
  if (maxDim > 0) {
    final longest = im.width > im.height ? im.width : im.height;
    if (longest > maxDim) {
      if (im.width >= im.height) {
        im = img.copyResize(im, width: maxDim, maintainAspect: true);
      } else {
        im = img.copyResize(im, height: maxDim, maintainAspect: true);
      }
    }
  }

  return img.encodeJpg(im, quality: ReceiptImageEditor.quality);
}

({int width, int height})? _measure(Uint8List bytes) {
  final im = img.decodeImage(bytes);
  if (im == null) return null;
  return (width: im.width, height: im.height);
}
