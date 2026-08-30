import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flow_note/design/fn_tab_intent.dart';
import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/providers/receipt_provider.dart';
import 'package:flow_note/screens/ds/scan_confirm_list_ds_screen.dart';
import 'package:flow_note/screens/scan/scan_draft.dart';

/// #113 회귀 테스트
///
/// (A) 뒤로가기가 느리다        → allReceipts 캐시 + batch() 알림 묶음
/// (B) '캘린더 보기' 가 안 된다 → FnTabIntent
/// (C) 마지막 확인 화면이 없다  → ScanConfirmListDsScreen
void main() {
  // ────────────────────────────────────────────────────────────
  group('#113(B) 저장 완료 화면의 캘린더 보기', () {
    tearDown(() => FnTabIntent.pending.value = null);

    test('🔴 요청한 탭 키를 한 번만 꺼낼 수 있다', () {
      expect(FnTabIntent.take(), isNull);
      FnTabIntent.request('calendar');
      expect(FnTabIntent.take(), 'calendar');
      expect(FnTabIntent.take(), isNull, reason: '두 번 읽으면 두 번 이동해 버린다');
    });

    testWidgets('🔴 요청이 오면 루트 화면이 그 탭으로 바꾼다', (t) async {
      // main_ds_screen 이 하는 일과 같은 구조의 축소 하네스
      await t.pumpWidget(const MaterialApp(home: _FakeRoot()));
      expect(find.text('탭=2'), findsOneWidget); // 스캔 탭에서 시작

      FnTabIntent.request('calendar');
      await t.pumpAndSettle();
      expect(find.text('탭=3'), findsOneWidget,
          reason: '캘린더(index 3)로 전환되지 않았다');
      expect(FnTabIntent.pending.value, isNull, reason: '요청이 소비되지 않았다');
    });

    testWidgets('🔴 홈으로가기와 캘린더보기가 같은 동작이면 안 된다', (t) async {
      final src = _read('lib/screens/ds/scan_done_ds_screen.dart');
      // 두 버튼이 서로 다른 탭 키를 남겨야 한다
      expect(src.contains("_leaveTo('home'"), isTrue,
          reason: '홈으로가기가 home 탭을 지정하지 않는다');
      expect(src.contains("_leaveTo('calendar'"), isTrue,
          reason: '캘린더보기가 calendar 탭을 지정하지 않는다');
      // 예전 버그: 둘 다 popUntil 만 했다
      final popOnly = src.split('\n').where((l) {
        final s = l.trim();
        return s.startsWith('Navigator.of(context).popUntil') ||
            s.startsWith('else { Navigator.of(context).popUntil');
      }).length;
      expect(popOnly, lessThanOrEqualTo(1),
          reason: 'popUntil 만 하는 코드가 두 곳 이상 남아 있다 (예전 버그)');
    });

    testWidgets('🔴 루트 화면이 탭 요청을 듣고 있다', (t) async {
      final src = _read('lib/screens/ds/main_ds_screen.dart');
      expect(src.contains('FnTabIntent.pending.addListener'), isTrue);
      expect(src.contains('FnTabIntent.pending.removeListener'), isTrue,
          reason: 'dispose 에서 떼지 않으면 누수된다');
    });
  });

  // ────────────────────────────────────────────────────────────
  group('#113(A) 저장·조회 비용', () {
    test('🔴 batch 안의 알림 여러 번이 한 번으로 묶인다', () async {
      final p = ReceiptProvider();
      var n = 0;
      p.addListener(() => n++);

      await p.batch(() async {
        // 영수증 4장 저장 = addReceipt 4회 = notifyListeners 4회
        for (var i = 0; i < 4; i++) {
          p.notifyListeners();
        }
      });
      expect(n, 1, reason: '4장 저장에 화면 갱신이 $n번 났다 (1번이어야 한다)');
      p.dispose();
    });

    test('🔴 batch 를 안 쓰면 예전처럼 4번 난다 (대조군)', () async {
      final p = ReceiptProvider();
      var n = 0;
      p.addListener(() => n++);
      for (var i = 0; i < 4; i++) {
        p.notifyListeners();
      }
      expect(n, 4);
      p.dispose();
    });

    test('🔴 batch 가 중첩돼도 알림은 한 번이다', () async {
      final p = ReceiptProvider();
      var n = 0;
      p.addListener(() => n++);
      await p.batch(() async {
        await p.batch(() async {
          p.notifyListeners();
        });
        p.notifyListeners();
      });
      expect(n, 1);
      p.dispose();
    });

    test('🔴 allReceipts 는 같은 결과를 다시 정렬하지 않는다', () async {
      final dir = await io.Directory.systemTemp.createTemp('fn113');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(ReceiptModelAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(FlowerItemAdapter());
      }
      final p = ReceiptProvider();
      await p.init();

      final a = p.allReceipts;
      final b = p.allReceipts;
      expect(identical(a, b), isTrue,
          reason: '호출마다 목록을 다시 만들고 정렬한다 (1000건 12회 = 25ms)');
      expect(a, isNotEmpty);

      // 목록이 바뀌면 캐시를 버려야 한다
      await p.deleteReceipt(a.first.id);
      final c = p.allReceipts;
      expect(identical(a, c), isFalse, reason: '영수증을 지웠는데 옛 목록이 남아 있다');
      expect(c.length, a.length - 1);

      p.dispose();
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });
  });

  // ────────────────────────────────────────────────────────────
  group('#113(C) 인식 결과 확인 목록', () {
    List<ScanDraft> make(int n) {
      final out = <ScanDraft>[];
      const names = ['대한꽃도매', '화람원예', '미림화훼', '그린플러스'];
      const amounts = [256000.0, 184000.0, 45000.0, 98000.0];
      for (var i = 0; i < n; i++) {
        final d = ScanDraft(file: XFile('/tmp/none$i.jpg'), id: 'd$i');
        d.storeName = names[i % names.length];
        d.date = DateTime(2026, 7, 24);
        d.items = [
          for (var k = 0; k < (i + 2); k++)
            DraftItem(name: '장미$k', quantity: 1, unitPrice: 1000),
        ];
        d.userTotal = amounts[i % amounts.length];
        out.add(d);
      }
      return out;
    }

    testWidgets('🔴 시안대로 요약과 목록을 보여준다', (t) async {
      final drafts = make(4);
      await t.pumpWidget(MaterialApp(
        home: ScanConfirmListDsScreen(drafts: drafts, onSaveAll: () {}),
      ));
      await t.pumpAndSettle();

      expect(find.text('인식 결과 확인'), findsOneWidget);
      expect(find.text('인식된 영수증'), findsOneWidget);
      expect(find.text('4장'), findsOneWidget);
      expect(find.text('총 합계'), findsOneWidget);
      // 256000+184000+45000+98000 = 583,000 (시안과 동일)
      expect(find.text('₩583,000'), findsOneWidget);
      expect(find.text('영수증 목록 4건'), findsOneWidget);

      for (final n in ['대한꽃도매', '화람원예', '미림화훼', '그린플러스']) {
        expect(find.text(n), findsOneWidget, reason: '$n 행이 없다');
      }
      expect(find.text('₩256,000'), findsOneWidget);
      expect(find.textContaining('2026.07.24 · 품목 2건'), findsOneWidget);
      expect(find.text('모두 저장하기'), findsOneWidget);
    });

    testWidgets('🔴 모두 저장하기를 누르면 저장이 시작된다', (t) async {
      var saved = 0;
      await t.pumpWidget(MaterialApp(
        home: ScanConfirmListDsScreen(drafts: make(2), onSaveAll: () => saved++),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('모두 저장하기'));
      await t.pumpAndSettle();
      expect(saved, 1);
    });

    testWidgets('🔴 항목을 누르면 그 번째로 돌아간다', (t) async {
      final got = <int>[];
      await t.pumpWidget(MaterialApp(
        home: ScanConfirmListDsScreen(
          drafts: make(4),
          onSaveAll: () {},
          onEdit: got.add,
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('미림화훼'));
      await t.pumpAndSettle();
      expect(got, [2], reason: '세 번째 영수증(index 2)을 눌렀는데 $got 이 왔다');
    });

    testWidgets('🔴 검토 화면이 2건 이상일 때 이 목록을 띄운다', (t) async {
      final src = _read('lib/screens/ds/scan_review_ds_screen.dart');
      expect(src.contains('ScanConfirmListDsScreen('), isTrue,
          reason: '확인 목록이 어디에도 연결되지 않았다');
      expect(src.contains('live.length > 1'), isTrue,
          reason: '1건일 때도 목록을 띄우면 방해만 된다');
      expect(src.contains('provider.batch('), isTrue,
          reason: '저장 루프가 batch 로 묶이지 않았다');
    });
  });
}

/// main_ds_screen 의 탭 요청 처리 구조만 떼어낸 축소판
class _FakeRoot extends StatefulWidget {
  const _FakeRoot();
  @override
  State<_FakeRoot> createState() => _FakeRootState();
}

class _FakeRootState extends State<_FakeRoot> {
  static const _keys = ['home', 'settle', 'scan', 'calendar', 'profile'];
  int _index = 2;

  @override
  void initState() {
    super.initState();
    FnTabIntent.pending.addListener(_onIntent);
  }

  @override
  void dispose() {
    FnTabIntent.pending.removeListener(_onIntent);
    super.dispose();
  }

  void _onIntent() {
    if (FnTabIntent.pending.value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = FnTabIntent.take();
      if (key == null) return;
      final i = _keys.indexOf(key);
      if (i < 0 || i == _index) return;
      setState(() => _index = i);
    });
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('탭=$_index')));
}

String _read(String rel) => io.File(rel).readAsStringSync();
