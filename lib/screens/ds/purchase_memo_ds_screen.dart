import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/fn_feedback.dart';
import '../../design/fn_shell.dart';
import '../../models/purchase_list_model.dart';
import '../../services/cost_calc.dart';
import '../../services/purchase_list_service.dart';
import '../../theme/fn_ds.dart';
import '../../widgets/fn_inquiry_parts.dart';
import '../../widgets/fn_purchase_parts.dart';
import 'saved_lists_ds_screen.dart';

/// 사입 메모장 — 시장에서 쓰는 화면. (시안 #185 / 저장 #189)
///
/// ## 배치
///
/// ```
///   [←] 사입 메모장
///   사입 갈 때 챙길 것과 주문 메모를 적고, 부케 모양이나 꽃 배치를
///   그려 기록해요.
///   ┌ 사입 날짜 [2026.07.24 (금)]   목적 [주말 부케 3건 대비] ┐  _MemoHeadCard
///   ( 메모 3/5 )( 스케치 • )                        _MemoTabs
///   ┌─────────────────────────────── 화면 아래까지 ┐
///   │ ○ 금요일 웨딩 부케 3개 — 화이트 위주          │  메모 탭
///   │ ✓ 장미(레드) 단가 오르면 소국으로 대체        │  (산 줄은 가운데줄)
///   └───────────────────────────────────────────┘
///   [ 사입 리스트 저장 ]                            (새 메모장)
///   [ 저장 ]                                        (저장된 리스트를 고칠 때)
/// ```
///
/// ## 두 가지 모드 (#189)
///
/// | 들어온 곳 | [listId] | 담기는 곳 | 하단 버튼 | 누른 뒤 |
/// |---|---|---|---|---|
/// | 가이드·바로가기 칩 | 없음 | **임시 작성분** | `사입 리스트 저장` | 저장된 사입 리스트로 이동 |
/// | 저장된 사입 리스트 | 있음 | 그 리스트 | `저장` | 화면에 머무름 |
///
/// 🔴 **#189 에서 고친 것** — 예전에는 가이드·칩으로 들어오면
///    `activeOne`(아직 안 끝난 가장 최근 리스트)을 집어 왔다. 그래서
///    예산 검토에서 저장해 둔 **남의 리스트에 메모가 덮어써졌다.**
///    이제 새 메모장은 자기만의 임시 작성분(`memoDraft()`)에 적고,
///    "사입 리스트 저장" 을 눌러야 저장된 사입 리스트에 올라간다.
///
/// 🔴 저장 구조를 새로 만들지 않았다. 사장님 지시(#185): "1단계에서 만든
///    PurchaseList 와 purchase_list_service.dart 를 그대로 써줘."
///    체크 상태는 [MemoText] 가 글 앞에 `[x] ` 를 붙여 `memo` 한 칸에 담는다.
///
/// 🔴 쓰는 중에는 `touch()`(폰 즉시 + 서버 4초 모아서) 로 자동 저장한다.
///    앱을 꺼도 임시 작성분이 그대로 남는다. 버튼을 누를 때만
///    예산 검토와 **같은** `saveNow()` 를 쓴다.
class PurchaseMemoDsScreen extends StatefulWidget {
  const PurchaseMemoDsScreen({super.key, this.listId, this.list});

  /// 어느 사입 리스트를 펼칠지.
  ///
  /// 🔴 비워 두면 **임시 작성분**을 연다(새 메모장). 저장된 사입 리스트에서
  ///    열면 그 리스트의 id 가 들어온다. 둘은 섞이지 않는다. (#189)
  final String? listId;

  /// 미리 넣어 줄 리스트. 비워 두면 저장된 것에서 찾는다.
  ///
  /// 🔴 테스트에서 Hive 없이 띄우려고 열어 두었다. (저장된 사입 리스트
  ///    화면의 `lists` 와 같은 방식) 앱에서는 쓰지 않는다.
  final PurchaseList? list;

  @override
  State<PurchaseMemoDsScreen> createState() => _PurchaseMemoDsScreenState();
}

class _PurchaseMemoDsScreenState extends State<PurchaseMemoDsScreen> {
  /// 메모 0 · 스케치 1.
  int _tab = 0;

  PurchaseList? _list;

  /// 저장하는 중. 두 번 눌러 두 건이 되는 걸 막는다.
  bool _saving = false;

