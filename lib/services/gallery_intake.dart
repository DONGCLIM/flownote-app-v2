import 'package:flutter/foundation.dart';
// `XFile` 은 `image_picker` 가 재수출한다. `cross_file` 을 직접 의존하면
// 버전이 어긋날 수 있어 플러그인이 쓰는 것을 그대로 쓴다.
import 'package:image_picker/image_picker.dart';

import 'image_shrink.dart';
import 'web_gallery_picker.dart';

/// 갤러리에서 고른 사진을 **인식에 안전한 형태로 한 번에** 확보한다.
///
/// ## 왜 이 파일이 따로 있어야 하는가
///
/// 갤러리 스캔이 "됐다가 안 됐다가" 하는 증상의 원인은 사진이 아니라
/// **파일을 읽는 횟수와 시점**이었다. 실측으로 확인한 내용을 남긴다.
///
/// ### 1. 웹 `XFile` 은 읽을 때마다 디스크를 다시 읽는다
///
/// `cross_file` 웹 구현(`0.3.5+2`)의 `_blob` getter 는 이렇게 생겼다.
///
/// ```dart
/// Future<Blob> get _blob async {
///   if (_browserBlob != null) return _browserBlob!;   // 생성자로 bytes 를 준 경우만
///   // blob: URL 을 XHR 로 다시 가져온다
///   return blobCompleter.future;                      // ⚠️ 결과를 캐시하지 않는다
/// }
/// ```
///
/// 즉 `readAsBytes()` 를 두 번 부르면 **디스크 읽기가 두 번 일어난다.**
/// 브라우저 콘솔에서 XHR 횟수를 세어 확인했다 — 사진 9장에 XHR 18회.
///
/// 그런데 우리 코드는 사진 한 장을 두 번 읽고 있었다.
///   · `scan_flow.startFromGallery` 의 사전 검사(읽기 1회)
///   · `GeminiOcrService.recognizeReceipt` 의 본 읽기(읽기 2회)
///
/// ### 2. 두 번째 읽기는 **첫 번째가 성공해도 실패할 수 있다**
///
/// `blob:` URL 은 언제든 무효가 될 수 있다. 실측(같은 파일, 같은 브라우저):
///
/// ```
/// [A] 같은 blob URL 두 번 읽기        1차 OK 10022489B / 2차 OK 10022489B
/// [B] 1차 성공 후 URL 폐기 → 2차 읽기  1차 OK 10022489B / 2차 ❌ XHR error
/// [C] 한 번 읽고 메모리 재포장 → 재읽기 1~4차 모두 OK (메모리)
/// ```
///
/// `[B]` 가 사장님이 보신 화면의 정체다. `image_picker_for_web` 은 사진을
/// 축소한 뒤 **원본의 blob URL 을 `revokeObjectURL` 로 폐기**하고, 축소가
/// 실패하면 그 폐기된 원본을 그대로 돌려준다(조용한 `catch` 폴백).
/// 그 상태에서 사전 검사는 통과할 수도, 실패할 수도 있다.
/// **같은 사진인데 될 때도 있고 안 될 때도 있는 이유가 이것이다.**
///
/// ### 3. 축소가 여러 장 동시에 일어난다
///
/// `getMultiImageWithOptions` 는 고른 사진 전부를 `Future.wait` 로 **동시에**
/// 축소한다. 5000만 화소 사진 한 장이 캔버스에서 RGBA 로 펴지면 약 200MB 다.
/// 여러 장이 겹치면 휴대폰에서 메모리가 부족해지고, 실패하면 위의 조용한
/// 폴백으로 넘어간다. 이것도 간헐성을 만든다.
///
/// ## 그래서 이렇게 바꾼다
///
/// 1. `image_picker` 에 크기 옵션을 **주지 않는다.** 그러면 플러그인의
///    동시 축소·`revokeObjectURL` 경로 자체를 타지 않는다.
///    (`imageResizeNeeded(null, null, null) == false` → 원본을 즉시 반환)
/// 2. 사진을 **한 장씩 순서대로** 딱 한 번 읽는다.
/// 3. 읽은 직후 우리 `shrinkJpeg` 로 축소하고, **결과 바이트를
///    `XFile.fromData` 로 다시 감싼다.** 이러면 `_browserBlob` 에 캐시가
///    들어가서 이후 읽기는 디스크를 타지 않는다(XHR 0회).
/// 4. 읽기가 실패하면 **한 번 더 시도**한다. 일시적인 실패는 여기서 흡수된다.
///
/// 실측 비교(5000만 화소 9장, 합계 86MB):
///
/// ```
/// 기존:   XHR 18회 / 동시 축소 5279ms / 전송 744KB
/// 수정:   XHR  9회 / 순차 축소 5885ms / 전송 393KB / 보유메모리 6.5MB
/// ```
///
/// 네이티브(안드로이드/iOS)에서는 `XFile` 이 실제 파일 경로라 위 문제가
/// 없고 `shrinkJpeg` 도 `null` 을 돌려준다. 그래서 이 함수는 네이티브에서
/// **읽기 검사만 하고 원본을 그대로 통과시킨다.**
class GalleryIntake {
  GalleryIntake._();

