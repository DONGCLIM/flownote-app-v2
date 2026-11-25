import 'package:flutter/material.dart';
import 'dart:io' as io;
import 'package:flow_note/design/fn_home_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/providers/receipt_provider.dart';
import 'package:flow_note/screens/ds/scan_ds_screen.dart';
import 'package:flow_note/services/guest_service.dart';
import 'package:flow_note/services/subscription_service.dart';
import 'package:flow_note/services/training_data_service.dart';
import 'package:flow_note/widgets/fn_signup_sheet.dart';

/// 🔴 #101 — 스캔 메인 화면을 사장님이 준 시안으로 갈아끼웠다.
///
/// #100 에서 배운 것: **데이터 테스트만으로는 화면이 깨진 걸 못 잡는다.**
/// 날짜별 목록이 릴리즈에서 조용히 한 칸만 보였던 이유가 레이아웃 예외였고,
/// 그건 데이터 테스트 28개를 다 통과하면서도 일어났다. 그래서 UI 를 만질
/// 때는 렌더 테스트를 같이 넣는다.
///
/// 이 테스트가 지키는 것:
///  1. 화면이 예외 없이 그려진다 (`takeException() == null`)
///  2. 시안의 문구가 실제로 보인다
///  3. 일러스트(겹친 영수증 3장 + 카메라 FAB)가 실제로 그려진다
///  4. 프로/구독 문구가 화면에 남아있지 않다 (#98 지시)
///  5. 좁은 화면에서도 오버플로가 없다 (시안은 402x874 고정이지만
///     우리는 실제 기기 폭을 다 받는다)

/// `ReceiptProvider` 는 Hive Box 를 열어야 해서 테스트에서 그대로 못 쓴다.
/// 화면이 실제로 읽는 것은 `allReceipts` 하나뿐이므로 그것만 바꿔 끼운다.
class _FakeReceiptProvider extends ReceiptProvider {
  _FakeReceiptProvider(this._items);
  final List<ReceiptModel> _items;

  @override
  List<ReceiptModel> get allReceipts => _items;
}

ReceiptModel _r(String id, DateTime createdAt) => ReceiptModel(
      id: id,
      date: createdAt,
      storeName: '테스트상회',
      items: const [],
      totalAmount: 10000,
      rawOcrText: 'test',
      createdAt: createdAt,
    );

Widget _wrap(List<ReceiptModel> items, {Size size = const Size(402, 874)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: ChangeNotifierProvider<ReceiptProvider>.value(
        value: _FakeReceiptProvider(items),
        child: const Scaffold(body: ScanDsScreen()),
      ),
    ),
  );
}

