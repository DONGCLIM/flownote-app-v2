import 'dart:typed_data';

/// 네이티브 구현 — 축소하지 않는다.
///
/// 순수 Dart 로 JPEG 를 다시 인코딩할 수단이 없다. 대신 네이티브에서는
/// `image_picker` 의 `maxWidth`/`maxHeight` 가 사진을 **가져오는 시점에**
/// 이미 줄여주므로 여기서 할 일이 없다.
///
/// `null` 을 돌려주면 호출부가 "축소하지 못했다" 로 판단해 원본을 쓴다.
Future<Uint8List?> shrinkJpeg(
  Uint8List bytes,
  int maxDimension, {
  String mimeType = 'image/jpeg',
}) async =>
    null;
