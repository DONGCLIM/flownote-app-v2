import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../design/fn_badge_ds.dart';
import '../design/fn_card.dart';
import '../design/fn_controls_ds.dart';
import '../design/fn_feedback.dart';
import '../design/fn_sheet.dart';
import '../design/fn_shell.dart';
import '../design/fn_tokens.dart';
import '../models/receipt_model.dart';
import '../providers/receipt_provider.dart';
import '../services/vendor_tax_service.dart';
import '../widgets/flower_name_field.dart';
import '../widgets/receipt_photo.dart';
import '../widgets/flower_price_line.dart';

/// 저장된 영수증 상세 / 수정 화면.
///
/// 스캔 검토 화면(`ScanReviewDsScreen`)과 **완전히 동일한 상호작용 모델**:
/// 영수증 이미지를 상단에 고정하고, 아래에 상시 노출 입력 폼을 둔다.
/// 디자인은 Wanted DS 토큰(`FnColors` / `FnCard` / `FnShell`)으로 통일했다.
class ReceiptDetailScreen extends StatefulWidget {
  const ReceiptDetailScreen({
    super.key,
    required this.receipt,
    this.isNew = false,
  });

  final ReceiptModel receipt;
  final bool isNew;

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  late TextEditingController _storeCtrl;
  late TextEditingController _yearCtrl;
  late TextEditingController _monthCtrl;
  late TextEditingController _dayCtrl;
  late List<_ItemControllers> _itemCtrls;

  /// 편집 모드. 새 영수증(스캔 직후)이면 바로 편집 상태로 시작한다.
  bool _isEditing = false;
  bool _isSaving = false;

