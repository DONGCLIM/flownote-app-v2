/// 영수증 사진을 **웹에서도 남게** 만든다 — 플랫폼별 구현 선택.
///
/// ## 왜 필요한가
///
/// 웹에서 영수증을 저장하면 캘린더/상세 화면에서 사진이 사라졌다.
/// 원인은 저장되는 값이 **사진이 아니라 blob URL 문자열**이기 때문이다.
///
/// ```
/// receipt.imagePath = "blob:https://flownote-404ef.web.app/8f3c-..."
/// ```
///
/// `blob:` URL 은 **그 탭이 살아있는 동안만** 유효하다.
/// 탭을 닫거나 새로고침하면 즉시 무효가 되고, 다음에 열었을 때
/// `Image.network` 가 실패해서 회색 자리만 남는다.
///
/// 그런데 `ReceiptImageStore.persist()` 는 웹에서 아무것도 하지 않았다.
///
/// ```dart
/// // file_saver_web.dart — 전부 no-op 였다
/// Future<String?> ensureDocsSubdir(String folder) async => null;
/// Future<bool> copyLocalFile(String from, String to) async => false;
/// ```
///
/// 웹에는 앱 문서 폴더가 없으니 "복사"라는 개념이 성립하지 않는다.
/// 그래서 원본(=곧 죽을 blob URL)을 그대로 돌려주고 있었다.
///
/// ## 그래서 이렇게 한다 — 클라우드에 올린다
///
/// 웹에서 사진을 영구히 남기는 방법은 **서버에 올리는 것**뿐이다.
/// 다행히 Firebase Storage 가 이미 붙어 있고 규칙도 있다.
///
/// ```
/// storage.rules
///   match /users/{uid}/{allPaths=**} {
///     allow read, write: if request.auth != null && request.auth.uid == uid;
///   }
/// ```
///
/// 사장님 사진은 **사장님 계정 폴더**에만 올라가고, 다른 사람은 읽을 수
/// 없다. 올린 뒤 받은 `https://...` 다운로드 URL 을 `imagePath` 에 넣으면
/// 기기를 바꾸거나 브라우저를 지워도 사진이 그대로 보인다.
///
/// | | 기존 | 변경 후 |
/// |---|---|---|
/// | 저장되는 값 | `blob:https://...` | `https://firebasestorage...` |
/// | 새로고침 후 | ❌ 깨짐 | ✅ 보임 |
/// | 다른 기기 | ❌ 없음 | ✅ 보임 |
/// | 정산서 PDF | ❌ 사진 없음 | ✅ 사진 포함 |
///
/// ## 실패해도 저장은 막지 않는다
///
/// 업로드가 실패하면 원래 경로를 그대로 돌려준다. 사진 한 장 때문에
/// 영수증 기록 자체를 못 만들게 하는 건 손해가 더 크다.
/// (`ReceiptImageStore` 와 같은 원칙)
library;

export 'receipt_image_upload_stub.dart'
    if (dart.library.js_interop) 'receipt_image_upload_web.dart';