void main() {
  testWidgets('스캔 메인이 예외 없이 그려지고 시안 문구가 보인다', (t) async {
    await t.pumpWidget(_wrap(const []));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull,
        reason: '레이아웃 예외가 나면 릴리즈에서는 조용히 깨진다');

    expect(find.text('오늘 촬영한 영수증 0장'), findsOneWidget);
    expect(find.textContaining('이번 달 무료 스캔'), findsOneWidget);
    // #136 시안의 버튼 문구
    expect(find.text('영수증 촬영하기'), findsOneWidget);
    expect(find.text('앨범에서 가져오기'), findsOneWidget);

    // 팁 카드
    expect(find.text('촬영 전 스캔 팁'), findsOneWidget);
    expect(find.text('밝은 환경에서'), findsOneWidget);
    expect(find.text('영수증 전체가 보이게'), findsOneWidget);
    expect(find.text('인식 후 수정 가능'), findsOneWidget);
    // #136 시안은 체크 칩이 아니라 01 / 02 / 03 번호다.
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
  });

  testWidgets('히어로 일러스트 — 영수증 3장이 그려진다 (#136)', (t) async {
    await t.pumpWidget(_wrap(const []));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    // #136 시안 실측: 일러스트 bbox 206.1 x 162.4 dp
    final art = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 206 && w.height == 162);
    expect(art, findsOneWidget);

    // 겹친 영수증 3장 — 가운데 1장(86x122) + 좌우 2장(74x104)
    final big = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxWidth == 86 &&
        w.constraints?.maxHeight == 122);
    final small = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxWidth == 74 &&
        w.constraints?.maxHeight == 104);
    expect(big, findsOneWidget);
    expect(small, findsNWidgets(2));

    // 🔴 시안 일러스트에는 코랄 카메라 FAB 가 없다.
    //    (일러스트 영역에서 검출된 코랄 175픽셀은 가운데 영수증의
    //     분홍 머리글 줄 #F6C2C6 이었다 — 픽셀로 확인했다)
    //    카메라 아이콘은 '영수증 촬영하기' 버튼 안에만 하나 있다.
    expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
    final inButton = find.descendant(
      of: find.ancestor(
        of: find.text('영수증 촬영하기'),
        matching: find.byType(Row),
      ).first,
      matching: find.byIcon(Icons.photo_camera_rounded),
    );
    expect(inButton, findsOneWidget,
        reason: '카메라 아이콘은 버튼 안에 있어야 한다');
  });

  testWidgets("'오늘' 은 createdAt 기준으로 센다 (기능 유지)", (t) async {
    final now = DateTime.now();
    await t.pumpWidget(_wrap([
      // date 는 과거지만 createdAt 이 오늘 → 오늘 촬영한 것으로 센다
      _r('a', now),
      _r('b', now),
      // 어제 찍은 것은 세지 않는다
      _r('c', now.subtract(const Duration(days: 1))),
    ]));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('오늘 촬영한 영수증 2장'), findsOneWidget);
  });

  testWidgets('프로/구독 문구가 화면에 남아있지 않다 (#98)', (t) async {
    await t.pumpWidget(_wrap(const []));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    expect(find.textContaining('PRO'), findsNothing);
    expect(find.textContaining('무제한'), findsNothing);
  });


  // ───────────────────────────────────────────────────────────────────
  //  #136 — 스캔 화면을 시안 PNG 톤앤톤으로 다시 그린 뒤의 회귀 방지
  //
  //  시안 실측 (473x1024, 환산비 0.8245 -> 390x844dp):
  //    페이지 배경 #FEF9F5 (37.8%) / 흰 카드 #FFFFFF (24.7%)
  //    코랄 버튼 #FF6D78 단색 / 보조 버튼 #FEFDFB
  //    팁 카드 좌우 여백 23.9dp · r 14.2dp
  //    버튼 높이 52.8 / 54.4dp — 둘 다 알약(r = h/2)
  // ───────────────────────────────────────────────────────────────────

  testWidgets('#136 시안 색이 실제로 칠해진다', (t) async {
    await t.pumpWidget(_wrap(const []));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    final used = <int>{};
    void add(Color? c) {
      if (c != null) used.add(c.toARGB32());
    }

    for (final e in find.byType(Container).evaluate()) {
      final w = e.widget as Container;
      add(w.color);
      final d = w.decoration;
      if (d is BoxDecoration) {
        add(d.color);
        final b = d.border;
        if (b is Border) add(b.top.color);
      }
    }
    // 페이지 배경은 `ColoredBox` 로 칠한다 (Container 가 아니다).
    for (final e in find.byType(ColoredBox).evaluate()) {
      add((e.widget as ColoredBox).color);
    }
    for (final e in find.byType(Text).evaluate()) {
      add((e.widget as Text).style?.color);
    }
    for (final e in find.byType(Icon).evaluate()) {
      add((e.widget as Icon).color);
    }

    expect(used, contains(0xFFFEF9F5), reason: '페이지 배경 #FEF9F5');
    expect(used, contains(0xFFFF6D78), reason: '코랄 버튼 #FF6D78');
    expect(used, contains(0xFFFEFDFB), reason: '보조 버튼 #FEFDFB');
    expect(used, contains(0xFFC76769), reason: '팁 번호 #C76769');
  });

  testWidgets('#136 두 버튼이 알약 모양이다', (t) async {
    await t.pumpWidget(_wrap(const []));
    await t.pumpAndSettle();

    // 🔴 #137 재실측: 촬영 52.8dp / 앨범 56.9dp 로 **서로 다르다**.
    //    전에는 둘 다 54 로 통일했는데, 앨범이 3dp 낮았다.
    const want = <String, double>{
      '영수증 촬영하기': FnHome.buttonH,
      '앨범에서 가져오기': FnHome.buttonH2,
    };
    for (final e in want.entries) {
      final box = find
          .ancestor(of: find.text(e.key), matching: find.byType(Container))
          .first;
      final rect = t.getRect(box);
      expect(rect.height, closeTo(e.value, 0.5), reason: '${e.key} 높이');

      final c = t.widget<Container>(box);
      final dec = c.decoration as BoxDecoration;
      final br = dec.borderRadius! as BorderRadius;
      expect(br.topLeft.x, closeTo(e.value / 2, 0.5),
          reason: '${e.key} 은 알약이어야 한다 (r = 높이/2)');
    }
  });

  testWidgets('#136 좌우 여백이 대칭이다 (시안 23.9dp)', (t) async {
    await t.pumpWidget(_wrap(const [], size: const Size(390, 844)));
    await t.pumpAndSettle();

    final screen = t.getSize(find.byType(ScanDsScreen));
    final box = find
        .ancestor(
            of: find.text('영수증 촬영하기'), matching: find.byType(Container))
        .first;
    final r = t.getRect(box);
    final left = r.left;
    final right = screen.width - r.right;
    expect((left - right).abs(), lessThan(1.0),
        reason: '좌 $left / 우 $right — 어긋났다');
    expect(left, closeTo(FnHome.scanPad, 1.0));
  });

  testWidgets('#136 한도에 닿으면 촬영을 막는다 (기능 유지)', (t) async {
    // 한도 판단은 SubscriptionService.canScan 이 그대로 쓰인다.
    // 지금은 unlockEverything 이라 늘 촬영 가능 — 그 상태를 고정한다.
    expect(SubscriptionService.instance.canScan, isTrue);
    await t.pumpWidget(_wrap(const []));
    await t.pumpAndSettle();
    expect(find.text('영수증 촬영하기'), findsOneWidget);
    expect(find.text('이번 달 스캔 한도 도달'), findsNothing);
  });

  testWidgets('#136 기능 연결이 소스에 그대로 있다', (t) async {
    final src = io.File('lib/screens/ds/scan_ds_screen.dart')
        .readAsStringSync()
        .split('\n')
        .where((l) {
          final x = l.trim();
          return !x.startsWith('//') && !x.startsWith('///');
        })
        .join('\n');
    for (final name in [
      'showCameraOptions',          // 탭 재탭 시 촬영 열기
      'ScanFlow.start(context)',    // 촬영 흐름
      'ScanFlow.startFromGallery',  // 앨범 흐름
      'PlanPolicy.freeMonthlyScans',// 무료 한도
      'sub.canScan',                // 한도 판단
      'sub.scansThisMonth',         // 사용량
      'createdAt',                  // 오늘 집계 기준
      'ListenableBuilder',          // 구독 변화 반영
    ]) {
      expect(src, contains(name), reason: '$name 이(가) 사라졌다');
    }
  });


  testWidgets('#136 배경이 화면 끝까지 칠해진다', (t) async {
    // 🔴 처음엔 `Container(color:)` 로만 감쌌더니 배경이 내용 높이까지만
    //    칠해졌다. `FnColumn` 이 `SingleChildScrollView` 여서 높이가
    //    내용만큼이기 때문이다. 390x844 렌더를 픽셀로 재 보니
    //    678.5dp 아래 165dp 가 #FEF7FF 로 남아 있었다.
    //    `SizedBox.expand` 로 화면을 먼저 채워서 고쳤다.
    // 🔴 화면 크기를 `tester.view` 로 **실제로** 바꿔야 한다.
    //    MediaQuery 만 끼우면 뷰포트는 기본 800x600 이라, 배경 높이와
    //    ScanDsScreen 높이가 같이 줄어들어 비교가 자기 자신과의 비교가
    //    된다. (처음에 그렇게 써서 일부러 망친 코드도 통과해 버렸다)
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(_wrap(const [], size: const Size(390, 844)));
    await t.pumpAndSettle();

    final painted = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == FnHome.bgWarm);
    expect(painted, findsOneWidget, reason: '배경을 칠하는 박스가 없다');

    final box = t.getRect(painted.first);
    // 뷰포트 높이와 직접 비교한다 (자기 자손과 비교하면 안 된다).
    expect(box.height, closeTo(844.0, 1.0),
        reason: '배경 높이 ${box.height} — 화면 844 를 다 못 덮었다');
    expect(box.width, closeTo(390.0, 1.0));
  });

  testWidgets('좁은 화면(320)에서도 오버플로가 없다', (t) async {
    await t.pumpWidget(_wrap(const [], size: const Size(320, 640)));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull,
        reason: '시안은 402 고정이지만 실제 기기 폭은 더 좁을 수 있다');
    expect(find.text('영수증 촬영하기'), findsOneWidget);
  });

  test('스캔 한도 계산은 그대로다 (기능 유지)', () {
    // 화면 문구를 시안 하나로 통일했지만, 한도 정책은 손대지 않았다.
    expect(PlanPolicy.freeMonthlyScans, 100);
  });

  _k195GuestScan();
}

