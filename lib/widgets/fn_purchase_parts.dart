import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cost_calc.dart';
import '../theme/fn_ds.dart';

/// 품목을 한 줄씩 적는 화면들이 같이 쓰는 조각. (#179)
///
/// 🔴 왜 따로 뺐나 — 원가 계산기(#178)가 쓰던 입력칸·자동완성·항목 추가를
///    예산 검토도 **그대로** 쓴다. 사장님 지시: "원가 계산기 컴포넌트 그대로".
///    복사해 두면 한쪽만 고치고 다른 쪽을 잊는다.
///
/// 쓰는 곳: `insight_ds_screens.dart` 의 원가 계산기 · 예산 검토.

/// 적은 글자에서 숫자만 추려 낸다. `3,000원` → 3000
double fnNum(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9.]'), '');
  if (digits.isEmpty) return 0;
  return double.tryParse(digits) ?? 0;
}

/// 테두리·채움이 **하나도 없는** 입력칸 꾸밈. (#188)
///
/// 🔴 왜 필요한가 — `app_theme.dart` 의 `inputDecorationTheme` 이
///    `filled: true` 와 `enabledBorder`·`focusedBorder` 를 전역으로 깔아 둔다.
///    `border: InputBorder.none` 만 주면 `border` 하나만 꺼지고
///    `enabledBorder`/`focusedBorder` 는 **그대로 남아** 테두리가 한 번 더
///    그려졌다. 바깥 `Container` 에도 테두리가 있어서 칸 하나에 선이 둘이었다.
///    → 여기서 다섯 가지를 전부 끄고 `filled` 도 끈다.
InputDecoration fnBareInput({String hint = '', double? hintSize}) {
  return InputDecoration(
    isDense: true,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    contentPadding: EdgeInsets.zero,
    hintText: hint,
    hintStyle: TextStyle(
      fontFamily: FnDs.font,
      fontSize: hintSize ?? FnDs.inputBigFont,
      color: FnDs.inputHint,
    ),
  );
}

/// 칠해지는 알약 버튼. 칩·판매 배수·자주 산 품목이 같이 쓴다.
class FnPill extends StatelessWidget {
  const FnPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? FnDs.onCoral : FnDs.sub;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? FnDs.coral : FnDs.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? FnDs.coral : FnDs.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.fontXs,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 라벨 + 입력칸.
class FnNamedField extends StatelessWidget {
  const FnNamedField({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '',
    this.suffix = '',
    this.numeric = false,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final String hint;

  /// 칸 오른쪽에 붙는 글자 (`원`, `%`).
  final String suffix;
  final bool numeric;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FnDs.tsSub),
        const SizedBox(height: 6),
        Container(
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
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: numeric
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  style: const TextStyle(
                    fontFamily: FnDs.font,
                    fontSize: FnDs.inputFont,
                    color: FnDs.title,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: hint,
                    hintStyle: const TextStyle(
                      fontFamily: FnDs.font,
                      fontSize: FnDs.inputFont,
                      color: FnDs.inputHint,
                    ),
                  ),
                ),
              ),
              if (suffix.isNotEmpty)
                Text(suffix,
                    style: const TextStyle(
                      fontFamily: FnDs.font,
                      fontSize: FnDs.inputFont,
                      color: FnDs.sub,
                    )),
            ],
          ),
        ),
      ],
    );
  }
}

/// 품목 한 줄이 들고 있는 입력칸 묶음.
class FnLineCtrl {
  FnLineCtrl({required this.onChanged}) {
    name.addListener(onChanged);
    qty.addListener(onChanged);
    price.addListener(onChanged);
  }

  final VoidCallback onChanged;
  final TextEditingController name = TextEditingController();
  final TextEditingController qty = TextEditingController();
  final TextEditingController price = TextEditingController();
  final FocusNode nameFocus = FocusNode();

  /// 영수증에 적혀 있던 단위. 자동완성으로 고르면 채워진다.
  String unit = '';

  /// 영수증에서 단가를 끌어왔는가.
  bool fromReceipt = false;

  /// 그 단가가 적힌 영수증 날짜. 화면에 `10/24 기준` 으로 보여준다.
  DateTime? basisDate;

