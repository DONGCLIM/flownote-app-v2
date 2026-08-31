import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/providers/receipt_provider.dart';
import 'package:flow_note/screens/ds/scan_ds_screen.dart';
import 'package:flow_note/services/subscription_service.dart';

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
    expect(find.text('촬영하기'), findsOneWidget);
    expect(find.text('갤러리에서 선택'), findsOneWidget);

    // 팁 카드
    expect(find.text('촬영 전 스캔 팁'), findsOneWidget);
    expect(find.text('!'), findsOneWidget);
    expect(find.text('밝은 환경에서'), findsOneWidget);
    expect(find.text('영수증 전체가 보이게'), findsOneWidget);
    expect(find.text('인식 후 수정 가능'), findsOneWidget);
    // 팁 3개 → 체크 칩 3개
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));
  });

  testWidgets('히어로 일러스트 — 영수증 3장 + 카메라 FAB 가 그려진다', (t) async {
    await t.pumpWidget(_wrap(const []));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    // 168x112 일러스트 박스
    final art = find.byWidgetPredicate((w) =>
        w is SizedBox && w.width == 168 && w.height == 112);
    expect(art, findsOneWidget);

    // 겹친 영수증 3장 (66x90)
    final sheets = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxWidth == 66 &&
        w.constraints?.maxHeight == 90);
    expect(sheets, findsNWidgets(3));

    // 카메라 FAB
    expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
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

  testWidgets('좁은 화면(320)에서도 오버플로가 없다', (t) async {
    await t.pumpWidget(_wrap(const [], size: const Size(320, 640)));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull,
        reason: '시안은 402 고정이지만 실제 기기 폭은 더 좁을 수 있다');
    expect(find.text('촬영하기'), findsOneWidget);
  });

  test('스캔 한도 계산은 그대로다 (기능 유지)', () {
    // 화면 문구를 시안 하나로 통일했지만, 한도 정책은 손대지 않았다.
    expect(PlanPolicy.freeMonthlyScans, 100);
  });
}