  /// 저장된 리스트를 고치는 중인가. (false = 새 메모장)
  bool get _editing => widget.listId != null;

  /// 메모 줄들. 글칸 하나와 체크 하나가 한 줄을 이룬다.
  final List<_MemoRow> _rows = [];

  final _purpose = TextEditingController();
  DateTime _date = DateTime.now();

  /// 스케치.
  final List<SketchStroke> _strokes = [];
  SketchStroke? _drawing;
  int _penColor = _penColors.first;
  double _penWidth = _penWidths[1].$2;

  @override
  void initState() {
    super.initState();
    _list = _resolveList();
    _date = _list?.date ?? DateTime.now();
    _purpose.text = _list?.purpose ?? '';
    _loadMemo();
    _strokes.addAll(_list?.strokes.map((e) => e.copy()) ?? const []);
    _purpose.addListener(_onTyped);
  }

  /// 어디에 적을지 고른다.
  ///
  /// 🔴 기다리지 않는다. 임시 메모장 id 는 `PurchaseListService.init()` 이
  ///    앱 시작 때 이미 읽어 뒀다. 여기서 await 하면 한 박자 빈 화면이
  ///    보였다가 글이 튀어나와 깜빡인다.
  ///
  /// 🔴 못 고르는 경우를 남기지 않는다. 메모장은 시장에서 급히 여는
  ///    화면이라, "리스트를 찾지 못했어요" 를 띄우면 아무것도 못 적는다.
  PurchaseList? _resolveList() {
    final given = widget.list;
    if (given != null) return given;      // 테스트에서 넣어 준 것
    try {
      final svc = PurchaseListService.instance;
      final given = widget.listId;
      if (given != null) {
        final found = svc.byId(given);
        if (found != null) return found;
      }
      // 🔴 `activeOne` 을 쓰지 않는다(#189). 그건 예산 검토에서 저장해
      //    둔 **남의 리스트**를 집어 와 메모를 덮어쓰던 길이다.
      //    새 메모장은 자기만의 임시 작성분에 적는다.
      return svc.memoDraft();
    } catch (_) {
      // 상자를 못 열었다. 적을 수는 있게 두고, 저장할 때 알린다.
      return null;
    }
  }

  void _loadMemo() {
    final raw = _list?.memo ?? '';
    final lines = MemoText.parse(raw);
    for (final l in lines) {
      _rows.add(_MemoRow(line: l, onChanged: _onTyped));
    }
    // 빈 메모라도 적을 줄 하나는 있어야 한다.
    if (_rows.isEmpty) _rows.add(_MemoRow(onChanged: _onTyped));
  }

