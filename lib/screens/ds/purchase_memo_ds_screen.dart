import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/fn_feedback.dart';
import '../../design/fn_shell.dart';
import '../../models/purchase_list_model.dart';
import '../../services/purchase_list_service.dart';
import '../../theme/fn_ds.dart';
import '../../widgets/fn_purchase_parts.dart';

/// 사입 메모장 — 시장에서 쓰는 화면. (시안 #185)
///
/// ## 배치 (시안의 두 카드를 탭으로 나눴다)
///
/// ```
///   [←] 사입 메모장
///   11/26(목) 사입
///   사입 갈 때 챙길 것과 주문 메모를 적고, 부케 모양이나 꽃 배치를
///   그려 기록해요.
///   ( 메모 3/5 )( 스케치 • )                       _MemoTabs
///   ┌─────────────────────────────── 화면 아래까지 ┐
///   │ ○ 금요일 웨딩 부케 3개 — 화이트 위주          │  메모 탭
///   │ ✓ 장미(레드) 단가 오르면 소국으로 대체        │  (산 줄은 가운데줄)
///   └───────────────────────────────────────────┘
///   ┌ ● ● ● ● ● ● ● ●              지우기         ┐  스케치 탭
///   │ (얇게)(보통)(굵게)                           │
///   │                                             │
///   └ 꽃 배치나 부케 모양을 손으로 그려 기록해두세요 ┘
/// ```
///
/// 🔴 저장 구조를 새로 만들지 않았다. 사장님 지시(#185): "1단계에서 만든
///    PurchaseList 와 purchase_list_service.dart 를 그대로 써줘."
///    체크 상태는 [MemoText] 가 글 앞에 `[x] ` 를 붙여 `memo` 한 칸에 담는다.
///
/// 🔴 저장은 1단계와 같다. 글자를 칠 때마다 서버에 올리지 않고
///    `touch()`(폰 즉시 + 서버 4초 모아서) → 나갈 때 `flush()`(즉시).
class PurchaseMemoDsScreen extends StatefulWidget {
  const PurchaseMemoDsScreen({super.key, this.listId});

  /// 어느 사입 리스트를 펼칠지.
  ///
  /// 🔴 비워 두면 스스로 고른다. 사장님 지시(#185):
  ///    예산 검토에서 오면 그 리스트, 가이드·칩에서 오면 가장 최근
  ///    "준비/사입 중" 리스트, 그마저 없으면 내일 날짜로 새로 만든다.
  final String? listId;

  @override
  State<PurchaseMemoDsScreen> createState() => _PurchaseMemoDsScreenState();
}

class _PurchaseMemoDsScreenState extends State<PurchaseMemoDsScreen> {
  static const _dow = ['월', '화', '수', '목', '금', '토', '일'];

  /// 메모 0 · 스케치 1.
  int _tab = 0;

  PurchaseList? _list;

  /// 메모 줄들. 글칸 하나와 체크 하나가 한 줄을 이룬다.
  final List<_MemoRow> _rows = [];

  /// 스케치.
  final List<SketchStroke> _strokes = [];
  SketchStroke? _drawing;
  int _penColor = _penColors.first;
  double _penWidth = _penWidths[1].$2;

  @override
  void initState() {
    super.initState();
    _list = _resolveList();
    _loadMemo();
    _strokes.addAll(_list?.strokes.map((e) => e.copy()) ?? const []);
  }

  /// 어느 리스트에 적을지 고른다.
  ///
  /// 🔴 못 고르는 경우를 남기지 않는다. 메모장은 시장에서 급히 여는
  ///    화면이라, "리스트를 찾지 못했어요" 를 띄우면 아무것도 못 적는다.
  PurchaseList? _resolveList() {
    final svc = PurchaseListService.instance;
    final given = widget.listId;
    if (given != null) {
      final found = svc.byId(given);
      if (found != null) return found;
    }
    // 가이드·바로가기 칩으로 들어왔다. 아직 안 끝난 리스트를 이어 쓴다.
    final active = svc.activeOne;
    if (active != null) return active;
    // 그것도 없으면 내일 날짜로 새로 만든다. 저장은 첫 수정 때 한다.
    return svc.draft();
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
    _save(immediate: true);
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _onTyped() {
    // 탭 옆의 `3/5` 가 같이 바뀌어야 해서 다시 그린다.
    setState(() {});
    _save();
  }

  /// 적은 것을 리스트에 담는다.
  ///
  /// [immediate] 면 서버까지 바로 올린다(화면을 나갈 때).
  void _save({bool immediate = false}) {
    final list = _list;
    if (list == null) return;
    list
      ..memo = MemoText.encode([for (final r in _rows) r.snapshot])
      ..strokes = _strokes.map((e) => e.copy()).toList();
    // `notify: false` — 이 화면은 스스로 그리고 있다. 알리면 목록 화면이
    // 글자마다 다시 그려져 느려진다.
    unawaited(
        PurchaseListService.instance.touch(list, notify: immediate));
    if (immediate) unawaited(PurchaseListService.instance.flush());
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
    _save();
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
    _save();
  }

  /// 🔴 체크해도 줄 순서는 **그대로 둔다.** 사장님 지시(#185):
  ///    "줄 순서는 쓴 순서 그대로 (체크해도 위치 안 바뀜)".
  ///    산 것을 아래로 내리면 눈이 줄을 다시 찾아야 해서 시장에서 헷갈린다.
  void _toggle(int i) {
    setState(() => _rows[i].checked = !_rows[i].checked);
    _save();
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
    _save();
  }

  void _clearSketch() {
    if (_strokes.isEmpty) return;
    setState(_strokes.clear);
    _save();
  }

  // ── 그리기 ───────────────────────────────────────────────────

  String get _dateLabel {
    final d = _list?.date ?? DateTime.now();
    return '${d.month}/${d.day}(${_dow[d.weekday - 1]}) 사입';
  }

  @override
  Widget build(BuildContext context) {
    final counter = MemoText.counter([for (final r in _rows) r.snapshot]);

    return FnShell(
      navTitle: '사입 메모장',
      bg: FnDs.bg,
      onBack: () {
        _save(immediate: true);
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
              Text(
                _dateLabel,
                style: const TextStyle(
                  fontFamily: FnDs.font,
                  fontSize: FnDs.fontL,
                  fontWeight: FontWeight.w700,
                  color: FnDs.title,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '사입 갈 때 챙길 것과 주문 메모를 적고, 부케 모양이나 꽃 배치를 '
                '그려 기록해요.',
                style: FnDs.tsSub,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _memoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          FnDs.gapS, FnDs.gapM, FnDs.gapS, FnDs.gapM),
      decoration: FnDs.cardDeco(),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _rows.length,
        itemBuilder: (_, i) => _MemoRowView(
          row: _rows[i],
          onToggle: () => _toggle(i),
          onEnter: () => _addLineAfter(i),
          onBackspaceEmpty: () => _removeLine(i),
        ),
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