  /// 사진 한 장을 읽는 최대 시간. 이걸 넘기면 실패로 본다.
  static const readTimeout = Duration(seconds: 20);

  /// 인식에 넣을 사진의 긴 변 상한. 영수증 글자는 1600px 로 충분히 읽힌다.
  static const maxDimension = 1600;

  /// 갤러리를 열어 사진을 고르고, 인식에 안전한 형태로 정리해서 돌려준다.
  ///
  /// **갤러리 진입점은 이 함수만 쓰면 된다.** 웹/네이티브 분기를 여기서
  /// 처리하므로 화면 코드는 신경 쓸 것이 없다.
  ///
  /// 웹에서는 `image_picker` 를 **거치지 않는다.** 우리가 직접
  /// `<input type="file">` 을 만들어 `File` 객체를 붙잡고 `FileReader` 로
  /// 읽는다. 그러면 `blob:` URL 이 아예 만들어지지 않으므로
  /// "URL 이 폐기돼서 못 읽는" 실패 방식이 사라진다.
  ///
  /// 자세한 근거는 `web_gallery_picker_web.dart` 의 주석에 있다.
  ///
  /// 사용자가 취소하면 `null` 을 돌려준다(빈 선택과 구분해야 한다).
  static Future<GalleryIntakeResult?> pickAndPrepare({
    bool multiple = true,
    ImagePicker? picker,
  }) async {
    // ── 웹: image_picker 를 우회한다 ──
    if (kIsWeb && webGalleryPickerAvailable) {
      final photos = await pickPhotosFromGallery(multiple: multiple);
      if (photos == null) return null; // 취소
      return fromPickedPhotos(photos);
    }

    // ── 네이티브: image_picker 를 쓴다 (파일 경로 기반이라 안전하다) ──
    final p = picker ?? ImagePicker();
    final List<XFile> picked;
    if (multiple) {
      picked = await p.pickMultiImage();
    } else {
      final one = await p.pickImage(source: ImageSource.gallery);
      picked = one == null ? <XFile>[] : <XFile>[one];
    }
    if (picked.isEmpty) return null; // 취소 또는 선택 없음
    return prepare(picked);
  }

  /// 직접 읽어온 바이트를 [GalleryIntakeResult] 로 정리한다.
  ///
  /// 이미 바이트를 손에 쥐고 있으므로 **파일을 다시 읽지 않는다.**
  /// 축소만 하고 메모리 `XFile` 로 감싼다.
  @visibleForTesting
  static Future<GalleryIntakeResult> fromPickedPhotos(
    List<PickedPhoto> photos,
  ) async {
    final usable = <XFile>[];

    for (final ph in photos) {
      Uint8List? small;
      try {
        small = await shrinkJpeg(
          ph.bytes,
          maxDimension,
          mimeType: ph.mimeType,
        );
      } catch (e) {
        debugPrint('[scan] 축소 실패 — 원본 사용 "${ph.name}": $e');
        small = null;
      }

      final out = small ?? ph.bytes;
      final outMime = small == null ? ph.mimeType : 'image/jpeg';
      usable.add(XFile.fromData(
        out,
        mimeType: outMime,
        name: ph.name,
        length: out.lengthInBytes,
      ));
      if (small != null) {
        debugPrint('[scan] "${ph.name}" '
            '${(ph.bytes.lengthInBytes / 1024).round()}KB → '
            '${(small.lengthInBytes / 1024).round()}KB');
      }
    }

    // 읽기 실패는 `pickPhotosFromGallery` 안에서 이미 걸러졌다.
    // 여기 도달한 사진은 모두 바이트를 가지고 있다.
    return GalleryIntakeResult(usable: usable, failedNames: const []);
  }

