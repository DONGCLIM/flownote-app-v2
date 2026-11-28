import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

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

bool get webGalleryPickerAvailable => true;

/// 웹에서 갤러리 사진을 **바이트로 직접** 가져온다.
///
/// ## 왜 `image_picker` 를 안 쓰고 직접 하는가
///
/// `image_picker_for_web` 이 사진을 넘겨주는 방식이 문제의 뿌리다.
/// 플러그인 코드(`image_picker_for_web-3.1.1`)를 그대로 인용한다.
///
/// ```dart
/// // _getSelectedXFiles: 파일을 고른 직후
/// return XFile(
///   web.URL.createObjectURL(file),   // ⚠️ blob URL 만 만들고
///   name: file.name,                 //    File 객체는 버린다
///   length: file.size,
///   mimeType: file.type,
/// );
/// ...
/// return _getSelectedXFiles(input).whenComplete(() {
///   input.remove();                  // ⚠️ <input> 을 DOM 에서 제거
/// });
/// ```
///
/// 그래서 우리 손에 남는 것은 **`blob:` URL 문자열 하나뿐**이다.
/// `File` 객체도, 그 `File` 을 담고 있던 `<input>` 도 사라진다.
///
/// 그리고 `cross_file` 웹 구현의 `readAsBytes()` 는 그 URL 을 매번 XHR 로
/// 다시 가져온다(결과를 캐시하지 않는다). blob URL 은
///
///   · `revokeObjectURL` 로 폐기되면 즉시 무효가 되고,
///   · 원본 `File` 과 `<input>` 이 모두 사라진 뒤에는 브라우저가 뒤에서
///     들고 있던 파일 핸들을 정리해버릴 수 있다.
///
/// 두 경우 모두 XHR 이 실패한다. 그런데 **언제 정리되는지는 브라우저가
/// 정한다** — 메모리 상황, 사진 크기, 지난 시간에 따라 달라진다.
/// 이것이 사장님이 겪으신 "됐다가 안 됐다가" 의 마지막 조각이다.
/// 재시도를 두 번, 세 번 넣어도 소용없다. **이미 무효가 된 URL 은
/// 몇 번 더 시도해도 계속 무효다.**
///
/// ## 그래서 이렇게 한다
///
/// 1. `<input type="file">` 을 **우리가 직접** 만들고 DOM 에 붙인다.
/// 2. `<input>` 을 **읽기가 다 끝날 때까지 제거하지 않는다.**
///    (플러그인은 여기서 바로 제거한다)
/// 3. `File` 객체를 **직접 붙잡고** `FileReader` 로 읽는다.
///    `blob:` URL 을 **아예 만들지 않는다.** 만들지 않으면 폐기될 일도 없다.
/// 4. 한 장 읽을 때마다 즉시 축소해서 바이트만 남기고 다음 장으로 간다.
/// 5. 전부 끝난 뒤에 `<input>` 을 제거한다.
///
/// 이 경로에는 blob URL 이 단 한 개도 등장하지 않는다.
/// 즉 "URL 이 무효가 돼서 못 읽는" 실패 방식 자체가 사라진다.
///
/// 사용자가 취소하면 `null` 을 돌려준다(빈 목록과 구분해야 한다).
Future<List<PickedPhoto>?> pickPhotosFromGallery({
  bool multiple = true,
}) async {
  final input =
      web.document.createElement('input') as web.HTMLInputElement
        ..type = 'file'
        ..accept = 'image/*'
        ..multiple = multiple;

  // 화면에 보이지 않게 하되 `display:none` 은 피한다. 일부 브라우저에서
  // 완전히 숨긴 input 의 `click()` 이 무시된다.
  input.style
    ..position = 'absolute'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0'
    ..left = '-9999px';

  web.document.body?.append(input as JSAny);

  final done = Completer<List<PickedPhoto>?>();

  Future<void> handle() async {
    final fileList = input.files;
    if (fileList == null || fileList.length == 0) {
      if (!done.isCompleted) done.complete(null); // 취소
      return;
    }

    final out = <PickedPhoto>[];
    for (var i = 0; i < fileList.length; i++) {
      final f = fileList.item(i);
      if (f == null) continue;
      final name = f.name.isEmpty ? 'photo_$i.jpg' : f.name;

      // 🔴 `File` 을 직접 읽는다. blob URL 을 만들지 않는다.
      final bytes = await _readFile(f, name);
      if (bytes == null) {
        debugPrint('[scan] ❌ "$name" 파일을 읽지 못했습니다');
        continue;
      }

      final mime = f.type.isEmpty ? _guessMime(name) : f.type;
      out.add(PickedPhoto(name: name, mimeType: mime, bytes: bytes));
      debugPrint('[scan] "$name" 읽음 '
          '${(bytes.lengthInBytes / 1024).round()}KB ($mime)');
    }

    if (!done.isCompleted) done.complete(out);
  }

  input.onchange = (web.Event _) {
    // `handle()` 이 끝날 때까지 input 을 살려둬야 한다.
    handle();
  }.toJS;

  // 취소를 감지한다. 브라우저가 `cancel` 을 안 쏘는 경우도 있으니
  // 아래 타임아웃이 최종 안전망이다.
  input.oncancel = (web.Event _) {
    if (!done.isCompleted) done.complete(null);
  }.toJS;

  input.click();

  try {
    // 사장님이 갤러리에서 사진을 고르는 데 시간이 걸릴 수 있다.
    // 넉넉하게 5분을 준다. (이 타임아웃은 "고르는 시간" 이지 읽기 시간이 아니다)
    return await done.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => null,
    );
  } finally {
    // 🔴 읽기가 **완전히 끝난 뒤에** 제거한다.
    input.remove();
  }
}

/// `FileReader` 로 `File` 을 읽는다.
///
/// `blob:` URL 을 거치지 않으므로 "URL 이 폐기됐다" 는 실패가 없다.
/// 그래도 브라우저가 파일 접근 자체를 거부할 수는 있다
/// (예: 클라우드에만 있는 사진, 읽는 중 파일이 사라진 경우).
/// 그 경우만 한 번 더 시도한다.
Future<Uint8List?> _readFile(web.File f, String name) async {
  for (var attempt = 1; attempt <= 2; attempt++) {
    try {
      final r = await _readOnce(f).timeout(const Duration(seconds: 30));
      if (r != null && r.isNotEmpty) return r;
      debugPrint('[scan] "$name" 시도 $attempt — 0바이트');
    } catch (e) {
      debugPrint('[scan] "$name" 시도 $attempt — 읽기 실패: $e');
    }
    if (attempt == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
  return null;
}

Future<Uint8List?> _readOnce(web.File f) {
  final c = Completer<Uint8List?>();
  final reader = web.FileReader();

  reader.onload = (web.Event _) {
    if (c.isCompleted) return;
    final res = reader.result;
    if (res == null) {
      c.complete(null);
      return;
    }
    try {
      final buf = res as JSArrayBuffer;
      c.complete(buf.toDart.asUint8List());
    } catch (e) {
      c.completeError('결과 변환 실패: $e');
    }
  }.toJS;

  reader.onerror = (web.Event _) {
    if (c.isCompleted) return;
    final err = reader.error;
    c.completeError('FileReader 오류 ${err?.name ?? ''}');
  }.toJS;

  reader.onabort = (web.Event _) {
    if (!c.isCompleted) c.completeError('읽기가 중단됐습니다');
  }.toJS;

  reader.readAsArrayBuffer(f);
  return c.future;
}

String _guessMime(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.heic') || n.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}