  /// 값을 한 번에 채운다. (자주 산 품목 버튼 · 저장된 리스트 불러오기)
  void fill({
    required String itemName,
    double? quantity,
    double? unitPrice,
    String? unitLabel,
    DateTime? basis,
  }) {
    name.text = itemName;
    if (quantity != null) qty.text = CostCalc.comma(quantity);
    if (unitPrice != null) price.text = CostCalc.comma(unitPrice);
    if (unitLabel != null) unit = unitLabel;
    if (basis != null) {
      basisDate = basis;
      fromReceipt = true;
    }
  }

  CostLine toLine() => CostLine(
        name: name.text.trim(),
        qty: fnNum(qty.text),
        unitPrice: fnNum(price.text),
        unit: unit,
        fromReceipt: fromReceipt,
      );

  double get amount => toLine().amount;

  void dispose() {
    name
      ..removeListener(onChanged)
      ..dispose();
    qty
      ..removeListener(onChanged)
      ..dispose();
    price
      ..removeListener(onChanged)
      ..dispose();
    nameFocus.dispose();
  }
}

/// 품목 한 줄 — 품목명(자동완성) / 수량 / 단가.
///
/// 품목명을 적으면 **내 영수증에 있던 품목**이 자동완성으로 뜨고, 고르면
/// 가장 최근 단가와 단위가 채워진다. 그 뒤로는 고쳐 쓸 수 있다.
class FnItemLineRow extends StatefulWidget {
  const FnItemLineRow({
    super.key,
    required this.line,
    required this.book,
    required this.onRemove,
    required this.onChanged,
  });

  final FnLineCtrl line;
  final PriceBook book;

  /// null 이면 지우기 버튼을 감춘다.
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  @override
  State<FnItemLineRow> createState() => _FnItemLineRowState();
}

class _FnItemLineRowState extends State<FnItemLineRow> {
  /// 자동완성 목록을 펼칠지. 칸을 벗어나면 닫는다.
  bool _open = false;

  @override
  void initState() {
    super.initState();
    widget.line.name.addListener(_onType);
    widget.line.nameFocus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.line.name.removeListener(_onType);
    widget.line.nameFocus.removeListener(_onFocus);
    super.dispose();
  }

  void _onType() {
    // 손으로 고쳐 적으면 더 이상 "영수증에서 가져온 값"이 아니다.
    if (widget.line.fromReceipt &&
        widget.book.lookup(widget.line.name.text) == null) {
      widget.line.fromReceipt = false;
      widget.line.basisDate = null;
    }
    if (mounted) setState(() => _open = widget.line.nameFocus.hasFocus);
  }

  void _onFocus() {
    if (mounted) setState(() => _open = widget.line.nameFocus.hasFocus);
  }