// ─────────────────────────────────────────────────────────────────────
//  #195 게스트 체험 ③ — 스캔 한도 · 체험 안내 · 학습 수집 제외
//
//  🔴 테스트에는 Firebase 가 없어 `isAnonymous` 를 만들 수 없다.
//     `GuestService.debugIsGuest` 로 게스트인 척하고, 쓴 장수는
//     `setForTest` 로 넣는다. 실제 앱은 두 가지 다 건드리지 않는다.
// ─────────────────────────────────────────────────────────────────────
void _k195GuestScan() {
  group('#195 게스트 스캔 한도', () {
    tearDown(() {
      GuestService.debugIsGuest = null;
      GuestService.instance.setForTest();
    });

    testWidgets('🔴 게스트에게는 남은 체험 장수가 보인다', (t) async {
      GuestService.debugIsGuest = true;
      GuestService.instance.setForTest(scans: 2);
      await t.pumpWidget(_wrap(const []));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.text('무료 체험 3장 남았어요'), findsOneWidget);
      // 달 한도 문구는 게스트에게 뜻이 없다.
      expect(find.textContaining('이번 달 무료 스캔'), findsNothing);
    });

    testWidgets('🔴 회원에게는 예전 문구 그대로다', (t) async {
      GuestService.debugIsGuest = false;
      await t.pumpWidget(_wrap(const []));
      await t.pumpAndSettle();

      expect(find.textContaining('이번 달 무료 스캔'), findsOneWidget);
      expect(find.textContaining('무료 체험'), findsNothing);
    });

    testWidgets('🔴 아무 설정도 안 하면(기본값) 회원 문구다', (t) async {
      // 실제 앱에서 `debugIsGuest` 는 늘 null 이다. 여기서 게스트 갈래로
      // 새면 가입하신 분들 화면에 체험 문구가 뜬다.
      expect(GuestService.debugIsGuest, isNull);
      await t.pumpWidget(_wrap(const []));
      await t.pumpAndSettle();
      expect(find.textContaining('이번 달 무료 스캔'), findsOneWidget);
    });

    testWidgets('🔴 게스트가 5장을 다 쓰면 6번째는 스캔 대신 가입 안내다',
        (t) async {
      GuestService.debugIsGuest = true;
      GuestService.instance.setForTest(scans: GuestService.scanMax);
      await t.pumpWidget(_wrap(const []));
      await t.pumpAndSettle();

      expect(find.text('무료 체험 0장 남았어요'), findsOneWidget);

      await t.tap(find.text('영수증 촬영하기'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(t.takeException(), isNull);
      expect(find.text(kSignUpSheetTitle), findsOneWidget);
      // 촬영 시트(단일/연속)는 열리지 않았다.
      expect(find.textContaining('연속 촬영'), findsNothing);
    });

    testWidgets('🔴 앨범에서 가져오기도 같이 막힌다', (t) async {
      // 한쪽만 막으면 앨범으로 얼마든지 더 넣을 수 있다.
      GuestService.debugIsGuest = true;
      GuestService.instance.setForTest(scans: GuestService.scanMax);
      await t.pumpWidget(_wrap(const []));
      await t.pumpAndSettle();

      // 🔴 테스트 화면(800x600)에서는 이 버튼이 스크롤 아래에 있다.
      //    그냥 tap 하면 화면 밖을 눌러 아무 일도 안 일어난다.
      await t.ensureVisible(find.text('앨범에서 가져오기'));
      await t.pump();
      await t.tap(find.text('앨범에서 가져오기'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text(kSignUpSheetTitle), findsOneWidget);
    });

    testWidgets('🔴 게스트 첫 장은 찍기 전에 보관 안내에 동의를 받는다',
        (t) async {
      GuestService.debugIsGuest = true;
      GuestService.instance.setForTest(scans: 0);
      await t.pumpWidget(_wrap(const []));
      await t.pumpAndSettle();

      await t.tap(find.text('영수증 촬영하기'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(t.takeException(), isNull);
      expect(find.text(kTrialConsentTitle), findsOneWidget);
      expect(
          find.text('체험으로 찍은 영수증은 가입하지 않으면 30일 뒤 삭제돼요'),
          findsOneWidget);
      expect(find.text('개인정보 처리방침 보기'), findsOneWidget);
    });

    testWidgets('🔴 이미 동의했으면 두 번 묻지 않는다', (t) async {
      GuestService.debugIsGuest = true;
      GuestService.instance.setForTest(scans: 1, agreed: true);
      await t.pumpWidget(_wrap(const []));
      await t.pumpAndSettle();

      await t.tap(find.text('영수증 촬영하기'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text(kTrialConsentTitle), findsNothing);
    });
  });

  group('#195 게스트 영수증은 학습 데이터로 보내지 않는다', () {
    tearDown(() => GuestService.debugIsGuest = null);

    test('🔴 게스트면 수집하지 않는다', () {
      // 막는 이유는 보안이 아니라 **동의**다. 게스트는 가입 절차가 없어
      // 학습 활용 동의를 받은 적이 없다.
      GuestService.debugIsGuest = true;
      expect(TrainingDataService.collectAllowed, isFalse);
    });

    test('🔴 회원은 지금처럼 수집한다', () {
      GuestService.debugIsGuest = false;
      expect(TrainingDataService.collectAllowed, isTrue);
    });

    test('🔴 기본값(실제 앱)은 수집하는 쪽이다', () {
      // 판정이 흔들리면 회원 쪽으로 기운다. 게스트 한 명을 놓치는 것보다
      // 회원 수집이 조용히 멈추는 게 훨씬 나쁘다.
      expect(GuestService.debugIsGuest, isNull);
      expect(TrainingDataService.collectAllowed, isTrue);
    });

    test('🔴 세 길목(문서·수정본·이미지)에 전부 걸려 있다', () {
      final src =
          io.File('lib/services/training_data_service.dart').readAsStringSync();
      // 하나만 막으면 나머지로 샌다. `receipts/**` 업로드가 특히 그렇다.
      expect('collectAllowed'.allMatches(src).length, greaterThanOrEqualTo(4));
      final up = src.indexOf('Future<String?> _uploadImage');
      expect(src.indexOf('collectAllowed', up), greaterThan(up));
    });

    test('🔴 보안 규칙은 건드리지 않았다 (#194 재발 방지)', () {
      // 막는 일을 앱이 하므로 규칙을 고칠 이유가 없다. 이 두 줄이 바로
      // #194 에서 **회원** 영수증 저장을 막았던 자리다.
      final fs = io.File('firestore.rules').readAsStringSync();
      final st = io.File('storage.rules').readAsStringSync();
      expect(fs.substring(fs.indexOf('match /training_data/{docId}')),
          contains('allow create: if isSignedIn();'));
      expect(
          st
              .substring(st.indexOf('match /receipts/{allPaths=**}'))
              .substring(0, 220),
          contains('allow write: if isSignedIn()'));
    });
  });

  group('#195 게스트 횟수는 저장 성공 지점에서만 센다', () {
    test('🔴 저장이 끝난 뒤에 장당 한 번 올린다', () {
      final src = io.File('lib/screens/ds/scan_review_ds_screen.dart')
          .readAsStringSync();
      // 세는 곳은 한 곳뿐이어야 한다. 여러 곳이면 두 번 세거나 빠진다.
      expect('GuestService.instance.countScan()'.allMatches(src).length, 1);
      // `addReceipt` 가 **끝난 뒤**라야 실패·다시 찍기가 안 세진다.
      final add = src.indexOf('await provider.addReceipt(d.toReceipt());');
      final count = src.indexOf('await GuestService.instance.countScan();');
      expect(add, greaterThan(0));
      expect(count, greaterThan(add));
    });

    test('🔴 회원은 횟수를 세지 않는다', () {
      final src =
          io.File('lib/services/guest_service.dart').readAsStringSync();
      final body = src.substring(src.indexOf('Future<bool> countScan()'));
      // 첫 줄에서 그냥 돌아간다.
      expect(body.indexOf('if (!isGuest) return true;'),
          lessThan(body.indexOf('_scans = _scans + 1;')));
    });

    test('🔴 한도를 넘으면 올리지 않는다', () {
      final src =
          io.File('lib/services/guest_service.dart').readAsStringSync();
      final body = src.substring(src.indexOf('Future<bool> countScan()'));
      expect(body, contains('if (_scans >= scanMax) return false;'));
    });

    test('🔴 체험은 아직 꺼져 있다', () {
      expect(GuestService.enabled, isFalse);
    });
  });
}
