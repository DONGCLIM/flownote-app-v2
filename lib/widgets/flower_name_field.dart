import 'package:flutter/material.dart';

import '../design/fn_autocomplete.dart';
import '../design/fn_tokens.dart';
import '../services/flower_name_service.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// FlowerNameField — 꽃 이름 입력란 (자동완성 + 표준명 보정)
/// ═══════════════════════════════════════════════════════════════════════
///
/// ## 목적
/// 지금 꽃 이름은 사실상 다 틀린다. 이유는 두 가지다.
///
/// 1. **OCR이 품목명을 일부러 포기한다.** `gemini_ocr_service.dart` 프롬프트는
///    `5. 품목명(name) — 최선을 다하되, 1~4를 훼손하면서 맞추지 않는다`,
///    `name 은 판독 불가 시 "" (지어내지 않음)` 이라고 명시한다. 사업자번호와
///    합계를 지키기 위한 의도된 설계다. → 사람이 고치는 게 정상 경로다.
/// 2. **고치는 UI가 맨 텍스트필드였다.** 아무 도움 없이 자유 입력이라
///    `장미` / `장미(레드)` / `레드장미` 가 서로 다른 품목으로 쌓이고,
///    `InsightService` 통계가 조용히 갈라진다.
///
/// 이 위젯이 2번을 해결한다. (1번은 프롬프트에 표준 품목명을 주입해서 별도 처리)
///
/// ## 기존 `_plainField` 와 시각적으로 100% 동일
/// 세 화면(`scan_review_ds_screen`, `receipt_detail_screen`,
/// `receipt_edit_screen`)의 품목 행 레이아웃을 건드리지 않기 위해
/// h40 / r9 / 14pt·w700 / rose50 1.5px focus 를 그대로 복제했다.
/// **드롭다운만 추가되고 행 높이는 안 바뀐다.**
class FlowerNameField extends StatefulWidget {
  const FlowerNameField({
    super.key,
    required this.controller,
    this.hint = '꽃 이름',
    this.bold = true,
    this.error = false,
    this.onChanged,
    this.onStandardized,
    this.height = 40,
    this.radius = 9,
  });

  final TextEditingController controller;
  final String hint;
  final bool bold;
  final bool error;

  /// 자유 입력 변경 (기존 `onChanged: (_) => _touch()` 자리)
  final VoidCallback? onChanged;

  /// 후보를 확정해 표준명이 들어갔을 때. 호출자가 토스트를 띄우고 싶을 때 쓴다.
  final void Function(String standardName)? onStandardized;

  final double height;
  final double radius;

  @override
  State<FlowerNameField> createState() => _FlowerNameFieldState();
}

class _FlowerNameFieldState extends State<FlowerNameField> {
  FlowerNameService get _svc => FlowerNameService.instance;

