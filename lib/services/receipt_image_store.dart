import 'package:flutter/foundation.dart';

import 'file_saver.dart';
import 'receipt_image_upload.dart';

/// 영수증 사진을 **영구 폴더**에 보관한다.
///
/// ## 왜 필요한가
///
/// 카메라(`camera`) 와 갤러리(`image_picker`) 는 둘 다 결과 파일을
/// **캐시 폴더**에 떨군다. 실제 저장된 경로를 확인해 보면 전부 이렇다.
///
/// ```
/// /data/user/0/com.flownote.app/cache/scaled_1000018259.jpg
///                                ^^^^^
/// ```
///
/// 🔴 `cache` 는 안드로이드가 **예고 없이 비우는** 폴더다.
///    - 저장공간이 부족하면 OS 가 임의로 삭제한다
///    - 설정 → 앱 → 저장공간 → "캐시 삭제" 를 누르면 사라진다
///    - 앱을 지웠다 깔면 무조건 사라진다
///
/// 그래서 영수증 사진 경로를 그대로 저장하면, 몇 주 뒤 상세 화면과
/// 정산서 PDF 에서 `이미지를 불러올 수 없어요` 만 남는다.
/// (실제로 209건 중 사진이 살아있는 건 16건뿐이었다)
///
/// `getApplicationDocumentsDirectory()` 는 OS 가 건드리지 않는다.
/// 스캔 직후 여기로 **복사**해 두고, 그 경로를 영수증에 저장한다.
///
/// ## 실패해도 저장은 막지 않는다
///
/// 복사가 실패하면 원본(캐시) 경로를 그대로 돌려준다. 사진 한 장 때문에
/// 영수증 기록 자체를 못 만들게 하는 건 손해가 더 크다.
class ReceiptImageStore {
  ReceiptImageStore._();
  static final ReceiptImageStore instance = ReceiptImageStore._();

  /// 앱 문서 폴더 안의 보관 폴더 이름
  static const _folder = 'receipts';

  String? _dirPath;

  /// 보관 폴더를 준비한다(없으면 만든다).
  ///
  /// 웹에서는 앱 문서 폴더가 없어서 항상 `null` 이다. 그러면 아래
  /// [persist] 가 원본 경로를 그대로 돌려주므로 웹에서도 저장 자체는
  /// 막히지 않는다.
  Future<String?> _ensureDir() async {
    if (_dirPath != null) return _dirPath;
    final p = await ensureDocsSubdir(_folder);
    if (p == null) {
      if (kDebugMode) debugPrint('[ReceiptImage] 보관 폴더 사용 불가(웹?)');
      return null;
    }
    _dirPath = p;
    return p;
  }

  /// [sourcePath] 의 사진을 영구 폴더로 복사하고 **새 경로**를 돌려준다.
  ///
  /// - 이미 영구 폴더 안의 파일이면 그대로 돌려준다(중복 복사 방지)
  /// - 원본이 없거나 복사가 실패하면 [sourcePath] 를 그대로 돌려준다
  /// - `http` 로 시작하면 원격 이미지이므로 손대지 않는다
  Future<String> persist(String? sourcePath, {String? receiptId}) async {
    final src = sourcePath ?? '';
    if (src.isEmpty) return src;

    // 원격 URL 은 복사 대상이 아니다.
    if (src.startsWith('http')) return src;

    // 이미 우리 폴더 안이면 다시 복사할 이유가 없다.
    if (src.contains('/$_folder/')) return src;

    // ── 웹: 클라우드에 올린다 ─────────────────────────────────
    //
    // 🔴 웹에서는 여기가 유일한 영구 보관 수단이다.
    //    브라우저에서 고른 사진의 경로는 `blob:https://...` 인데, 이 URL 은
    //    **그 탭이 살아있는 동안만** 유효하다. 새로고침하면 즉시 무효가 되고
    //    캘린더/상세 화면에서 회색 자리만 남는다.
    //
    //    예전에는 아래 `localFileExists(src)` 가 웹에서 항상 `false` 라서
    //    곧 죽을 blob URL 을 그대로 저장하고 있었다. 그게 "웹에서 영수증
    //    저장하고 캘린더 가면 이미지가 없다" 의 원인이다.
    //
    //    올린 뒤 받은 `https://...` 를 저장하면 새로고침·기기 변경·브라우저
    //    삭제 후에도 사진이 그대로 보이고, 정산서 PDF 에도 붙는다.
    //
    //    저장 **직후에 바로** 올리는 것이 중요하다. 시간이 지나면 blob URL
    //    이 이미 죽어 있을 수 있다(#95 참조).
    if (kIsWeb && receiptImageUploadAvailable) {
      final url = await uploadReceiptImage(src, receiptId: receiptId);
      // 실패하면 원본을 유지한다. 사진 한 장 때문에 영수증 저장을 막지 않는다.
      // (그 세션 안에서는 blob URL 로도 보이므로 아주 못 쓰는 값은 아니다)
      return url ?? src;
    }

    if (!await localFileExists(src)) {
      if (kDebugMode) debugPrint('[ReceiptImage] 원본 없음: $src');
      return src;
    }

    final dir = await _ensureDir();
    if (dir == null) return src;

    // 확장자는 원본을 따르되, 이상한 값이면 jpg 로 둔다.
    var ext = '';
    final dot = src.lastIndexOf('.');
    if (dot > 0 && src.length - dot <= 5) {
      ext = src.substring(dot).toLowerCase();
    }
    if (ext.isEmpty) ext = '.jpg';

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final base = receiptId == null || receiptId.isEmpty
        ? 'r_$stamp'
        : 'r_${receiptId}_$stamp';
    final target = '$dir/$base$ext';

    // 사진 복사 실패로 영수증 저장을 막지 않는다. 원본 경로를 유지한다.
    if (!await copyLocalFile(src, target)) {
      if (kDebugMode) debugPrint('[ReceiptImage] 복사 실패(원본 유지): $src');
      return src;
    }
    if (kDebugMode) debugPrint('[ReceiptImage] 보관 완료: $target');
    return target;
  }

  /// 영수증을 삭제할 때 보관 사진도 함께 지운다.
  ///
  /// 우리 폴더 안의 파일만 지운다. 캐시나 갤러리 원본은 건드리지 않는다.
  Future<void> remove(String? path) async {
    final p = path ?? '';
    if (p.isEmpty) return;

    // 웹에서 올려둔 사진은 클라우드에서 지운다. 안 지우면 저장 용량만 먹는다.
    if (p.startsWith('http')) {
      if (kIsWeb && receiptImageUploadAvailable) {
        await deleteUploadedReceiptImage(p);
      }
      return;
    }

    if (!p.contains('/$_folder/')) return; // 우리가 만든 파일이 아니다
    await deleteLocalFile(p);
  }

  /// 보관된 사진이 실제로 열리는지 확인한다.
  ///
  /// 정산서 PDF 를 만들 때 "사진 없음" 을 미리 알려주려고 쓴다.
  Future<bool> exists(String? path) async {
    final p = path ?? '';
    if (p.isEmpty) return false;
    if (p.startsWith('http')) return true; // 원격은 확인하지 않는다
    return localFileExists(p);
  }
}
