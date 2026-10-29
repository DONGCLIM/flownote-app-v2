import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'image_shrink.dart';
import 'inquiry_service.dart';

/// 문의 첨부 사진 고르기 + 압축.
///
/// 🔴 사진만 받는다. (사장님 지시 — 이미지만, 최대 3장)
///    예전에는 `file_picker` 로 아무 파일이나 받았는데, 그러면 실행파일도
///    올라갈 수 있고 관리자가 열어 보기도 위험하다.
///
/// ## 압축을 왜 두 겹으로 하나
///
/// | 단계 | 하는 일 |
/// |---|---|
/// | ① `image_picker` 옵션 | 가져오는 순간 긴 쪽 1600px 로 줄인다 (네이티브) |
/// | ② [compress] | 그래도 큰 사진을 다시 줄인다 (웹 canvas / 네이티브 `image`) |
///
/// 웹의 `image_picker` 는 `maxWidth` 를 무시하는 브라우저가 있어서
/// ① 만 믿을 수 없다. 그래서 가져온 뒤 바이트를 직접 보고 다시 줄인다.
class InquiryPicker {
  InquiryPicker._();

  /// 앨범에서 사진을 고른다. [remaining] 장까지만 받는다.
  static Future<List<InquiryAttachment>> pickImages(int remaining) async {
    if (remaining <= 0) return const [];
    final picked = await ImagePicker().pickMultiImage(
      maxWidth: InquiryService.targetLongSide.toDouble(),
      maxHeight: InquiryService.targetLongSide.toDouble(),
      imageQuality: 85,
    );
    if (picked.isEmpty) return const [];

    final out = <InquiryAttachment>[];
    for (final x in picked.take(remaining)) {
      final raw = await x.readAsBytes();
      final mime = x.mimeType ?? _guessType(x.name);
      final small = await compress(raw, mime);
      out.add(InquiryAttachment(
        name: _jpgName(x.name),
        bytes: small.bytes,
        contentType: small.contentType,
      ));
    }
    return out;
  }

  /// 긴 쪽 1600px / 약 1MB 로 줄인다.
  ///
  /// 줄이지 못하면 원본을 그대로 돌려준다 — 압축 실패 때문에 첨부 자체가
  /// 막히면 안 된다. 대신 [InquiryService] 가 5MB 상한으로 한 번 더 거른다.
  @visibleForTesting
  static Future<CompressedImage> compress(Uint8List raw, String mime) async {
    // ① 웹: 브라우저 canvas. 네이티브: null 을 준다.
    final viaCanvas =
        await shrinkJpeg(raw, InquiryService.targetLongSide, mimeType: mime);
    if (viaCanvas != null && viaCanvas.lengthInBytes < raw.lengthInBytes) {
      return CompressedImage(viaCanvas, 'image/jpeg');
    }

    // ② 네이티브: 순수 Dart 디코더로 줄인다.
    //    이미 충분히 작으면 건드리지 않는다 — 다시 인코딩하면 화질만 나빠진다.
    if (raw.lengthInBytes <= InquiryService.targetBytes) {
      return CompressedImage(raw, mime);
    }
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return CompressedImage(raw, mime);

      var work = decoded;
      final long = decoded.width > decoded.height ? decoded.width : decoded.height;
      if (long > InquiryService.targetLongSide) {
        work = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: InquiryService.targetLongSide)
            : img.copyResize(decoded, height: InquiryService.targetLongSide);
      }

      // 1MB 에 들어올 때까지 화질을 낮춘다. 85 → 70 → 55 → 40.
      for (final q in [85, 70, 55, 40]) {
        final jpg = Uint8List.fromList(img.encodeJpg(work, quality: q));
        if (jpg.lengthInBytes <= InquiryService.targetBytes || q == 40) {
          return jpg.lengthInBytes < raw.lengthInBytes
              ? CompressedImage(jpg, 'image/jpeg')
              : CompressedImage(raw, mime);
        }
      }
    } catch (e) {
      debugPrint('[inquiry] 사진 압축 실패(원본 사용): $e');
    }
    return CompressedImage(raw, mime);
  }

  /// 압축하면 JPEG 가 되므로 확장자도 맞춰 준다.
  static String _jpgName(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '$base.jpg';
  }

  static String _guessType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }
}

/// 압축 결과.
@immutable
class CompressedImage {
  const CompressedImage(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}
