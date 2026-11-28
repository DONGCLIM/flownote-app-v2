import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// 문의(제안 및 피드백) 저장·조회.
///
/// ## 저장 위치
///   * 글      : Firestore `inquiries`
///   * 첨부사진 : Storage `inquiries/<uid>/<문의id>/<순번>_<파일명>`
///
/// ## 누가 무엇을 할 수 있나
///
/// | | 사장님(작성자) | 관리자 |
/// |---|---|---|
/// | 읽기 | 본인 글만 | 전부 |
/// | 수정 | 본인 글, **접수 상태일 때만**, 카테고리·내용·첨부만 | 답변 |
/// | 삭제 | 본인 글, 언제든 | 전부 |
/// | 답변 | 불가 | 작성·수정·삭제 |
///
/// 🔴 이 표는 [firestore.rules] 에도 **같은 내용으로** 적혀 있다.
///    앱에서만 막으면 누구든 서버에 직접 요청해서 뚫을 수 있다.
///    한쪽만 고치면 "앱은 되는데 저장이 안 됨" 이 된다. 늘 같이 고친다.
class InquiryService {
  InquiryService._();
  static final InquiryService instance = InquiryService._();

  /// 관리자 계정.
  ///
  /// 🔴 이 주소를 바꾸면 `firestore.rules` 와 `storage.rules` 의
  ///    `isAdmin()` 도 **반드시 같이** 바꿔야 한다.
  static const String adminEmail = 'flownote.kr@gmail.com';

  /// 첨부 장수. (사장님 지시: 최대 3장)
  static const int maxFiles = 3;

  /// 첨부 한 장의 상한. 올리기 전에 1MB 근처로 줄이므로 넉넉한 안전선이다.
  /// Storage 규칙의 5MB 와 맞춰 둔다.
  static const int maxFileBytes = 5 * 1024 * 1024;

  /// 압축 목표 — 긴 쪽 픽셀 / 장당 바이트.
  static const int targetLongSide = 1600;
  static const int targetBytes = 1024 * 1024;

  static const List<String> categories = <String>[
    '기능 제안',
    '오류 신고',
    '결제·구독 문의',
    '사용 방법 문의',
    '기타',
  ];

  static const String statusNew = '접수';
  static const String statusAnswered = '답변완료';

  /// 지금 로그인한 사람이 관리자인가.
  ///
  /// 🔴 `displayName` 이나 앱에 저장된 값으로 판단하지 않는다.
  ///    그런 값은 사용자가 바꿀 수 있다. 로그인 제공자가 확인해 준
  ///    이메일만 믿는다.
  static bool get isAdmin {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return false;
    final e = (u.email ?? '').trim().toLowerCase();
    return e == adminEmail;
  }

