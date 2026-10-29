import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/screens/ds/inquiry_ds_screen.dart';
import 'package:flow_note/services/inquiry_service.dart';
import 'package:flow_note/theme/fn_ds.dart';
import 'package:flow_note/widgets/fn_inquiry_parts.dart';

String _read(String p) => File(p).readAsStringSync();

/// 화면을 띄우지 않고 쓸 수 있는 가짜 문의.
Inquiry _mk({
  String id = 'x1',
  String uid = 'u1',
  String category = '기능 제안',
  String content = '영수증 정산 기능 제안',
  String status = '접수',
  String answer = '',
  List<String> urls = const <String>[],
}) =>
    Inquiry(
      id: id,
      uid: uid,
      email: 'boss@example.com',
      displayName: '사장님',
      category: category,
      content: content,
      status: status,
      answer: answer,
      createdAt: DateTime(2026, 9, 18),
      answeredAt: answer.isEmpty ? null : DateTime(2026, 9, 19, 14, 5),
      attachmentUrls: urls,
      attachmentNames: const <String>[],
    );

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

  // 공용 조각만 떼어서 띄운다. 화면 전체는 Firebase 가 필요하다.
  Future<void> pumpPart(WidgetTester t, Widget w) => pump(
        t,
        Scaffold(
          backgroundColor: FnDs.bg,
          body: Padding(
            padding: const EdgeInsets.all(FnDs.pagePad),
            child: w,
          ),
        ),
      );

  group('문의 쓰기 — 화면', () {
    testWidgets('시안 문구가 모두 보인다', (t) async {
      await pump(t, const InquiryDsScreen());
      expect(find.text('제안 및 피드백'), findsOneWidget);
      expect(find.text('더 나은 플로우노트를 함께 만들어요'), findsOneWidget);
      expect(find.text('카테고리'), findsOneWidget);
      expect(find.text('내용'), findsOneWidget);
      expect(find.text('사진 첨부'), findsOneWidget);
      expect(find.text('사진 첨부하기'), findsOneWidget);
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
      expect(_btnBg(t, '문의하기'), FnDs.buttonOffBg, reason: '빈 내용인데 켜져 있다');

      await t.enterText(find.byType(TextField), '내용');
      await t.pump(const Duration(milliseconds: 200));
      expect(_btnBg(t, '문의하기'), FnDs.coral, reason: '내용을 적었는데 안 켜졌다');
    });

    testWidgets('🔴 공백만 적으면 여전히 꺼져 있어야 한다', (t) async {
      await pump(t, const InquiryDsScreen());
      await t.enterText(find.byType(TextField), '    ');
      await t.pump(const Duration(milliseconds: 200));
      expect(_btnBg(t, '문의하기'), FnDs.buttonOffBg);
    });
  });

  group('문의 고치기 — 같은 화면이 수정 모드가 된다', () {
    testWidgets('🔴 원래 내용과 카테고리가 채워져서 열린다', (t) async {
      await pump(t, InquiryDsScreen(origin: _mk(category: '오류 신고')));
      expect(find.text('문의 수정'), findsOneWidget);
      expect(find.text('수정 완료'), findsOneWidget);
      expect(find.text('오류 신고'), findsOneWidget);
      expect(find.text('영수증 정산 기능 제안'), findsOneWidget);
      expect(find.text('12 / 1000'), findsOneWidget);
    });

    testWidgets('🔴 수정 모드에서도 내용이 비면 버튼이 꺼진다', (t) async {
      await pump(t, InquiryDsScreen(origin: _mk()));
      await t.enterText(find.byType(TextField), '');
      await t.pump(const Duration(milliseconds: 200));
      expect(_btnBg(t, '수정 완료'), FnDs.buttonOffBg);
    });

    testWidgets('목록에 없는 카테고리면 첫 번째로 되돌린다', (t) async {
      // 예전 글에 지금은 사라진 카테고리가 들어 있을 수 있다.
      await pump(t, InquiryDsScreen(origin: _mk(category: '없어진분류')));
      expect(find.text('기능 제안'), findsOneWidget);
      expect(find.text('없어진분류'), findsNothing);
    });
  });

  group('공용 조각 — 상태 배지', () {
    testWidgets('접수와 답변완료의 색이 다르다', (t) async {
      await pumpPart(
        t,
        const Column(children: [
          FnStatusBadge('접수'),
          FnStatusBadge('답변완료'),
        ]),
      );
      expect(find.text('접수'), findsOneWidget);
      expect(find.text('답변완료'), findsOneWidget);
      expect(_textColor(t, '답변완료'), FnDs.coral);
      expect(_textColor(t, '접수'), FnDs.sub);
    });

    testWidgets('🔴 배지가 가로로 끝까지 늘어나면 안 된다', (t) async {
      // #164 에서 알림 배지가 화면 끝까지 늘어났던 적이 있다.
      await pumpPart(t, const FnStatusBadge('접수'));
      final w = t.getSize(find.ancestor(
        of: find.text('접수'),
        matching: find.byType(Container),
      ).first).width;
      expect(w, lessThan(90), reason: '배지가 늘어났다 (Align 을 빼먹었다)');
    });
  });

  group('공용 조각 — 버튼', () {
    testWidgets('onTap 이 null 이면 꺼진 모습이다', (t) async {
      await pumpPart(
        t,
        const Column(children: [
          FnPrimaryButton(label: '켜짐', onTap: _noop),
          FnPrimaryButton(label: '꺼짐', onTap: null),
        ]),
      );
      expect(_btnBg(t, '켜짐'), FnDs.coral);
      expect(_btnBg(t, '꺼짐'), FnDs.buttonOffBg);
      expect(_textColor(t, '꺼짐'), FnDs.buttonOffFg);
    });

    testWidgets('테두리 버튼은 삭제일 때 붉다', (t) async {
      await pumpPart(
        t,
        const Column(children: [
          FnOutlineButton(label: '수정', onTap: _noop),
          FnOutlineButton(label: '삭제', onTap: _noop, destructive: true),
        ]),
      );
      expect(_textColor(t, '수정'), FnDs.coral);
      expect(_textColor(t, '삭제'), FnDs.negative);
    });

    testWidgets('버튼 높이가 기준(52)과 같다', (t) async {
      await pumpPart(t, const FnPrimaryButton(label: '확인', onTap: _noop));
      expect(
        t.getSize(find.ancestor(
          of: find.text('확인'),
          matching: find.byType(Container),
        ).first).height,
        FnDs.buttonH,
      );
    });
  });

  group('공용 조각 — 본문과 답변', () {
    testWidgets('본문에 분류·날짜·내용이 나온다', (t) async {
      await pumpPart(t, FnInquiryBody(item: _mk()));
      expect(find.text('기능 제안'), findsOneWidget);
      expect(find.text('26.09.18'), findsOneWidget);
      expect(find.text('영수증 정산 기능 제안'), findsOneWidget);
      expect(find.text('접수'), findsOneWidget);
    });

    testWidgets('🔴 작성자는 관리자 화면에서만 보인다', (t) async {
      await pumpPart(t, FnInquiryBody(item: _mk()));
      expect(find.text('boss@example.com'), findsNothing);

      await pumpPart(t, FnInquiryBody(item: _mk(), showWriter: true));
      expect(find.text('boss@example.com'), findsOneWidget);
    });

    testWidgets('🔴 보통 사용자에게는 답변 입력칸이 없다', (t) async {
      await pumpPart(
        t,
        FnAnswerBlock(
          item: _mk(),
          isAdmin: false,
          onSave: (_) async {},
          onDelete: () async {},
        ),
      );
      expect(find.byType(TextField), findsNothing, reason: '남이 답변을 쓸 수 있다');
      expect(find.text('답변 등록'), findsNothing);
      expect(find.text('답변 삭제'), findsNothing);
      expect(find.textContaining('관리자가 확인하고 있어요'), findsOneWidget);
    });

    testWidgets('답변이 달리면 사용자에게 답변이 보인다', (t) async {
      await pumpPart(
        t,
        FnAnswerBlock(
          item: _mk(status: '답변완료', answer: '다음 업데이트에 넣겠습니다.'),
          isAdmin: false,
          onSave: (_) async {},
          onDelete: () async {},
        ),
      );
      expect(find.text('답변'), findsOneWidget);
      expect(find.text('다음 업데이트에 넣겠습니다.'), findsOneWidget);
      expect(find.text('26.09.19 14:05'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('🔴 관리자에게는 답변 입력칸이 바로 열려 있다', (t) async {
      await pumpPart(
        t,
        FnAnswerBlock(
          item: _mk(),
          isAdmin: true,
          onSave: (_) async {},
          onDelete: () async {},
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('답변 등록'), findsOneWidget);
      // 아직 아무것도 안 적었으니 꺼져 있어야 한다.
      expect(_btnBg(t, '답변 등록'), FnDs.buttonOffBg);

      await t.enterText(find.byType(TextField), '확인했습니다.');
      await t.pump(const Duration(milliseconds: 200));
      expect(_btnBg(t, '답변 등록'), FnDs.coral);
    });

    testWidgets('🔴 답변이 있으면 관리자에게 수정·삭제가 보인다', (t) async {
      await pumpPart(
        t,
        FnAnswerBlock(
          item: _mk(status: '답변완료', answer: '처리했습니다.'),
          isAdmin: true,
          onSave: (_) async {},
          onDelete: () async {},
        ),
      );
      expect(find.text('답변 수정'), findsOneWidget);
      expect(find.text('답변 삭제'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: '처음부터 열려 있으면 안 된다');

      await t.tap(find.text('답변 수정'));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('취소'), findsOneWidget);
    });

    testWidgets('답변 삭제를 누르면 콜백이 불린다', (t) async {
      var deleted = false;
      await pumpPart(
        t,
        FnAnswerBlock(
          item: _mk(status: '답변완료', answer: '처리했습니다.'),
          isAdmin: true,
          onSave: (_) async {},
          onDelete: () async => deleted = true,
        ),
      );
      await t.tap(find.text('답변 삭제'));
      await t.pump(const Duration(milliseconds: 200));
      expect(deleted, isTrue);
    });
  });

  group('공용 조각 — 사진 첨부', () {
    testWidgets('3장을 채우면 더 못 고른다고 알려 준다', (t) async {
      var tapped = 0;
      // 🔴 링크(Image.network)로 채우면 테스트에서 HTTP 400 이 난다.
      //    테스트 환경은 바깥으로 나가지 못한다. 그래서 진짜 바이트를 쓴다.
      await pumpPart(
        t,
        FnPhotoAttachField(
          newFiles: [_png(), _png(), _png()],
          onAdd: () => tapped++,
          onRemoveExisting: (_) {},
          onRemoveNew: (_) {},
        ),
      );
      expect(find.text('사진은 최대 3장까지예요'), findsOneWidget);
      await t.tap(find.text('사진은 최대 3장까지예요'));
      await t.pump();
      expect(tapped, 0, reason: '가득 찼는데 더 고를 수 있었다');
    });

    testWidgets('🔴 썸네일의 ⊗ 를 누르면 그 장만 빠진다', (t) async {
      final removed = <int>[];
      await pumpPart(
        t,
        FnPhotoAttachField(
          newFiles: [_png(), _png()],
          onAdd: () {},
          onRemoveExisting: (_) {},
          onRemoveNew: removed.add,
        ),
      );
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
      await t.tap(find.byIcon(Icons.close_rounded).last);
      await t.pump();
      expect(removed, [1], reason: '엉뚱한 장이 지워졌다');
    });

    testWidgets('비어 있으면 고를 수 있다', (t) async {
      var tapped = 0;
      await pumpPart(
        t,
        FnPhotoAttachField(
          onAdd: () => tapped++,
          onRemoveExisting: (_) {},
          onRemoveNew: (_) {},
        ),
      );
      await t.tap(find.text('사진 첨부하기'));
      await t.pump();
      expect(tapped, 1);
    });
  });

  group('문의 — 통합 기준(FnDs)을 쓴다', () {
    test('🔴 화면과 조각이 옛 토큰을 쓰면 안 된다', () {
      for (final f in [
        'lib/screens/ds/inquiry_ds_screen.dart',
        'lib/screens/ds/inquiry_list_ds_screen.dart',
        'lib/screens/ds/inquiry_detail_ds_screen.dart',
        'lib/widgets/fn_inquiry_parts.dart',
      ]) {
        final src = _read(f);
        expect(src.contains('fn_ds.dart'), isTrue, reason: '$f 가 기준을 안 쓴다');
        for (final old in [
          'FnColors.', 'FnHome.', 'FnSignup.', 'FnScan.', 'FnProfile.'
        ]) {
          expect(src.contains(old), isFalse, reason: '$f 에 $old 가 남아 있다');
        }
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

    test('🔴 구 화면(lib/screens/*.dart)은 건드리지 않았다', () {
      // 문의 기능은 ds 폴더 안에서만 산다.
      final dir = Directory('lib/screens');
      final touched = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.readAsStringSync().contains('Inquiry'))
          .map((f) => f.path)
          .toList();
      expect(touched, isEmpty, reason: '구 화면에 문의 코드가 들어갔다');
    });
  });

  group('문의 — 권한과 저장', () {
    test('첨부는 사진만 최대 3장이다', () {
      expect(InquiryService.maxFiles, 3);
      expect(InquiryService.maxFileBytes, 5 * 1024 * 1024);
    });

    test('압축 목표가 사장님 기준과 같다', () {
      expect(InquiryService.targetLongSide, 1600);
      expect(InquiryService.targetBytes, 1024 * 1024);
    });

    test('처리 상태는 접수 / 답변완료 두 가지다', () {
      expect(InquiryService.statusNew, '접수');
      expect(InquiryService.statusAnswered, '답변완료');
    });

    test('관리자 계정이 사장님이 정한 주소다', () {
      expect(InquiryService.adminEmail, 'flownote.kr@gmail.com');
    });

    test('카테고리 목록이 비어 있지 않다', () {
      expect(InquiryService.categories, isNotEmpty);
      expect(InquiryService.categories.first, '기능 제안');
    });

    test('답변이 달리면 수정할 수 없다', () {
      expect(_mk().editable, isTrue);
      expect(_mk(answer: '처리했습니다.').editable, isFalse);
      expect(_mk(answer: '처리했습니다.').isAnswered, isTrue);
      expect(_mk(answer: '   ').isAnswered, isFalse, reason: '공백은 답변이 아니다');
    });

    test('🔴 저장 위치와 필드를 바꾸면 안 된다', () {
      final src = _read('lib/services/inquiry_service.dart');
      expect(src.contains("collection('inquiries')"), isTrue);
      for (final field in [
        "'category'", "'content'", "'createdAt'", "'status'",
        "'uid'", "'email'", "'attachmentUrls'",
        "'answer'", "'answeredAt'",
      ]) {
        expect(src.contains(field), isTrue, reason: '$field 가 빠졌다');
      }
      expect(src.contains('FieldValue.serverTimestamp()'), isTrue,
          reason: '기기 시계를 쓰면 시간이 틀어진다');
    });

    test('🔴 사진이 아닌 파일은 아예 고를 수 없어야 한다', () {
      final src = _read('lib/services/inquiry_picker.dart');
      expect(src.contains("import 'package:file_picker"), isFalse,
          reason: '아무 파일이나 올릴 수 있게 되돌아갔다');
      expect(src.contains('pickMultiImage'), isTrue);
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

  group('문의 — 보안 규칙', () {
    test('🔴 남의 문의를 읽을 수 없어야 한다', () {
      final block = _read('firestore.rules')
          .split('match /inquiries/{docId}')[1]
          .split('match /{document=**}')[0];
      expect(block.contains('allow read: if isOwner(resource.data.uid)'), isTrue,
          reason: '본인 확인 없이 읽기를 열면 아무나 남의 글을 긁어간다');
      expect(block.contains('isAdmin()'), isTrue);
    });

    test('🔴 작성자가 status / answer 를 건드릴 수 없어야 한다', () {
      final block = _read('firestore.rules')
          .split('match /inquiries/{docId}')[1]
          .split('match /{document=**}')[0];
      expect(block.contains('hasOnly'), isTrue,
          reason: 'hasOnly 가 없으면 작성자가 자기 글을 답변완료로 바꿀 수 있다');
      expect(block.contains("'category', 'content'"), isTrue);
      expect(block.contains("'answer', 'answeredAt', 'status'"), isTrue);
    });

    test('🔴 관리자 주소가 세 곳에서 같아야 한다', () {
      const email = InquiryService.adminEmail;
      expect(_read('firestore.rules').contains(email), isTrue);
      expect(_read('storage.rules').contains(email), isTrue);
    });

    test('🔴 첨부는 사진만, 5MB 까지', () {
      final block = _read('storage.rules')
          .split('match /inquiries/{uid}/{allPaths=**}')[1]
          .split('match /{allPaths=**}')[0];
      expect(block.contains("contentType.matches('image/.*')"), isTrue,
          reason: '실행파일도 올라갈 수 있다');
      expect(block.contains('5 * 1024 * 1024'), isTrue,
          reason: '앱의 maxFileBytes 와 어긋나면 서버만 거부한다');
      expect(block.contains('isAdmin()'), isTrue,
          reason: '관리자가 못 읽으면 답변할 때 사진이 깨져 보인다');
    });
  });
}

/// 1×1 투명 PNG. 테스트에서 진짜 그릴 수 있는 가장 작은 사진.
InquiryAttachment _png() => InquiryAttachment(
      name: 'tiny.png',
      bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
          '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='),
      contentType: 'image/png',
    );

void _noop() {}

/// 버튼 바탕색.
Color _btnBg(WidgetTester t, String label) {
  final box = t.widget<Container>(find
      .ancestor(of: find.text(label), matching: find.byType(Container))
      .first);
  return (box.decoration as BoxDecoration).color!;
}

/// 글자색.
Color _textColor(WidgetTester t, String label) =>
    t.widget<Text>(find.text(label)).style!.color!;
