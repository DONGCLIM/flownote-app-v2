import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/user_model.dart';
import '../models/receipt_model.dart';

/// Firestore `users/{uid}` 문서를 다루는 저장소.
///
/// 구조:
///   users/{uid}                     ← UserModel (개인정보 + 사업자정보 + 동의이력)
///   users/{uid}/receipts/{id}       ← 영수증 백업 (기기 변경 시 복원용)
///
/// Firebase가 초기화되지 않은 환경(웹 미설정 등)에서는 `isAvailable == false`가 되고
/// 모든 메서드가 조용히 no-op 하거나 null을 돌려준다. → 앱이 죽지 않는다.
class UserRepository {
  UserRepository._();
  static final UserRepository instance = UserRepository._();

  FirebaseFirestore? _db;
  bool _initialized = false;

  static const String _usersCol = 'users';
  static const String _receiptsCol = 'receipts';

  void init() {
    if (_initialized) return;
    try {
      if (Firebase.apps.isEmpty) return;
      _db = FirebaseFirestore.instance;
      _initialized = true;
    } catch (_) {
      _db = null;
      _initialized = false;
    }
  }

  bool get isAvailable => _initialized && _db != null;

  DocumentReference<Map<String, dynamic>>? _userDoc(String uid) =>
      isAvailable ? _db!.collection(_usersCol).doc(uid) : null;

  // ---------------------------------------------------------------- 사용자 문서

  /// 사용자 문서를 읽어 온다. 없으면 null.
  Future<UserModel?> fetch(String uid) async {
    final doc = _userDoc(uid);
    if (doc == null) return null;
    try {
      final snap = await doc.get();
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      return UserModel.fromMap(_normalize(uid, data));
    } catch (_) {
      return null;
    }
  }