  /// 내가 쓴 글인가. 화면에서 수정·삭제 버튼을 보일지 고를 때 쓴다.
  static bool isMine(Inquiry item) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && uid.isNotEmpty && item.uid == uid;
  }

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('inquiries');

  // ── 읽기 ───────────────────────────────────────────────────

  /// 목록.
  ///
  /// * 사장님 → 본인 글만
  /// * 관리자 → 전부, **답변 안 한 것 먼저**
  ///
  /// 🔴 정렬을 서버 쿼리로 하지 않고 받아와서 한다.
  ///    `where(uid) + orderBy(createdAt)` 은 Firestore 복합 색인을 따로
  ///    만들어야 하고, 색인이 없으면 목록이 통째로 안 뜬다.
  ///    문의는 많아야 수백 건이라 받아서 줄 세우는 편이 안전하다.
  Stream<List<Inquiry>> watch() {
    final admin = isAdmin;
    final uid = _uid;
    if (uid == null) return Stream.value(const <Inquiry>[]);

    final q = admin ? _col : _col.where('uid', isEqualTo: uid);
    return q.snapshots().map((snap) {
      final list = snap.docs.map(Inquiry.fromDoc).toList();
      list.sort((a, b) {
        if (admin) {
          // 미답변 먼저.
          final ao = a.isAnswered ? 1 : 0;
          final bo = b.isAnswered ? 1 : 0;
          if (ao != bo) return ao - bo;
        }
        return b.sortTime.compareTo(a.sortTime); // 최신 먼저
      });
      return list;
    });
  }

  /// 한 건. 화면이 열려 있는 동안 답변이 달리면 바로 보이도록 스트림이다.
  Stream<Inquiry?> watchOne(String id) =>
      _col.doc(id).snapshots().map((d) => d.exists ? Inquiry.fromDoc(d) : null);

  // ── 쓰기 ───────────────────────────────────────────────────

  /// 새 문의. 성공하면 문서 id 를 돌려준다.
  ///
  /// 🔴 첨부를 먼저 올리고 링크까지 담아 글을 **한 번에** 쓴다.
  ///    글을 먼저 쓰고 링크를 나중에 붙이면 중간에 끊겼을 때
  ///    "첨부가 있다는데 링크가 없는" 문서가 남는다.
  Future<String> submit({
    required String category,
    required String content,
    List<InquiryAttachment> files = const <InquiryAttachment>[],
  }) async {
    final text = _checkContent(content);
    final user = _requireUser();
    _checkFiles(files);

    final doc = _col.doc();
    try {
      final up = await _uploadAll(user.uid, doc.id, files, startAt: 0);
      await doc.set(<String, dynamic>{
        'category': category,
        'content': text,
        // 기기 시계를 믿지 않는다. 서버 시각으로 적는다.
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'status': statusNew,
        'answer': '',
        'answeredAt': null,
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': user.displayName ?? '',
        'attachmentUrls': up.urls,
        'attachmentNames': up.names,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      }).timeout(const Duration(seconds: 30));
      return doc.id;
    } catch (e) {
      throw _wrap(e);
    }
  }

  /// 본인 글 수정. 접수 상태일 때만, 카테고리·내용·첨부만 바뀐다.
  ///
  /// [keepUrls] 는 그대로 둘 기존 첨부 링크, [added] 는 새로 고른 사진이다.
  /// 목록에서 빠진 기존 첨부는 Storage 에서도 지운다.
  Future<void> update({
    required Inquiry origin,
    required String category,
    required String content,
    required List<String> keepUrls,
    List<InquiryAttachment> added = const <InquiryAttachment>[],
  }) async {
    final text = _checkContent(content);
    final user = _requireUser();

    if (origin.uid != user.uid) {
      throw const InquiryFailure('내가 쓴 문의만 고칠 수 있어요.');
    }
    if (origin.isAnswered) {
      throw const InquiryFailure('답변이 달린 문의는 고칠 수 없어요.');
    }
    if (keepUrls.length + added.length > maxFiles) {
      throw const InquiryFailure('사진은 최대 $maxFiles장까지예요.');
    }
    _checkFiles(added);

    try {
      // 남길 첨부의 이름을 원래 순서대로 추려 둔다.
      final keepNames = <String>[];
      for (final u in keepUrls) {
        final i = origin.attachmentUrls.indexOf(u);
        keepNames.add(i >= 0 && i < origin.attachmentNames.length
            ? origin.attachmentNames[i]
            : '사진');
      }

      final up = await _uploadAll(user.uid, origin.id, added,
          startAt: DateTime.now().millisecondsSinceEpoch % 100000);

      await _col.doc(origin.id).update(<String, dynamic>{
        'category': category,
        'content': text,
        'attachmentUrls': [...keepUrls, ...up.urls],
        'attachmentNames': [...keepNames, ...up.names],
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 30));

      // 글이 바뀐 다음에 지운다. 먼저 지웠다가 글 수정이 실패하면
      // 화면에는 남아 있는데 파일은 사라진 상태가 된다.
      for (final old in origin.attachmentUrls) {
        if (!keepUrls.contains(old)) {
          await _deleteByUrl(old);
        }
      }
    } catch (e) {
      throw _wrap(e);
    }
  }

  /// 삭제. 첨부 사진도 Storage 에서 함께 지운다.
  Future<void> delete(Inquiry item) async {
    final user = _requireUser();
    if (!isAdmin && item.uid != user.uid) {
      throw const InquiryFailure('내가 쓴 문의만 지울 수 있어요.');
    }
    try {
      // 🔴 파일을 먼저 지운다. 글을 먼저 지우면 링크를 잃어버려서
      //    Storage 에 주인 없는 파일이 영원히 남는다.
      for (final u in item.attachmentUrls) {
        await _deleteByUrl(u);
      }
      await _col.doc(item.id).delete().timeout(const Duration(seconds: 30));
    } catch (e) {
      throw _wrap(e);
    }
  }

  // ── 관리자: 답변 ────────────────────────────────────────────

  /// 답변 작성/수정. 관리자만.
  Future<void> saveAnswer(String id, String answer) async {
    if (!isAdmin) throw const InquiryFailure('관리자만 답변할 수 있어요.');
    final text = answer.trim();
    if (text.isEmpty) throw const InquiryFailure('답변 내용을 입력해 주세요.');
    try {
      await _col.doc(id).update(<String, dynamic>{
        'answer': text,
        'answeredAt': FieldValue.serverTimestamp(),
        'status': statusAnswered,
      }).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw _wrap(e);
    }
  }

  /// 답변 삭제 → 다시 '접수' 로 되돌린다. 관리자만.
  Future<void> deleteAnswer(String id) async {
    if (!isAdmin) throw const InquiryFailure('관리자만 답변을 지울 수 있어요.');
    try {
      await _col.doc(id).update(<String, dynamic>{
        'answer': '',
        'answeredAt': null,
        'status': statusNew,
      }).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw _wrap(e);
    }
  }

  // ── 안쪽 도우미 ─────────────────────────────────────────────

  static String _checkContent(String content) {
    final t = content.trim();
    if (t.isEmpty) throw const InquiryFailure('내용을 입력해 주세요.');
    if (t.length > 1000) throw const InquiryFailure('내용은 1,000자까지 쓸 수 있어요.');
    return t;
  }

  static User _requireUser() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      // 로그인 없이는 보낼 수 없다. 답변을 보낼 곳이 없기 때문이다.
      throw const InquiryFailure('로그인이 필요해요. 다시 로그인한 뒤 보내주세요.');
    }
    return u;
  }

  static void _checkFiles(List<InquiryAttachment> files) {
    if (files.length > maxFiles) {
      throw const InquiryFailure('사진은 최대 $maxFiles장까지예요.');
    }
    for (final f in files) {
      if (!f.isImage) {
        throw const InquiryFailure('사진만 첨부할 수 있어요.');
      }
      if (f.bytes.lengthInBytes > maxFileBytes) {
        throw InquiryFailure('${f.name} 이(가) 너무 커요. 다른 사진을 골라 주세요.');
      }
    }
  }

  Future<_Uploaded> _uploadAll(
    String uid,
    String docId,
    List<InquiryAttachment> files, {
    required int startAt,
  }) async {
    final urls = <String>[];
    final names = <String>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final path = 'inquiries/$uid/$docId/${startAt + i}_${_safeName(f.name)}';
      final ref = FirebaseStorage.instance.ref(path);
      await ref
          .putData(f.bytes, SettableMetadata(contentType: f.contentType))
          .timeout(const Duration(seconds: 120));
      urls.add(await ref.getDownloadURL().timeout(const Duration(seconds: 30)));
      names.add(f.name);
    }
    return _Uploaded(urls, names);
  }

  /// 링크로 Storage 파일을 지운다.
  ///
  /// 실패해도 넘어간다 — 이미 지워졌거나 권한이 없을 수 있는데,
  /// 그 때문에 글 삭제 자체를 막으면 사장님만 곤란해진다.
  Future<void> _deleteByUrl(String url) async {
    if (url.isEmpty || !url.startsWith('http')) return;
    try {
      await FirebaseStorage.instance
          .refFromURL(url)
          .delete()
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[inquiry] 첨부 삭제 실패(무시): $e');
    }
  }

  /// 파일 이름에서 경로를 깨뜨릴 수 있는 글자를 지운다.
  /// 한글은 그대로 둔다 — Storage 는 UTF-8 이름을 받는다.
  static String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[/\\?%*:|"<>\x00-\x1F]'), '_');
    return cleaned.length <= 80 ? cleaned : cleaned.substring(0, 80);
  }

  /// 어떤 예외든 사장님이 읽을 수 있는 문장으로 바꾼다.
  static InquiryFailure _wrap(Object e) {
    if (e is InquiryFailure) return e;
    if (e is TimeoutException) {
      return const InquiryFailure('네트워크가 느려 처리하지 못했어요. 잠시 뒤 다시 시도해 주세요.');
    }
    if (e is FirebaseException) {
      debugPrint('[inquiry] ${e.plugin}/${e.code}: ${e.message}');
      if (e.code == 'permission-denied' || e.code == 'unauthorized') {
        return const InquiryFailure('권한이 없어요. 로그아웃 후 다시 로그인해 주세요.');
      }
      return const InquiryFailure('처리하지 못했어요. 잠시 뒤 다시 시도해 주세요.');
    }
    debugPrint('[inquiry] 실패: $e');
    return const InquiryFailure('처리하지 못했어요. 잠시 뒤 다시 시도해 주세요.');
  }
}