  /// 자동완성에서 하나 골랐을 때 — 최근 단가와 단위를 채운다.
  void _pick(PriceBookEntry e) {
    final l = widget.line;
    l.name.text = e.name;
    // 🔴 단가는 **덮어쓴다.** 고르는 행동 자체가 "이 값으로 해 줘" 라는 뜻이다.
    //    그 뒤에 사장님이 고치면 그대로 둔다.
    l.price.text = CostCalc.comma(e.unitPrice);
    l.unit = e.unit;
    l.fromReceipt = true;
    l.basisDate = e.date;
    l.nameFocus.unfocus();
    setState(() => _open = false);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    final hits =
        _open ? widget.book.suggest(l.name.text) : const <PriceBookEntry>[];
    final unitLabel = l.unit.isEmpty ? '' : '1${l.unit} 기준';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FnNamedField(
                label: '품목명',
                controller: l.name,
                focusNode: l.nameFocus,
                hint: '예) 장미(레드)',
              ),
            ),
            if (widget.onRemove != null) ...[
              const SizedBox(width: FnDs.gapXs),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onRemove,
                child: const SizedBox(
                  height: FnDs.inputH,
                  width: 32,
                  child: Icon(Icons.remove_circle_outline_rounded,
                      size: 20, color: FnDs.sub),
                ),
              ),
            ],
          ],
        ),
        // 자동완성. 적은 글자가 들어간 **내 영수증 품목**만 나온다.
        if (hits.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: FnDs.card,
              borderRadius: BorderRadius.circular(FnDs.inputRadius),
              border: Border.all(color: FnDs.line),
            ),
            child: Column(
              children: [
                for (final e in hits)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pick(e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: FnDs.inputPadH, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.name,
                              style: const TextStyle(
                                fontFamily: FnDs.font,
                                fontSize: FnDs.fontS,
                                fontWeight: FontWeight.w600,
                                color: FnDs.title,
                              ),
                            ),
                          ),
                          Text(e.label, style: FnDs.tsSub),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: FnDs.gapS),
        Row(
          children: [
            Expanded(
              child: FnNamedField(
                label: '수량',
                controller: l.qty,
                hint: '0',
                numeric: true,
                suffix: l.unit,
              ),
            ),
            const SizedBox(width: FnDs.gapS),
            Expanded(
              child: FnNamedField(
                label: '단가',
                controller: l.price,
                hint: '0',
                numeric: true,
                suffix: '원',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                _basisText(l, unitLabel),
                style: FnDs.tsSub,
              ),
            ),
            Text(
              CostCalc.won(l.amount),
              style: const TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.fontS,
                fontWeight: FontWeight.w700,
                color: FnDs.title,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// `직전 영수증 단가 기준 · 10/24 기준` 처럼 어디서 온 값인지 알려 준다.
  ///
  /// 🔴 날짜를 붙이는 이유(사장님 지시 #179): 두 달 전 단가를 오늘 값으로
  ///    믿고 예산을 짜면 시장에서 모자란다. 언제 값인지 보여야 한다.
  String _basisText(FnLineCtrl l, String unitLabel) {
    if (!l.fromReceipt) {
      return unitLabel.isEmpty ? '단가를 직접 입력했어요.' : unitLabel;
    }
    final d = l.basisDate;
    final when = d == null
        ? ''
        : ' · ${d.month.toString().padLeft(2, '0')}/'
            '${d.day.toString().padLeft(2, '0')} 기준';
    final u = unitLabel.isEmpty ? '' : ' · $unitLabel';
    return '직전 영수증 단가 기준$when$u';
  }
}

/// 수량 칸 — `[ 20  단 ]`. (#187 예산 검토 전용 / #189 － ＋ 뺌)
///
/// 🔴 `FnNamedField` 를 안 쓰고 따로 만든 이유: 원가 계산기도 같은 조각을
///    쓰는데, 거기까지 모양이 바뀌면 안 된다. 사장님 지시(#187):
///    "다른 화면 디자인은 건드리지 마."
///
/// 🔴 #188 에서 양옆에 두었던 `－` `＋` 버튼을 #189 에서 뺐다. 사장님 지시:
///    "수량의 － / ＋ 버튼은 빼기 (지금 왼쪽에 빈 칸으로 보이는 문제도 같이
///    없어짐)". 이제 칸 하나에 숫자만 적고 단위는 오른쪽에 고정이다.
///
/// 🔴 단가 칸과 **똑같은** [FnBigField] 를 쓴다. 따로 그리면 테두리 두께나
///    여백이 미묘하게 달라져서, 나란히 놓았을 때 어긋나 보인다.
class FnStepperField extends StatelessWidget {
  const FnStepperField({
    super.key,
    required this.controller,
    required this.unit,
    required this.onChanged,
  });

  final TextEditingController controller;

  /// 칸 오른쪽에 **고정으로** 붙는 단위 글자. 지워지지 않는다.
  final String unit;

  /// 값이 바뀌면 알린다. 컨트롤러 리스너가 이미 잡지만, 쓰는 쪽이
  /// 늘 같은 모양으로 넘길 수 있게 받아 둔다.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return FnBigField(
      label: '수량',
      controller: controller,
      hint: '0',
      suffix: unit.isEmpty ? FnUnits.fallback : unit,
      numeric: true,
      alignRight: true,
      formatters: [FnDigitsFormatter()],
    );
  }
}

/// 숫자만 받는다.
class FnDigitsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue now) {
    final digits = now.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits == now.text) return now;
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

