import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../models/receipt_model.dart';
import '../../services/gemini_ocr_service.dart';
import '../../services/vendor_tax_service.dart';

/// 스캔 파이프라인 한 장(영수증 1건)의 작업 상태.
enum ScanDraftStatus { pending, processing, success, failed }

/// 촬영 → 인식 → 검토 → 저장 전 구간에서 사용하는 임시 모델.
///
/// `ReceiptModel` 은 Hive 객체라 편집 중 상태를 담기 부적절해서,
/// 검토 단계 전용의 가변 모델을 따로 둔다.
class ScanDraft {
  ScanDraft({required this.file, String? id})
      : id = id ?? const Uuid().v4(),
        date = DateTime.now();

  final String id;
  final XFile file;

  ScanDraftStatus status = ScanDraftStatus.pending;
  String? error;

  /// OCR 원문 (저장 시 그대로 보존)
  String rawText = '';
  double confidence = 0;

  String storeName = '';

  /// OCR 이 읽은 사업자등록번호 (XXX-XX-XXXXX). 판독 불가 시 ''.
  String businessNumber = '';
  DateTime date;
  List<DraftItem> items = [];

  /// 모델이 스스로 검산 실패를 표시한 경우 true.
  bool ocrNeedsReview = false;

  /// `ocrNeedsReview` 사유 한 줄.
  String ocrReviewReason = '';

  /// OCR 이 **영수증에 적힌 합계란에서 읽은 값**. 0 이면 못 읽었다는 뜻.
  ///
  /// 🔴 이건 참고용이다. 저장되는 총액이 아니다.
  ///
  /// Build 20 이전에는 이 값을 `totalOverridden = true` 와 함께 `_total` 에
  /// 밀어넣었다. 그래서 OCR 이 합계를 잘못 읽으면 **사장님이 품목 단가를
  /// 아무리 고쳐도 총액이 그 잘못된 숫자에 그대로 고정**됐다.
  /// (`금액이 처음에 오류가 나면 수정해도 저장이 안된다. 특히 합계랑 안맞으면`)
  double ocrTotal = 0;

  /// 사장님이 **합계를 직접 입력한 경우에만** 값이 들어간다.
  /// null 이면 품목 합산이 총액이다.
  ///
  /// OCR 결과는 절대 여기에 쓰지 않는다. `ocrTotal` 과 분리한 이유가 그거다.
  double? userTotal;

  /// 사용자가 이 건을 검토 완료로 표시했는지
  bool reviewed = false;

  /// 저장 대상에서 제외
  bool excluded = false;

  /// 품목 합산.
  double get itemSum => items.fold(0.0, (s, e) => s + e.totalPrice);

  /// **실제로 저장되는 총액.**
  ///
  /// 우선순위: 사장님이 직접 입력한 값 → 품목 합산 → (품목이 비었을 때만) OCR 합계.
  /// 품목을 고치면 총액이 **즉시 따라온다.** 이게 핵심 수정이다.
  double get total {
    final u = userTotal;
    if (u != null) return u;
    final s = itemSum;
    return s > 0 ? s : ocrTotal;
  }

  set total(double v) => userTotal = v;

  /// 직접 입력한 합계를 버리고 품목 합산으로 되돌린다.
  void recalcTotal() => userTotal = null;

  /// 사장님이 합계를 직접 입력했는지 (구 `totalOverridden` 호환).
  bool get totalOverridden => userTotal != null;

  /// 영수증에 적힌 합계와 품목 합산이 어긋나는지 — **실시간 계산**이다.
  /// 고치면 즉시 사라진다. 예전처럼 플래그로 굳어 있지 않다.
  bool get totalMismatch =>
      ocrTotal > 0 && itemSum > 0 && (ocrTotal - itemSum).abs() > 1;

  /// 영수증 합계 - 품목 합산 (양수면 품목이 덜 잡힌 것)
  double get totalDiff => ocrTotal - itemSum;

  bool get isSuccess => status == ScanDraftStatus.success;
  bool get isFailed => status == ScanDraftStatus.failed;
  bool get hasItems => items.isNotEmpty;

  TaxType get taxType => VendorTaxService.instance.typeOf(storeName);
  TaxSplit get split => VendorTaxService.instance.split(storeName, total);

  /// **저장을 막아야 하는 상태인가.**
  ///
  /// 🔴 Build 20 수정: 여기에 `ocrNeedsReview` 가 들어 있었다. 그 플래그는
  /// OCR 이 한 번 세우면 **사장님이 뭘 고쳐도 절대 안 내려가는** 값이라
  /// 저장 버튼이 영구히 비활성화됐다. 특히 합계가 안 맞으면
  /// `needsReview: needsReview || mismatch` 로 무조건 켜졌다.
  /// (`금액이 처음에 오류가 나면 수정해도 저장이 안된다. 특히 합계랑 안맞으면`)
  ///
  /// 이제 **고칠 수 있는 것만** 막는다. 매입처와 금액은 사장님이 이 화면에서
  /// 바로 채울 수 있으니 채우면 즉시 풀린다. 합계 불일치는 **경고만** 하고
  /// 저장을 막지 않는다 — 영수증 자체가 안 맞게 적혀 있을 수도 있고,
  /// 그걸 우리가 판단해서 저장을 거부할 권리는 없다.
  bool get blocksSave =>
      storeName.trim().isEmpty || items.isEmpty || total <= 0;

