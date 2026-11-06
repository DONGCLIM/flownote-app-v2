import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/screens/scan/scan_draft.dart';
import 'package:flow_note/screens/ds/scan_duplicate_ds_screen.dart';
import 'package:flow_note/services/receipt_duplicate_service.dart';

/// #118 중복 영수증 검사
///
/// 사장님 요청:
///   "같은 가게에서 같은 데이터를 넣었을 때 중복이라고 알려줘야할 거 같아"
///
/// 예전에는 `addReceipt` 가 새 UUID 로 그냥 `put` 했기 때문에 같은
/// 영수증을 두 번 찍으면 두 건이 쌓이고 매입 합계가 부풀었다.

ScanDraft _draft({
  required String store,
  required DateTime date,
  List<(String, int, double)> items = const [('장미', 2, 10000.0)],
  double? total,
}) {
  final d = ScanDraft(file: XFile('/tmp/x.jpg'));
  d.status = ScanDraftStatus.success;
  d.storeName = store;
  d.date = date;
  d.items = [
    for (final (n, q, up) in items)
      DraftItem(name: n, quantity: q, unitPrice: up),
  ];
  if (total != null) d.userTotal = total;
  return d;
}

ReceiptModel _saved({
  required String store,
  required DateTime date,
  List<(String, int, double)> items = const [('장미', 2, 10000.0)],
  double? total,
}) {
  final list = [
    for (final (n, q, up) in items)
      FlowerItem(name: n, quantity: q, unitPrice: up, unit: '단'),
  ];
  return ReceiptModel(
    id: 'saved-${store}_${date.day}_${total ?? 0}',
    date: date,
    storeName: store,
    items: list,
    totalAmount: total ?? list.fold(0.0, (s, e) => s + e.totalPrice),
    rawOcrText: '',
    createdAt: DateTime.now(),
  );
}