/// 숫자만 받고 **세 자리마다 쉼표**를 넣는다. 단가 칸이 쓴다. (#187)
class FnCommaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue now) {
    final digits = now.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final out = CostCalc.comma(double.parse(digits));
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

/// 큰 입력칸 — 높이 56, 글자 L. 오른쪽에 고정 글자. (#187 예산 검토 전용)
///
/// 🔴 테두리는 바깥 [Container] 하나뿐이다. 안쪽 `TextField` 는
///    [fnBareInput] 으로 전부 꺼 둔다(#188). 예전에는 전역 테마의
///    `enabledBorder` 가 살아 있어 선이 두 겹으로 보였다.
class FnBigField extends StatelessWidget {
  const FnBigField({
    super.key,
    this.label = '',
    required this.controller,
    this.hint = '',
    this.suffix = '',
    this.focusNode,
    this.formatters,
    this.numeric = false,
    this.alignRight = false,
    this.padH = FnDs.inputPadH,
  });

  /// 칸 위에 붙는 작은 라벨. 빈 글자면 라벨 줄을 아예 그리지 않는다.
  final String label;
  final TextEditingController controller;
  final String hint;

  /// 칸 오른쪽에 **고정으로** 붙는 글자 (`원`). 지워지지 않는다.
  final String suffix;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? formatters;
  final bool numeric;

  /// 숫자를 고정 글자 쪽(오른쪽)에 붙여 쓴다. 단가 칸이 쓴다.
  final bool alignRight;

  /// 칸 안 좌우 여백. 반쪽 폭에서는 좁혀 쓴다.
  final double padH;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      height: FnDs.inputBigH,
      padding: EdgeInsets.symmetric(horizontal: padH),
      decoration: BoxDecoration(
        color: FnDs.card,
        borderRadius: BorderRadius.circular(FnDs.inputRadius),
        border: Border.all(color: FnDs.line, width: FnDs.inputBorderW),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType:
                  numeric ? TextInputType.number : TextInputType.text,
              inputFormatters: formatters,
              textAlign: alignRight ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.inputBigFont,
                fontWeight: FontWeight.w600,
                color: FnDs.title,
              ),
              decoration: fnBareInput(hint: hint),
            ),
          ),
          if (suffix.isNotEmpty) ...[
            const SizedBox(width: 2),
            Text(
              suffix,
              style: const TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.inputBigFont,
                color: FnDs.sub,
              ),
            ),
          ],
        ],
      ),
    );

    if (label.isEmpty) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FnDs.tsSub),
        const SizedBox(height: 6),
        box,
      ],
    );
  }
}

/// 수량 단위를 정하는 규칙. (#187)
class FnUnits {
  FnUnits._();

  /// 영수증에 아무 기록이 없을 때 쓰는 기본 단위.
  static const String fallback = '단';

  /// 이 품목을 어떤 단위로 셀지.
  ///
  /// 🔴 영수증에 그 품목이 **다른 단위**(개·송이·롤)로 적혀 있으면 그걸
  ///    따른다. 꽃집마다 세는 법이 달라서, 늘 `단` 으로 두면 화분을 사도
  ///    `20단` 이 된다.
  static String forItem(String name, PriceBook book) {
    final e = book.lookup(name);
    final u = e?.unit.trim() ?? '';
    return u.isEmpty ? fallback : u;
  }
}

/// 품목 한 줄 — **예산 검토 전용** 큰 입력칸. (#187)
///
/// 🔴 [FnItemLineRow] 를 고치지 않고 따로 만들었다. 그건 원가 계산기도
///    쓰는데, 사장님 지시(#187)는 "다른 화면 디자인은 건드리지 마" 다.
///    자동완성 고르는 동작은 같게 맞춰 두었다.
class FnBigItemLineRow extends StatefulWidget {
  const FnBigItemLineRow({
    super.key,
    required this.line,
    required this.book,
    required this.onRemove,
    required this.onChanged,
  });

  final FnLineCtrl line;
  final PriceBook book;

  /// null 이면 지우기 버튼을 감춘다.
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  @override
  State<FnBigItemLineRow> createState() => _FnBigItemLineRowState();
}

