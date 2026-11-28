/// 네이티브 구현 — 아무것도 하지 않는다.
///
/// 안드로이드/iOS 에서는 `ReceiptImageStore` 가 사진을 앱 문서 폴더로
/// 복사해 둔다. 그 경로는 OS 가 건드리지 않으므로 클라우드에 올릴 필요가
/// 없다(데이터 요금도 아낀다).
///
/// `null` 을 돌려주면 호출부가 "업로드 대상 아님" 으로 판단해 기존
/// 로컬 보관 경로를 그대로 쓴다.
bool get receiptImageUploadAvailable => false;

/// 네이티브에서는 쓰이지 않는다.
Future<String?> uploadReceiptImage(
  String source, {
  String? receiptId,
}) async =>
    null;

/// 네이티브에서는 쓰이지 않는다.
Future<void> deleteUploadedReceiptImage(String url) async {}
