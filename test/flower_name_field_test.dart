import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/services/flower_name_service.dart';
import 'package:flow_note/widgets/flower_name_field.dart';

/// `FlowerNameField` 위젯 동작 검증.
///
/// 특히 확인해야 하는 것:
/// - 드롭다운이 Overlay 로 뜨는지 (부모 스크롤에 잘리면 안 됨)
/// - 후보를 탭했을 때 **표준명**이 입력란에 들어가는지
/// - 사전 로딩 실패 시에도 입력 자체는 계속 되는지 (편집 화면이 막히면 안 됨)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = FlowerNameService.instance;

  Future<void> loadDict() async {
    final raw = await rootBundle.loadString('assets/data/flower_names.json');
    svc.resetForTest();
    svc.loadFromJsonForTest(raw);
  }

  Widget host(TextEditingController c, {VoidCallback? onChanged}) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              FlowerNameField(controller: c, onChanged: onChanged),
              const SizedBox(height: 400),
            ],
          ),
        ),
      ),
    );
  }

  group('자동완성 동작', () {
    setUp(loadDict);

    testWidgets('탭하면 드롭다운이 뜨고 이번 달 추천 품목이 보인다', (t) async {
      final c = TextEditingController();
      final svc = FlowerNameService.instance;
      await t.pumpWidget(host(c));

      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();

      // Build 22 부터 추천은 계절을 탄다. 특정 이름(`장미`)을 못 박으면
      // 8월엔 통과하고 3월엔 깨지는 테스트가 된다. 그래서 서비스가 실제로
      // 내려주는 첫 후보가 화면에 있는지로 검증한다.
      final expected = svc.suggest('', limit: 9);
      expect(expected, isNotEmpty);
      expect(find.text(expected.first.name), findsWidgets);

      // footer 안내가 함께 뜬다. 시세 문구는 여기서 뺐다 —
      // 시세는 이름 확정 후 항목 카드(`FlowerPriceLine`)에서 보여준다.
      expect(find.textContaining('적은 그대로 저장돼요'), findsOneWidget);
      expect(find.textContaining('속'), findsNothing);
      // 이번 달을 알려주는 문구도 함께
      expect(find.textContaining('${svc.currentMonth}월 제철'), findsOneWidget);
    });

    testWidgets('타이핑하면 후보가 좁혀진다', (t) async {
      final c = TextEditingController();
      await t.pumpWidget(host(c));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), '리시안');
      await t.pumpAndSettle();

      expect(find.text('리시안사스'), findsWidgets);
    });

    testWidgets('후보를 탭했을 때만 이름이 바뀐다', (t) async {
      final c = TextEditingController();
      await t.pumpWidget(host(c));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), '리시안셔스');
      await t.pumpAndSettle();

      // 아직 아무것도 안 눌렀으면 입력한 글자 그대로다 (강요 없음)
      expect(c.text, '리시안셔스');

      await t.tap(find.text('리시안사스').first);
      await t.pumpAndSettle();
      expect(c.text, '리시안사스');
    });

    testWidgets('맨 위 후보는 언제나 “내가 친 그대로” 다', (t) async {
      // 강요 구조 제거의 핵심. 사전에 없는 이름이든 있는 이름이든
      // 1순위는 사장님이 친 글자다.
      final c = TextEditingController();
      await t.pumpWidget(host(c));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), '리시안셔스');
      await t.pumpAndSettle();

      expect(find.text('입력한 그대로 저장'), findsOneWidget);
      await t.tap(find.text('입력한 그대로 저장'));
      await t.pumpAndSettle();
      expect(c.text, '리시안셔스');
    });

    testWidgets('품종 후보를 탭하면 품종까지 저장된다 (품목으로 뭉개지 않는다)', (t) async {
      // Build 19 의 정확한 실패 지점. `장미 · 쥬밀리아` 를 눌러도 `장미` 만 남았다.
      final c = TextEditingController();
      await t.pumpWidget(host(c));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), '장미');
      await t.pumpAndSettle();

      // `장미 · <품종>` 형태의 후보가 목록에 있어야 한다
      final rose = svc.itemOf('장미')!;
      final v = rose.varieties.first.name;
      final row = find.text('장미 · $v');
      expect(row, findsOneWidget);

      await t.tap(row);
      await t.pumpAndSettle();
      expect(c.text, '장미 $v');
    });

    testWidgets('푸터가 강요를 선언하지 않는다', (t) async {
      final c = TextEditingController();
      await t.pumpWidget(host(c));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();

      // 예전 문구 `표준 품목명으로 저장돼요` 는 사라졌어야 한다.
      expect(find.textContaining('표준 품목명으로 저장'), findsNothing);
      expect(find.textContaining('적은 그대로 저장돼요'), findsOneWidget);
    });

    testWidgets('초성만 쳐도 후보가 나온다', (t) async {
      final c = TextEditingController();
      await t.pumpWidget(host(c));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), 'ㅈㅁ');
      await t.pumpAndSettle();

      expect(find.text('장미'), findsWidgets);
    });

    testWidgets('사전에 없는 이름도 그대로 저장된다', (t) async {
      // `컨트리B` 처럼 실제 거래명이지만 경매 품목명이 아닌 이름을
      // 억지로 바꿔버리면 안 된다.
      final c = TextEditingController();
      await t.pumpWidget(host(c));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), '컨트리B');
      await t.pumpAndSettle();

      expect(find.text('입력한 그대로 저장'), findsOneWidget);

      await t.tap(find.text('입력한 그대로 저장'));
      await t.pumpAndSettle();
      expect(c.text, '컨트리B');
    });

    testWidgets('onChanged 가 타이핑마다 호출된다', (t) async {
      var n = 0;
      final c = TextEditingController();
      await t.pumpWidget(host(c, onChanged: () => n++));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), '장');
      await t.pumpAndSettle();
      expect(n, greaterThan(0));
    });

    testWidgets('아무것도 안 맞으면 드롭다운에 억지 후보가 없다', (t) async {
      final c = TextEditingController();
      await t.pumpWidget(host(c));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), 'zzzzqqqq');
      await t.pumpAndSettle();

      // "내가 친 그대로" 1건만 있어야 한다
      expect(find.text('입력한 그대로 저장'), findsOneWidget);
      expect(find.text('장미'), findsNothing);
    });

    testWidgets('행 높이가 40으로 유지된다 (기존 레이아웃 보존)', (t) async {
      // 세 편집 화면의 품목 행 레이아웃을 건드리지 않는 게 전제조건이다.
      final c = TextEditingController();
      await t.pumpWidget(host(c));
      final box = t.getSize(find.byType(FlowerNameField));
      expect(box.height, 40);
    });

    testWidgets('연속 타이핑/삭제에도 죽지 않는다', (t) async {
      final c = TextEditingController();
      await t.pumpWidget(host(c));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();

      for (final q in ['ㄹ', '리', '리시', '리시안', '리시', '리', '']) {
        await t.enterText(find.byType(TextField), q);
        await t.pump(const Duration(milliseconds: 30));
      }
      await t.pumpAndSettle();
      // 예외 없이 여기까지 오면 통과 (pumpAndSettle 이 예외를 재던진다)
      expect(find.byType(FlowerNameField), findsOneWidget);
    });
  });

  group('사전 없을 때 (강등 동작)', () {
    setUp(() => svc.resetForTest());

    testWidgets('자동완성 없이도 입력은 계속 된다', (t) async {
      // 자산 누락/파싱 실패로 영수증 편집이 막히면 안 된다.
      final c = TextEditingController();
      await t.pumpWidget(host(c));

      await t.enterText(find.byType(TextField), '아무이름');
      await t.pumpAndSettle();
      expect(c.text, '아무이름');
    });
  });
}