  @override
  void dispose() {
    // 🔴 화면을 나가기 전에 **지금 적힌 것**을 담고 즉시 올린다.
    //    `save()` 를 안 부르면 마지막으로 친 글자가 사라진다.
    //    새 메모장이면 임시 작성분으로 남아, 다음에 열 때 돌아온다.
    _autoSave(immediate: true);
    _purpose
      ..removeListener(_onTyped)
      ..dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _onTyped() {
    // 탭 옆의 `3/5` 와 하단 버튼이 같이 바뀌어야 해서 다시 그린다.
    setState(() {});
    _autoSave();
  }

  /// 적힌 것을 리스트 객체에 담는다. (저장은 하지 않는다)
  PurchaseList? _collect() {
    final list = _list;
    if (list == null) return null;
    list
      ..date = _date
      ..purpose = _purpose.text.trim()
      ..memo = MemoText.encode([for (final r in _rows) r.snapshot])
      ..strokes = _strokes.map((e) => e.copy()).toList();
    return list;
  }

  /// 쓰는 중 자동 저장. [immediate] 면 서버까지 바로 올린다(나갈 때).
  ///
  /// 🔴 버튼으로 하는 저장과 **다른 길**이다. 이건 조용히 모아 두는
  ///    것이고, 버튼은 `saveNow()` 로 끝날 때까지 기다린다.
  void _autoSave({bool immediate = false}) {
    final list = _collect();
    if (list == null) return;
    // `notify: false` — 이 화면은 스스로 그리고 있다. 알리면 목록 화면이
    // 글자마다 다시 그려져 느려진다.
    unawaited(
        PurchaseListService.instance.touch(list, notify: immediate));
    if (immediate) unawaited(PurchaseListService.instance.flush());
  }

  /// 적은 게 하나라도 있는가. 메모 줄도 스케치도 없으면 저장할 게 없다.
  bool get _hasContent {
    final written =
        _rows.any((r) => r.ctrl.text.trim().isNotEmpty);
    return written || _strokes.isNotEmpty;
  }

  /// 하단 버튼을 눌렀다.
  ///
  /// 🔴 예산 검토와 **같은** `saveNow()` 를 쓴다. 사장님 지시(#189):
  ///    "예산 검토의 saveNow() 를 그대로 재사용."
  Future<void> _saveButton() async {
    if (_saving) return;
    final list = _collect();
    if (list == null || !_hasContent) {
      showFnToast(context, '한 줄 이상 적거나 그려 주세요',
          type: FnToastType.warning);
      return;
    }

    setState(() => _saving = true);
    final ok = await PurchaseListService.instance.saveNow(list);
    if (!mounted) return;
    setState(() => _saving = false);

    if (!ok) {
      // 🔴 실패하면 임시 작성분을 **그대로 둔다.** 지우면 적은 게 날아간다.
      showFnToast(context, '저장하지 못했어요. 다시 눌러 주세요',
          type: FnToastType.error);
      return;
    }

    showFnToast(context, '저장했어요', type: FnToastType.success);

    if (_editing) {
      // 저장된 리스트를 고치던 중이다. 화면에 머문다. (사장님 지시 #189)
      return;
    }

    // 🔴 새 메모장이었다. 임시 표시를 지워서, 다음에 열면 **빈 메모장**으로
    //    시작하게 한다. 안 지우면 방금 저장한 글이 또 떠서, 저장이 안 된
    //    줄 알고 한 번 더 누르게 된다.
    await PurchaseListService.instance.clearMemoDraft();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SavedListsDsScreen(openId: list.id),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      locale: const Locale('ko'),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
      _autoSave();
    }
  }

  /// 시장에서 체크할 품목 줄. 예산 검토에서 적은 것이 그대로 온다. (#190)
  ///
  /// 🔴 **복사해 두지 않는다.** `_list.items` 를 그대로 가리킨다. 복사하면
  ///    예산 검토에서 품목을 고쳤을 때 메모장이 옛 품목을 들고 있게 된다.
  ///    사장님 지시(#190): "예산 검토에서 품목을 고치면 여기도 같이 바뀜".
  List<PurchaseItem> get _items => _list?.items ?? const <PurchaseItem>[];

  /// 품목 목록을 보여 줄까. 품목이 없는 메모 리스트는 숨긴다.
  bool get _showItems => _items.isNotEmpty;

  /// 품목을 샀다고 체크했다.
  ///
  /// 🔴 체크 상태는 **그 품목에** 담는다(`PurchaseItem.checked`). 메모 글에
  ///    옮겨 적지 않는다 — 예산 검토가 품목을 고치면 글과 어긋난다.
  void _toggleItem(int i) {
    final list = _items;
    if (i >= list.length) return;
    setState(() => list[i].checked = !list[i].checked);
    _autoSave();
  }

  // ── 메모 탭 ──────────────────────────────────────────────────

