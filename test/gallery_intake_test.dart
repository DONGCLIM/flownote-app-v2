import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flow_note/services/gallery_intake.dart';
import 'package:flow_note/services/web_gallery_picker.dart';

/// 갤러리 사진 확보 규칙을 고정한다.
///
/// 이 테스트가 있는 이유: 갤러리 스캔이 "됐다가 안 됐다가" 한 원인은
/// **파일을 두 번 읽었기 때문**이었다. 웹 `XFile` 은 읽을 때마다 `blob:`
/// URL 을 다시 XHR 하고(`cross_file` 의 `_blob` getter 는 결과를 캐시하지
/// 않는다), 그 사이 URL 이 폐기되면 두 번째 읽기가 실패한다.
///
/// 그래서 `GalleryIntake` 는 **읽기를 정확히 필요한 횟수만** 해야 한다.
/// 이 규칙이 조용히 깨지면 같은 증상이 다시 난다.
void main() {
  group('GalleryIntake.prepare', () {
    test('정상 사진은 그대로 통과한다', () async {
      final f = _CountingXFile('good.jpg', _bytes(2048), 'image/jpeg');
      final r = await GalleryIntake.prepare([f]);

      expect(r.usable.length, 1);
      expect(r.failedNames, isEmpty);
      expect(r.allFailed, isFalse);
      expect(r.hasFailures, isFalse);
    });

    test('사진 한 장당 읽기는 1회다 (이중 읽기 금지)', () async {
      // 🔴 회귀 방지의 핵심.
      // 예전에는 사전 검사에서 1회, 인식에서 또 1회 = 총 2회 읽었다.
      // 두 번째 읽기가 실패하면 "사진을 열지 못했어요" 가 떴다.
      final f = _CountingXFile('once.jpg', _bytes(4096), 'image/jpeg');
      await GalleryIntake.prepare([f]);

      expect(f.readCount, 1, reason: '성공한 사진은 딱 한 번만 읽어야 한다');
    });

    test('0바이트면 한 번 더 시도한 뒤 실패로 분류한다', () async {
      final f = _CountingXFile('empty.jpg', Uint8List(0), 'image/jpeg');
      final r = await GalleryIntake.prepare([f]);

      expect(f.readCount, 2, reason: '실패 시 재시도가 한 번 있어야 한다');
      expect(r.usable, isEmpty);
      expect(r.failedNames, ['empty.jpg']);
      expect(r.allFailed, isTrue);
    });

    test('읽기 예외도 재시도한 뒤 실패로 분류한다', () async {
      final f = _CountingXFile('boom.jpg', null, 'image/jpeg');
      final r = await GalleryIntake.prepare([f]);

      expect(f.readCount, 2);
      expect(r.allFailed, isTrue);
      expect(r.failedNames, ['boom.jpg']);
    });

    test('두 번째 시도에서 성공하면 살려낸다', () async {
      // 일시적인 blob 읽기 실패는 앱이 흡수해야 한다.
      // 사장님에게 실패 화면을 띄우기 전에 한 번 더 해보는 것이 맞다.
      final f = _CountingXFile('flaky.jpg', _bytes(1024), 'image/jpeg',
          failFirst: true);
      final r = await GalleryIntake.prepare([f]);

      expect(f.readCount, 2);
      expect(r.usable.length, 1, reason: '재시도로 살아나야 한다');
      expect(r.failedNames, isEmpty);
    });

    test('일부만 실패하면 되는 것은 통과시킨다', () async {
      final ok1 = _CountingXFile('a.jpg', _bytes(1024), 'image/jpeg');
      final bad = _CountingXFile('b.jpg', Uint8List(0), 'image/jpeg');
      final ok2 = _CountingXFile('c.jpg', _bytes(1024), 'image/jpeg');

      final r = await GalleryIntake.prepare([ok1, bad, ok2]);

      expect(r.usable.length, 2);
      expect(r.failedNames, ['b.jpg']);
      expect(r.hasFailures, isTrue);
      expect(r.allFailed, isFalse, reason: '되는 사진이 있으면 진행해야 한다');
      expect(r.failedCount, 1);
    });

    test('사진을 순서대로 처리한다 (동시 처리 금지)', () async {
      // 🔴 동시에 처리하면 캔버스가 여러 장 겹쳐 휴대폰 메모리가 터진다.
      // `image_picker_for_web` 이 `Future.wait` 로 전부 동시에 축소하는
      // 것이 간헐적 실패의 원인 중 하나였다.
      final order = <String>[];
      final files = [
        _CountingXFile('1.jpg', _bytes(512), 'image/jpeg', onRead: order.add),
        _CountingXFile('2.jpg', _bytes(512), 'image/jpeg', onRead: order.add),
        _CountingXFile('3.jpg', _bytes(512), 'image/jpeg', onRead: order.add),
      ];
      await GalleryIntake.prepare(files);

      expect(order, ['1.jpg', '2.jpg', '3.jpg']);
    });

    test('빈 목록은 빈 결과를 준다', () async {
      final r = await GalleryIntake.prepare([]);
      expect(r.usable, isEmpty);
      expect(r.failedNames, isEmpty);
      expect(r.allFailed, isFalse, reason: '고른 게 없으면 실패가 아니다');
    });

    test('전부 실패해도 실패 목록에 이름이 모두 남는다', () async {
      final r = await GalleryIntake.prepare([
        _CountingXFile('x.jpg', Uint8List(0), 'image/jpeg'),
        _CountingXFile('y.jpg', null, 'image/jpeg'),
      ]);
      expect(r.usable, isEmpty);
      expect(r.failedNames, ['x.jpg', 'y.jpg']);
      expect(r.failedCount, 2);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // #95 회귀 방지 — blob URL 우회 경로
  //
  // 갤러리 스캔이 마지막까지 "됐다가 안 됐다가" 한 진짜 원인은
  // `image_picker_for_web` 이 `File` 객체를 버리고 `blob:` URL 문자열만
  // 남긴 뒤 `<input>` 까지 DOM 에서 제거하기 때문이었다.
  //
  // ```dart
  // // image_picker_for_web-3.1.1  _getSelectedXFiles
  // return XFile(
  //   web.URL.createObjectURL(file),   // ⚠️ URL 만 보관, File 은 버림
  //   name: file.name, ...
  // );
  //
  // // 같은 파일  getFiles
  // return _getSelectedXFiles(input).whenComplete(() {
  //   input.remove();                  // ⚠️ File 을 들고 있던 input 도 제거
  // });
  // ```
  //
  // 두 소유자가 모두 사라지면 브라우저는 임의의 시점에 뒷단 파일 핸들을
  // 회수할 수 있고, 그 뒤의 XHR 은 실패한다. **무효가 된 blob URL 은
  // 재시도해도 계속 무효라서 재시도 로직으로는 절대 고쳐지지 않는다.**
  //
  // 그래서 웹에서는 `File` 을 직접 붙잡고 `FileReader` 로 읽어
  // `fromPickedPhotos` 로 넘긴다. 이 경로는 **파일을 다시 읽지 않는다.**
  // 아래 테스트가 그 성질을 고정한다.
  // ─────────────────────────────────────────────────────────────────
  group('GalleryIntake.fromPickedPhotos', () {
    test('이미 읽은 바이트를 그대로 통과시킨다', () async {
      final r = await GalleryIntake.fromPickedPhotos([
        _photo('a.jpg', 2048),
        _photo('b.jpg', 4096),
      ]);

      expect(r.usable.length, 2);
      expect(r.failedNames, isEmpty);
      expect(r.hasFailures, isFalse);
      expect(r.allFailed, isFalse);
      expect(await r.usable[0].readAsBytes(), hasLength(2048));
      expect(await r.usable[1].readAsBytes(), hasLength(4096));
    });

    test('결과는 메모리 XFile 이라 몇 번이든 다시 읽힌다', () async {
      // 🔴 회귀 방지의 핵심.
      // `XFile.fromData` 는 `_browserBlob` 을 채워두므로 `readAsBytes()` 가
      // XHR 을 타지 않는다. 즉 폐기될 blob URL 이 개입할 여지가 없다.
      final r = await GalleryIntake.fromPickedPhotos([_photo('x.jpg', 1234)]);
      final f = r.usable.single;

      final b1 = await f.readAsBytes();
      final b2 = await f.readAsBytes();
      final b3 = await f.readAsBytes();

      expect(b1.length, 1234);
      expect(b2.length, 1234);
      expect(b3.length, 1234);
    });

    test('선택 순서를 유지한다', () async {
      final r = await GalleryIntake.fromPickedPhotos([
        _photo('1.jpg', 100),
        _photo('2.jpg', 200),
        _photo('3.jpg', 300),
      ]);

      // 이름 대신 크기로 확인한다. `XFile.fromData` 의 `name` 은
      // 네이티브 구현에서 무시되고 웹 구현에서만 보관되기 때문이다
      // (`cross_file` io.dart: "[name] is ignored"). 이 경로는 웹 전용이라
      // 실제 동작에는 문제가 없지만, 테스트는 VM 에서 돌기 때문에
      // 플랫폼에 의존하지 않는 값으로 순서를 확인한다.
      final sizes = <int>[];
      for (final f in r.usable) {
        sizes.add((await f.readAsBytes()).length);
      }
      expect(sizes, [100, 200, 300], reason: '고른 순서가 뒤바뀌면 안 된다');
    });

    test('빈 선택은 빈 결과다 (allFailed 아님)', () async {
      final r = await GalleryIntake.fromPickedPhotos([]);

      expect(r.usable, isEmpty);
      expect(r.failedNames, isEmpty);
      expect(r.allFailed, isFalse, reason: '고른 게 없는 것과 못 읽은 것은 다르다');
    });

    test('PNG/HEIC 등 JPEG 아닌 형식도 그대로 넘어간다', () async {
      final r = await GalleryIntake.fromPickedPhotos([
        _photo('p.png', 512, mime: 'image/png'),
        _photo('h.heic', 512, mime: 'image/heic'),
      ]);

      expect(r.usable.length, 2);
      // 네이티브 테스트 환경에서는 축소 스텁이 `null` 을 주므로 원본 형식이
      // 유지된다. 형식을 잘못 바꿔 붙이면 인식 단계에서 깨진다.
      expect(r.usable[0].mimeType, 'image/png');
      expect(r.usable[1].mimeType, 'image/heic');
    });
  });

  group('web_gallery_picker (네이티브 스텁)', () {
    test('네이티브에서는 우회로가 비활성이다', () {
      // 안드로이드/iOS 는 실제 파일 경로를 받으므로 blob URL 문제가 없다.
      // 여기서 `true` 가 되면 네이티브가 엉뚱한 경로를 타게 된다.
      expect(webGalleryPickerAvailable, isFalse);
    });

    test('네이티브 스텁은 항상 null 이라 image_picker 로 폴백한다', () async {
      expect(await pickPhotosFromGallery(), isNull);
      expect(await pickPhotosFromGallery(multiple: false), isNull);
    });
  });
}

PickedPhoto _photo(String name, int size, {String mime = 'image/jpeg'}) =>
    PickedPhoto(name: name, mimeType: mime, bytes: _bytes(size));

Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, 0x41));

/// 읽기 횟수를 세는 테스트용 [XFile].
///
/// [data] 가 `null` 이면 읽기가 예외를 던진다.
/// [failFirst] 면 첫 시도만 실패하고 두 번째는 성공한다.
class _CountingXFile extends XFile {
  _CountingXFile(
    this._name,
    this.data,
    String mime, {
    this.failFirst = false,
    this.onRead,
  }) : super('/dev/null', name: _name, mimeType: mime);

  final String _name;
  final Uint8List? data;
  final bool failFirst;
  final void Function(String name)? onRead;

  int readCount = 0;

  @override
  String get name => _name;

  @override
  Future<Uint8List> readAsBytes() async {
    readCount++;
    onRead?.call(_name);
    if (failFirst && readCount == 1) {
      throw Exception('일시적 읽기 실패 (테스트)');
    }
    final d = data;
    if (d == null) throw Exception('읽기 실패 (테스트)');
    return d;
  }
}
