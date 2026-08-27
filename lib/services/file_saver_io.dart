import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 저장 결과.
///
/// [path] 는 앱에서만 값이 있다. 웹은 브라우저가 다운로드 폴더로 바로
/// 내려보내므로 앱이 알 수 있는 경로가 없다(=`null`).
class SavedFile {
  const SavedFile({required this.name, this.path});

  final String name;
  final String? path;

  /// `share_plus` 로 공유할 수 있는가.
  /// 웹은 파일 경로가 없으니 공유 대신 다운로드로 끝난다.
  bool get canShare => path != null;
}

/// 앱(Android/iOS/데스크톱) — 문서 폴더 `exports/` 에 파일로 쓴다.
///
/// 캐시가 아니라 문서 폴더를 쓴다. 캐시는 OS 가 예고 없이 비운다.
Future<SavedFile> saveDocumentBytes({
  required Uint8List bytes,
  required String fileName,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final out = Directory('${dir.path}/exports');
  if (!await out.exists()) {
    await out.create(recursive: true);
  }
  final file = File('${out.path}/$fileName');
  await file.writeAsBytes(bytes);
  return SavedFile(name: fileName, path: file.path);
}

/// 이 플랫폼에서 로컬 사진 파일을 읽을 수 있는가.
///
/// 웹은 `dart:io` 가 없어서 항상 false 다. (영수증 사진은 기기 안에만
/// 있으므로 웹에서는 정산서에 사진을 붙일 수 없다.)
const bool kCanReadLocalFiles = true;

/// 로컬 사진 읽기. 실패하면 `null`.
Future<Uint8List?> readLocalFile(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    final b = await f.readAsBytes();
    return b.isEmpty ? null : b;
  } catch (_) {
    return null;
  }
}

// ── 영수증 사진 영구 보관용 원시 기능 ────────────────────────────
//
// `ReceiptImageStore` 가 쓴다. 웹판은 전부 no-op 이다.

/// 앱 문서 폴더 안의 하위 폴더 경로를 만들어서 돌려준다.
Future<String?> ensureDocsSubdir(String folder) async {
  try {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/$folder');
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  } catch (_) {
    return null;
  }
}

/// 파일 존재 확인.
Future<bool> localFileExists(String path) async {
  try {
    return await File(path).exists();
  } catch (_) {
    return false;
  }
}

/// [from] → [to] 복사. 성공하면 true.
Future<bool> copyLocalFile(String from, String to) async {
  try {
    await File(from).copy(to);
    return true;
  } catch (_) {
    return false;
  }
}

/// 파일 삭제.
Future<void> deleteLocalFile(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {
    // 지우기 실패는 조용히 넘긴다.
  }
}