void main() {
  final day = DateTime(2026, 5, 12);

  group('#118 매입처 이름 정규화', () {
    test('법인 표기와 공백을 무시한다', () {
      const n = ReceiptKey.normalizeStore;
      expect(n('대한꽃도매'), n('(주)대한꽃도매'));
      expect(n('대한꽃도매'), n('대한 꽃도매'));
      expect(n('대한꽃도매'), n('㈜ 대한·꽃도매'));
      expect(n('주식회사 화람원예'), n('화람원예'));
    });

    test('다른 가게는 여전히 다르다', () {
      const n = ReceiptKey.normalizeStore;
      expect(n('대한꽃도매') == n('한국꽃도매'), isFalse);
    });
  });

  group('#118 품목 서명', () {
    test('순서가 뒤바뀌어도 같은 서명이다', () {
      final a = ReceiptKey.signature([('장미', 2, 10000.0), ('튤립', 1, 5000.0)]);
      final b = ReceiptKey.signature([('튤립', 1, 5000.0), ('장미', 2, 10000.0)]);
      expect(a, b);
    });

    test('수량이 다르면 다른 서명이다', () {
      final a = ReceiptKey.signature([('장미', 2, 10000.0)]);
      final b = ReceiptKey.signature([('장미', 3, 10000.0)]);
      expect(a == b, isFalse);
    });
  });

  group('#118 중복 판정', () {
    test('🔴 같은 가게 · 같은 날 · 같은 금액 · 같은 품목 = 중복 확실', () {
      final hits = ReceiptDuplicateService.check(
        [_draft(store: '대한꽃도매', date: day)],
        [_saved(store: '대한꽃도매', date: day)],
      );
      expect(hits.length, 1);
      expect(hits.first.level, DuplicateLevel.exact);
      expect(hits.first.saved, isNotNull);
    });

    test('🔴 상호를 다르게 읽어도 잡는다 ((주) · 공백)', () {
      final hits = ReceiptDuplicateService.check(
        [_draft(store: '(주) 대한 꽃도매', date: day)],
        [_saved(store: '대한꽃도매', date: day)],
      );
      expect(hits.length, 1);
      expect(hits.first.isExact, isTrue);
    });

    test('금액만 같고 품목이 다르면 중복 의심', () {
      final hits = ReceiptDuplicateService.check(
        [
          _draft(store: '대한꽃도매', date: day, items: [('튤립', 4, 5000.0)]),
        ],
        [
          _saved(store: '대한꽃도매', date: day, items: [('장미', 2, 10000.0)]),
        ],
      );
      expect(hits.length, 1);
      expect(hits.first.level, DuplicateLevel.likely);
    });

    test('날짜가 다르면 중복이 아니다', () {
      final hits = ReceiptDuplicateService.check(
        [_draft(store: '대한꽃도매', date: day)],
        [_saved(store: '대한꽃도매', date: DateTime(2026, 5, 13))],
      );
      expect(hits, isEmpty);
    });

    test('가게가 다르면 중복이 아니다', () {
      final hits = ReceiptDuplicateService.check(
        [_draft(store: '대한꽃도매', date: day)],
        [_saved(store: '한국꽃도매', date: day)],
      );
      expect(hits, isEmpty);
    });

    test('🔴 매입처를 모르는 건끼리는 중복으로 잡지 않는다', () {
      // '미지정 매입처' 가 전부 중복으로 잡히면 경고가 쓸모없어진다.
      final hits = ReceiptDuplicateService.check(
        [_draft(store: '   ', date: day)],
        [_saved(store: '', date: day)],
      );
      expect(hits, isEmpty);
    });

    test('🔴 이번에 함께 찍은 두 장이 같으면 뒤엣것만 경고한다', () {
      final a = _draft(store: '대한꽃도매', date: day);
      final b = _draft(store: '대한꽃도매', date: day);
      final hits = ReceiptDuplicateService.check([a, b], []);
      expect(hits.length, 1, reason: '둘 다 경고하면 둘 다 빼 버리게 된다');
      expect(hits.first.draft, same(b));
      expect(hits.first.sibling, same(a));
      expect(hits.first.againstLabel, '이번에 함께 찍은 영수증');
    });

    test('중복이 없으면 빈 목록이다', () {
      final hits = ReceiptDuplicateService.check(
        [_draft(store: '대한꽃도매', date: day)],
        [
          _saved(store: '한국꽃도매', date: day),
          _saved(store: '대한꽃도매', date: DateTime(2026, 4, 1)),
        ],
      );
      expect(hits, isEmpty);
    });

    test('기본 제외는 확실한 중복만이다', () {
      final exact = _draft(store: '대한꽃도매', date: day);
      final likely =
          _draft(store: '한국꽃도매', date: day, items: [('튤립', 4, 5000.0)]);
      final hits = ReceiptDuplicateService.check(
        [exact, likely],
        [
          _saved(store: '대한꽃도매', date: day),
          _saved(store: '한국꽃도매', date: day, items: [('장미', 2, 10000.0)]),
        ],
      );
      expect(hits.length, 2);
      final skip = ReceiptDuplicateService.defaultSkipIds(hits);
      expect(skip.contains(exact.id), isTrue);
      expect(skip.contains(likely.id), isFalse,
          reason: '같은 날 두 번 사는 일은 실제로 있다. 의심은 사장님이 고르셔야 한다');
    });
  });

  group('#118 중복 확인 화면', () {
    testWidgets('🔴 확실한 중복은 체크가 꺼진 채로 열리고 저장 건수가 줄어 있다',
        (tester) async {
      final d = _draft(store: '대한꽃도매', date: day);
      final hits = ReceiptDuplicateService.check(
        [d],
        [_saved(store: '대한꽃도매', date: day)],
      );
      Set<String>? got;
      await tester.pumpWidget(MaterialApp(
        home: ScanDuplicateDsScreen(
          hits: hits,
          totalCount: 3,
          onContinue: (s) => got = s,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('중복 영수증 확인'), findsOneWidget);
      expect(find.text('이미 넣은 영수증 같아요'), findsOneWidget);
      expect(find.text('중복 확실'), findsOneWidget);
      expect(find.text('이미 저장된 영수증'), findsOneWidget);
      // 3건 중 1건이 기본 제외 -> 2건 저장
      expect(find.text('2건 저장하기'), findsOneWidget);

      await tester.tap(find.text('2건 저장하기'));
      await tester.pumpAndSettle();
      expect(got, isNotNull);
      expect(got!.contains(d.id), isTrue);
    });

    testWidgets('🔴 체크를 다시 켜면 저장 건수가 늘어난다', (tester) async {
      final d = _draft(store: '대한꽃도매', date: day);
      final hits = ReceiptDuplicateService.check(
        [d],
        [_saved(store: '대한꽃도매', date: day)],
      );
      Set<String>? got;
      await tester.pumpWidget(MaterialApp(
        home: ScanDuplicateDsScreen(
          hits: hits,
          totalCount: 3,
          onContinue: (s) => got = s,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('2건 저장하기'), findsOneWidget);

      await tester.tap(find.text('대한꽃도매'));
      await tester.pumpAndSettle();
      expect(find.text('3건 저장하기'), findsOneWidget);

      await tester.tap(find.text('3건 저장하기'));
      await tester.pumpAndSettle();
      expect(got, isNotNull);
      expect(got!.isEmpty, isTrue);
    });

    testWidgets('의심만 있으면 전부 체크된 채로 열린다', (tester) async {
      final d = _draft(store: '대한꽃도매', date: day, items: [('튤립', 4, 5000.0)]);
      final hits = ReceiptDuplicateService.check(
        [d],
        [_saved(store: '대한꽃도매', date: day)],
      );
      expect(hits.single.level, DuplicateLevel.likely);

      await tester.pumpWidget(MaterialApp(
        home: ScanDuplicateDsScreen(
          hits: hits,
          totalCount: 1,
          onContinue: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('같은 날 같은 매입처가 있어요'), findsOneWidget);
      expect(find.text('중복 의심'), findsWidgets);
      expect(find.text('1건 저장하기'), findsOneWidget);
    });

    testWidgets('🔴 전부 빼면 저장 버튼이 잠긴다', (tester) async {
      final d = _draft(store: '대한꽃도매', date: day);
      final hits = ReceiptDuplicateService.check(
        [d],
        [_saved(store: '대한꽃도매', date: day)],
      );
      await tester.pumpWidget(MaterialApp(
        home: ScanDuplicateDsScreen(
          hits: hits,
          totalCount: 1,
          onContinue: (_) => fail('저장이 잠겨 있어야 한다'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('저장할 영수증이 없어요'), findsOneWidget);
      await tester.tap(find.text('저장할 영수증이 없어요'));
      await tester.pumpAndSettle();
    });
  });
}