  /// 회원가입 직후 최초 문서를 만든다. 이미 있으면 merge만 한다.
  Future<void> createIfAbsent(UserModel user) async {
    final doc = _userDoc(user.id);
    if (doc == null) return;
    try {
      final snap = await doc.get();
      if (snap.exists) {
        // 로그인 시 갱신되어야 하는 값만 살짝 덮어쓴다.
        await doc.set({
          'email': user.email,
          'provider': user.provider,
          if (user.photoUrl.isNotEmpty) 'photoUrl': user.photoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }
      await doc.set({
        ...user.toMap(),
        'createdAt': user.createdAt.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // 오프라인이면 Firestore SDK가 자체 큐에 담아두므로 무시해도 안전
    }
  }

  /// 전체 사용자 정보를 저장(merge)한다.
  Future<void> save(UserModel user) async {
    final doc = _userDoc(user.id);
    if (doc == null) return;
    try {
      await doc.set({
        ...user.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// 일부 필드만 갱신한다.
  Future<void> update(String uid, Map<String, dynamic> patch) async {
    final doc = _userDoc(uid);
    if (doc == null) return;
    try {
      await doc.set({
        ...patch,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// 약관 동의 이력을 기록한다. (개인정보보호법상 동의 시점/버전 보관 의무)
  Future<void> recordConsents(
    String uid,
    UserConsents consents, {
    String? appVersion,
  }) async {
    final doc = _userDoc(uid);
    if (doc == null) return;
    try {
      await doc.set({
        'consents': consents.toMap(),
        if (appVersion != null) 'consentAppVersion': appVersion,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 감사(audit) 목적의 append-only 이력
      await doc.collection('consent_log').add({
        'consents': consents.toMap(),
        if (appVersion != null) 'appVersion': appVersion,
        'at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 영수증 백업

  /// 영수증 1건을 클라우드에 백업한다.
  Future<void> backupReceipt(String uid, ReceiptModel r) async {
    final doc = _userDoc(uid);
    if (doc == null) return;
    try {
      await doc.collection(_receiptsCol).doc(r.id).set({
        'id': r.id,
        'storeName': r.storeName,
        'date': r.date.toIso8601String(),
        'totalAmount': r.totalAmount,
        'createdAt': r.createdAt.toIso8601String(),
        'rawOcrText': r.rawOcrText,
        'imagePath': r.imagePath,
        'isManuallyEdited': r.isManuallyEdited,
        'items': r.items
            .map((i) => {
                  'name': i.name,
                  'quantity': i.quantity,
                  'unitPrice': i.unitPrice,
                  'unit': i.unit,
                  'color': i.color,
                })
            .toList(),
        'syncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// 여러 건을 배치로 백업한다. (재접속 시 일괄 업로드)
  Future<int> backupReceipts(String uid, List<ReceiptModel> list) async {
    if (!isAvailable || list.isEmpty) return 0;
    var done = 0;
    // Firestore 배치 한도 500
    for (var i = 0; i < list.length; i += 400) {
      final chunk = list.sublist(i, (i + 400).clamp(0, list.length));
      try {
        final batch = _db!.batch();
        for (final r in chunk) {
          final ref =
              _db!.collection(_usersCol).doc(uid).collection(_receiptsCol).doc(r.id);
          batch.set(ref, {
            'id': r.id,
            'storeName': r.storeName,
            'date': r.date.toIso8601String(),
            'totalAmount': r.totalAmount,
            'createdAt': r.createdAt.toIso8601String(),
            'rawOcrText': r.rawOcrText,
            'imagePath': r.imagePath,
            'isManuallyEdited': r.isManuallyEdited,
            'items': r.items
                .map((it) => {
                      'name': it.name,
                      'quantity': it.quantity,
                      'unitPrice': it.unitPrice,
                      'unit': it.unit,
                      'color': it.color,
                    })
                .toList(),
            'syncedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await batch.commit();
        done += chunk.length;
      } catch (_) {}
    }
    return done;
  }

  Future<void> deleteReceiptBackup(String uid, String receiptId) async {
    final doc = _userDoc(uid);
    if (doc == null) return;
    try {
      await doc.collection(_receiptsCol).doc(receiptId).delete();
    } catch (_) {}
  }

  /// 클라우드에 백업된 영수증을 모두 내려받는다. (기기 변경 복원)
  Future<List<ReceiptModel>> restoreReceipts(String uid) async {
    final doc = _userDoc(uid);
    if (doc == null) return [];
    try {
      final snap = await doc.collection(_receiptsCol).get();
      return snap.docs.map((d) {
        final m = d.data();
        final rawItems = (m['items'] as List?) ?? const [];
        return ReceiptModel(
          id: m['id'] as String? ?? d.id,
          storeName: m['storeName'] as String? ?? '',
          date: DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
          totalAmount: (m['totalAmount'] as num?)?.toDouble() ?? 0,
          createdAt:
              DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
          rawOcrText: m['rawOcrText'] as String? ?? '',
          imagePath: m['imagePath'] as String?,
          isManuallyEdited: m['isManuallyEdited'] as bool? ?? false,
          items: rawItems.map((raw) {
            final it = Map<String, dynamic>.from(raw as Map);
            return FlowerItem(
              name: it['name'] as String? ?? '',
              quantity: (it['quantity'] as num?)?.toInt() ?? 0,
              unitPrice: (it['unitPrice'] as num?)?.toDouble() ?? 0,
              unit: it['unit'] as String? ?? '송이',
              color: it['color'] as String?,
            );
          }).toList(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------- 회원 탈퇴

  /// 회원 탈퇴 시 클라우드에 저장된 모든 개인정보를 삭제한다.
  /// (users/{uid} 문서 + receipts 서브컬렉션 + consent_log 서브컬렉션)
  Future<void> deleteAllUserData(String uid) async {
    final doc = _userDoc(uid);
    if (doc == null) return;
    try {
      await _deleteCollection(doc.collection(_receiptsCol));
      await _deleteCollection(doc.collection('consent_log'));
      await doc.delete();
    } catch (_) {}
  }

  Future<void> _deleteCollection(CollectionReference<Map<String, dynamic>> col) async {
    while (true) {
      final snap = await col.limit(300).get();
      if (snap.docs.isEmpty) return;
      final batch = _db!.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < 300) return;
    }
  }

  // ---------------------------------------------------------------- helpers

  /// Firestore Timestamp / 누락 필드를 UserModel.fromMap이 이해하는 형태로 보정
  Map<String, dynamic> _normalize(String uid, Map<String, dynamic> data) {
    final out = Map<String, dynamic>.from(data);
    out['id'] = uid;
    final created = out['createdAt'];
    if (created is Timestamp) {
      out['createdAt'] = created.toDate().toIso8601String();
    } else if (created is! String) {
      out['createdAt'] = DateTime.now().toIso8601String();
    }
    out.remove('updatedAt');
    out.remove('lastLoginAt');
    out.remove('consentAppVersion');
    return out;
  }
}
