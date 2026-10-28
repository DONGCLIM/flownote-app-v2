import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// 문의하기(제안 및 피드백) 저장.
///
/// 저장 위치
///   * 글      : Firestore `inquiries` 컬렉션
///   * 첨부파일 : Storage `inquiries/<uid>/<문의id>/<순번>_<파일명>`
///
/// 🔴 첨부를 먼저 올리고, 링크까지 담아서 글을 **한 번에** 쓴다.
///    글을 먼저 쓰고 링크를 나중에 붙이면, 중간에 끊겼을 때
///    "첨부가 있다고 적혀 있는데 링크가 없는" 문서가 남는다.
class InquiryService {
  InquiryService._();
  static final InquiryService instance = InquiryService._();

  /// 한 번에 올릴 수 있는 첨부 개수. (사장님 지시: 최대 3개)
  static const int maxFiles = 3;

  /// 첨부 한 개의 최대 크기. Storage 규칙(10MB)과 같은 값으로 둔다.
  /// 여기서 먼저 막아야 "올리다가 거부당함" 대신 고르는 순간 알려줄 수 있다.
  static const int maxFileBytes = 10 * 1024 * 1024;

  /// 카테고리 선택지. 화면과 저장값이 같은 목록을 쓴다.
  static const List<String> categories = <String>[
    '기능 제안',
    '오류 신고',
    '결제·구독 문의',
    '사용 방법 문의',
    '기타',
  ];

  /// 처리 상태 첫 값. 관리자가 이후에 바꾼다.
  static const String statusNew = '접수';

  /// 문의를 보낸다. 성공하면 만들어진 문서 id 를 돌려준다.
  ///
  /// 실패하면 [InquiryFailure] 를 던진다. 화면은 그 메시지를 그대로
  /// 보여주면 된다 — 사장님이 무엇을 해야 할지 알 수 있는 문장만 담았다.
  Future<String> submit({
    required String category,
    required String content,
    List<InquiryAttachment> files = const <InquiryAttachment>[],
  }) async {
    final text = content.trim();
    if (text.isEmpty) {
      throw const InquiryFailure('내용을 입력해 주세요.');
    }
    if (files.length > maxFiles) {
      throw const InquiryFailure('첨부는 최대 $maxFiles개까지 보낼 수 있어요.');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // 로그인 없이는 보낼 수 없다. 답변을 보낼 곳이 없기 때문이다.
      throw const InquiryFailure('로그인이 필요해요. 다시 로그인한 뒤 보내주세요.');
    }
    final uid = user.uid;

    // 문서 id 를 미리 만든다. 첨부 경로에 이 id 를 써야
    // 나중에 어떤 문의의 첨부인지 경로만 보고 알 수 있다.
    final doc = FirebaseFirestore.instance.collection('inquiries').doc();

    final urls = <String>[];
    final names = <String>[];
    try {
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        if (f.bytes.lengthInBytes > maxFileBytes) {
          throw InquiryFailure('${f.name} 파일이 너무 커요. 10MB 이하만 보낼 수 있어요.');
        }
        final safe = _safeName(f.name);
        final path = 'inquiries/$uid/${doc.id}/${i}_$safe';
        final ref = FirebaseStorage.instance.ref(path);
        await ref
            .putData(
              f.bytes,
              SettableMetadata(contentType: f.contentType),
            )
            .timeout(const Duration(seconds: 120));
        urls.add(await ref.getDownloadURL().timeout(const Duration(seconds: 30)));
        names.add(f.name);
      }

      await doc.set(<String, dynamic>{
        'category': category,
        'content': text,
        // 🔴 기기 시계를 믿지 않는다. 서버 시각으로 적는다.
        'createdAt': FieldValue.serverTimestamp(),
        'status': statusNew,
        'uid': uid,
        'email': user.email ?? '',
        'displayName': user.displayName ?? '',
        'attachmentUrls': urls,
        'attachmentNames': names,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      }).timeout(const Duration(seconds: 30));

      return doc.id;
    } on InquiryFailure {
      rethrow;
    } on TimeoutException {
      throw const InquiryFailure('네트워크가 느려 보내지 못했어요. 잠시 뒤 다시 시도해 주세요.');
    } on FirebaseException catch (e) {
      debugPrint('[inquiry] ${e.plugin}/${e.code}: ${e.message}');
      if (e.code == 'permission-denied' || e.code == 'unauthorized') {
        throw const InquiryFailure('보낼 권한이 없어요. 로그아웃 후 다시 로그인해 주세요.');
      }
      throw const InquiryFailure('문의를 보내지 못했어요. 잠시 뒤 다시 시도해 주세요.');
    } catch (e) {
      debugPrint('[inquiry] 실패: $e');
      throw const InquiryFailure('문의를 보내지 못했어요. 잠시 뒤 다시 시도해 주세요.');
    }
  }

  /// 파일 이름에서 경로를 깨뜨릴 수 있는 글자를 지운다.
  /// 한글은 그대로 둔다 — Storage 는 UTF-8 이름을 받는다.
  static String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[/\\?%*:|"<>\x00-\x1F]'), '_');
    return cleaned.length <= 80 ? cleaned : cleaned.substring(0, 80);
  }
}

/// 첨부 한 개.
@immutable
class InquiryAttachment {
  const InquiryAttachment({
    required this.name,
    required this.bytes,
    required this.contentType,
  });

  final String name;
  final Uint8List bytes;
  final String contentType;

  /// 화면에 보여줄 크기 (`2.3MB`).
  String get sizeLabel {
    final kb = bytes.lengthInBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)}KB';
    return '${(kb / 1024).toStringAsFixed(1)}MB';
  }

  bool get isImage => contentType.startsWith('image/');
}

/// 사장님께 그대로 보여줄 수 있는 실패 사유.
class InquiryFailure implements Exception {
  const InquiryFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
