import 'dart:async';
import 'dart:js_interop';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'auth_service.dart';

/// 웹에서는 클라우드 업로드가 유일한 영구 보관 수단이다.
bool get receiptImageUploadAvailable => true;

/// 사진 한 장을 Firebase Storage 에 올리고 **영구 https URL** 을 돌려준다.
///
/// [source] 는 `blob:` URL 이다(브라우저에서 고른 사진).
/// 이미 `http` 로 시작하면 이미 올라간 것이므로 그대로 돌려준다.
///
/// 실패하면 `null` — 호출부는 원래 값을 유지한다. 사진 하나 때문에
/// 영수증 저장 자체가 막히면 안 된다.
Future<String?> uploadReceiptImage(
  String source, {
  String? receiptId,
}) async {
  if (source.isEmpty) return null;

  // 이미 영구 URL 이면 다시 올릴 이유가 없다(중복 업로드 · 요금 방지).
  if (source.startsWith('http')) return source;

  final uid = AuthService.instance.uid;
  if (uid == null || uid.isEmpty) {
    // 게스트는 올릴 곳이 없다. 규칙이 `request.auth.uid == uid` 라서
    // 로그인하지 않으면 거부된다. 조용히 포기한다.
    debugPrint('[receiptImage] 로그인 상태가 아니라 업로드를 건너뜁니다');
    return null;
  }

  // 1) blob URL 에서 실제 바이트를 꺼낸다.
  final bytes = await _readBlobUrl(source);
  if (bytes == null || bytes.isEmpty) {
    debugPrint('[receiptImage] 사진 바이트를 읽지 못했습니다: '
        '${source.length > 48 ? '${source.substring(0, 48)}…' : source}');
    return null;
  }

  // 2) Storage 에 올린다.
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final base = receiptId == null || receiptId.isEmpty
      ? 'r_$stamp'
      : 'r_${receiptId}_$stamp';
  final path = 'users/$uid/receipts/$base.jpg';

  try {
    final ref = FirebaseStorage.instance.ref(path);
    await ref
        .putData(
          bytes,
          SettableMetadata(
            contentType: 'image/jpeg',
            // 브라우저가 오래 캐시해도 안전하다. 파일명이 매번 다르다.
            cacheControl: 'public, max-age=31536000, immutable',
          ),
        )
        .timeout(const Duration(seconds: 90));

    final url = await ref.getDownloadURL().timeout(const Duration(seconds: 30));
    debugPrint('[receiptImage] 업로드 완료 '
        '${(bytes.lengthInBytes / 1024).round()}KB → $path');
    return url;
  } on TimeoutException {
    debugPrint('[receiptImage] 업로드 시간 초과 — 원본 경로 유지');
    return null;
  } catch (e) {
    debugPrint('[receiptImage] 업로드 실패 — 원본 경로 유지: $e');
    return null;
  }
}

/// 영수증을 지울 때 올려둔 사진도 함께 지운다.
///
/// 우리가 올린 URL(`users/<uid>/receipts/`)만 지운다. 다른 원격 이미지는
/// 건드리지 않는다. 실패해도 조용히 넘긴다 — 영수증 삭제를 막으면 안 된다.
Future<void> deleteUploadedReceiptImage(String url) async {
  if (url.isEmpty || !url.startsWith('http')) return;
  if (!url.contains('%2Freceipts%2F') && !url.contains('/receipts/')) return;

  try {
    await FirebaseStorage.instance
        .refFromURL(url)
        .delete()
        .timeout(const Duration(seconds: 20));
    debugPrint('[receiptImage] 업로드 사진 삭제 완료');
  } catch (e) {
    debugPrint('[receiptImage] 업로드 사진 삭제 실패(무시): $e');
  }
}

/// `blob:` URL 에서 바이트를 꺼낸다.
///
/// 🔴 여기서 실패할 수 있다는 점이 중요하다.
///    `blob:` URL 은 언제든 무효가 될 수 있다(#95 참조). 그래서 저장
///    **직후에 바로** 올려야 한다. 시간이 지난 뒤에 올리려고 하면
///    이미 죽어 있을 수 있다.
///
/// `fetch` 를 쓴다. XHR 보다 코드가 짧고 `arrayBuffer()` 가 바로 있다.
Future<Uint8List?> _readBlobUrl(String url) async {
  try {
    final resp = await web.window
        .fetch(url.toJS)
        .toDart
        .timeout(const Duration(seconds: 30));
    if (!resp.ok) {
      debugPrint('[receiptImage] blob 읽기 실패 status=${resp.status}');
      return null;
    }
    final buf = await resp.arrayBuffer().toDart;
    return buf.toDart.asUint8List();
  } catch (e) {
    debugPrint('[receiptImage] blob 읽기 예외: $e');
    return null;
  }
}
