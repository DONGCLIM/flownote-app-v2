import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'inquiry_service.dart';

/// 문의 첨부 고르기.
///
/// 두 길을 준다. 사장님이 화면에서 무엇을 고를지 먼저 묻는다.
///   * 앨범 : [ImagePicker] — 사진만. 안드로이드/아이폰 기본 사진 선택기.
///   * 파일 : [FilePicker]  — PDF·엑셀 등 아무 파일.
///
/// 🔴 `photo_manager`(앱 안에서 직접 그리는 갤러리)를 쓰지 않았다.
///    그건 영수증을 여러 장 고르려고 만든 화면이고, 권한을 더 많이
///    요구한다. 첨부는 많아야 3개라 OS 기본 선택기로 충분하다.
class InquiryPicker {
  InquiryPicker._();

  /// 앨범에서 사진을 고른다. [remaining] 개까지만 받는다.
  static Future<List<InquiryAttachment>> pickImages(int remaining) async {
    if (remaining <= 0) return const [];
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      // 첨부는 '보여주기' 용이다. 원본 그대로 올리면 한 장에 8MB 가
      // 넘어 10MB 제한에 걸리고, 사장님 데이터도 축낸다.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked.isEmpty) return const [];

    final out = <InquiryAttachment>[];
    for (final x in picked.take(remaining)) {
      final bytes = await x.readAsBytes();
      out.add(InquiryAttachment(
        name: x.name,
        bytes: bytes,
        contentType: x.mimeType ?? _guessType(x.name),
      ));
    }
    return out;
  }

  /// 파일에서 고른다.
  static Future<List<InquiryAttachment>> pickFiles(int remaining) async {
    if (remaining <= 0) return const [];
    // 🔴 file_picker 11 부터는 `FilePicker.platform.pickFiles` 가 아니라
    //    **정적 호출**이다. `.platform` 을 쓰면 컴파일이 안 된다.
    final res = await FilePicker.pickFiles(
      allowMultiple: true,
      // 웹에서는 바이트를 직접 받아야 한다. 경로가 없기 때문이다.
      // 네이티브에서도 withData 를 켜면 경로 분기가 사라진다.
      withData: true,
    );
    if (res == null || res.files.isEmpty) return const [];

    final out = <InquiryAttachment>[];
    for (final f in res.files.take(remaining)) {
      final Uint8List? bytes = f.bytes;
      if (bytes == null) {
        // 바이트를 못 읽은 파일은 조용히 거른다. 올려봐야 빈 파일이 된다.
        debugPrint('[inquiry] 바이트를 읽지 못해 건너뜀: ${f.name}');
        continue;
      }
      out.add(InquiryAttachment(
        name: f.name,
        bytes: bytes,
        contentType: _guessType(f.name),
      ));
    }
    return out;
  }

  static String _guessType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic')) return 'image/heic';
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.csv')) return 'text/csv';
    if (n.endsWith('.txt')) return 'text/plain';
    if (n.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }
}
