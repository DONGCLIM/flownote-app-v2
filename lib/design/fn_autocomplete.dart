import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fn_tokens.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// FnAutoComplete — 디자인 시스템 `components/inputs/AutoComplete.jsx` 포팅
/// ═══════════════════════════════════════════════════════════════════════
///
/// 원본 스펙(시안 그대로):
/// ```
/// wrapper                position: relative
/// inputRow               flex, center, gap 8, h 48, pad '0 16', r 12
///                        bg  --background-normal-normal
///                        inset shadow 0 0 0 {open?1.5:1}px {open?--blue-50:--line-normal-normal}
/// input                  flex 1, no border/outline, transparent, 16, --label-normal, minWidth 0
/// ul                     margin '6px 0 0', pad 6, absolute, l/r 0, z 10
///                        bg --background-elevated-normal, r 12, --shadow-strong
///                        maxHeight 260, overflowY auto
/// li                     pad '10px 12px', r 8, bg focused ? --fill-normal : transparent
/// label                  15 / w500 / --label-normal
/// sub                    13 / --label-alternative
/// ```
/// (이 디자인에서 `--blue-50` 은 실제로 로즈 #EE7686 = [FnColors.rose50] 이다)
///
/// ## 표시 전용(presentational)
/// 원본 주석이 `Presentational — pass items already filtered.` 라고 명시한다.
/// 필터링/랭킹은 호출자([items] 를 만드는 쪽)가 끝내고 넘긴다. 여기서는
/// **포커스 인덱스 관리와 오버레이 배치만** 담당한다.
///
/// ## 왜 Overlay 인가
/// 영수증 편집 화면의 품목 행은 `FnColumn`(스크롤) 안에 들어있다. 드롭다운을
/// 그냥 `Stack` 으로 그리면 부모의 `ClipRect` 에 잘리거나 아래 행을 밀어낸다.
/// 그래서 [OverlayEntry] + [CompositedTransformFollower] 로 띄운다.
/// 원본의 `position:absolute; z-index:10` 에 대응하는 Flutter 관용구다.
class FnAutoComplete extends StatefulWidget {
  const FnAutoComplete({
    super.key,
    required this.controller,
    required this.itemsBuilder,
    this.onSelected,
    this.onChanged,
    this.placeholder = '검색어를 입력하세요',
    this.leading,
    this.trailing,
    this.bold = false,
    this.error = false,
    this.height = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.radius = 12,
    this.fontSize = 16,
    this.background,
    this.borderColor,
    this.maxDropdownHeight = 260,
    this.textInputAction,
    this.footer,
    this.showChevron = false,
  });

  final TextEditingController controller;

  /// 현재 입력값에 대한 후보 목록. **이미 필터링·정렬된 상태**여야 한다.
  final List<FnAcItem> Function(String query) itemsBuilder;

  /// 후보 확정. 호출자가 [controller] 에 값을 넣는 책임을 진다면 여기서 하고,
  /// 안 하면 [FnAcItem.value] 가 자동으로 들어간다.
  final void Function(FnAcItem item)? onSelected;

  /// 자유 입력 변경 (후보를 안 고르고 직접 타이핑한 경우까지 포함)
  final ValueChanged<String>? onChanged;

  final String placeholder;
  final Widget? leading;
  final Widget? trailing;

  /// 품목명처럼 강조해야 하는 입력란
  final bool bold;

  /// 비어있음 등 오류 상태 (테두리 강조)
  final bool error;

  final double height;
  final EdgeInsets padding;
  final double radius;
  final double fontSize;
  final Color? background;
  final Color? borderColor;
  final double maxDropdownHeight;
  final TextInputAction? textInputAction;

  /// 드롭다운 맨 아래 고정 영역 (예: "표준명으로 저장됩니다" 안내)
  final Widget? footer;

  /// 우측 펼침 화살표 표시
  final bool showChevron;

  @override
  State<FnAutoComplete> createState() => _FnAutoCompleteState();
}

class _FnAutoCompleteState extends State<FnAutoComplete> {
  final _link = LayerLink();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  OverlayEntry? _entry;

  List<FnAcItem> _items = const [];
  int _focused = -1;

  /// dispose 진행 중 플래그.
  ///
  /// `dispose()` 안에서 `_remove()` → `setState()` 를 타면
  /// `_lifecycleState != defunct` assertion 이 터진다. 드롭다운이 열린 채로
  /// 영수증 편집 화면을 나가면 바로 재현되는 실제 버그다.
  /// (릴리즈 빌드에서는 assertion 이 없어 조용히 넘어가지만, Overlay 가
  ///  남아 화면 위에 유령 드롭다운이 떠 있을 수 있다)
  bool _disposed = false;

