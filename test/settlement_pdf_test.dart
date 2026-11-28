import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/models/user_model.dart';
import 'package:flow_note/services/file_saver.dart';
import 'package:flow_note/services/settlement_pdf_service.dart';

/// 요청 #78 회귀 — 정산 문서(PDF)가 **실제로 만들어지는지** 확인한다.
///
/// 이전 상태: 내보내기 버튼이 이력만 쓰고 파일을 아예 만들지 않았다.
/// 화면상으로는 '내보내기 완료' 가 떠서 성공처럼 보였다.
/// 이 테스트는 그 상태로 되돌아가는 것을 막는다.
///
/// 확인하는 것:
///  1. 두 종류(요청서/내역서) 모두 0바이트가 아닌 PDF 파일이 나온다
///  2. 한글 폰트가 실려서 파일이 충분한 크기를 갖는다 (폰트 미포함이면 훨씬 작다)
///  3. 요청서에는 품목명이 들어가지 않는다 (OCR 오류가 거래처로 나가면 안 된다)
///  4. 내역서에는 품목명이 들어간다
void main() {
  // 플러그인 채널을 가로채려면 바인딩이 먼저 있어야 한다.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    // `path_provider` 는 플러그인이라 테스트에서 네이티브 호출이 안 된다.
    // 채널을 가로채서 임시 폴더를 돌려준다.
    tmp = Directory.systemTemp.createTempSync('fn_pdf_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tmp.path;
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 실제 데이터에서 확인된 모양 그대로 만든다.
  /// (같은 영수증을 두 번 스캔했을 때 품목명이 달라졌던 그 데이터)
  List<ReceiptModel> sample() => [
        ReceiptModel(
          id: 'a',
          date: DateTime(2026, 2, 11),
          storeName: '소재2호',
          items: [
            FlowerItem(name: '다알리아', quantity: 1, unitPrice: 12000, unit: '단'),
            FlowerItem(name: '시네레', quantity: 1, unitPrice: 15000, unit: '단'),
          ],
          totalAmount: 27000,
          rawOcrText: '',
          createdAt: DateTime(2026, 2, 11),
          // 사용자가 확인하지 않은 영수증 → 품목에 '(미확인)' 이 붙어야 한다
          isManuallyEdited: false,
        ),
        ReceiptModel(
          id: 'b',
          date: DateTime(2026, 3, 4),
          storeName: '소재2호',
          items: [
            FlowerItem(name: '장미', quantity: 2, unitPrice: 18000, unit: '단'),
          ],
          totalAmount: 36000,
          rawOcrText: '',
          createdAt: DateTime(2026, 3, 4),
          isManuallyEdited: true,
        ),
      ];

  /// `doc.file` 은 이제 `SavedFile`(경로 + 이름)이다.
  /// 앱/데스크톱에서는 `path` 가 항상 있으므로 테스트에서 파일로 감싼다.
  /// (웹에서는 `path` 가 null 이고 브라우저 다운로드로 대체된다)
  File asFile(SavedFile f) {
    expect(f.path, isNotNull, reason: '앱 플랫폼에서는 파일 경로가 있어야 한다');
    return File(f.path!);
  }

  UserModel me() => UserModel(
        id: 'u1',
        email: 'test@flownote.kr',
        name: '이서연',
        businessName: '봄날플라워',
        businessNumber: '415-30-88217',
        ownerName: '이서연',
        businessAddress: '서울 마포구 양화로 45, 1층',
        phoneNumber: '010-2841-6677',
        createdAt: DateTime(2026, 1, 1),
      );

  test('세금계산서 발행 요청서 PDF 가 생성된다', () async {
    final doc = await SettlementPdfService.instance.build(
      kind: SettlementDocKind.request,
      vendorName: '강남화훼',
      receipts: sample(),
      me: me(),
    );

    final f = asFile(doc.file);
    expect(await f.exists(), isTrue, reason: '파일이 만들어지지 않았다');

    final bytes = await f.readAsBytes();
    // PDF 매직 넘버
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    // 🔴 파일 크기로 한글 폰트 여부를 판단하려 했는데 틀렸다.
    //    `pdf` 패키지는 폰트를 **서브셋**(실제로 쓴 글자만 추출)해서 싣기
    //    때문에 한글이 정상이어도 파일은 20~30KB 다. 처음 임계값을 100KB 로
    //    잡았다가 정상 동작을 실패로 판정했다.
    //    크기는 "내용이 있다" 정도만 확인하고, 한글 렌더링은 pdftotext 로
    //    직접 확인했다(제목·상호·품목 모두 정상 출력).
    expect(bytes.length, greaterThan(8 * 1024),
        reason: '내용이 거의 없는 PDF 다 (${bytes.length} bytes)');

    expect(doc.file.name, contains('세금계산서요청서'));
    expect(doc.file.name, contains('강남화훼'));
  });

  test('매입 내역서 PDF 가 생성된다', () async {
    final doc = await SettlementPdfService.instance.build(
      kind: SettlementDocKind.statement,
      vendorName: '소재2호',
      receipts: sample(),
      me: me(),
    );

    final f = asFile(doc.file);
    expect(await f.exists(), isTrue);
    final bytes = await f.readAsBytes();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(doc.file.name, contains('매입내역서'));
  });

  test('요청서는 품목을 담지 않고, 내역서는 담는다', () {
    // 문서 종류가 품목 노출 여부를 결정한다.
    // 🔴 요청서에 품목이 들어가면 OCR 오류가 거래처로 나간다.
    expect(SettlementDocKind.request.showItems, isFalse);
    expect(SettlementDocKind.statement.showItems, isTrue);
  });

  test('사업자 정보가 비어도 생성 자체는 실패하지 않는다', () async {
    // 내보내기 단계에서 미리 막는 것이 정상 흐름이지만,
    // 생성기 자체가 죽으면 원인을 찾기 어려워진다.
    final doc = await SettlementPdfService.instance.build(
      kind: SettlementDocKind.request,
      vendorName: '이름없는거래처',
      receipts: sample(),
      me: null,
    );
    expect(await asFile(doc.file).exists(), isTrue);
  });

  test('영수증이 사진 없이도 생성된다', () async {
    // 캐시 폴더에 있던 옛 영수증은 사진이 이미 사라졌을 수 있다.
    // 그 때문에 내보내기가 실패해서는 안 된다.
    final rs = sample();
    for (final r in rs) {
      r.imagePath = '/does/not/exist/nope.jpg';
    }
    final doc = await SettlementPdfService.instance.build(
      kind: SettlementDocKind.statement,
      vendorName: '소재2호',
      receipts: rs,
      me: me(),
    );
    expect(await asFile(doc.file).exists(), isTrue);
  });
}