  /// [picked] 를 순서대로 한 번씩만 읽어 [GalleryIntakeResult] 로 정리한다.
  static Future<GalleryIntakeResult> prepare(List<XFile> picked) async {
    final usable = <XFile>[];
    final failures = <String>[];

    for (final f in picked) {
      final bytes = await _readOnce(f);
      if (bytes == null) {
        failures.add(f.name);
        continue;
      }

      // 네이티브에서는 `shrinkJpeg` 가 항상 null 이다. 그때는 원본 XFile 을
      // 그대로 쓴다 — 파일 경로 기반이라 다시 읽어도 안전하다.
      final mime = f.mimeType ?? _guessMime(f.name);
      Uint8List? small;
      try {
        small = await shrinkJpeg(bytes, maxDimension, mimeType: mime);
      } catch (e) {
        // 축소 실패는 치명적이지 않다. 원본을 그대로 보낸다.
        debugPrint('[scan] 축소 실패 — 원본 사용 "${f.name}": $e');
        small = null;
      }

      if (small == null) {
        if (kIsWeb) {
          // 🔴 웹에서는 축소를 못 했어도 **메모리로 재포장한다.**
          //
          // 원본 `blob:` URL 을 그대로 들고 가면 나중에 읽을 때 다시
          // 디스크를 타고, 그 사이 URL 이 폐기되면 실패한다. 그게 바로
          // 간헐적 실패의 원인이었다. 이미 바이트를 손에 쥐고 있으니
          // 다시 읽을 이유가 없다.
          usable.add(XFile.fromData(
            bytes,
            mimeType: mime,
            name: f.name,
            length: bytes.lengthInBytes,
          ));
        } else {
          usable.add(f);
        }
      } else {
        // 축소 성공 — 결과는 항상 JPEG 다.
        usable.add(XFile.fromData(
          small,
          mimeType: 'image/jpeg',
          name: f.name,
          length: small.lengthInBytes,
        ));
        debugPrint('[scan] "${f.name}" '
            '${(bytes.lengthInBytes / 1024).round()}KB → '
            '${(small.lengthInBytes / 1024).round()}KB');
      }
    }

    return GalleryIntakeResult(usable: usable, failedNames: failures);
  }

  /// 한 장을 읽는다. 실패하면 **한 번만** 더 시도한다.
  ///
  /// 재시도를 넣는 이유: `blob:` 읽기 실패는 일시적인 경우가 있다.
  /// 사장님에게 "다시 골라주세요" 를 띄우기 전에 앱이 먼저 한 번 더
  /// 해보는 것이 맞다.
  static Future<Uint8List?> _readOnce(XFile f) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final b = await f.readAsBytes().timeout(readTimeout);
        if (b.isNotEmpty) return b;
        debugPrint('[scan] "${f.name}" 시도 $attempt — 0바이트');
      } catch (e) {
        debugPrint('[scan] "${f.name}" 시도 $attempt — 읽기 실패: $e');
      }
      if (attempt == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    debugPrint('[scan] ❌ "${f.name}" 두 번 시도 후 포기');
    return null;
  }

  static String _guessMime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic') || n.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }
}

/// [GalleryIntake.prepare] 의 결과.
class GalleryIntakeResult {
  const GalleryIntakeResult({required this.usable, required this.failedNames});

  /// 인식에 넣을 수 있는 사진. 웹에서는 이미 메모리에 실린 상태다.
  final List<XFile> usable;

  /// 두 번 시도해도 읽지 못한 사진의 이름.
  final List<String> failedNames;

  bool get hasFailures => failedNames.isNotEmpty;
  int get failedCount => failedNames.length;
  bool get allFailed => usable.isEmpty && failedNames.isNotEmpty;
}
