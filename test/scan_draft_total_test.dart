// 스캔 검토 화면의 금액 저장 회귀 테스트.
//
// 사장님 지적:
//   `스캔할 때 금액이 처음에 오류가 나면 수정해도 저장이 안된다.
//    특히 합계랑 안맞으면.`
//
// 원인은 두 갈래였다.
//  1. OCR 이 읽은 합계를 `totalOverridden = true` 로 잠가버려서, 품목 단가를
//     고쳐도 총액이 잘못된 숫자에 고정됐다.
//  2. `needsAttention` 에 OCR 이 세운 `ocrNeedsReview` 가 포함돼 있어서
//     저장 버튼이 영구히 비활성화됐다. 그 플래그는 합계 불일치만으로도
//     켜졌고, 한 번 켜지면 사용자가 뭘 해도 내려가지 않았다.
//
// 아래 테스트는 두 경우가 다시 생기면 즉시 깨진다.

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flow_note/screens/scan/scan_draft.dart';
import 'package:flow_note/services/gemini_ocr_service.dart';

ScanDraft _draft() => ScanDraft(file: XFile('/tmp/x.jpg'));

GeminiOcrResult _ocr({
  required double totalAmount,
  required List<GeminiItem> items,
  String storeName = '대한꽃도매',
  bool needsReview = false,
}) =>
    GeminiOcrResult(
      success: true,
      storeName: storeName,
      date: DateTime(2026, 8, 20),
      items: items,
      totalAmount: totalAmount,
      needsReview: needsReview,
      rawText: '',
      confidence: 0.9,
    );

GeminiItem _gi(String name, int qty, double price) => GeminiItem(
      name: name,
      quantity: qty,
      unitPrice: price,
      unit: '단',
      totalPrice: qty * price,
    );

