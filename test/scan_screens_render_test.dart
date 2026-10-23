import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flow_note/design/fn_scan_tokens.dart';
import 'package:flow_note/screens/ds/scan_processing_ds_screen.dart';
import 'package:flow_note/screens/scan/scan_draft.dart';

/// 🔴 #161 — 사장님이 주신 스캔 4화면 시안을 코드로 고정한다.
///
///   ① 갤러리        `scan_gallery_ds_screen.dart`  (신규)
///   ② 영수증 촬영   `scan_camera_ds_screen.dart`
///   ③ 영수증 인식 중 `scan_processing_ds_screen.dart`
///   ④ 인식 결과 확인 `scan_review_ds_screen.dart`
///
/// 토큰은 시안 PNG 를 픽셀로 재서 뽑았다. 이 테스트는 **그 숫자가
/// 조용히 바뀌는 것**을 막는다. 자기참조(토큰끼리 비교)는 사보타주를
/// 못 잡으므로 전부 **리터럴**과 비교한다.
void main() {
  Future<void> pump(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(393 * 3, 852 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: w));
    await t.pump(const Duration(milliseconds: 60));
  }

  group('#161 스캔 시안 토큰', () {
    test('🔴 페이지 배경은 크림 #FEF9F5 다', () {
      // 시안 네 장 중 세 장의 최빈색이 정확히 이 값이었다.
      expect(FnScan.bg, const Color(0xFFFEF9F5));
      expect(FnScan.camBg, const Color(0xFF171717));
    });

    test('🔴 코랄 계열 실측값', () {
      // 진행바 채움 rgb(251,111,122) / 버튼 면 rgb(233,119,127)
      expect(FnScan.coral, const Color(0xFFFB6F7A));
      expect(FnScan.coralBtn, const Color(0xFFE9777F));
      expect(FnScan.track, const Color(0xFFFFE3DF));
    });

    test('🔴 갤러리 그리드 기하 (pitch 142px 에서 역산)', () {
      expect(FnScan.galCols, 3);
      expect(FnScan.galPad, closeTo(21.6, 0.05));
      expect(FnScan.galGapX, closeTo(4.2, 0.05));
      expect(FnScan.galGapY, closeTo(7.5, 0.05));
      expect(FnScan.galTileAspect, closeTo(0.80, 0.005));
      expect(FnScan.galCheck, closeTo(19.1, 0.05));
    });

    test('🔴 인식 중 화면 치수', () {
      expect(FnScan.procPad, closeTo(18.3, 0.05));
      expect(FnScan.procCardH, closeTo(91.4, 0.05));
      expect(FnScan.procBarH, closeTo(8.0, 0.01));
    });

    test('🔴 결과 화면 치수', () {
      expect(FnScan.resPhotoPad, closeTo(22.3, 0.05));
      expect(FnScan.resPhotoH, closeTo(288.5, 0.05));
      expect(FnScan.resCardPad, closeTo(18.8, 0.05));
      expect(FnScan.resZoomH, closeTo(40.0, 0.01));
    });
  });

  group('#161 ③ 인식 중 화면', () {
    testWidgets('🔴 시안 제목·부제가 보인다', (t) async {
      await pump(
          t, ScanProcessingDsScreen(drafts: [ScanDraft(file: XFile('/x.jpg'))]));
      expect(find.text('영수증을 읽고 있어요'), findsOneWidget);
      expect(find.text('품목과 금액을 꼼꼼하게 정리하고 있어요.'), findsOneWidget);
      expect(find.text('인식 진행 중'), findsOneWidget);
      expect(find.text('결과 확인하기'), findsOneWidget);
    });

    testWidgets('🔴 영수증 일러스트가 글자 위에 있다', (t) async {
      await pump(
          t, ScanProcessingDsScreen(drafts: [ScanDraft(file: XFile('/x.jpg'))]));
      final illu = find.byType(SizedBox).evaluate().where((e) {
        final w = e.widget as SizedBox;
        return w.width != null && (w.width! - 208.0).abs() < 0.5;
      });
      expect(illu.isNotEmpty, isTrue,
          reason: '일러스트(폭 208dp)가 사라졌다');
      final illuY = t.getTopLeft(find.byWidget(illu.first.widget)).dy;
      final headY = t.getTopLeft(find.text('영수증을 읽고 있어요')).dy;
      expect(illuY, lessThan(headY), reason: '그림이 글자 아래로 내려갔다');
    });

    testWidgets('🔴 Pro 혜택 카드는 더이상 없다 (시안에 없음)', (t) async {
      await pump(
          t, ScanProcessingDsScreen(drafts: [ScanDraft(file: XFile('/x.jpg'))]));
      expect(find.textContaining('Pro 업그레이드'), findsNothing);
    });

    test('🔴 비율 배치(Spacer flex 3/4)로 되돌리지 않았다', () {
      // Spacer 비율로 두면 카드가 시안보다 151dp 아래로 밀렸었다.
      final code =
          File('lib/screens/ds/scan_processing_ds_screen.dart')
              .readAsStringSync();
      expect(code.contains('Spacer(flex: 4)'), isFalse,
          reason: '비율 배치로 되돌아갔다 — 카드가 아래로 밀린다');
      expect(code.contains('SizedBox(height: 60)'), isTrue,
          reason: '시안 상단 고정 여백이 사라졌다');
    });
  });

  group('#161 ① 갤러리 화면', () {
    test('🔴 화면 파일이 존재하고 photo_manager 를 쓴다', () {
      final f = File('lib/screens/ds/scan_gallery_ds_screen.dart');
      expect(f.existsSync(), isTrue, reason: '갤러리 화면이 사라졌다');
      final code = f.readAsStringSync();
      expect(code.contains("package:photo_manager/photo_manager.dart"), isTrue,
          reason: '앨범을 직접 읽지 않으면 시안대로 못 그린다');
      expect(code.contains('FnScan.galCols'), isTrue);
      expect(code.contains('PickedGalleryPhoto'), isTrue);
    });

    test('🔴 pubspec 에 photo_manager 가 있다', () {
      final y = File('pubspec.yaml').readAsStringSync();
      expect(y.contains('photo_manager:'), isTrue);
    });

    test('🔴 ScanFlow 가 앱에서 이 화면을 띄운다', () {
      final code =
          File('lib/screens/scan/scan_flow.dart').readAsStringSync();
      expect(code.contains('ScanGalleryDsScreen('), isTrue,
          reason: '갤러리 화면이 흐름에서 끊겼다');
      expect(code.contains('if (!kIsWeb)'), isTrue,
          reason: '웹 분기가 사라지면 웹에서 빈 화면이 뜬다');
    });
  });

  group('#161 ②④ 촬영·결과 화면', () {
    test('🔴 촬영 화면은 이전 상태 그대로 둔다 (#162 사장님 지시)', () {
      // 사장님: "영수증 촬영은 이전대로 해주고"
      // #161 에서 제목·배지를 시안값으로 바꿨다가 되돌렸다.
      // 촬영 화면은 화각(#147~#154) 때문에 여섯 번을 고친 곳이라
      // 손대면 또 어긋난다. 디자인 변경 대상에서 제외한다.
      final code =
          File('lib/screens/ds/scan_camera_ds_screen.dart').readAsStringSync();
      expect(code.contains("this.navTitle = '',"), isTrue,
          reason: '촬영 화면 제목이 다시 바뀌었다');
      expect(code.contains('Color(0x4DF2687A)'), isTrue,
          reason: '촬영 화면 배지색이 다시 바뀌었다');

      // 화각 수정(#154)은 반드시 살아 있어야 한다.
      expect(code.contains('return shortSide / longSide;'), isTrue,
          reason: '#154 방향 정규화가 사라지면 프레임이 가로로 눕는다');
      expect(code.contains('frameAspect = 0.62'), isTrue,
          reason: '가이드 프레임 비율이 바뀌었다');
    });

    test('🔴 결과 화면이 시안 사진 카드와 줌 알약을 쓴다', () {
      final code =
          File('lib/screens/ds/scan_review_ds_screen.dart').readAsStringSync();
      expect(code.contains('_zoomBar()'), isTrue,
          reason: '줌 알약이 사라졌다');
      expect(code.contains('FnScan.resPhotoH'), isTrue,
          reason: '사진 카드 높이가 시안 토큰을 안 쓴다');
      expect(code.contains('bg: FnScan.bg'), isTrue,
          reason: '배경이 크림색이 아니다');
      // 주석에도 걸리는 문자열 검사 대신, 회색 툴바의 회전 아이콘만 금지한다.
      //  - '원본 영수증' 은 시안 원문을 적어 둔 주석에도 들어 있다.
      //  - `_toolBtn` 은 날짜 선택 버튼에도 쓰여서 금지할 수 없다.
      expect(code.contains('Icons.rotate_left,'), isFalse,
          reason: 'old gray toolbar came back');
    });
  });

  // ===================================================================
  // 🔴 #162 — "영수증 촬영하고 나면 이렇게 뜨고 다음으로 안 넘어간다"
  //
  // 사장님이 보내주신 화면에 원인이 그대로 찍혀 있었다.
  //   API 오류 (402): Your prepayment credits are depleted.
  //
  // 즉 앱 버그가 아니라 **AI 크레딧 소진**이다. (지금은 충전되어 복구됨.
  //  같은 키로 이미지 포함 OCR 요청을 보내 HTTP 200 을 확인했다)
  //
  // 그런데 그때 다이얼로그 버튼이 `닫기` 하나뿐이라 **흐름이 거기서
  // 끝났다.** 402 는 사진 문제가 아니므로 '다시 찍기' 는 의미가 없고,
  // 잠시 뒤 같은 사진으로 다시 돌리면 대부분 된다. 그 길을 열었다.
  // ===================================================================
  group('#162 인식 실패 후 다음으로 넘어갈 수 있다', () {
    final flow = File('lib/screens/scan/scan_flow.dart').readAsStringSync();

    test('🔴 402/크레딧 오류를 재시도 가능으로 분류한다', () {
      // ⚠️ 'canRerun' 이라는 단어만 찾으면 `canRerun: false` 로 바꿔도
      //    통과한다(실제로 사보타주에 뚫렸다). 켜진 값을 확인한다.
      expect(flow.contains('canRerun: true,'), isTrue,
          reason: '재시도 경로가 꺼졌다 — 402 에서 또 멈춘다');
      expect(flow.contains("has('402')"), isTrue,
          reason: '402 를 따로 집어내지 않으면 안내 문구가 엉뚱해진다');
      expect(flow.contains('credits are depleted'), isTrue,
          reason: '크레딧 소진을 알아보지 못한다');
    });

    test('🔴 같은 사진으로 다시 돌리는 경로가 연결돼 있다', () {
      expect(
          flow.contains('await runWithFiles(context, files, '
              'forcedDate: forcedDate);'),
          isTrue,
          reason: '재시도를 눌러도 사진을 다시 고르라고 하면 의미가 없다');
    });

    test('🔴 버튼이 닫기 하나만 남지 않는다', () {
      expect(flow.contains("confirm = '다시 시도';"), isTrue,
          reason: '재시도 버튼이 사라졌다');
      expect(
          flow.contains('cancelLabel: (why.canRetry || why.canRerun) '
              "? '닫기' : null,"),
          isTrue,
          reason: '취소 버튼 조건이 바뀌었다');
    });

    test('🔴 크레딧 문제를 촬영 탓으로 돌리지 않는다', () {
      expect(flow.contains('사진이나 촬영 문제가 아니에요.'), isTrue,
          reason: '사장님이 조명·구도를 고치려 헛수고하게 된다');
    });
  });
}
