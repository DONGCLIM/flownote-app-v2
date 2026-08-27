import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../providers/receipt_provider.dart';
import '../models/receipt_model.dart';
import '../services/receipt_parser.dart';
import '../services/training_data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/receipt_photo.dart';
import '../widgets/flower_name_field.dart';
import '../widgets/flower_price_line.dart';

/// OCR 인식 결과를 보여주고 사용자가 수정한 뒤 저장하는 화면
class ReceiptEditScreen extends StatefulWidget {
  final ParsedReceipt parsed;
  final String? imagePath;
  final bool isManual;
  /// 캘린더에서 특정 날짜로 추가할 때 설정. 설정되면 OCR 날짜를 무시하고 이 날짜를 사용.
  final DateTime? fixedDate;
  /// 학습 데이터 문서 ID (scan_screen에서 전달)
  final String? trainingDocId;

  const ReceiptEditScreen({
    super.key,
    required this.parsed,
    this.imagePath,
    this.isManual = false,
    this.fixedDate,
    this.trainingDocId,
  });

  @override
  State<ReceiptEditScreen> createState() => _ReceiptEditScreenState();
}

class _ReceiptEditScreenState extends State<ReceiptEditScreen> {
  late TextEditingController _storeNameCtrl;
  late TextEditingController _yearCtrl;
  late TextEditingController _monthCtrl;
  late TextEditingController _dayCtrl;
  late List<_EditableItem> _items;
  bool _isSaving = false;
  bool _ocrTextExpanded = false;
  int _imageRotation = 0; // 0,1,2,3 = 0°,90°,180°,270°
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _storeNameCtrl = TextEditingController(text: widget.parsed.storeName);
    // fixedDate가 있으면 OCR 날짜 무시하고 해당 날짜 사용
    final d = widget.fixedDate ?? widget.parsed.date;
    _yearCtrl = TextEditingController(text: d.year.toString());
    _monthCtrl = TextEditingController(text: d.month.toString().padLeft(2, '0'));
    _dayCtrl = TextEditingController(text: d.day.toString().padLeft(2, '0'));
    _items = widget.parsed.items
        .map((item) => _EditableItem.fromFlowerItem(item))
        .toList();

    if (widget.isManual || _items.isEmpty) {
      _items.add(_EditableItem.empty());
    }
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    _dayCtrl.dispose();
    _scrollCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  DateTime get _parsedDate {
    final y = int.tryParse(_yearCtrl.text) ?? DateTime.now().year;
    final m = int.tryParse(_monthCtrl.text) ?? 1;
    final d = int.tryParse(_dayCtrl.text) ?? 1;
    try {
      return DateTime(y, m.clamp(1, 12), d.clamp(1, 31));
    } catch (_) {
      return DateTime.now();
    }
  }

  double get _calcTotal => _items.fold(0.0, (s, i) => s + i.calcTotal);

