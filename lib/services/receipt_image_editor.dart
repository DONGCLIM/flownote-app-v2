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

  /// 저장할 때 쓰는 기본 긴 변 길이(px).
  ///
  /// 영수증 글자를 Gemini OCR 이 읽을 수 있어야 하므로 너무 줄이면 안 된다.
  /// 실측으로 1600px 이면 감열지 영수증의 품목/금액이 또렷하게 남는다.
  static const int defaultMaxDimension = 2000;

  /// 사용자가 고를 수 있는 리사이즈 단계.
  ///
  /// `null` = 원본 유지.
  static const List<({String label, int? maxDimension, String note})>
      resizeChoices = [
    (label: '원본', maxDimension: null, note: '가장 선명 · 용량 큼'),
    (label: '높음', maxDimension: 2400, note: '거의 원본'),
    (label: '보통', maxDimension: 1600, note: '권장 · 인식 잘 됨'),
    (label: '작게', maxDimension: 1200, note: '용량 최소'),
  ];

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

  /// 촬영 직후, 화면에서 보이던 프레임 영역만 남긴다.
  ///
  /// [previewAspect] = 화면 프레임의 `가로/세로` 비율.
  /// 프리뷰를 `BoxFit.cover` 로 보여줬다는 전제 하에, 센서 프레임의
  /// 중앙에서 그 비율에 해당하는 사각형을 계산한다.
  ///
  /// 예: 프레임이 0.62 (세로로 긴 영수증 모양), 사진이 0.75 (4:3 세로) 라면
  /// 사진이 프레임보다 가로로 넓으므로 좌우를 잘라낸다.
  static Rel coverCropRect({
    required int imageWidth,
    required int imageHeight,
    required double previewAspect,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0 || previewAspect <= 0) {
      return const Rel(0, 0, 1, 1);
    }
    final imageAspect = imageWidth / imageHeight;
    if ((imageAspect - previewAspect).abs() < 0.001) {
      return const Rel(0, 0, 1, 1);
    }
    if (imageAspect > previewAspect) {
      // 사진이 더 넓다 → 좌우를 자른다.
      final w = previewAspect / imageAspect;
      return Rel((1 - w) / 2, 0, w, 1);
    }
    // 사진이 더 좁다(길다) → 위아래를 자른다.
    final h = imageAspect / previewAspect;
    return Rel(0, (1 - h) / 2, 1, h);
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