  /// 엔터를 쳤다. 그 아래에 줄을 하나 더한다.
  void _addLineAfter(int i) {
    final row = _MemoRow(onChanged: _onTyped);
    setState(() => _rows.insert(i + 1, row));
    // 새 줄로 커서를 옮긴다. 안 옮기면 사장님이 한 번 더 눌러야 한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.focus.requestFocus();
    });
    _autoSave();
  }

  /// 빈 줄에서 지우기를 눌렀다. 그 줄을 없애고 윗줄 끝으로 간다.
  void _removeLine(int i) {
    if (_rows.length <= 1) return;
    final gone = _rows[i];
    final prev = i > 0 ? _rows[i - 1] : null;
    setState(() => _rows.removeAt(i));
    gone.dispose();
    if (prev != null) {
      prev.focus.requestFocus();
      prev.ctrl.selection =
          TextSelection.collapsed(offset: prev.ctrl.text.length);
    }
    _autoSave();
  }

  /// 🔴 체크해도 줄 순서는 **그대로 둔다.** 사장님 지시(#185):
  ///    "줄 순서는 쓴 순서 그대로 (체크해도 위치 안 바뀜)".
  ///    산 것을 아래로 내리면 눈이 줄을 다시 찾아야 해서 시장에서 헷갈린다.
  void _toggle(int i) {
    setState(() => _rows[i].checked = !_rows[i].checked);
    _autoSave();
  }

  // ── 스케치 탭 ────────────────────────────────────────────────

  void _strokeStart(Offset p) {
    _drawing = SketchStroke(
      colorValue: _penColor,
      width: _penWidth,
      points: [p.dx, p.dy],
    );
    setState(() => _strokes.add(_drawing!));
  }

  void _strokeMove(Offset p) {
    final s = _drawing;
    if (s == null) return;
    setState(() => s.points.addAll([p.dx, p.dy]));
  }

  void _strokeEnd() {
    _drawing = null;
    _autoSave();
  }

  void _clearSketch() {
    if (_strokes.isEmpty) return;
    setState(_strokes.clear);
    _autoSave();
  }

  // ── 그리기 ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 🔴 품목과 메모 줄을 **합쳐서** 센다(#190). 사장님 지시:
    //    "메모 탭 이름 옆 개수는 품목 + 메모 줄 합쳐서 3/5".
    //    모델(`checkLabel`)과 같은 규칙이라 카드와 탭 숫자가 어긋나지 않는다.
    final memoLines = [for (final r in _rows) r.snapshot];
    final total = _items.length + MemoText.total(memoLines);
    final done = _items.where((e) => e.checked).length +
        MemoText.done(memoLines);
    final counter = total == 0 ? '' : '$done/$total';
    final ready = _hasContent;

    return FnShell(
      navTitle: '사입 메모장',
      bg: FnDs.bg,
      onBack: () {
        _autoSave(immediate: true);
        Navigator.of(context).pop();
      },
      child: ColoredBox(
        color: FnDs.bg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              FnDs.pagePad, 14, FnDs.pagePad, FnDs.gapM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '사입 갈 때 챙길 것과 주문 메모를 적고, 부케 모양이나 꽃 배치를 '
                '그려 기록해요.',
                style: FnDs.tsSub,
              ),
              const SizedBox(height: FnDs.gapS),
              // 🔴 예산 검토와 **같은 모양**의 날짜·목적 칸. (사장님 지시 #189)
              _MemoHeadCard(
                date: _date,
                purpose: _purpose,
                onPickDate: _pickDate,
              ),
              const SizedBox(height: FnDs.gapS),
              _MemoTabs(
                index: _tab,
                counter: counter,
                hasSketch: _strokes.isNotEmpty,
                onTap: (i) {
                  // 🔴 탭을 바꿔도 적은 것은 그대로 둔다. 줄 컨트롤러와
                  //    선 목록을 State 가 들고 있어서 다시 만들지 않는다.
                  FocusScope.of(context).unfocus();
                  setState(() => _tab = i);
                },
              ),
              const SizedBox(height: FnDs.gapS),
              // 고른 탭의 카드가 화면 아래까지 꽉 찬다. (사장님 지시 #185)
              Expanded(
                child: _tab == 0 ? _memoCard() : _sketchCard(),
              ),
              const SizedBox(height: FnDs.gapS),
              FnPrimaryButton(
                // 저장된 리스트를 고치는 중이면 그냥 '저장'.
                label: _editing ? '저장' : '사입 리스트 저장',
                busy: _saving,
                // 🔴 적은 게 없으면 흐리게. 사장님 지시(#189).
                onTap: ready ? () => unawaited(_saveButton()) : null,
              ),
              if (!ready) ...[
                const SizedBox(height: FnDs.gapXs),
                const Text(
                  '한 줄 이상 적거나 그려 주세요',
                  textAlign: TextAlign.center,
                  style: FnDs.tsSub,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _memoCard() {
    // 🔴 품목 목록 + 자유 메모를 **한 스크롤**에 담는다(#190). 카드를 둘로
    //    나누면 시장에서 한 화면에 안 들어와 번갈아 스크롤해야 한다.
    final items = _items;
    final head = _showItems ? items.length + 1 : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          FnDs.gapS, FnDs.gapM, FnDs.gapS, FnDs.gapM),
      decoration: FnDs.cardDeco(),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: head + _rows.length,
        itemBuilder: (_, i) {
          if (_showItems) {
            if (i == 0) return const _ItemsHead();
            if (i <= items.length) {
              final at = i - 1;
              return _ItemCheckRow(
                item: items[at],
                onToggle: () => _toggleItem(at),
              );
            }
          }
          final at = i - head;
          return _MemoRowView(
            row: _rows[at],
            onToggle: () => _toggle(at),
            onEnter: () => _addLineAfter(at),
            onBackspaceEmpty: () => _removeLine(at),
          );
        },
      ),
    );
  }

  Widget _sketchCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.gapM),
      decoration: FnDs.cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('스케치', style: FnDs.tsSection),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _clearSketch();
                  showFnToast(context, '스케치를 지웠어요.');
                },
                child: const Text(
                  '지우기',
                  style: TextStyle(
                    fontFamily: FnDs.font,
                    fontSize: FnDs.fontS,
                    fontWeight: FontWeight.w700,
                    color: FnDs.title,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FnDs.gapS),
          _PenColors(
            colors: _penColors,
            selected: _penColor,
            onTap: (c) => setState(() => _penColor = c),
          ),
          const SizedBox(height: FnDs.gapXs),
          Row(
            children: [
              for (final (label, w) in _penWidths) ...[
                SizedBox(
                  height: 28,
                  child: FnPill(
                    label: label,
                    selected: _penWidth == w,
                    onTap: () => setState(() => _penWidth = w),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: FnDs.gapS),
          Expanded(
            child: _SketchPad(
              strokes: _strokes,
              onStart: _strokeStart,
              onMove: _strokeMove,
              onEnd: _strokeEnd,
            ),
          ),
          const SizedBox(height: FnDs.gapXs),
          const Text(
            '꽃 배치나 부케 모양을 손으로 그려 기록해두세요.',
            style: FnDs.tsSub,
          ),
        ],
      ),
    );
  }
}