class _Uploaded {
  const _Uploaded(this.urls, this.names);
  final List<String> urls;
  final List<String> names;
}

/// 저장된 문의 한 건.
@immutable
class Inquiry {
  const Inquiry({
    required this.id,
    required this.uid,
    required this.email,
    required this.displayName,
    required this.category,
    required this.content,
    required this.status,
    required this.answer,
    required this.createdAt,
    required this.answeredAt,
    required this.attachmentUrls,
    required this.attachmentNames,
  });

  final String id;
  final String uid;
  final String email;
  final String displayName;
  final String category;
  final String content;
  final String status;
  final String answer;
  final DateTime? createdAt;
  final DateTime? answeredAt;
  final List<String> attachmentUrls;
  final List<String> attachmentNames;

  bool get isAnswered => answer.trim().isNotEmpty;

  /// 작성자가 고칠 수 있는 상태인가. (답변 전에만)
  bool get editable => !isAnswered;

  /// 목록 정렬용. `createdAt` 은 서버가 적어줄 때까지 잠깐 null 이다.
  DateTime get sortTime => createdAt ?? DateTime.now();

  /// `26.09.18` 표기.
  String get ymd {
    final d = createdAt;
    if (d == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.year % 100)}.${two(d.month)}.${two(d.day)}';
  }

  /// 목록에서 보여줄 작성자. 관리자 화면에서만 쓴다.
  String get writerLabel =>
      email.isNotEmpty ? email : (displayName.isNotEmpty ? displayName : uid);

  static Inquiry fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : null;
    List<String> strs(Object? v) =>
        v is List ? v.map((e) => '$e').toList() : const <String>[];
    return Inquiry(
      id: d.id,
      uid: m['uid'] as String? ?? '',
      email: m['email'] as String? ?? '',
      displayName: m['displayName'] as String? ?? '',
      category: m['category'] as String? ?? '',
      content: m['content'] as String? ?? '',
      status: m['status'] as String? ?? InquiryService.statusNew,
      answer: m['answer'] as String? ?? '',
      createdAt: ts(m['createdAt']),
      answeredAt: ts(m['answeredAt']),
      attachmentUrls: strs(m['attachmentUrls']),
      attachmentNames: strs(m['attachmentNames']),
    );
  }
}

/// 첨부 한 장 (아직 올리기 전).
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