  Future<void> _save() async {
    final validItems = _items
        .where((i) => i.nameCtrl.text.isNotEmpty && i.calcTotal > 0)
        .toList();

    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('최소 1개의 꽃 항목을 입력해주세요.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final receipt = ReceiptModel(
      id: const Uuid().v4(),
      date: _parsedDate,
      storeName: _storeNameCtrl.text.isNotEmpty ? _storeNameCtrl.text : '꽃집',
      items: validItems
          .map(
            (i) => FlowerItem(
              // 입력한 그대로 저장한다. 표준화는 자동완성 제안에서만 하고,
              // 저장 시점에 이름을 바꾸지 않는다. (강요 구조 제거)
              name: i.nameCtrl.text.trim(),
              quantity: int.tryParse(i.qtyCtrl.text) ?? 1,
              unitPrice:
                  double.tryParse(i.priceCtrl.text.replaceAll(',', '')) ?? 0,
              unit: i.unit,
            ),
          )
          .toList(),
      totalAmount: _calcTotal,
      imagePath: widget.imagePath,
      rawOcrText: widget.parsed.rawText,
      createdAt: DateTime.now(),
      isManuallyEdited: widget.isManual || widget.parsed.confidence < 0.6,
    );

    await context.read<ReceiptProvider>().addReceipt(receipt);

    // 학습 데이터: 사용자 수정본(label) 저장
    if (widget.trainingDocId != null && !widget.isManual) {
      final userLabel = ParsedReceipt(
        storeName: receipt.storeName,
        date: receipt.date,
        items: receipt.items,
        totalAmount: receipt.totalAmount,
        rawText: receipt.rawOcrText,
        confidence: 1.0, // 사용자가 확인한 데이터 = 신뢰도 100%
      );
      TrainingDataService().saveUserLabel(
        docId: widget.trainingDocId!,
        userEdited: userLabel,
      );
    }

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 영수증이 저장되었습니다!'),
          backgroundColor: AppColors.accent,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###', 'ko');

    final hasImage = !widget.isManual &&
        widget.imagePath != null &&
        widget.imagePath!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.isManual ? '수동 입력' : 'OCR 결과 확인'),
        actions: [
          if (!widget.isManual) _buildConfidenceBadge(),
        ],
      ),
      // Column: 이미지 고정(상단) + 나머지 스크롤
      body: Column(
        children: [
          // ── 상단 고정: 원본 영수증 이미지 ──
          if (hasImage) _buildStickyImageCard(),

          // ── 스크롤 영역 ──
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // OCR 원문 (접기/펼치기)
                  if (!widget.isManual && widget.parsed.rawText.isNotEmpty)
                    _buildOcrTextCollapsible(),

                  const SizedBox(height: 14),

                  // 상점명
                  _buildSectionLabel('상점명'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _storeNameCtrl,
                    decoration: const InputDecoration(
                      hintText: '예: 꽃향기 플라워',
                      prefixIcon: Icon(Icons.storefront_outlined,
                          color: AppColors.textHint),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 날짜
                  _buildSectionLabel('구매 날짜'),
                  const SizedBox(height: 8),
                  _buildDateInputRow(),

                  const SizedBox(height: 16),

                  // 꽃 항목 목록
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionLabel('구매 항목'),
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _items.add(_EditableItem.empty()));
                          // 새 항목으로 자동 스크롤
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scrollCtrl.animateTo(
                              _scrollCtrl.position.maxScrollExtent,
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOut,
                            );
                          });
                        },
                        icon: const Icon(Icons.add_circle_outline,
                            size: 16, color: AppColors.accent),
                        label: const Text(
                          '항목 추가',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.accent),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  ..._items.asMap().entries.map(
                        (entry) =>
                            _buildItemCard(entry.key, entry.value, fmt),
                      ),

                  const SizedBox(height: 12),

                  // 합계
                  _buildTotalCard(fmt),

                  const SizedBox(height: 24),

                  // 저장 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined, size: 20),
                      label: Text(_isSaving ? '저장 중...' : '저장하기'),
                    ),
                  ),

                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 날짜 입력 (탭하면 선택 리스트 + 직접 입력 병행) ──
  Widget _buildDateInputRow() {
    String dateStr = '';
    try {
      dateStr = DateFormat('yyyy년 M월 d일 (E)', 'ko').format(_parsedDate);
    } catch (_) {
      dateStr = '날짜 선택';
    }
    return GestureDetector(
      onTap: () => _showDatePickerSheet(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                color: AppColors.primary, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded,
                color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }

  void _showDatePickerSheet() {
    int pickerYear = int.tryParse(_yearCtrl.text) ?? DateTime.now().year;
    int pickerMonth = int.tryParse(_monthCtrl.text) ?? DateTime.now().month;
    int pickerDay = int.tryParse(_dayCtrl.text) ?? DateTime.now().day;

    final yearScrollCtrl = ScrollController();

    final years = List.generate(10, (i) => 2020 + i);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final yi = years.indexOf(pickerYear);
      if (yi >= 0 && yearScrollCtrl.hasClients) {
        yearScrollCtrl.jumpTo(yi * 88.0);
      }
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final daysInMonth =
                DateTime(pickerYear, pickerMonth + 1, 0).day;
            final days = List.generate(daysInMonth, (i) => i + 1);
            if (pickerDay > daysInMonth) pickerDay = daysInMonth;

            return SingleChildScrollView(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        const Text('날짜 선택',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            _yearCtrl.text = pickerYear.toString();
                            _monthCtrl.text =
                                pickerMonth.toString().padLeft(2, '0');
                            _dayCtrl.text =
                                pickerDay.toString().padLeft(2, '0');
                            setState(() {});
                            Navigator.pop(ctx);
                          },
                          child: const Text('확인',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('연도',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textHint,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 40,
                          child: ListView.builder(
                            controller: yearScrollCtrl,
                            scrollDirection: Axis.horizontal,
                            itemCount: years.length,
                            itemBuilder: (_, i) {
                              final y = years[i];
                              final sel = y == pickerYear;
                              return GestureDetector(
                                onTap: () =>
                                    setModal(() => pickerYear = y),
                                child: Container(
                                  width: 80,
                                  margin: const EdgeInsets.only(right: 8),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? AppColors.primary
                                        : AppColors.surfaceVariant,
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    border: sel
                                        ? null
                                        : Border.all(
                                            color: AppColors.border),
                                  ),
                                  child: Text('${y}년',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: sel
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                      )),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text('월',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textHint,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            childAspectRatio: 2.0,
                          ),
                          itemCount: 12,
                          itemBuilder: (_, i) {
                            final m = i + 1;
                            final sel = m == pickerMonth;
                            return GestureDetector(
                              onTap: () =>
                                  setModal(() => pickerMonth = m),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: sel
                                      ? AppColors.primary
                                      : AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(8),
                                  border: sel
                                      ? null
                                      : Border.all(
                                          color: AppColors.border),
                                ),
                                child: Text('${m}월',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: sel
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                    )),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        const Text('일',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textHint,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            childAspectRatio: 1.8,
                          ),
                          itemCount: days.length,
                          itemBuilder: (_, i) {
                            final d = days[i];
                            final sel = d == pickerDay;
                            return GestureDetector(
                              onTap: () =>
                                  setModal(() => pickerDay = d),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: sel
                                      ? AppColors.primary
                                      : AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(8),
                                  border: sel
                                      ? null
                                      : Border.all(
                                          color: AppColors.border),
                                ),
                                child: Text('${d}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: sel
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                    )),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── 신뢰도 배지 ──
  Widget _buildConfidenceBadge() {
    final conf = widget.parsed.confidence;
    final isHigh = conf >= 0.6;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isHigh
                ? AppColors.accent.withValues(alpha: 0.12)
                : AppColors.warning.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isHigh ? Icons.check_circle_outline : Icons.info_outline,
                size: 12,
                color: isHigh ? AppColors.accent : AppColors.warning,
              ),
              const SizedBox(width: 4),
              Text(
                isHigh ? '인식 양호' : '확인 필요',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isHigh ? AppColors.accent : AppColors.warning,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 상단 고정 이미지 (receipt_detail_screen 와 동일한 레이아웃) ──
  Widget _buildStickyImageCard() {
    final path = widget.imagePath!;
    final isNetwork = path.startsWith('http');

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          // ── 회전 버튼 툴바 ──
          Container(
            color: AppColors.surfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.image_outlined,
                    size: 14, color: AppColors.textHint),
                const SizedBox(width: 6),
                const Text(
                  '원본 영수증',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                // 반시계 회전
                GestureDetector(
                  onTap: () => setState(
                      () => _imageRotation = (_imageRotation - 1 + 4) % 4),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.rotate_left,
                        size: 18, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                // 시계 회전
                GestureDetector(
                  onTap: () => setState(
                      () => _imageRotation = (_imageRotation + 1) % 4),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.rotate_right,
                        size: 18, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                // 전체화면
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _FullReceiptImageViewer(
                          path: path,
                          isNetwork: isNetwork,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.zoom_in_rounded,
                        size: 18, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          // ── 이미지 본체 (핀치줌 가능) ──
          InteractiveViewer(
            minScale: 1.0,
            maxScale: 5.0,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 260),
              width: double.infinity,
              color: AppColors.surfaceVariant,
              child: RotatedBox(
                quarterTurns: _imageRotation,
                // 상세 화면과 같은 이유로 `ReceiptPhoto` 를 쓴다.
                // (웹의 `blob:` 경로가 Image.file 로 흘러가면 터진다)
                child: ReceiptPhoto(path, fit: BoxFit.fitWidth, onDark: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── OCR 원문 ──
  Widget _buildOcrTextCollapsible() {
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                setState(() => _ocrTextExpanded = !_ocrTextExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Text('📄', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  const Text(
                    'OCR 인식 원문',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '(탭하여 보기)',
                    style: TextStyle(fontSize: 10, color: AppColors.textHint),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _ocrTextExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textHint,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  widget.parsed.rawText,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.6,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            crossFadeState: _ocrTextExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }

  // ── 항목 카드 ──
  Widget _buildItemCard(int index, _EditableItem item, NumberFormat fmt) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 꽃 이름 + 삭제
          Row(
            children: [
              const Text('🌸', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                // 자동완성 + 표준명 보정. 힌트의 `튤립` 은 경매 표준 표기가
                // `튜립` 이므로 예시를 실제 표준명으로 바꿨다.
                child: FlowerNameField(
                  controller: item.nameCtrl,
                  hint: '꽃 이름 (예: 장미, 리시안사스)',
                  onChanged: () => setState(() {}),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: AppColors.error, size: 18),
                onPressed: () {
                  setState(() => _items.removeAt(index));
                },
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 수량 행
          Row(
            children: [
              const SizedBox(
                width: 52,
                child: Text('수량',
                    style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: item.qtyCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: item.unit,
                isDense: true,
                underline: const SizedBox(),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textPrimary),
                items: ['송이', '단(묶음)', '개']
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => item.unit = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 단가 행
          Row(
            children: [
              const SizedBox(
                width: 52,
                child: Text('단가',
                    style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextFormField(
                  controller: item.priceCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '예: 3000',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    prefixText: '₩ ',
                    prefixStyle: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),

          // 양재 경매 시세 — 이름이 확정된 뒤에만, 없으면 스스로 사라진다.
          FlowerPriceLine(flowerName: item.nameCtrl.text),

          // 소계
          if (item.calcTotal > 0) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '소계 ₩${fmt.format(item.calcTotal)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 합계 카드 ──
  Widget _buildTotalCard(NumberFormat fmt) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.07),
            AppColors.secondary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('총 금액',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              SizedBox(height: 2),
              Text('항목 합산',
                  style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            ],
          ),
          Text(
            '₩${fmt.format(_calcTotal)}',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────
// 편집 가능한 항목 모델
// ──────────────────────────────────────────
class _EditableItem {
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  String unit;

  _EditableItem({
    required this.nameCtrl,
    required this.qtyCtrl,
    required this.priceCtrl,
    required this.unit,
  });

  factory _EditableItem.fromFlowerItem(FlowerItem item) {
    return _EditableItem(
      nameCtrl: TextEditingController(text: item.name),
      qtyCtrl: TextEditingController(text: item.quantity.toString()),
      priceCtrl:
          TextEditingController(text: item.unitPrice.toInt().toString()),
      unit: item.unit,
    );
  }

  factory _EditableItem.empty() {
    return _EditableItem(
      nameCtrl: TextEditingController(),
      qtyCtrl: TextEditingController(text: '1'),
      priceCtrl: TextEditingController(),
      unit: '단(묶음)',
    );
  }

  double get calcTotal {
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    final price = double.tryParse(priceCtrl.text.replaceAll(',', '')) ?? 0;
    return qty * price;
  }

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

// ─────────────────────────────────────
// 전체화면 이미지 뷰어 (레터박스 없음, 수동 회전 지원)
// ─────────────────────────────────────
class _FullReceiptImageViewer extends StatefulWidget {
  final String path;
  final bool isNetwork;

  const _FullReceiptImageViewer({
    required this.path,
    required this.isNetwork,
  });

  @override
  State<_FullReceiptImageViewer> createState() =>
      _FullReceiptImageViewerState();
}

class _FullReceiptImageViewerState extends State<_FullReceiptImageViewer> {
  int _rotation = 0;

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
            tooltip: '반시계 회전',
          ),
          IconButton(
            icon: const Icon(Icons.rotate_right, color: Colors.white),
            onPressed: () =>
                setState(() => _rotation = (_rotation + 1) % 4),
            tooltip: '시계 회전',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isRotated90 = _rotation % 2 != 0;
          // 회전 90/270도일 때 가로/세로 바뀜 → 화면에 꽉 채우려면
          // 이미지를 감싸는 SizedBox 크기를 화면 반전 크기로 설정
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