/// 날짜 + 목적. 예산 검토의 `_BudgetHeadCard` 와 **같은 모양**이다. (#189)
///
/// 🔴 복사해 둔 이유 — 예산 검토 쪽은 `insight_ds_screens.dart` 안의
///    `private` 위젯이라 밖에서 못 쓴다. 그 파일을 건드리면 다른 화면까지
///    흔들려서(사장님 지시: "다른 화면은 건드리지 마") 여기에 같은 값으로
///    맞춰 두었다. 고칠 때는 두 곳을 같이 본다.
class _MemoHeadCard extends StatelessWidget {
  const _MemoHeadCard({
    required this.date,
    required this.purpose,
    required this.onPickDate,
  });

  final DateTime date;
  final TextEditingController purpose;
  final VoidCallback onPickDate;

  static const _dow = ['월', '화', '수', '목', '금', '토', '일'];

  String get _label =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.'
      '${date.day.toString().padLeft(2, '0')} '
      '(${_dow[date.weekday - 1]})';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: FnDs.cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('사입 날짜', style: FnDs.tsSub),
          const SizedBox(height: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPickDate,
            child: Container(
              height: FnDs.inputH,
              padding: const EdgeInsets.symmetric(horizontal: FnDs.inputPadH),
              decoration: BoxDecoration(
                color: FnDs.card,
                borderRadius: BorderRadius.circular(FnDs.inputRadius),
                border: Border.all(color: FnDs.line, width: FnDs.inputBorderW),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _label,
                      style: const TextStyle(
                        fontFamily: FnDs.font,
                        fontSize: FnDs.inputFont,
                        color: FnDs.title,
                      ),
                    ),
                  ),
                  const Icon(Icons.calendar_today_outlined,
                      size: 16, color: FnDs.sub),
                ],
              ),
            ),
          ),
          const SizedBox(height: FnDs.gapS),
          FnNamedField(
            label: '목적',
            controller: purpose,
            hint: '예) 주말 부케 3건 대비',
          ),
        ],
      ),
    );
  }
}

/// 시안의 색 여덟 가지.
const List<int> _penColors = [
  0xFFFF6D78, // 코랄
  0xFFB08458, // 갈색
  0xFFF2C75C, // 노랑
  0xFF1A1A1A, // 검정
  0xFF1273EB, // 파랑
  0xFF3FBF63, // 초록
  0xFFE8202A, // 빨강
  0xFF7B3FF2, // 보라
];

