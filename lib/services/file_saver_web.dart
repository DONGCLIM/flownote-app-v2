import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 저장 결과. (io 판과 형태를 똑같이 유지한다)
class SavedFile {
  const SavedFile({required this.name, this.path});

  final String name;
  final String? path;

  bool get canShare => path != null;
}

/// 웹 — 브라우저 다운로드로 내려보낸다.
///
/// 방법: 바이트로 Blob 을 만들고, 임시 `<a download>` 를 만들어 클릭한다.
/// 이게 별 기교 없이 모든 브라우저(크롬/사파리/삼성)에서 동작하는
/// 유일한 방식이다. `showSaveFilePicker` 는 사파리가 지원하지 않는다.
///
/// URL 을 반드시 `revokeObjectURL` 로 회수한다. 안 하면 정산서를 여러 번
/// 뽑을 때마다 PDF 바이트가 탭 메모리에 계속 쌓인다.
Future<SavedFile> saveDocumentBytes({
  required Uint8List bytes,
  required String fileName,
}) async {
  final parts = <JSAny>[bytes.toJS].toJS;
  final blob = web.Blob(
    parts,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);

  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = url;
  a.download = fileName;
  a.style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();

  // 클릭 직후 즉시 회수하면 일부 브라우저가 다운로드를 취소한다.
  // 한 박자 뒤에 정리한다.
  Future<void>.delayed(const Duration(seconds: 20), () {
    web.URL.revokeObjectURL(url);
  });

  // 웹은 파일이 브라우저 다운로드 폴더로 갔으므로 앱이 아는 경로가 없다.
  return SavedFile(name: fileName, path: null);
}

/// 웹은 기기의 로컬 사진 파일 경로를 읽을 수 없다.
const bool kCanReadLocalFiles = false;

Future<Uint8List?> readLocalFile(String path) async => null;

// ── 영수증 사진 영구 보관 — 웹에서는 전부 no-op ────────────────
//
// 웹에는 앱 문서 폴더가 없다. 브라우저에서 올린 사진은 blob URL 이라
// 복사할 대상 파일 시스템 자체가 없다. 호출부는 원본 경로를 그대로
// 유지하는 쪽으로 안전하게 흘러간다.

Future<String?> ensureDocsSubdir(String folder) async => null;

Future<bool> localFileExists(String path) async => false;

Future<bool> copyLocalFile(String from, String to) async => false;

/// 웹에는 쓸 파일 시스템이 없다. 호출부는 `XFile.fromData` 의 blob URL 을
/// 쓰고, 저장 시점에 `ReceiptImageStore` 가 클라우드로 올린다.
Future<bool> writeLocalBytes(String path, Uint8List bytes) async => false;

Future<void> deleteLocalFile(String path) async {}
