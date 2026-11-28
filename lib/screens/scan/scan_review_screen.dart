import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_button.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_card.dart';
import '../../design/fn_input.dart';
import '../../design/fn_sheet.dart';
import '../../design/fn_feedback.dart';
import '../../design/fn_scaffold.dart';
import '../../providers/receipt_provider.dart';
import '../../services/vendor_tax_service.dart';
import '../../services/subscription_service.dart';
import 'scan_draft.dart';
import 'scan_complete_screen.dart';

final _won = NumberFormat('#,###');

/// 인식 결과 검토 화면.
///
/// 프로토타입의 "4단계 검토" — 영수증 여러 장을 한 장씩 넘기면서
/// 매입처 / 날짜 / 품목 / 합계를 확인하고 저장한다.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({super.key, required this.drafts});

  final List<ScanDraft> drafts;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  late final PageController _page = PageController();
  int _index = 0;
  bool _saving = false;

  List<ScanDraft> get _drafts => widget.drafts;
  ScanDraft get _d => _drafts[_index];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i < 0 || i >= _drafts.length) return;
    _page.animateToPage(i,
        duration: FnDuration.normal, curve: Curves.easeOutCubic);
  }

  Future<void> _next() async {
    _d.reviewed = true;
    if (_index < _drafts.length - 1) {
      setState(() {});
      _go(_index + 1);
    } else {
      await _save();
    }
  }

  Future<void> _save() async {
    final live = _drafts.where((d) => !d.excluded && d.total > 0).toList();
    if (live.isEmpty) {
      showFnToast(context, '저장할 영수증이 없어요', type: FnToastType.warning);
      return;
    }

    final ok = await showFnAlert(
      context,
      title: '${live.length}건을 저장할까요?',
      message:
          '합계 ${_won.format(live.fold(0.0, (s, d) => s + d.total).round())}원',
      icon: Icons.save_alt_rounded,
      confirmLabel: '저장',
      cancelLabel: '더 볼게요',
    );
    if (!ok || !mounted) return;

    setState(() => _saving = true);
    final provider = context.read<ReceiptProvider>();
    for (final d in live) {
      await provider.addReceipt(d.toReceipt());
      await SubscriptionService.instance.recordScan();
    }
    if (!mounted) return;
    setState(() => _saving = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ScanCompleteScreen(summary: ScanSummary.of(live)),
      ),
    );
  }

  Future<void> _confirmExit() async {
    final ok = await showFnAlert(
      context,
      title: '검토를 그만둘까요?',
      message: '아직 저장하지 않은 인식 결과가 사라져요.',
      icon: Icons.warning_amber_rounded,
      iconColor: FnColors.statusCautionary,
      confirmLabel: '나가기',
      cancelLabel: '계속 검토',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final n = _drafts.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Stack(
        children: [
          FnScaffold(
            appBar: FnAppBar(
              title: n > 1 ? '인식 결과 ${_index + 1}/$n' : '인식 결과',
              onBack: _confirmExit,
              actions: [
                if (n > 1)
                  FnTextButton(
                    label: '전체보기',
                    onPressed: _showAllSheet,
                  ),
              ],
            ),
            bottomBar: _BottomBar(
              isLast: _index == n - 1,
              count: n,
              index: _index,
              amount: _d.total,
              onNext: _next,
              onSaveAll: n > 1 ? _save : null,
            ),
            body: Column(
              children: [
                if (n > 1) _StepDots(count: n, index: _index, drafts: _drafts),
                Expanded(
                  child: PageView.builder(
                    controller: _page,
                    itemCount: n,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _DraftEditor(
                      key: ValueKey(_drafts[i].id),
                      draft: _drafts[i],
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_saving) const FnLoadingOverlay(message: '저장하는 중...'),
        ],
      ),
    );
  }

  void _showAllSheet() {
    showFnSheet(
      context,
      title: '인식한 영수증 ${_drafts.length}건',
      subtitle: '탭하면 해당 영수증으로 이동해요',
      child: Column(
        children: [
          for (var i = 0; i < _drafts.length; i++)
            _AllRow(
              draft: _drafts[i],
              index: i,
              current: i == _index,
              onTap: () {
                Navigator.pop(context);
                _go(i);
              },
              onToggle: () {
                setState(() => _drafts[i].excluded = !_drafts[i].excluded);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── 단계 인디케이터

class _StepDots extends StatelessWidget {
  const _StepDots(
      {required this.count, required this.index, required this.drafts});

  final int count;
  final int index;
  final List<ScanDraft> drafts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          FnSpace.x20, FnSpace.x12, FnSpace.x20, FnSpace.x4),
      child: Row(
        children: List.generate(count, (i) {
          final d = drafts[i];
          final done = d.reviewed && !d.excluded;
          final active = i == index;
          Color c;
          if (d.excluded) {
            c = FnColors.lineNeutral;
          } else if (active) {
            c = FnColors.primaryNormal;
          } else if (done) {
            c = FnColors.statusPositive;
          } else {
            c = FnColors.lineNormal;
          }
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == count - 1 ? 0 : 4),
              child: AnimatedContainer(
                duration: FnDuration.fast,
                height: 4,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: FnRadius.brFull,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ───────────────────────────── 한 장 편집기

class _DraftEditor extends StatefulWidget {
  const _DraftEditor({super.key, required this.draft, required this.onChanged});

  final ScanDraft draft;
  final VoidCallback onChanged;

  @override
  State<_DraftEditor> createState() => _DraftEditorState();
}

class _DraftEditorState extends State<_DraftEditor> {
  late final TextEditingController _store =
      TextEditingController(text: widget.draft.storeName);

  ScanDraft get d => widget.draft;

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  void _touch() {
    setState(() {});
    widget.onChanged();
  }

  Future<void> _pickDate() async {
    final r = await showDatePicker(
      context: context,
      initialDate: d.date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ko'),
    );
    if (r != null) {
      d.date = DateTime(r.year, r.month, r.day, d.date.hour, d.date.minute);
      _touch();
    }
  }

  Future<void> _editItem(int? i) async {
    final item = i == null ? DraftItem(name: '') : d.items[i].copy();
    final saved = await showFnSheet<DraftItem>(
      context,
      title: i == null ? '품목 추가' : '품목 수정',
      child: _ItemForm(item: item),
    );
    if (saved == null) return;
    if (saved.name.trim().isEmpty) return;
    setState(() {
      if (i == null) {
        d.items.add(saved);
      } else {
        d.items[i] = saved;
      }
      d.recalcTotal();
    });
    widget.onChanged();
  }

  Future<void> _editTotal() async {
    final c = TextEditingController(text: d.total.round().toString());
    final r = await showFnSheet<double>(
      context,
      title: '합계 직접 입력',
      subtitle: '영수증에 적힌 최종 금액을 넣어주세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FnAmountField(controller: c, label: '합계 금액'),
          const SizedBox(height: FnSpace.x16),
          Row(
            children: [
              Expanded(
                child: FnButton(
                  label: '품목 합계로 되돌리기',
                  variant: FnButtonVariant.outlined,
                  expand: true,
                  onPressed: () => Navigator.pop(context, -1.0),
                ),
              ),
              const SizedBox(width: FnSpace.x8),
              Expanded(
                child: FnButton(
                  label: '적용',
                  expand: true,
                  onPressed: () {
                    final v = double.tryParse(
                            c.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
                        0;
                    Navigator.pop(context, v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (r == null) return;
    setState(() {
      if (r < 0) {
        d.recalcTotal();
      } else {
        d.total = r;
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final split = d.split;
    final warn = d.warning;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          FnSpace.x20, FnSpace.x12, FnSpace.x20, FnSpace.x24),
      children: [
        if (warn != null) _WarnBanner(text: warn, failed: d.isFailed),
        if (warn != null) const SizedBox(height: FnSpace.x12),

        // 영수증 미리보기 + 매입처
        FnCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Thumb(draft: d),
                  const SizedBox(width: FnSpace.x12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('매입처',
                                style: FnType.label2.copyWith(
                                    color: FnColors.labelAlternative)),
                            const SizedBox(width: FnSpace.x6),
                            if (d.storeName.trim().isNotEmpty)
                              d.taxType == TaxType.exempt
                                  ? const FnBadge.taxExempt()
                                  : const FnBadge.taxable(),
                          ],
                        ),
                        const SizedBox(height: FnSpace.x6),
                        TextField(
                          controller: _store,
                          style: FnType.heading2,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '매입처 이름',
                            hintStyle: FnType.heading2
                                .copyWith(color: FnColors.labelDisable),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (v) {
                            d.storeName = v;
                            _touch();
                          },
                        ),
                        const SizedBox(height: FnSpace.x8),
                        GestureDetector(
                          onTap: _pickDate,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today_rounded,
                                  size: 13, color: FnColors.labelAlternative),
                              const SizedBox(width: FnSpace.x6),
                              Text(
                                DateFormat('yyyy.MM.dd (E)', 'ko')
                                    .format(d.date),
                                style: FnType.body2
                                    .copyWith(color: FnColors.labelNeutral),
                              ),
                              const Icon(Icons.expand_more_rounded,
                                  size: 16, color: FnColors.labelAlternative),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // OCR 이 사업자등록번호를 읽어냈으면 함께 보여준다.
              if (d.businessNumber.isNotEmpty) ...[
                const SizedBox(height: FnSpace.x10),
                Row(
                  children: [
                    Text('사업자번호',
                        style: FnType.label2
                            .copyWith(color: FnColors.labelAlternative)),
                    const SizedBox(width: FnSpace.x6),
                    Text(d.businessNumber,
                        style: FnType.body2
                            .copyWith(color: FnColors.labelNeutral)),
                  ],
                ),
              ],
              if (d.storeName.trim().isNotEmpty) ...[
                const SizedBox(height: FnSpace.x12),
                _TaxToggle(
                  vendor: d.storeName.trim(),
                  onChanged: _touch,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: FnSpace.x12),

        // 품목
        Row(
          children: [
            Text('품목 ${d.items.length}개', style: FnType.heading2),
            const Spacer(),
            FnTextButton(
              label: '추가',
              trailingIcon: Icons.add_rounded,
              onPressed: () => _editItem(null),
            ),
          ],
        ),
        const SizedBox(height: FnSpace.x8),
        if (d.items.isEmpty)
          FnCard(
            bordered: true,
            child: Column(
              children: [
                const Icon(Icons.inbox_rounded,
                    size: 32, color: FnColors.labelDisable),
                const SizedBox(height: FnSpace.x8),
                Text('인식된 품목이 없어요',
                    style: FnType.body2
                        .copyWith(color: FnColors.labelAlternative)),
                const SizedBox(height: FnSpace.x12),
                FnButton(
                  label: '직접 추가하기',
                  size: FnButtonSize.small,
                  variant: FnButtonVariant.outlined,
                  onPressed: () => _editItem(null),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < d.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: FnSpace.x8),
              child: _ItemRow(
                item: d.items[i],
                onTap: () => _editItem(i),
                onDelete: () {
                  setState(() {
                    d.items.removeAt(i);
                    d.recalcTotal();
                  });
                  widget.onChanged();
                },
              ),
            ),

        const SizedBox(height: FnSpace.x16),

        // 합계
        FnCard(
          color: FnColors.rose99,
          child: Column(
            children: [
              Row(
                children: [
                  Text('합계', style: FnType.heading2),
                  if (d.totalOverridden) ...[
                    const SizedBox(width: FnSpace.x6),
                    const FnBadge(label: '직접입력', size: FnBadgeSize.xsmall),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: _editTotal,
                    child: Row(
                      children: [
                        Text('${_won.format(d.total.round())}원',
                            style: FnType.title3
                                .copyWith(color: FnColors.primaryNormal)),
                        const SizedBox(width: FnSpace.x4),
                        const Icon(Icons.edit_rounded,
                            size: 15, color: FnColors.labelAlternative),
                      ],
                    ),
                  ),
                ],
              ),
              if (d.taxType == TaxType.taxable) ...[
                const SizedBox(height: FnSpace.x12),
                const Divider(height: 1, color: FnColors.lineAlternative),
                const SizedBox(height: FnSpace.x12),
                _SplitRow(label: '공급가액', value: split.supply),
                const SizedBox(height: FnSpace.x6),
                _SplitRow(label: '부가세', value: split.vat, accent: true),
              ],
            ],
          ),
        ),
        const SizedBox(height: FnSpace.x12),

        // 제외 토글
        Center(
          child: FnTextButton(
            label: d.excluded ? '저장 목록에 다시 넣기' : '이 영수증은 저장하지 않기',
            color:
                d.excluded ? FnColors.primaryNormal : FnColors.labelAlternative,
            onPressed: () {
              setState(() => d.excluded = !d.excluded);
              widget.onChanged();
            },
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── 부품

class _Thumb extends StatelessWidget {
  const _Thumb({required this.draft});
  final ScanDraft draft;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFull(context),
      child: ClipRRect(
        borderRadius: FnRadius.br10,
        child: SizedBox(
          width: 64,
          height: 84,
          child: kIsWeb
              ? Container(
                  color: FnColors.neutral97,
                  child: const Icon(Icons.receipt_long_rounded,
                      color: FnColors.neutral80),
                )
              : Image.file(
                  File(draft.file.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: FnColors.neutral97,
                    child: const Icon(Icons.receipt_long_rounded,
                        color: FnColors.neutral80),
                  ),
                ),
        ),
      ),
    );
  }

  void _showFull(BuildContext context) {
    if (kIsWeb) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          child: Center(child: Image.file(File(draft.file.path))),
        ),
      ),
    );
  }
}

class _WarnBanner extends StatelessWidget {
  const _WarnBanner({required this.text, required this.failed});
  final String text;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final c = failed ? FnColors.statusNegative : FnColors.statusCautionary;
    final bg = failed ? FnColors.statusNegativeBg : FnColors.statusCautionaryBg;
    return Container(
      padding: const EdgeInsets.all(FnSpace.x12),
      decoration: BoxDecoration(color: bg, borderRadius: FnRadius.br12),
      child: Row(
        children: [
          Icon(
              failed ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              size: 18,
              color: c),
          const SizedBox(width: FnSpace.x8),
          Expanded(
            child: Text(text,
                style: FnType.caption1.copyWith(color: FnColors.labelNeutral)),
          ),
        ],
      ),
    );
  }
}

class _TaxToggle extends StatelessWidget {
  const _TaxToggle({required this.vendor, required this.onChanged});
  final String vendor;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final svc = VendorTaxService.instance;
    final t = svc.typeOf(vendor);
    return Container(
      padding: const EdgeInsets.all(FnSpace.x10),
      decoration: BoxDecoration(
        color: FnColors.fillAlternative,
        borderRadius: FnRadius.br10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('과세 구분', style: FnType.label2),
                const SizedBox(height: 2),
                Text(t.description,
                    style: FnType.caption2
                        .copyWith(color: FnColors.labelAlternative)),
              ],
            ),
          ),
          SizedBox(
            width: 132,
            child: FnSegmented<TaxType>(
              value: t,
              items: const [TaxType.exempt, TaxType.taxable],
              labelOf: (e) => e.label,
              onChanged: (v) async {
                await svc.setType(vendor, v);
                onChanged();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow(
      {required this.item, required this.onTap, required this.onDelete});

  final DraftItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: FnSpace.x20),
        decoration: BoxDecoration(
          color: FnColors.statusNegativeBg,
          borderRadius: FnRadius.br12,
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: FnColors.statusNegative),
      ),
      child: FnCard(
        bordered: true,
        padding: const EdgeInsets.symmetric(
            horizontal: FnSpace.x14, vertical: FnSpace.x12),
        radius: FnRadius.r12,
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name.isEmpty ? '이름 없음' : item.name,
                      style: FnType.body1.copyWith(
                        fontWeight: FontWeight.w600,
                        color: item.name.isEmpty
                            ? FnColors.labelDisable
                            : FnColors.labelNormal,
                      )),
                  const SizedBox(height: 2),
                  Text(
                    '${item.quantity}${item.unit} × ${_won.format(item.unitPrice.round())}원',
                    style: FnType.caption1
                        .copyWith(color: FnColors.labelAlternative),
                  ),
                ],
              ),
            ),
            Text('${_won.format(item.totalPrice.round())}원',
                style: FnType.label1.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: FnSpace.x4),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: FnColors.labelAssistive),
          ],
        ),
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow(
      {required this.label, required this.value, this.accent = false});

  final String label;
  final double value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: FnType.body2.copyWith(color: FnColors.labelAlternative)),
        const Spacer(),
        Text('${_won.format(value.round())}원',
            style: FnType.body2.copyWith(
              fontWeight: FontWeight.w600,
              color: accent ? FnColors.statusPositive : FnColors.labelNeutral,
            )),
      ],
    );
  }
}

class _ItemForm extends StatefulWidget {
  const _ItemForm({required this.item});
  final DraftItem item;

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _price = TextEditingController(
      text: widget.item.unitPrice > 0
          ? _won.format(widget.item.unitPrice.round())
          : '');
  late int _qty = widget.item.quantity;
  late String _unit = widget.item.unit;

  static const _units = ['단', '속', '박스', '개', '송이', 'kg'];

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  double get _unitPrice =>
      double.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FnTextField(
          label: '품목명',
          hint: '예) 장미 레드나오미',
          controller: _name,
          autofocus: widget.item.name.isEmpty,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: FnSpace.x16),
        Text('단위', style: FnType.label2.copyWith(color: FnColors.labelNeutral)),
        const SizedBox(height: FnSpace.x8),
        Wrap(
          spacing: FnSpace.x8,
          children: [
            for (final u in _units)
              ChoiceChip(
                label: Text(u),
                selected: _unit == u,
                onSelected: (_) => setState(() => _unit = u),
                labelStyle: FnType.caption1.copyWith(
                  color: _unit == u ? Colors.white : FnColors.labelNeutral,
                  fontWeight: FontWeight.w600,
                ),
                selectedColor: FnColors.primaryNormal,
                backgroundColor: FnColors.fillNormal,
                showCheckmark: false,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: FnRadius.brFull),
              ),
          ],
        ),
        const SizedBox(height: FnSpace.x16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('수량',
                      style:
                          FnType.label2.copyWith(color: FnColors.labelNeutral)),
                  const SizedBox(height: FnSpace.x8),
                  _Stepper(
                    value: _qty,
                    onChanged: (v) => setState(() => _qty = v),
                  ),
                ],
              ),
            ),
            const SizedBox(width: FnSpace.x12),
            Expanded(
              flex: 6,
              child: FnAmountField(
                label: '단가',
                controller: _price,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: FnSpace.x16),
        Container(
          padding: const EdgeInsets.all(FnSpace.x12),
          decoration: BoxDecoration(
            color: FnColors.rose99,
            borderRadius: FnRadius.br10,
          ),
          child: Row(
            children: [
              Text('금액',
                  style:
                      FnType.body2.copyWith(color: FnColors.labelAlternative)),
              const Spacer(),
              Text('${_won.format((_qty * _unitPrice).round())}원',
                  style:
                      FnType.heading2.copyWith(color: FnColors.primaryNormal)),
            ],
          ),
        ),
        const SizedBox(height: FnSpace.x20),
        FnButton(
          label: '적용',
          expand: true,
          size: FnButtonSize.large,
          onPressed: _name.text.trim().isEmpty
              ? null
              : () {
                  Navigator.pop(
                    context,
                    DraftItem(
                      name: _name.text.trim(),
                      quantity: _qty,
                      unitPrice: _unitPrice,
                      unit: _unit,
                      color: widget.item.color,
                    ),
                  );
                },
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: FnColors.fillNormal,
        borderRadius: FnRadius.br10,
      ),
      child: Row(
        children: [
          _btn(Icons.remove_rounded,
              value > 1 ? () => onChanged(value - 1) : null),
          Expanded(
            child: Center(
              child: Text('$value', style: FnType.heading2),
            ),
          ),
          _btn(Icons.add_rounded, () => onChanged(value + 1)),
        ],
      ),
    );
  }

  Widget _btn(IconData i, VoidCallback? onTap) => SizedBox(
        width: 44,
        height: 48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
            borderRadius: FnRadius.br10,
            child: Icon(i,
                size: 18,
                color: onTap == null
                    ? FnColors.labelDisable
                    : FnColors.labelNeutral),
          ),
        ),
      );
}

class _AllRow extends StatelessWidget {
  const _AllRow({
    required this.draft,
    required this.index,
    required this.current,
    required this.onTap,
    required this.onToggle,
  });

  final ScanDraft draft;
  final int index;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final off = draft.excluded;
    return Padding(
      padding: const EdgeInsets.only(bottom: FnSpace.x8),
      child: FnCard(
        bordered: true,
        radius: FnRadius.r12,
        borderColor: current ? FnColors.primaryNormal : null,
        padding: const EdgeInsets.symmetric(
            horizontal: FnSpace.x12, vertical: FnSpace.x10),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: off
                    ? FnColors.fillNormal
                    : draft.isFailed
                        ? FnColors.statusNegativeBg
                        : FnColors.rose95,
                shape: BoxShape.circle,
              ),
              child: Text('${index + 1}',
                  style: FnType.caption2.copyWith(
                    fontWeight: FontWeight.w700,
                    color: off
                        ? FnColors.labelDisable
                        : draft.isFailed
                            ? FnColors.statusNegative
                            : FnColors.primaryNormal,
                  )),
            ),
            const SizedBox(width: FnSpace.x10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    draft.storeName.isEmpty ? '매입처 미입력' : draft.storeName,
                    style: FnType.body2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: off ? FnColors.labelDisable : FnColors.labelNormal,
                      decoration: off ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text('품목 ${draft.items.length}개',
                      style: FnType.caption2
                          .copyWith(color: FnColors.labelAlternative)),
                ],
              ),
            ),
            Text('${_won.format(draft.total.round())}원',
                style: FnType.label2.copyWith(
                  color: off ? FnColors.labelDisable : FnColors.labelNormal,
                )),
            const SizedBox(width: FnSpace.x4),
            IconButton(
              icon: Icon(
                off
                    ? Icons.add_circle_outline_rounded
                    : Icons.remove_circle_outline_rounded,
                size: 18,
              ),
              color: off ? FnColors.statusPositive : FnColors.labelAssistive,
              onPressed: onToggle,
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isLast,
    required this.count,
    required this.index,
    required this.amount,
    required this.onNext,
    this.onSaveAll,
  });

  final bool isLast;
  final int count;
  final int index;
  final double amount;
  final VoidCallback onNext;
  final VoidCallback? onSaveAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('이 영수증',
                style:
                    FnType.caption1.copyWith(color: FnColors.labelAlternative)),
            const Spacer(),
            Text('${_won.format(amount.round())}원', style: FnType.heading2),
          ],
        ),
        const SizedBox(height: FnSpace.x10),
        Row(
          children: [
            if (onSaveAll != null && !isLast) ...[
              Expanded(
                child: FnButton(
                  label: '전체 저장',
                  variant: FnButtonVariant.outlined,
                  size: FnButtonSize.large,
                  expand: true,
                  onPressed: onSaveAll,
                ),
              ),
              const SizedBox(width: FnSpace.x8),
            ],
            Expanded(
              flex: 2,
              child: FnButton(
                label: isLast ? '저장하기' : '다음 (${index + 2}/$count)',
                size: FnButtonSize.large,
                expand: true,
                trailingIcon:
                    isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                onPressed: onNext,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