class _FnBigItemLineRowState extends State<FnBigItemLineRow> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    widget.line.name.addListener(_onType);
    widget.line.nameFocus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.line.name.removeListener(_onType);
    widget.line.nameFocus.removeListener(_onFocus);
    super.dispose();
  }

  void _onType() {
    if (widget.line.fromReceipt &&
        widget.book.lookup(widget.line.name.text) == null) {
      widget.line.fromReceipt = false;
      widget.line.basisDate = null;
    }
    if (mounted) setState(() => _open = widget.line.nameFocus.hasFocus);
  }

  void _onFocus() {
    if (mounted) setState(() => _open = widget.line.nameFocus.hasFocus);
  }

  /// 자동완성에서 하나 골랐다.
  void _pick(PriceBookEntry e) {
    final l = widget.line;
    l.name.text = e.name;
    l.unit = e.unit.isEmpty ? FnUnits.fallback : e.unit;

    if (e.mixedUnit) {
      // 🔴 단·송이를 섞어 산 품목이다. 단가를 **채우지 않는다.**
      //    사장님 지시(#187): "단위가 다른 영수증 단가는 섞어서 자동
      //    채우지 말 것". 열 배 틀린 예산보다 빈칸이 낫다.
      l.price.clear();
      l.fromReceipt = false;
      l.basisDate = null;
    } else {
      l.price.text = CostCalc.comma(e.unitPrice);
      l.fromReceipt = true;
      l.basisDate = e.date;
    }
    l.nameFocus.unfocus();
    setState(() => _open = false);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    final hits =
        _open ? widget.book.suggest(l.name.text) : const <PriceBookEntry>[];
    final unit = l.unit.isEmpty ? FnUnits.fallback : l.unit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1줄 — 품목명 + 오른쪽 ✕ 삭제.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FnBigField(
                label: '품목명',
                controller: l.name,
                focusNode: l.nameFocus,
                hint: '예) 장미(레드)',
              ),
            ),
            if (widget.onRemove != null) ...[
              const SizedBox(width: FnDs.gapXs),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onRemove,
                child: const SizedBox(
                  height: FnDs.inputBigH,
                  width: 30,
                  child: Icon(Icons.close_rounded, size: 18, color: FnDs.sub),
                ),
              ),
            ],
          ],
        ),
        if (hits.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: FnDs.card,
              borderRadius: BorderRadius.circular(FnDs.inputRadius),
              border: Border.all(color: FnDs.line),
            ),
            child: Column(
              children: [
                for (final e in hits)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pick(e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: FnDs.inputPadH, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.name,
                              style: const TextStyle(
                                fontFamily: FnDs.font,
                                fontSize: FnDs.fontS,
                                fontWeight: FontWeight.w600,
                                color: FnDs.title,
                              ),
                            ),
                          ),
                          Text(
                            // 단위가 섞인 품목은 단가를 안 채운다고 미리 알린다.
                            e.mixedUnit ? '단위가 섞여 있어요' : e.label,
                            style: FnDs.tsSub,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: FnDs.gapS),
        // 2줄 — 수량과 단가를 **같은 너비로** 나란히.
        //    사장님 지시(#188 "처음 시안처럼" · #189 "같은 너비로").
        //    Expanded 둘 다 flex 1 이라 정확히 반씩 나눠 쓴다.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FnStepperField(
                controller: l.qty,
                unit: unit,
                onChanged: widget.onChanged,
              ),
            ),
            const SizedBox(width: FnDs.gapS),
            Expanded(
              child: FnBigField(
                label: '단가',
                controller: l.price,
                hint: '0',
                suffix: '원',
                numeric: true,
                alignRight: true,
                formatters: [FnCommaFormatter()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 3줄 — 왼쪽에 어디서 온 단가인지, 오른쪽에 금액.
        Row(
          children: [
            Expanded(child: Text(_basisText(l), style: FnDs.tsSub)),
            Text(
              CostCalc.won(l.amount),
              style: const TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.fontS,
                fontWeight: FontWeight.w700,
                color: FnDs.title,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 어디서 온 단가인지 알려 준다.
  ///
  /// 🔴 단위(`1단 기준`)는 빼 둔다(#188). 수량 칸에 단위가 이미 붙어 있고,
  ///    반쪽 폭 줄에서는 글자가 길면 잘린다. 사장님 지시: 왼쪽에
  ///    "○/○ 영수증 기준" 또는 "직접 입력".
  String _basisText(FnLineCtrl l) {
    if (!l.fromReceipt) return '직접 입력';
    final d = l.basisDate;
    if (d == null) return '직전 영수증 기준';
    return '${d.month.toString().padLeft(2, '0')}/'
        '${d.day.toString().padLeft(2, '0')} 영수증 기준';
  }
}
