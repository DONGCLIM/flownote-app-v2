import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/screens/ds/inquiry_ds_screen.dart';
import 'package:flow_note/services/inquiry_service.dart';
import 'package:flow_note/theme/fn_ds.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  Future<void> pump(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: w,
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  group('문의하기 — 화면', () {
    testWidgets('시안 문구가 모두 보인다', (t) async {
      await pump(t, const InquiryDsScreen());
      expect(find.text('제안 및 피드백'), findsOneWidget);
      expect(find.text('더 나은 플로우노트를 함께 만들어요'), findsOneWidget);
      expect(find.text('카테고리'), findsOneWidget);
      expect(find.text('내용'), findsOneWidget);
      expect(find.text('파일 첨부'), findsOneWidget);
      expect(find.text('파일 첨부하기'), findsOneWidget);
      expect(find.text('문의하기'), findsOneWidget);
      expect(find.text('필수'), findsNWidgets(2));
      expect(find.text('선택'), findsOneWidget);
    });

    testWidgets('기본 카테고리와 글자 수가 시안대로다', (t) async {
      await pump(t, const InquiryDsScreen());
      expect(find.text('기능 제안'), findsOneWidget);
      expect(find.text('0 / 1000'), findsOneWidget);
    });

    testWidgets('🔴 내용을 적으면 글자 수가 따라 바뀐다', (t) async {
      await pump(t, const InquiryDsScreen());
      await t.enterText(find.byType(TextField), '영수증 정산 기능 제안');
      await t.pump(const Duration(milliseconds: 200));
      // '영수증 정산 기능 제안' = 공백 포함 12자. (내가 11자로 잘못 셌었다)
      expect(find.text('12 / 1000'), findsOneWidget,
          reason: '숫자가 안 바뀌면 입력이 화면에 안 붙은 것이다');
    });

    testWidgets('🔴 내용이 비면 보내기 버튼이 꺼져 있어야 한다', (t) async {
      await pump(t, const InquiryDsScreen());

      Color bgOf(String label) {
        final box = t.widget<Container>(find.ancestor(
          of: find.text(label),
          matching: find.byType(Container),
        ).first);
        return (box.decoration as BoxDecoration).color!;
      }

      expect(bgOf('문의하기'), FnDs.buttonOffBg, reason: '빈 내용인데 켜져 있다');

      await t.enterText(find.byType(TextField), '내용');
      await t.pump(const Duration(milliseconds: 200));
      expect(bgOf('문의하기'), FnDs.coral, reason: '내용을 적었는데 안 켜졌다');
    });

    testWidgets('🔴 공백만 적으면 여전히 꺼져 있어야 한다', (t) async {
      await pump(t, const InquiryDsScreen());
      await t.enterText(find.byType(TextField), '    ');
      await t.pump(const Duration(milliseconds: 200));
      final box = t.widget<Container>(find.ancestor(
        of: find.text('문의하기'),
        matching: find.byType(Container),
      ).first);
      expect((box.decoration as BoxDecoration).color, FnDs.buttonOffBg);
    });
  });

  group('문의하기 — 통합 기준(FnDs)을 쓴다', () {
    test('🔴 화면이 옛 토큰을 쓰면 안 된다', () {
      final src = _read('lib/screens/ds/inquiry_ds_screen.dart');
      expect(src.contains("theme/fn_ds.dart"), isTrue);
      for (final old in ['FnColors.', 'FnHome.', 'FnSignup.', 'FnScan.',
        'FnProfile.']) {
        expect(src.contains(old), isFalse, reason: '$old 가 남아 있다');
      }
    });

    test('버튼·입력창 치수가 사장님 기준과 같다', () {
      expect(FnDs.buttonH, 52.0);
      expect(FnDs.buttonRadius, 14.0);
      expect(FnDs.inputH, 48.0);
      expect(FnDs.inputRadius, 12.0);
      expect(FnDs.pagePad, 24.0);
      expect(FnDs.coral, const Color(0xFFFF6D78));
    });
  });

  group('문의하기 — 저장', () {
    test('첨부는 최대 3개다', () {
      expect(InquiryService.maxFiles, 3);
    });

    test('처리 상태는 접수로 시작한다', () {
      expect(InquiryService.statusNew, '접수');
    });

    test('카테고리 목록이 비어 있지 않다', () {
      expect(InquiryService.categories, isNotEmpty);
      expect(InquiryService.categories.first, '기능 제안');
    });

    test('🔴 저장 위치와 필드를 바꾸면 안 된다', () {
      final src = _read('lib/services/inquiry_service.dart');
      expect(src.contains("collection('inquiries')"), isTrue);
      for (final field in [
        "'category'", "'content'", "'createdAt'", "'status'",
        "'uid'", "'email'", "'attachmentUrls'",
      ]) {
        expect(src.contains(field), isTrue, reason: '$field 가 빠졌다');
      }
      expect(src.contains('FieldValue.serverTimestamp()'), isTrue,
          reason: '기기 시계를 쓰면 시간이 틀어진다');
    });

    test('🔴 보안 규칙이 inquiries 를 열어 두어야 한다', () {
      final fs = _read('firestore.rules');
      expect(fs.contains('match /inquiries/{docId}'), isTrue,
          reason: '규칙이 없으면 저장이 전부 거부된다');
      expect(fs.contains('allow read: if false;'), isTrue,
          reason: '남의 문의를 아무나 읽으면 안 된다');
      final st = _read('storage.rules');
      expect(st.contains('match /inquiries/{uid}/{allPaths=**}'), isTrue);
    });

    test('첨부 크기 표시가 사람이 읽는 모양이다', () {
      final small = InquiryAttachment(
          name: 'a.png', bytes: Uint8List(2048), contentType: 'image/png');
      expect(small.sizeLabel, '2KB');
      expect(small.isImage, isTrue);
      final big = InquiryAttachment(
          name: 'b.pdf',
          bytes: Uint8List(3 * 1024 * 1024),
          contentType: 'application/pdf');
      expect(big.sizeLabel, '3.0MB');
      expect(big.isImage, isFalse);
    });
  });
}
