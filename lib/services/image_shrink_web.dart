import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// 웹 구현 — 브라우저 canvas 로 실제 축소 + JPEG 재인코딩.
///
/// 왜 필요한가: 웹 카메라(`camera_web`)는 `imageQuality`/`maxWidth` 옵션이
/// 없어서 언제나 원본 해상도로 사진을 준다. 그 상태로 base64 에 실으면
/// 요청 본문이 10MB 를 넘고, 브라우저 업로드가 느려서 타임아웃이 난다.
///
/// 실패하면 `null` 을 돌려준다 — 호출부는 원본을 그대로 보낸다.
/// 축소 때문에 스캔 자체가 죽는 일은 없어야 한다.
Future<Uint8List?> shrinkJpeg(
  Uint8List bytes,
  int maxDimension, {
  String mimeType = 'image/jpeg',
}) async {
  web.HTMLImageElement? img;
  String? url;
  try {
    // 🔴 blob 타입은 **실제 바이트의 타입**을 그대로 준다.
    //
    // 예전에는 'image/jpeg' 로 고정했다. 갤러리에는 스크린샷(PNG)이나
    // 아이폰 사진(HEIC)이 흔한데, PNG 바이트에 jpeg 라고 이름표를 붙이면
    // 브라우저가 디코딩을 거부할 수 있다. 그러면 축소를 못 하고 원본이
    // 그대로 전송된다.
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    url = web.URL.createObjectURL(blob);

    img = web.document.createElement('img') as web.HTMLImageElement;
    final loaded = Completer<bool>();
    img.onload = (JSAny _) {
      if (!loaded.isCompleted) loaded.complete(true);
    }.toJS;
    img.onerror = (JSAny _) {
      if (!loaded.isCompleted) loaded.complete(false);
    }.toJS;
    img.src = url;

    // 디코딩이 멈추는 경우를 대비해 상한을 둔다.
    final ok = await loaded.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );
    if (!ok) return null;

    final w = img.naturalWidth;
    final h = img.naturalHeight;
    if (w <= 0 || h <= 0) return null;

    final longest = w > h ? w : h;
    // JPEG 가 아닌 입력(PNG/HEIC/WEBP)은 크기가 작아도 JPEG 로 바꿔주는
    // 것이 이득이다. PNG 는 같은 화면이 JPEG 의 2배 용량이고, HEIC 는
    // Gemini 가 받지 않는 형식이다. 그래서 크기 조건은 JPEG 에만 적용한다.
    final isJpeg = mimeType == 'image/jpeg';
    if (isJpeg && longest <= maxDimension) return null; // 줄일 필요 없음

    final scale = longest > maxDimension ? maxDimension / longest : 1.0;
    final tw = (w * scale).round();
    final th = (h * scale).round();

    final canvas = web.HTMLCanvasElement()
      ..width = tw
      ..height = th;
    final ctx = canvas.context2D
      ..imageSmoothingEnabled = true
      ..imageSmoothingQuality = 'high';
    ctx.drawImage(img, 0, 0, tw.toDouble(), th.toDouble());

    // 영수증 글자는 품질 0.88 로 충분히 읽힌다.
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.88);
    const marker = 'base64,';
    final idx = dataUrl.indexOf(marker);
    if (idx < 0) return null;
    final b64 = dataUrl.substring(idx + marker.length);
    final out = base64Decode(b64);

    // 오히려 커졌다면(작은 이미지에서 드물게 발생) 원본을 쓴다.
    // 단, JPEG 가 아닌 입력은 **형식을 바꾸는 것 자체가 목적**이므로
    // 용량이 커져도 결과를 쓴다. (HEIC 는 Gemini 가 받지 못한다)
    if (isJpeg && out.lengthInBytes >= bytes.lengthInBytes) return null;
    return out;
  } catch (e) {
    debugPrint('[ocr] 웹 이미지 축소 실패 — 원본을 그대로 보냅니다: $e');
    return null;
  } finally {
    img?.src = '';
    if (url != null) web.URL.revokeObjectURL(url);
  }
}