  /// 이미지 수동 회전 (0~3 = 0°/90°/180°/270°)
  int _imageRotation = 0;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.isNew;
    _initControllers(widget.receipt);
  }

  void _initControllers(ReceiptModel r) {
    _storeCtrl = TextEditingController(text: r.storeName);
    _yearCtrl = TextEditingController(text: r.date.year.toString());
    _monthCtrl =
        TextEditingController(text: r.date.month.toString().padLeft(2, '0'));
    _dayCtrl = TextEditingController(text: r.date.day.toString().padLeft(2, '0'));
    _itemCtrls = r.items.map(_ItemControllers.fromItem).toList();
  }

  void _resetControllers() {
    _storeCtrl.dispose();
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    _dayCtrl.dispose();
    for (final c in _itemCtrls) {
      c.dispose();
    }
    _initControllers(widget.receipt);
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    _dayCtrl.dispose();
    for (final c in _itemCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _parsedDate {
    final y = int.tryParse(_yearCtrl.text) ?? DateTime.now().year;
    final m = (int.tryParse(_monthCtrl.text) ?? 1).clamp(1, 12);
    final maxDay = DateTime(y, m + 1, 0).day;
    final d = (int.tryParse(_dayCtrl.text) ?? 1).clamp(1, maxDay);
    return DateTime(y, m, d);
  }

  double get _calcTotal => _itemCtrls.fold(0.0, (s, c) => s + c.calcTotal);

  /// 사진 영역을 보여줄지.
  ///
  /// 경로가 비어 있지 않으면 보여준다. 실제로 못 그리는 경우에도
  /// [ReceiptPhoto] 가 **이유를 설명하는 안내**를 그려주므로, 조용히
  /// 숨기는 것보다 사장님이 상황을 아는 편이 낫다.
  bool get _hasImage =>
      widget.receipt.imagePath != null && widget.receipt.imagePath!.isNotEmpty;

  // ── 저장 / 삭제 ──────────────────────────────────────────
  Future<void> _saveEdits() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final updatedItems = _itemCtrls
        .where((c) => c.nameCtrl.text.trim().isNotEmpty)
        .map((c) => FlowerItem(
              // 입력한 그대로 저장한다. 표준화는 자동완성 제안에서만 하고,
              // 저장 시점에 이름을 바꾸지 않는다. (강요 구조 제거)
              name: c.nameCtrl.text.trim(),
              quantity: c.qty,
              unitPrice: c.price,
              unit: c.unit,
              color: c.color,
            ))
        .toList();

    final updated = widget.receipt.copyWith(
      storeName: _storeCtrl.text.trim().isNotEmpty ? _storeCtrl.text.trim() : '꽃집',
      date: _parsedDate,
      items: updatedItems,
      totalAmount: _calcTotal,
      isManuallyEdited: true,
    );

    await context.read<ReceiptProvider>().updateReceipt(updated);

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _isEditing = false;
    });
    showFnToast(context, '변경사항이 저장되었습니다', type: FnToastType.success);
  }

  Future<void> _confirmDelete() async {
    final ok = await showFnAlert(
      context,
      title: '영수증 삭제',
      message: '${widget.receipt.storeName}\n'
          '${FnMoney.won(widget.receipt.totalAmount)}\n\n'
          '이 영수증을 삭제할까요? 되돌릴 수 없습니다.',
      confirmLabel: '삭제',
      cancelLabel: '취소',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    await context.read<ReceiptProvider>().deleteReceipt(widget.receipt.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleEdit() {
    if (_isEditing) _resetControllers(); // 취소 → 원래 값 복구
    setState(() => _isEditing = !_isEditing);
  }

  // ── 빌드 ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: widget.isNew ? '새 영수증' : '영수증 상세',
      onBack: () => Navigator.of(context).pop(),
      trailing: [
        if (!_isEditing && !widget.isNew)
          _navAction(
            icon: Icons.delete_outline_rounded,
            color: FnColors.statusNegative,
            onTap: _confirmDelete,
          ),
        if (_isEditing)
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: FnSpinner(size: 18, stroke: 2),
                  ),
                )
              : _navTextAction('저장', FnColors.statusPositive, _saveEdits),
        _navTextAction(
          _isEditing ? '취소' : '편집',
          FnColors.rose50,
          _toggleEdit,
        ),
      ],
      child: _body(),
    );
  }

  Widget _navAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }

  Widget _navTextAction(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  /// 이미지가 있으면 상단 고정 + 아래만 스크롤.
  /// (스캔 검토 화면 `_DraftPane.build` 와 동일한 구조)
  Widget _body() {
    if (!_hasImage) return _scrollBody();
    return Column(
      children: [
        _viewer(),
        Expanded(child: _scrollBody()),
      ],
    );
  }

  Widget _scrollBody() {
    final split = VendorTaxService.instance.split(
      widget.receipt.storeName,
      _calcTotal,
    );
    return ListView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        if (widget.isNew) ...[_newBanner(), const SizedBox(height: 14)],
        _infoCard(),
        const SizedBox(height: 14),
        _itemsCard(),
        const SizedBox(height: 14),
        _totalCard(),
        if (_isEditing) ...[
          const SizedBox(height: 12),
          _addItemButton(),
        ],
        const SizedBox(height: 14),
        _taxCard(split),
        if (!_isEditing && widget.receipt.isManuallyEdited) ...[
          const SizedBox(height: 12),
          _editedNote(),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _newBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FnColors.statusPositive.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: FnColors.statusPositive.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 16, color: FnColors.statusPositive),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '스캔이 끝났어요. 내용을 확인하고 필요하면 수정해 주세요.',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                height: 1.4,
                color: FnColors.leaf30,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editedNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.edit_outlined, size: 13, color: FnColors.labelAssistive),
        const SizedBox(width: 5),
        const Text(
          '직접 수정한 영수증이에요',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12,
            color: FnColors.labelAssistive,
          ),
        ),
      ],
    );
  }

  // ── 상단 고정 영수증 이미지 ───────────────────────────────
  Widget _viewer() {
    final path = widget.receipt.imagePath!;
    final isNetwork = path.startsWith('http');

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: FnColors.lineNeutral)),
      ),
      child: Column(
        children: [
          Container(
            color: FnColors.fillNormal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.image_outlined,
                    size: 14, color: FnColors.labelAssistive),
                const SizedBox(width: 6),
                const Text(
                  '원본 영수증',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FnColors.labelAlternative,
                  ),
                ),
                const Spacer(),
                _toolBtn(Icons.rotate_left,
                    () => setState(() => _imageRotation = (_imageRotation - 1 + 4) % 4)),
                const SizedBox(width: 8),
                _toolBtn(Icons.rotate_right,
                    () => setState(() => _imageRotation = (_imageRotation + 1) % 4)),
                const SizedBox(width: 8),
                _toolBtn(Icons.zoom_in_rounded, () => _showFull(path, isNetwork)),
              ],
            ),
          ),
          InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: GestureDetector(
              onTap: () => _showFull(path, isNetwork),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 260),
                width: double.infinity,
                color: const Color(0xFF33363D),
                child: RotatedBox(
                  quarterTurns: _imageRotation,
                  // 🔴 예전에는 `isNetwork` 하나로만 갈랐다. 그래서 웹에서
                  //    `blob:` 경로가 `Image.file(File('blob:...'))` 로
                  //    흘러가 통째로 실패했다(웹의 dart:io 는 전부
                  //    UnsupportedError 를 던지는 스텁이다).
                  //    `ReceiptPhoto` 가 http / 기기경로 / blob 세 가지를
                  //    모두 처리하고, 못 그릴 때는 이유까지 알려준다.
                  child: ReceiptPhoto(path, fit: BoxFit.fitWidth),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 스캔 검토 화면 `_toolBtn` 과 동일한 모양
  Widget _toolBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: FnColors.rose95,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: FnColors.rose50),
      ),
    );
  }

  void _showFull(String path, bool isNetwork) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullImageViewer(
          path: path,
          isNetwork: isNetwork,
          initialRotation: _imageRotation,
        ),
      ),
    );
  }

  // ── 거래처 / 날짜 카드 ───────────────────────────────────
  Widget _infoCard() {
    return FnCard(
      bordered: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              '도매업체 정보',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: FnColors.labelAlternative,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '거래일자',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  color: FnColors.labelNormal,
                ),
              ),
              if (_isEditing)
                _dateInputRow()
              else
                Text(
                  DateFormat('yyyy년 M월 d일 (E)', 'ko').format(_parsedDate),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: FnColors.labelStrong,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _labeledField('거래처', _storeCtrl, hint: '예: 대한꽃도매', required: true),
        ],
      ),
    );
  }

  /// 칩은 직접 입력용, 맨 끝 달력 버튼이 피커를 연다.
  ///
  /// 이전 구현은 칩을 `GestureDetector` 로 감싸 피커를 열려고 했지만
  /// 안쪽 `TextField` 가 탭을 흡수해 **실제로 열리지 않는 버그**가 있었다.
  /// 스캔 검토 화면과 동일하게 달력 버튼을 분리해 두 경로를 모두 보장한다.
  Widget _dateInputRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dateChipField(_yearCtrl, 4, 54, 'YYYY'),
        _dateSlash(),
        _dateChipField(_monthCtrl, 2, 34, 'MM'),
        _dateSlash(),
        _dateChipField(_dayCtrl, 2, 34, 'DD'),
        const SizedBox(width: 6),
        _toolBtn(Icons.calendar_today_rounded, _pickDate),
      ],
    );
  }

  Widget _dateSlash() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 3),
        child: Text(
          '/',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            color: FnColors.labelAssistive,
          ),
        ),
      );

  Widget _dateChipField(
      TextEditingController ctrl, int maxLen, double width, String hint) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: FnColors.rose99,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FnColors.rose50.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        maxLength: maxLen,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: FnColors.rose30,
        ),
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          hintStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 9,
            color: FnColors.labelAssistive,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final r = await showDatePicker(
      context: context,
      initialDate: _parsedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ko'),
    );
    if (r == null) return;
    _yearCtrl.text = r.year.toString();
    _monthCtrl.text = r.month.toString().padLeft(2, '0');
    _dayCtrl.text = r.day.toString().padLeft(2, '0');
    setState(() {});
  }

  Widget _labeledField(String label, TextEditingController ctrl,
      {required String hint, bool required = false}) {
    if (!_isEditing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              color: FnColors.labelNormal,
            ),
          ),
          Text(
            ctrl.text.trim().isEmpty ? '-' : ctrl.text,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: FnColors.labelStrong,
            ),
          ),
        ],
      );
    }
    final empty = required && ctrl.text.trim().isEmpty;
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              color: FnColors.labelNormal,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _plainField(ctrl,
              hint: hint, align: TextAlign.right, error: empty),
        ),
      ],
    );
  }

  // ── 항목 카드 ───────────────────────────────────────────
  Widget _itemsCard() {
    return FnCard(
      bordered: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '구매 항목',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: FnColors.labelStrong,
                  ),
                ),
                Text(
                  '${_itemCtrls.length}종',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: FnColors.labelAssistive,
                  ),
                ),
              ],
            ),
          ),
          if (_itemCtrls.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  const Text(
                    '등록된 품목이 없어요',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      color: FnColors.labelAssistive,
                    ),
                  ),
                  if (_isEditing) ...[
                    const SizedBox(height: 10),
                    FnDsButton(
                      label: '직접 추가하기',
                      size: FnDsButtonSize.small,
                      variant: FnDsButtonVariant.outlined,
                      onPressed: _addItem,
                    ),
                  ],
                ],
              ),
            )
          else
            for (var i = 0; i < _itemCtrls.length; i++)
              _isEditing ? _itemForm(i) : _itemView(i),
        ],
      ),
    );
  }

  /// 보기 모드 행
  Widget _itemView(int i) {
    final c = _itemCtrls[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: FnColors.backgroundNormal,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FnColors.lineNeutral),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.nameCtrl.text.trim().isEmpty ? '(이름 없음)' : c.nameCtrl.text,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: FnColors.labelStrong,
                  ),
                ),
              ),
              Text(
                FnMoney.won(c.calcTotal),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: FnColors.rose30,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${c.qty}${c.unit} × ${FnMoney.won(c.price)}',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              color: FnColors.labelAlternative,
            ),
          ),
        ],
      ),
    );
  }

  /// 편집 모드 폼 — 스캔 검토 화면 `_itemForm` 과 동일한 배치
  Widget _itemForm(int i) {
    final c = _itemCtrls[i];
    final nameEmpty = c.nameCtrl.text.trim().isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: nameEmpty
            ? FnColors.statusCautionaryBg
            : FnColors.backgroundNormal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: nameEmpty ? FnColors.statusCautionary : FnColors.lineNeutral,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                // 자동완성 + 표준명 보정 (스캔 검토 화면과 동일 컴포넌트)
                child: FlowerNameField(
                  controller: c.nameCtrl,
                  error: nameEmpty,
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _removeItem(i),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.remove_circle_outline,
                      size: 20, color: FnColors.statusNegative),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 40,
                child: Text(
                  '수량',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: FnColors.labelAssistive,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _plainField(c.qtyCtrl,
                    hint: '1', numeric: true, align: TextAlign.center),
              ),
              const SizedBox(width: 8),
              _unitDropdown(c),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(
                width: 40,
                child: Text(
                  '단가',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: FnColors.labelAssistive,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _plainField(c.priceCtrl,
                    hint: '0', numeric: true, prefix: '₩ '),
              ),
            ],
          ),
          // 양재 경매 시세 — 이름이 확정된 뒤에만, 없으면 스스로 사라진다.
          FlowerPriceLine(flowerName: c.nameCtrl.text),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              c.calcTotal > 0 ? '소계 ${FnMoney.won(c.calcTotal)}' : '금액 확인 필요',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: c.calcTotal > 0
                    ? FnColors.rose30
                    : FnColors.statusCautionaryStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 저장된 단위가 목록에 없으면 그 값도 함께 넣어 유지한다.
  Widget _unitDropdown(_ItemControllers c) {
    final units = <String>{..._ItemControllers.units, c.unit}.toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 40,
      decoration: BoxDecoration(
        color: FnColors.backgroundNormal,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: FnColors.lineNormal),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: c.unit,
          isDense: true,
          icon: const Icon(Icons.expand_more_rounded,
              size: 16, color: FnColors.labelAssistive),
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            color: FnColors.labelNormal,
          ),
          items: units
              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => c.unit = v);
          },
        ),
      ),
    );
  }

  void _addItem() => setState(() => _itemCtrls.add(_ItemControllers.empty()));

  void _removeItem(int i) => setState(() => _itemCtrls.removeAt(i).dispose());

  // ── 총 금액 / 세금 ───────────────────────────────────────
  Widget _totalCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            FnColors.rose50.withValues(alpha: 0.06),
            FnColors.leaf50.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FnColors.rose50.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '총 금액',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  color: FnColors.labelAlternative,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '항목 합산',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11,
                  color: FnColors.labelAssistive,
                ),
              ),
            ],
          ),
          Text(
            FnMoney.won(_calcTotal),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: FnColors.rose30,
            ),
          ),
        ],
      ),
    );
  }

  /// 과세 / 면세 분리 — 스캔 검토 화면의 세금 카드와 동일한 정보를 제공.
  Widget _taxCard(TaxSplit split) {
    final type = VendorTaxService.instance.typeOf(widget.receipt.storeName);
    final isTaxable = type == TaxType.taxable;
    return FnCard(
      bordered: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '세금 구분',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: FnColors.labelStrong,
                ),
              ),
              const SizedBox(width: 8),
              FnBadge(
                isTaxable ? '과세' : '면세',
                size: FnBadgeSize.xsmall,
                color: isTaxable
                    ? FnBadgeColor.accent
                    : FnBadgeColor.positive,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _kvRow('공급가액', FnMoney.won(split.supply)),
          const SizedBox(height: 6),
          _kvRow('부가세', FnMoney.won(split.vat)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: FnDsDivider(),
          ),
          _kvRow('합계', FnMoney.won(split.total), strong: true),
        ],
      ),
    );
  }

  Widget _kvRow(String k, String v, {bool strong = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          k,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: strong ? 15 : 13.5,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: strong ? FnColors.labelStrong : FnColors.labelAlternative,
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: strong ? 16 : 13.5,
            fontWeight: FontWeight.w700,
            color: strong ? FnColors.rose30 : FnColors.labelNormal,
          ),
        ),
      ],
    );
  }

  Widget _addItemButton() {
    return FnDsButton(
      label: '항목 추가',
      size: FnDsButtonSize.large,
      variant: FnDsButtonVariant.outlined,
      expand: true,
      leadingIcon: const Icon(Icons.add_rounded, size: 16),
      onPressed: _addItem,
    );
  }

  /// 상시 노출 입력 필드 — 스캔 검토 화면 `_plainField` 와 동일 스펙
  Widget _plainField(
    TextEditingController c, {
    required String hint,
    bool numeric = false,
    bool bold = false,
    bool error = false,
    String? prefix,
    TextAlign align = TextAlign.left,
  }) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: c,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        inputFormatters:
            numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        textAlign: align,
        onChanged: (_) => setState(() {}),
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: bold ? 14 : 13.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: FnColors.labelNormal,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          prefixText: prefix,
          prefixStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: FnColors.rose30,
          ),
          hintStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13.5,
            color: FnColors.labelAssistive,
          ),
          filled: true,
          fillColor: FnColors.backgroundNormal,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(
              color: error ? FnColors.statusCautionary : FnColors.lineNormal,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(
              color: error ? FnColors.statusCautionary : FnColors.lineNormal,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: FnColors.rose50, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// 금액 표기 헬퍼 (₩1,234).
class FnMoney {
  FnMoney._();
  static final _fmt = NumberFormat('#,###', 'ko');
  static String won(num n) => '₩${_fmt.format(n.round())}';
}

// ─────────────────────────────────────
// 전체화면 이미지 뷰어 (레터박스 없음, 수동 회전 지원)
// ─────────────────────────────────────
class _FullImageViewer extends StatefulWidget {
  const _FullImageViewer({
    required this.path,
    required this.isNetwork,
    this.initialRotation = 0,
  });

  final String path;
  final bool isNetwork;
  final int initialRotation;

  @override
  State<_FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<_FullImageViewer> {
  late int _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = widget.initialRotation;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('원본 영수증',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_left, color: Colors.white),
            onPressed: () =>
                setState(() => _rotation = (_rotation - 1 + 4) % 4),
          ),
          IconButton(
            icon: const Icon(Icons.rotate_right, color: Colors.white),
            onPressed: () => setState(() => _rotation = (_rotation + 1) % 4),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isRotated90 = _rotation % 2 != 0;
          final imgW = isRotated90 ? constraints.maxHeight : constraints.maxWidth;
          final imgH = isRotated90 ? constraints.maxWidth : constraints.maxHeight;

          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 8.0,
            constrained: false,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Center(
                child: RotatedBox(
                  quarterTurns: _rotation,
                  child: SizedBox(
                    width: imgW,
                    height: imgH,
                    child: ReceiptPhoto(widget.path, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────
// 항목 컨트롤러 묶음
// (스캔 검토 화면 `_ItemCtrls` 와 동일한 방식)
// ─────────────────────────────────────
class _ItemControllers {
  _ItemControllers({
    required this.nameCtrl,
    required this.qtyCtrl,
    required this.priceCtrl,
    required this.unit,
    this.color,
  });

  static const units = ['송이', '단(묶음)', '개'];

  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  String unit;
  String? color;

  factory _ItemControllers.fromItem(FlowerItem item) => _ItemControllers(
        nameCtrl: TextEditingController(text: item.name),
        qtyCtrl: TextEditingController(text: item.quantity.toString()),
        priceCtrl: TextEditingController(text: item.unitPrice.round().toString()),
        unit: item.unit.trim().isEmpty ? units[1] : item.unit,
        color: item.color,
      );

  factory _ItemControllers.empty() => _ItemControllers(
        nameCtrl: TextEditingController(),
        qtyCtrl: TextEditingController(text: '1'),
        priceCtrl: TextEditingController(),
        unit: units[1],
      );

  int get qty => int.tryParse(qtyCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  double get price =>
      double.tryParse(priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  double get calcTotal => qty * price;

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}