/// 시안의 굵기 세 가지.
const List<(String, double)> _penWidths = [
  ('얇게', 2),
  ('보통', 4),
  ('굵게', 7),
];

/// 메모 한 줄의 상태. 글칸·커서·체크를 묶어 들고 있다.
///
/// 🔴 위젯이 아니라 **State 가** 들고 있는 이유: 탭을 바꿔도 적은 것이
///    그대로 남아야 한다(사장님 지시 #185). 위젯 안에서 만들면 탭을
///    옮길 때마다 새로 생겨 글이 사라진다.
class _MemoRow {
  _MemoRow({MemoLine? line, required this.onChanged})
      : ctrl = TextEditingController(text: line?.text ?? ''),
        checked = line?.checked ?? false {
    ctrl.addListener(onChanged);
  }

  final TextEditingController ctrl;
  final FocusNode focus = FocusNode();
  final VoidCallback onChanged;
  bool checked;

  MemoLine get snapshot => MemoLine(text: ctrl.text, checked: checked);

  void dispose() {
    ctrl
      ..removeListener(onChanged)
      ..dispose();
    focus.dispose();
  }
}

/// 메모 탭 맨 위의 `사야 할 품목` 머리. (#190)
class _ItemsHead extends StatelessWidget {
  const _ItemsHead();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text('사야 할 품목', style: FnDs.tsSection),
    );
  }
}

/// 예산 검토에서 적은 품목 한 줄 — 체크칸 + 이름 + 수량·단위. (#190)
///
/// 🔴 글칸이 아니라 **읽기 전용**이다. 품목은 예산 검토에서 고친다.
///    여기서 고치면 같은 품목이 두 곳에서 달라져 어느 쪽이 맞는지 모른다.
class _ItemCheckRow extends StatelessWidget {
  const _ItemCheckRow({required this.item, required this.onToggle});

  final PurchaseItem item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final done = item.checked;
    final unit = item.unit.trim().isEmpty ? '단' : item.unit.trim();
    final qty = item.qty <= 0 ? '' : '${CostCalc.comma(item.qty)}$unit';

    return Semantics(
      button: true,
      checked: done,
      label: done ? '구매 완료' : '구매 전',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: [
              // 체크칸 — 자유 메모 줄과 **같은 모양**이다. (#185 과 맞춤)
              SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: done ? FnDs.coral : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: done ? FnDs.coral : FnDs.line,
                        width: 1.5,
                      ),
                    ),
                    child: done
                        ? const Icon(Icons.check_rounded,
                            size: 14, color: FnDs.onCoral)
                        : null,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: FnDs.font,
                    fontSize: FnDs.fontM,
                    color: done ? FnDs.sub : FnDs.title,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: FnDs.sub,
                  ),
                ),
              ),
              if (qty.isNotEmpty) ...[
                const SizedBox(width: FnDs.gapXs),
                Text(
                  qty,
                  style: TextStyle(
                    fontFamily: FnDs.font,
                    fontSize: FnDs.fontS,
                    fontWeight: FontWeight.w600,
                    color: done ? FnDs.sub : FnDs.body,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: FnDs.sub,
                  ),
                ),
              ],
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// 메모 한 줄 — 체크칸 + 글칸.
class _MemoRowView extends StatelessWidget {
  const _MemoRowView({
    required this.row,
    required this.onToggle,
    required this.onEnter,
    required this.onBackspaceEmpty,
  });

  final _MemoRow row;
  final VoidCallback onToggle;
  final VoidCallback onEnter;
  final VoidCallback onBackspaceEmpty;

