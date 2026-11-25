import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/gemini_ocr_service.dart';
import '../services/receipt_parser.dart';
import 'auth_service.dart';
import 'guest_service.dart';

/// 학습 데이터 수집 서비스
/// 저장하는 3가지:
///   1. 원본 영수증 이미지 (Firebase Storage)
///   2. AI 인식 결과 (Gemini OCR raw output)
///   3. 사용자 최종 수정본 (label)
class TrainingDataService {
  static final TrainingDataService _instance = TrainingDataService._();
  factory TrainingDataService() => _instance;
  TrainingDataService._();

  static const String _collection = 'training_data';

  FirebaseFirestore? _db;
  FirebaseStorage? _storage;
  bool _initialized = false;

  // ────────────────────────────────────────
  // 초기화
  // ────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    try {
      // Firebase가 이미 초기화된 경우 사용, 아니면 초기화
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _db = FirebaseFirestore.instance;
      _storage = FirebaseStorage.instance;
      _initialized = true;
      if (kDebugMode) debugPrint('[TrainingData] Firebase 초기화 완료');
    } catch (e) {
      if (kDebugMode) debugPrint('[TrainingData] 초기화 실패: $e');
    }
  }

  bool get isAvailable => _initialized && _db != null && _storage != null;

  /// 이 영수증을 **학습 데이터로 모아도 되는가.** (#195)
  ///
  /// 🔴 게스트는 안 된다. 막는 이유가 보안이 아니라 **동의**다. 게스트는
  ///    가입 절차가 없어서 **학습 활용 동의를 받은 적이 없다.** 동의 없이
  ///    남의 영수증을 학습에 쓰면 안 된다.
  ///
  /// 🔴 막는 일을 **앱이 한다.** 보안 규칙의 `training_data` 와
  ///    `receipts/**` 는 건드리지 않는다. 그 두 줄이 #194 에서 회원
  ///    영수증 저장을 막았던 자리다 — 게스트 전용이 아니라 **회원이
  ///    영수증을 찍을 때마다 지나는 길**이었다. 다시는 손대지 않는다.
  ///
  /// 🔴 판정이 흔들리면 **회원 쪽으로 기운다.** `isGuest` 가 false 면
  ///    예전과 완전히 똑같이 돈다.
  static bool get collectAllowed => !GuestService.instance.isGuest;

  // ────────────────────────────────────────
  // STEP 1: 스캔 직후 → 이미지 + AI결과 저장
  // 반환값: docId (나중에 사용자 수정본 저장에 사용)
  // ────────────────────────────────────────
  Future<String?> saveInitialScan({
    required String? imagePath,       // 원본 이미지 경로 (null이면 수동입력)
    required GeminiOcrResult aiResult, // Gemini OCR 결과
    String? userId,                   // 미지정 시 로그인한 Firebase uid 사용
  }) async {
    if (!isAvailable) return null;

    // 🔴 게스트 영수증은 학습 데이터로 보내지 않는다 (#195 — 동의가 없다).
    //    `receipts/**` 이미지 업로드도 이 아래에 있으므로 같이 건너뛴다.
    if (!collectAllowed) {
      if (kDebugMode) debugPrint('[TrainingData] 게스트 — 학습 수집 건너뜀');
      return null;
    }

    try {
      final docId = _generateDocId();
      String? imageUrl;

      // 1) 이미지 업로드 (경로가 있을 때만)
      if (imagePath != null && imagePath.isNotEmpty) {
        imageUrl = await _uploadImage(imagePath, docId);
      }

      // 2) AI 결과를 Map으로 변환
      final aiMap = _geminiResultToMap(aiResult);

      // 3) Firestore에 문서 생성
      await _db!.collection(_collection).doc(docId).set({
        'doc_id': docId,
        'user_id': userId ?? AuthService.instance.uid ?? 'unknown',
        'image_url': imageUrl,
        'ai_result': aiMap,
        'user_label': null,        // 아직 수정 전
        'is_corrected': false,
        'is_manual': imagePath == null,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'status': 'pending',       // pending → labeled
      });

      if (kDebugMode) debugPrint('[TrainingData] 초기 저장 완료: $docId');
      return docId;
    } catch (e) {
      if (kDebugMode) debugPrint('[TrainingData] 초기 저장 실패: $e');
      return null;
    }
  }

  // ────────────────────────────────────────
  // STEP 2: 사용자가 편집 완료 → 수정본(label) 저장
  // ────────────────────────────────────────
  Future<void> saveUserLabel({
    required String docId,
    required ParsedReceipt userEdited, // 사용자 최종 수정본
  }) async {
    if (!isAvailable || docId.isEmpty) return;
    // 🔴 수정본도 같은 이유로 보내지 않는다 (#195).
    if (!collectAllowed) return;

    try {
      final labelMap = _parsedReceiptToMap(userEdited);

      await _db!.collection(_collection).doc(docId).update({
        'user_label': labelMap,
        'is_corrected': true,
        'status': 'labeled',
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) debugPrint('[TrainingData] 수정본 저장 완료: $docId');
    } catch (e) {
      if (kDebugMode) debugPrint('[TrainingData] 수정본 저장 실패: $e');
    }
  }

  // ────────────────────────────────────────
  // 이미지 Firebase Storage 업로드
  // ────────────────────────────────────────
  Future<String?> _uploadImage(String localPath, String docId) async {
    // 🔴 `receipts/**` 학습 이미지. 부르는 곳이 늘어나도 게스트 사진이
    //    새지 않도록 여기서 한 번 더 막는다 (#195).
    if (!collectAllowed) return null;
    try {
      final file = File(localPath);
      if (!await file.exists()) return null;

      final ext = localPath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final ref = _storage!.ref('receipts/$docId.$ext');

      final metadata = SettableMetadata(
        contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
        customMetadata: {'doc_id': docId},
      );

      await ref.putFile(file, metadata);
      final url = await ref.getDownloadURL();
      if (kDebugMode) debugPrint('[TrainingData] 이미지 업로드 완료: $url');
      return url;
    } catch (e) {
      if (kDebugMode) debugPrint('[TrainingData] 이미지 업로드 실패: $e');
      return null;
    }
  }

  // ────────────────────────────────────────
  // 통계 조회 (나중에 관리 화면에서 사용)
  // ────────────────────────────────────────
  Future<TrainingStats> getStats() async {
    if (!isAvailable) return TrainingStats.empty();

    try {
      final total = await _db!.collection(_collection).count().get();
      final labeled = await _db!
          .collection(_collection)
          .where('is_corrected', isEqualTo: true)
          .count()
          .get();

      return TrainingStats(
        total: total.count ?? 0,
        labeled: labeled.count ?? 0,
      );
    } catch (e) {
      return TrainingStats.empty();
    }
  }

  // ────────────────────────────────────────
  // 변환 헬퍼
  // ────────────────────────────────────────
  Map<String, dynamic> _geminiResultToMap(GeminiOcrResult r) {
    return {
      'store_name': r.storeName,
      'date': r.date.toIso8601String(),
      'total_amount': r.totalAmount,
      'confidence': r.confidence,
      'raw_text': r.rawText,
      'items': r.items.map((i) => {
        'name': i.name,
        'quantity': i.quantity,
        'unit_price': i.unitPrice,
        'unit': i.unit,
        'total_price': i.totalPrice,
      }).toList(),
    };
  }

  Map<String, dynamic> _parsedReceiptToMap(ParsedReceipt r) {
    return {
      'store_name': r.storeName,
      'date': r.date.toIso8601String(),
      'total_amount': r.totalAmount,
      'raw_text': r.rawText,
      'items': r.items.map((i) => {
        'name': i.name,
        'quantity': i.quantity,
        'unit_price': i.unitPrice,
        'unit': i.unit,
      }).toList(),
    };
  }

  String _generateDocId() {
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch.toString();
    return 'receipt_$ts';
  }
}

// ────────────────────────────────────────
// 통계 데이터 클래스
// ────────────────────────────────────────
class TrainingStats {
  final int total;
  final int labeled;

  TrainingStats({required this.total, required this.labeled});

  factory TrainingStats.empty() => TrainingStats(total: 0, labeled: 0);

  int get unlabeled => total - labeled;
  double get labelRate => total == 0 ? 0 : labeled / total;
}