  bool get _open => _entry != null;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    _disposed = true;
    widget.controller.removeListener(_onText);
    _focus.removeListener(_onFocus);
    // setState 를 타지 않는 경로로 Overlay 만 정리한다.
    _entry?.remove();
    _entry = null;
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _refresh(show: true);
    } else {
      // 후보를 탭하는 순간에도 포커스가 빠지므로 프레임 하나를 기다린다.
      // (즉시 닫으면 탭 이벤트가 소실된다)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || !mounted) return;
        if (!_focus.hasFocus) _remove();
      });
    }
    _sync();
  }

  void _onText() {
    if (_disposed) return;
    widget.onChanged?.call(widget.controller.text);
    if (_focus.hasFocus) _refresh(show: true);
  }

  void _refresh({bool show = false}) {
    if (_disposed) return;
    List<FnAcItem> next;
    try {
      next = widget.itemsBuilder(widget.controller.text);
    } catch (_) {
      // 후보 생성 실패로 편집 화면 전체가 죽는 일은 없어야 한다.
      next = const [];
    }
    _items = next;
    if (_focused >= _items.length) _focused = -1;
    if (_items.isEmpty) {
      _remove();
      return;
    }
    if (show && _entry == null) {
      _insert();
    } else {
      _entry?.markNeedsBuild();
    }
  }

  void _insert() {
    if (_disposed) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: _buildDropdown);
    overlay.insert(_entry!);
    _sync();
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
    _focused = -1;
    _sync();
  }

  /// 안전한 setState. dispose 이후/중에는 아무것도 하지 않는다.
  void _sync() {
    if (_disposed || !mounted) return;
    setState(() {});
  }

  void _select(FnAcItem it) {
    if (widget.onSelected != null) {
      widget.onSelected!(it);
    } else {
      widget.controller.text = it.value;
      widget.controller.selection =
          TextSelection.collapsed(offset: it.value.length);
    }
    _remove();
    _focus.unfocus();
  }

  void _move(int delta) {
    if (_items.isEmpty || _disposed) return;
    _focused = (_focused + delta).clamp(-1, _items.length - 1);
    _sync();
    _entry?.markNeedsBuild();
  }

  // ─────────────────────────────────────────────────────────────────
  // input row
  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 원본: boxShadow inset 0 0 0 {open?1.5:1}px {open? blue-50 : line-normal}
    // Flutter 에 inset shadow 가 없으므로 동일 두께의 Border 로 대응한다.
    final focused = _focus.hasFocus || _open;
    final Color line = widget.error
        ? FnColors.statusCautionary
        : focused
            ? (widget.borderColor ?? FnColors.rose50)
            : (widget.borderColor ?? FnColors.lineNormal);

    return CompositedTransformTarget(
      link: _link,
      // 물리 키보드(웹/데스크톱/블루투스)에서 ↑↓/Enter/Esc 로 후보를 고를 수 있게 한다.
      // 모바일 소프트 키보드에서는 탭이 주 경로이므로 없어도 동작에 문제 없다.
      child: Focus(
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: _rawInput(line, focused),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      if (!_open) {
        _refresh(show: true);
      } else {
        _move(1);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_open) {
        _move(-1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.escape && _open) {
      _remove();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _rawInput(Color line, bool focused) {
    return Container(
      height: widget.height,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.background ?? FnColors.backgroundNormal,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: line, width: focused ? 1.5 : 1),
      ),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              textInputAction: widget.textInputAction,
              onSubmitted: (_) {
                if (_focused >= 0 && _focused < _items.length) {
                  _select(_items[_focused]);
                } else if (_items.isNotEmpty) {
                  _select(_items.first);
                }
              },
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: widget.fontSize,
                fontWeight: widget.bold ? FontWeight.w700 : FontWeight.w400,
                color: FnColors.labelNormal,
              ),
              cursorColor: FnColors.rose50,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: widget.placeholder,
                hintStyle: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w400,
                  color: FnColors.labelAssistive,
                ),
              ),
            ),
          ),
          if (widget.showChevron)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                _open ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: FnColors.labelAssistive,
              ),
            ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 8),
            widget.trailing!,
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // dropdown
  // ─────────────────────────────────────────────────────────────────

  Widget _buildDropdown(BuildContext ctx) {
    final size = (context.findRenderObject() as RenderBox?)?.size;
    final w = size?.width ?? 280;

    // 화면 아래쪽에 붙어있으면 위로 띄운다. (키보드가 올라온 상태에서
    // 아래로만 열면 드롭다운이 키보드 뒤로 숨는다)
    final box = context.findRenderObject() as RenderBox?;
    final screenH = MediaQuery.of(ctx).size.height;
    final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
    var below = true;
    var avail = widget.maxDropdownHeight;
    if (box != null && box.hasSize) {
      final top = box.localToGlobal(Offset.zero).dy;
      final spaceBelow = screenH - keyboard - (top + box.size.height) - 12;
      final spaceAbove = top - 12;
      if (spaceBelow < 140 && spaceAbove > spaceBelow) {
        below = false;
        avail = spaceAbove.clamp(0, widget.maxDropdownHeight);
      } else {
        avail = spaceBelow.clamp(0, widget.maxDropdownHeight);
      }
      if (avail < 80) avail = 80;
    }

    return Positioned(
      width: w,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: below ? Alignment.bottomLeft : Alignment.topLeft,
        followerAnchor: below ? Alignment.topLeft : Alignment.bottomLeft,
        offset: Offset(0, below ? 6 : -6),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            constraints: BoxConstraints(maxHeight: avail),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: FnColors.backgroundElevated,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                // --shadow-strong
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _items.length,
                    itemBuilder: (_, i) => _row(_items[i], i),
                  ),
                ),
                if (widget.footer != null) widget.footer!,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(FnAcItem it, int i) {
    final on = i == _focused;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(it),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: on ? FnColors.fillNormal : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (it.leading != null) ...[
              it.leading!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    it.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: FnColors.labelNormal,
                    ),
                  ),
                  if (it.sub != null && it.sub!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      it.sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        color: FnColors.labelAlternative,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (it.trailing != null) ...[
              const SizedBox(width: 8),
              it.trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 드롭다운 1행. 원본 `items: [{label, sub}]` 에 대응한다.
class FnAcItem {
  const FnAcItem({
    required this.label,
    required this.value,
    this.sub,
    this.leading,
    this.trailing,
  });

  /// 1행 (15/w500)
  final String label;

  /// 2행 (13/label-alternative). 시세 같은 부가 정보 자리.
  final String? sub;

  /// 확정 시 입력란에 들어갈 값. [label] 과 다를 수 있다
  /// (예: label `장미 · 쥬밀리아`, value `장미`)
  final String value;

  final Widget? leading;
  final Widget? trailing;
}