  @override
  Widget build(BuildContext context) {
    final done = row.checked;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 체크칸. 손가락이 닿게 넉넉히 잡는다.
          Semantics(
            button: true,
            checked: done,
            label: done ? '구매 완료' : '구매 전',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: done ? FnDs.coral : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: done ? FnDs.coral : FnDs.line,
                        width: 1.5,
                      ),
                    ),
                    child: done
                        ? const Icon(Icons.check_rounded,
                            size: 14, color: FnDs.onCoral)
                        : null,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4, right: 4),
              child: _MemoField(
                row: row,
                done: done,
                onEnter: onEnter,
                onBackspaceEmpty: onBackspaceEmpty,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 글칸 한 개.
///
/// 🔴 `TextField` 가 엔터를 스스로 먹지 않게 `maxLines: 1` 로 두고
///    `onSubmitted` 로 받는다. 여러 줄을 허용하면 한 칸 안에서 줄이
///    늘어나 **체크칸이 없는 줄**이 생긴다.
class _MemoField extends StatelessWidget {
  const _MemoField({
    required this.row,
    required this.done,
    required this.onEnter,
    required this.onBackspaceEmpty,
  });

  final _MemoRow row;
  final bool done;
  final VoidCallback onEnter;
  final VoidCallback onBackspaceEmpty;

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(skipTraversal: true, canRequestFocus: false),
      onKeyEvent: (e) {
        // 빈 줄에서 지우기 → 줄 삭제. (사장님 지시 #185)
        if (e is KeyDownEvent &&
            e.logicalKey == LogicalKeyboardKey.backspace &&
            row.ctrl.text.isEmpty) {
          onBackspaceEmpty();
        }
      },
      child: TextField(
        controller: row.ctrl,
        focusNode: row.focus,
        maxLines: 1,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => onEnter(),
        style: TextStyle(
          fontFamily: FnDs.font,
          fontSize: FnDs.fontS,
          height: 1.45,
          color: done ? FnDs.sub : FnDs.title,
          // 산 줄은 글자에 가운데줄을 긋는다.
          decoration: done ? TextDecoration.lineThrough : null,
          decorationColor: FnDs.sub,
        ),
        cursorColor: FnDs.coral,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: '적을 것을 입력하세요',
          hintStyle: TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.fontS,
            color: FnDs.inputHint,
          ),
        ),
      ),
    );
  }
}

/// 메모 | 스케치 탭.
///
/// 🔴 칩 모양은 `FnPill` 을 그대로 쓴다. 비슷한 걸 또 만들면 한쪽만
///    고치고 잊는다 (작업 규칙 ②).
class _MemoTabs extends StatelessWidget {
  const _MemoTabs({
    required this.index,
    required this.counter,
    required this.hasSketch,
    required this.onTap,
  });

  final int index;
  final String counter;
  final bool hasSketch;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          FnPill(
            label: counter.isEmpty ? '메모' : '메모 $counter',
            selected: index == 0,
            onTap: () => onTap(0),
          ),
          const SizedBox(width: FnDs.gapXs),
          Stack(
            clipBehavior: Clip.none,
            children: [
              FnPill(
                label: '스케치',
                selected: index == 1,
                onTap: () => onTap(1),
              ),
              // 그림이 있으면 작은 코랄 점. (사장님 지시 #185)
              if (hasSketch)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: FnDs.coral,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 색 여덟 개.
class _PenColors extends StatelessWidget {
  const _PenColors({
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final List<int> colors;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final c in colors)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(c),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                // 고른 색만 테두리를 둘러 알아보게 한다.
                border: selected == c
                    ? Border.all(color: FnDs.title, width: 2)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// 손으로 그리는 칸.
class _SketchPad extends StatelessWidget {
  const _SketchPad({
    required this.strokes,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
  });

  final List<SketchStroke> strokes;
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: const Color(0xFFF7F5F3),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => onStart(d.localPosition),
          onPanUpdate: (d) => onMove(d.localPosition),
          onPanEnd: (_) => onEnd(),
          child: CustomPaint(
            size: Size.infinite,
            painter: _SketchPainter(strokes),
          ),
        ),
      ),
    );
  }
}

/// 좌표를 선으로 그린다.
///
/// 🔴 그림 파일이 아니라 **좌표**를 그린다(`SketchStroke.points`).
///    그래서 다시 열어도 그대로 보이고 이어 그릴 수 있다. (#179 설계)
class _SketchPainter extends CustomPainter {
  _SketchPainter(this.strokes);

  final List<SketchStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.points.length < 2) continue;
      final paint = Paint()
        ..color = Color(s.colorValue)
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      // 점이 하나뿐이면 톡 찍은 것이다. 작은 동그라미로 남긴다.
      if (s.points.length == 2) {
        canvas.drawCircle(
          Offset(s.points[0], s.points[1]),
          s.width / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }
      final path = Path()..moveTo(s.points[0], s.points[1]);
      for (var i = 2; i + 1 < s.points.length; i += 2) {
        path.lineTo(s.points[i], s.points[i + 1]);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter old) => true;
}
