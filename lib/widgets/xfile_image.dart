import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// 촬영/선택한 사진(`XFile`)을 플랫폼에 상관없이 보여주는 위젯.
///
/// 🔴 왜 이 위젯이 필요한가
/// `Image.file(File(x.path))` 는 웹에서 무조건 터진다.
/// dart2js 는 `dart:io` 를 "컴파일은 되지만 전부 UnsupportedError 를 던지는"
/// 스텁(`_internal/js_runtime/lib/io_patch.dart`)으로 바꿔서 넣는다.
/// 그래서 `flutter build web` 은 성공하는데 실행하는 순간 죽는다.
/// (libraries.json: dart2js -> io -> "supported": false)
///
/// 웹에서 `XFile.path` 는 파일 경로가 아니라 `blob:https://...` URL 이라서
/// `Image.network` 로 그대로 그릴 수 있다.
class XFileImage extends StatelessWidget {
  const XFileImage(
    this.file, {
    super.key,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.errorBuilder,
  });

  final XFile file;
  final BoxFit fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final fallback = errorBuilder ??
        (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  size: 56, color: Color(0x99FFFFFF)),
            );

    if (kIsWeb) {
      // 웹: blob URL 을 네트워크 이미지처럼 읽는다.
      return Image.network(
        file.path,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: fallback,
      );
    }
    return Image.file(
      io.File(file.path),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: fallback,
    );
  }
}