void main() {
  group('합계 불일치가 저장을 막지 않는다', () {
    test('OCR 합계가 품목 합산과 달라도 저장이 막히지 않는다', () {
      final d = _draft()
        ..applyOcr(_ocr(
          totalAmount: 256000, // 영수증에 적힌 합계
          items: [_gi('장미', 10, 6000)], // 품목 합산은 60,000
        ));

      expect(d.totalMismatch, isTrue, reason: '불일치는 감지돼야 한다');
      // 🔴 이게 핵심. 예전에는 blocksSave 에 해당하는 값이 true 여서 막혔다.
      expect(d.blocksSave, isFalse, reason: '합계 불일치로 저장을 막지 않는다');
      expect(d.warning, isNotNull, reason: '경고는 보여줘야 한다');
      expect(d.warning, contains('저장은 가능'));
    });

    test('OCR 이 needs_review 를 세워도 저장이 막히지 않는다', () {
      final d = _draft()
        ..applyOcr(_ocr(
          totalAmount: 60000,
          items: [_gi('장미', 10, 6000)],
          needsReview: true,
        ));

      expect(d.ocrNeedsReview, isTrue);
      expect(d.blocksSave, isFalse,
          reason: 'OCR 이 세운 플래그는 사용자가 내릴 수 없으므로 저장을 막으면 영구 잠금이 된다');
    });

    test('정말 못 고친 것만 저장을 막는다', () {
      // 매입처 없음
      expect(
        (_draft()..applyOcr(_ocr(totalAmount: 1000, items: [_gi('장미', 1, 1000)], storeName: '')))
            .blocksSave,
        isTrue,
      );
      // 품목 없음
      expect(
        (_draft()..applyOcr(_ocr(totalAmount: 1000, items: []))).blocksSave,
        isTrue,
      );
    });

    test('매입처를 채우면 저장 잠금이 즉시 풀린다', () {
      final d = _draft()
        ..applyOcr(_ocr(
          totalAmount: 256000,
          items: [_gi('장미', 10, 6000)],
          storeName: '',
        ));
      expect(d.blocksSave, isTrue);

      d.storeName = '대한꽃도매';
      expect(d.blocksSave, isFalse, reason: '고치면 바로 풀려야 한다');
    });
  });

  group('총액은 품목 수정을 따라온다', () {
    test('OCR 합계가 틀렸어도 단가를 고치면 총액이 따라온다', () {
      final d = _draft()
        ..applyOcr(_ocr(
          totalAmount: 256000, // OCR 오독
          items: [_gi('장미', 10, 6000)],
        ));

      // 🔴 예전에는 여기서 256000 이 나왔다 (totalOverridden 으로 잠김).
      expect(d.total, 60000, reason: '총액은 품목 합산을 따라야 한다');
      expect(d.ocrTotal, 256000, reason: 'OCR 값은 비교용으로만 보존');

      // 사장님이 단가를 고친다
      d.items[0].unitPrice = 25600;
      expect(d.total, 256000, reason: '고치면 총액이 즉시 따라온다');
      expect(d.totalMismatch, isFalse, reason: '맞추면 불일치 경고가 사라진다');
      expect(d.warning, isNull);
    });

    test('수량을 고쳐도 총액이 따라온다', () {
      final d = _draft()
        ..applyOcr(_ocr(totalAmount: 0, items: [_gi('장미', 10, 6000)]));
      expect(d.total, 60000);
      d.items[0].quantity = 20;
      expect(d.total, 120000);
    });

    test('품목을 추가하면 총액이 따라온다', () {
      final d = _draft()
        ..applyOcr(_ocr(totalAmount: 256000, items: [_gi('장미', 10, 6000)]));
      d.items.add(DraftItem(name: '국화 소국', quantity: 10, unitPrice: 3000));
      expect(d.total, 90000);
    });

    test('OCR 이 합계를 못 읽었으면 품목 합산을 쓴다', () {
      final d = _draft()
        ..applyOcr(_ocr(totalAmount: 0, items: [_gi('장미', 10, 6000)]));
      expect(d.ocrTotal, 0);
      expect(d.total, 60000);
      expect(d.totalMismatch, isFalse);
    });

    test('품목이 아예 없으면 OCR 합계라도 살려서 쓴다', () {
      final d = _draft()..applyOcr(_ocr(totalAmount: 256000, items: []));
      expect(d.total, 256000, reason: '품목을 못 읽었을 때 금액까지 0 이면 저장이 막힌다');
    });
  });

  group('직접 입력한 합계', () {
    test('직접 입력하면 그 값이 저장되고 품목 수정에 흔들리지 않는다', () {
      final d = _draft()
        ..applyOcr(_ocr(totalAmount: 0, items: [_gi('장미', 10, 6000)]));

      d.total = 250000;
      expect(d.userTotal, 250000);
      expect(d.totalOverridden, isTrue);
      expect(d.total, 250000);

      d.items[0].unitPrice = 1;
      expect(d.total, 250000, reason: '직접 입력한 값은 사장님 뜻이므로 유지한다');
    });

    test('되돌리면 품목 합산으로 복귀한다', () {
      final d = _draft()
        ..applyOcr(_ocr(totalAmount: 0, items: [_gi('장미', 10, 6000)]));
      d.total = 250000;
      d.recalcTotal();
      expect(d.userTotal, isNull);
      expect(d.totalOverridden, isFalse);
      expect(d.total, 60000);
    });

    test('OCR 은 userTotal 을 절대 건드리지 않는다', () {
      final d = _draft()
        ..applyOcr(_ocr(totalAmount: 256000, items: [_gi('장미', 10, 6000)]));
      // 🔴 예전 버그의 정확한 지점: applyOcr 이 override 를 켰다.
      expect(d.userTotal, isNull);
      expect(d.totalOverridden, isFalse);
    });
  });

  group('저장 결과 (toReceipt)', () {
    test('저장되는 총액은 화면에 보이는 총액과 같다', () {
      final d = _draft()
        ..applyOcr(_ocr(totalAmount: 256000, items: [_gi('장미', 10, 6000)]));
      expect(d.toReceipt().totalAmount, d.total);
      expect(d.toReceipt().totalAmount, 60000);
    });

    test('단가를 고친 뒤 저장하면 고친 값이 반영된다', () {
      final d = _draft()
        ..applyOcr(_ocr(totalAmount: 256000, items: [_gi('장미', 10, 6000)]));
      d.items[0].unitPrice = 25600;
      final r = d.toReceipt();
      expect(r.totalAmount, 256000);
      expect(r.items.first.unitPrice, 25600);
    });

    test('영수증 합계를 채택하면 그대로 저장된다', () {
      final d = _draft()
        ..applyOcr(_ocr(totalAmount: 256000, items: [_gi('장미', 10, 6000)]));
      d.total = d.ocrTotal; // '영수증 합계로 저장' 버튼
      expect(d.toReceipt().totalAmount, 256000);
    });
  });
}