  @override
  Widget build(BuildContext context) {
    // 사전 로딩이 실패했으면(자산 누락 등) 자동완성 없는 평범한 입력란으로
    // 조용히 강등된다. 사전 때문에 영수증 편집이 막히면 안 된다.
    if (!_svc.isLoaded || _svc.items.isEmpty) {
      return _fallback();
    }

    return SizedBox(
      height: widget.height,
      child: FnAutoComplete(
        controller: widget.controller,
        placeholder: widget.hint,
        bold: widget.bold,
        error: widget.error,
        height: widget.height,
        radius: widget.radius,
        fontSize: widget.bold ? 14 : 13.5,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textInputAction: TextInputAction.done,
        onChanged: (_) => widget.onChanged?.call(),
        itemsBuilder: _build,
        onSelected: _select,
        footer: _footer(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────

  List<FnAcItem> _build(String q) {
    final list = _svc.suggest(q, limit: 9);
    final typed = q.trim();

    final out = <FnAcItem>[];

    // ── 맨 위는 언제나 “내가 친 그대로” ─────────────────────────────
    // Build 19 는 이 행이 없었고, 게다가 저장할 때 standardize() 를 태워서
    // 드롭다운을 건드리지 않아도 글자가 바뀌었다.
    // (`너무 상위카테고리로 잡히는데?? 그리고 그거 강요되는 구조야`)
    //
    // 이제 사전에 있는 이름이든 없는 이름이든, 사장님이 친 글자를 1순위로
    // 보여준다. 제안은 그 아래에 있고, **고를 때만** 바뀐다.
    if (typed.isNotEmpty) {
      out.add(FnAcItem(
        label: typed,
        sub: _svc.isKnown(typed)
            ? '입력한 그대로 (표준 이름)'
            : '입력한 그대로 저장',
        value: typed,
        leading: const Icon(Icons.check, size: 15, color: FnColors.leaf50),
      ));
    }

    for (final s in list) {
      // `value` 는 이제 품종까지 포함한다 (`장미 쥬밀리아`).
      // 예전엔 `s.name`(=품목)을 넣어서 품종을 골라도 `장미` 만 남았다.
      if (out.any((e) => e.value == s.value)) continue;
      out.add(FnAcItem(
        label: s.label,
        sub: s.sub,
        value: s.value,
        leading: _kindDot(s.kind, s),
      ));
    }
    return out;
  }

  void _select(FnAcItem it) {
    final typed = widget.controller.text;
    widget.controller.text = it.value;
    widget.controller.selection =
        TextSelection.collapsed(offset: it.value.length);
    // 사장님이 무엇을 무엇으로 고쳤는지 학습해서 다음엔 1순위로 제안한다.
    // (`컨트리B` 처럼 우리가 모르는 이름에 대해서만 학습한다 — learn() 내부 판정)
    _svc.learn(typed, it.value);
    widget.onChanged?.call();
    if (it.value != typed.trim()) {
      widget.onStandardized?.call(it.value);
    }
    if (mounted) setState(() {});
  }

  /// 매칭 경로를 아주 작은 색점으로 알려준다. 텍스트로 쓰면 좁은 행에서
  /// `sub` 를 밀어내므로 6px 점으로만.
  Widget _kindDot(FlowerMatchKind k, [FlowerSuggestion? s]) {
    // 이번 달 제철이면 색점을 잎색으로 바꿔서 눈에 먼저 걸리게 한다.
    // 반대로 이번 달에 아예 안 나오는 꽃은 흐리게 죽인다.
    final tag = s?.seasonTag ?? '';
    if (tag == '제철') {
      return Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: FnColors.leaf50,
          shape: BoxShape.circle,
        ),
      );
    }
    if (tag == '비수기') {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: FnColors.lineNeutral.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
      );
    }
    late Color c;
    switch (k) {
      case FlowerMatchKind.typo:
        c = FnColors.statusCautionary; // 오타 교정
        break;
      case FlowerMatchKind.alias:
        c = FnColors.rose50; // 별칭 → 표준
        break;
      case FlowerMatchKind.variety:
        c = FnColors.leaf50; // 품종
        break;
      case FlowerMatchKind.recent:
        c = FnColors.rose30;
        break;
      case FlowerMatchKind.chosung:
      case FlowerMatchKind.item:
      case FlowerMatchKind.popular:
        c = FnColors.lineNeutral;
        break;
    }
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 6, bottom: 2),
      child: Text(
        // 예전 문구는 `표준 품목명으로 저장돼요` 였다. 그게 강요를 선언하는
        // 문장이었다. 이제 저장값은 사장님이 정하고, 아래는 참고 정보만.
        // 시세 문구는 여기서 뺐다. 시세는 이름이 확정된 뒤 항목 카드에서
        // `FlowerPriceLine` 이 보여준다 — 고치는 중엔 볼 이유가 없다.
        '적은 그대로 저장돼요 · 고를 때만 바뀝니다 · '
        '${_svc.currentMonth}월 제철 우선',
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11.5,
          color: FnColors.labelAssistive,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────

  /// 사전이 없을 때의 평범한 입력란. 기존 `_plainField` 와 동일한 외형.
  Widget _fallback() {
    return SizedBox(
      height: widget.height,
      child: TextField(
        controller: widget.controller,
        onChanged: (_) => widget.onChanged?.call(),
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: widget.bold ? 14 : 13.5,
          fontWeight: widget.bold ? FontWeight.w700 : FontWeight.w500,
          color: FnColors.labelNormal,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          hintStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13.5,
            color: FnColors.labelAssistive,
          ),
          filled: true,
          fillColor: FnColors.backgroundNormal,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          border: _b(false),
          enabledBorder: _b(false),
          focusedBorder: _b(true),
        ),
      ),
    );
  }

  OutlineInputBorder _b(bool focused) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(widget.radius),
        borderSide: focused
            ? const BorderSide(color: FnColors.rose50, width: 1.5)
            : BorderSide(
                color: widget.error
                    ? FnColors.statusCautionary
                    : FnColors.lineNormal),
      );
}
