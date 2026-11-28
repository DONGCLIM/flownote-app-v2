import 'package:flutter/foundation.dart';

/// 갤러리에서 고른 사진 하나 — 이름 + 실제 바이트.
class PickedPhoto {
  const PickedPhoto({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// 네이티브 구현 — 쓰이지 않는다.
///
/// 안드로이드/iOS 에서는 `image_picker` 가 실제 파일 경로를 주고, 그 경로는
/// 몇 번이든 다시 읽을 수 있다. 웹처럼 "읽을 때마다 다시 XHR" 하는 문제가
/// 없으므로 이 우회로가 필요 없다.
bool get webGalleryPickerAvailable => false;

Future<List<PickedPhoto>?> pickPhotosFromGallery({
  bool multiple = true,
}) async =>
    null;