  /// 눈으로 한 번 확인해 보시면 좋은 상태 (저장은 가능).
  bool get needsAttention => blocksSave || totalMismatch || ocrNeedsReview;

  /// 이 건에 대한 짧은 경고 문구 (없으면 null)
  String? get warning {
    if (isFailed) return error ?? '인식에 실패했어요';
    if (storeName.trim().isEmpty) return '매입처를 입력해 주세요';
    if (items.isEmpty) return '품목이 인식되지 않았어요';
    if (total <= 0) return '금액을 확인해 주세요';
    // 영수증 합계와 품목 합산이 다른 경우 — **실시간 계산**이므로
    // 사장님이 단가를 고쳐서 맞추면 이 문구가 바로 사라진다.
    if (totalMismatch) {
      final d = totalDiff;
      return '영수증 합계와 ${d > 0 ? '적게' : '많게'} '
          '${d.abs().round()}원 차이나요 (저장은 가능해요)';
    }
    if (ocrNeedsReview) {
      return ocrReviewReason.isNotEmpty
          ? ocrReviewReason
          : '금액을 한 번 확인해 주세요 (저장은 가능해요)';
    }
    if (confidence > 0 && confidence < 0.6) return '인식 정확도가 낮아요. 확인해 주세요';
    return null;
  }

  void applyOcr(GeminiOcrResult r) {
    if (!r.success) {
      status = ScanDraftStatus.failed;
      error = r.errorMessage ?? '인식에 실패했어요';
      rawText = r.rawText;
      return;
    }
    status = ScanDraftStatus.success;
    storeName = r.storeName;
    businessNumber = r.businessNumber;
    date = r.date;
    rawText = r.rawText;
    confidence = r.confidence;
    ocrNeedsReview = r.needsReview;
    ocrReviewReason = r.reviewReason;
    items = r.items
        .map((e) => DraftItem(
              name: e.name,
              quantity: e.quantity,
              unitPrice: e.unitPrice,
              unit: e.unit,
            ))
        .toList();
    // 🔴 OCR 이 읽은 합계는 `ocrTotal` 에만 넣는다.
    //
    // 예전에는 항목 합계와 다르면 `_total` + `totalOverridden = true` 로
    // 밀어넣었다. 그 결과 사장님이 단가를 고쳐도 총액이 OCR 이 잘못 읽은
    // 숫자에 **고정**됐다. 이제 `total` 은 품목 합산을 따라가고,
    // `ocrTotal` 은 "영수증엔 이렇게 적혀 있어요" 비교용으로만 쓴다.
    // (userTotal 은 사장님이 직접 입력할 때만 채워진다.)
    ocrTotal = r.totalAmount > 0 ? r.totalAmount : 0;
  }

  ReceiptModel toReceipt() {
    return ReceiptModel(
      id: id,
      date: date,
      storeName: storeName.trim().isEmpty ? '미지정 매입처' : storeName.trim(),
      items: items.map((e) => e.toItem()).toList(),
      totalAmount: total,
      imagePath: file.path,
      rawOcrText: rawText,
      createdAt: DateTime.now(),
      isManuallyEdited: reviewed,
    );
  }
}

/// 검토 화면에서 편집 가능한 품목.
class DraftItem {
  DraftItem({
    required this.name,
    this.quantity = 1,
    this.unitPrice = 0,
    this.unit = '단',
    this.color,
  });

  String name;
  int quantity;
  double unitPrice;
  String unit;
  String? color;

  double get totalPrice => quantity * unitPrice;

  FlowerItem toItem() => FlowerItem(
        name: name.trim(),
        quantity: quantity,
        unitPrice: unitPrice,
        unit: unit,
        color: color,
      );

  DraftItem copy() => DraftItem(
        name: name,
        quantity: quantity,
        unitPrice: unitPrice,
        unit: unit,
        color: color,
      );
}

/// 스캔 세션 전체 요약.
class ScanSummary {
  const ScanSummary({
    required this.total,
    required this.success,
    required this.failed,
    required this.amount,
    required this.itemCount,
  });

  final int total;
  final int success;
  final int failed;
  final double amount;
  final int itemCount;

  factory ScanSummary.of(List<ScanDraft> drafts) {
    final live = drafts.where((d) => !d.excluded).toList();
    return ScanSummary(
      total: drafts.length,
      success: live.where((d) => d.isSuccess).length,
      failed: drafts.where((d) => d.isFailed).length,
      amount: live.fold(0.0, (s, d) => s + d.total),
      itemCount: live.fold(0, (s, d) => s + d.items.length),
    );
  }
}
