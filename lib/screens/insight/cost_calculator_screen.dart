import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_button.dart';
import '../../design/fn_card.dart';
import '../../design/fn_chart.dart';
import '../../design/fn_input.dart';
import '../../design/fn_list.dart';
import '../../design/fn_scaffold.dart';
import '../../providers/receipt_provider.dart';
import '../../services/insight_service.dart';

class _CostLine {
  String name;
  int qty;
  double unitPrice;
  _CostLine({required this.name, this.qty = 1, this.unitPrice = 0});
  double get total => qty * unitPrice;
}

/// 원가 계산기 — 상품(꽃다발/화환)의 재료 원가와 판매가를 산출
class CostCalculatorScreen extends StatefulWidget {
  const CostCalculatorScreen({super.key});

  @override
  State<CostCalculatorScreen> createState() => _CostCalculatorScreenState();
}

class _CostCalculatorScreenState extends State<CostCalculatorScreen> {
  final _won = NumberFormat('#,###');
  final _nameCtrl = TextEditingController(text: '기본 꽃다발');

  final List<_CostLine> _lines = [];
  double _laborCost = 10000; // 인건비
  double _packagingCost = 3000; // 포장비
  double _marginRate = 40; // 마진율 %

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  double get _materialCost =>
      _lines.fold<double>(0, (s, l) => s + l.total);
  double get _totalCost => _materialCost + _laborCost + _packagingCost;
  double get _sellPrice =>
      _marginRate >= 100 ? _totalCost : _totalCost / (1 - _marginRate / 100);
  double get _profit => _sellPrice - _totalCost;

  @override
  Widget build(BuildContext context) {
    final receipts = context.watch<ReceiptProvider>().allReceipts;

    return FnScaffold(
      title: '원가 계산기',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
        children: [
          FnTextField(
            label: '상품명',
            controller: _nameCtrl,
            hint: '예: 프러포즈 꽃다발',
          ),
          const SizedBox(height: FnSpace.x20),

          FnSectionHeader(
            title: '재료',
            action: '추가',
            onAction: () => _pickItem(receipts),
          ),
          const SizedBox(height: FnSpace.x8),
          if (_lines.isEmpty)
            FnCard(
              child: Column(
                children: [
                  const FnEmptyState(
                    message: '재료를 추가해 주세요',
                    subMessage: '매입 기록에서 최근 단가를 자동으로 불러옵니다',
                    icon: Icons.local_florist_outlined,
                  ),
                  const SizedBox(height: FnSpace.x12),
                  FnButton(
                    label: '재료 추가',
                    leadingIcon: Icons.add_rounded,
                    variant: FnButtonVariant.outlined,
                    size: FnButtonSize.medium,
                    onPressed: () => _pickItem(receipts),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_lines.length, (i) => _lineCard(i)),

          const SizedBox(height: FnSpace.x20),
          const FnSectionHeader(title: '부대 비용'),
          const SizedBox(height: FnSpace.x8),
          FnCard(
            child: Column(
              children: [
                _stepperRow('인건비 / 제작비', _laborCost,
                    (v) => setState(() => _laborCost = v)),
                FnDivider(height: 18),
                _stepperRow('포장 · 부자재', _packagingCost,
                    (v) => setState(() => _packagingCost = v)),
              ],
            ),
          ),

          const SizedBox(height: FnSpace.x20),
          const FnSectionHeader(title: '마진율'),
          const SizedBox(height: FnSpace.x8),
          FnCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Text('목표 마진율', style: FnType.body2),
                    const Spacer(),
                    Text('${_marginRate.round()}%',
                        style: FnType.title3
                            .copyWith(color: FnColors.primaryNormal)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: FnColors.primaryNormal,
                    inactiveTrackColor: FnColors.fillNormal,
                    thumbColor: Colors.white,
                    overlayColor:
                        FnColors.primaryNormal.withValues(alpha: 0.12),
                    trackHeight: 5,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 11, elevation: 2),
                  ),
                  child: Slider(
                    value: _marginRate,
                    min: 0,
                    max: 80,
                    divisions: 16,
                    onChanged: (v) => setState(() => _marginRate = v),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('0%',
                        style: FnType.caption2
                            .copyWith(color: FnColors.labelAssistive)),
                    Text('업계 평균 35~45%',
                        style: FnType.caption2
                            .copyWith(color: FnColors.labelAssistive)),
                    Text('80%',
                        style: FnType.caption2
                            .copyWith(color: FnColors.labelAssistive)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: FnSpace.x20),
          _breakdown(),
        ],
      ),
      bottomBar: _resultBar(),
    );
  }

  // ── parts ───────────────────────────────────────────

  Widget _lineCard(int i) {
    final l = _lines[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FnCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.name, style: FnType.headline2),
                  const SizedBox(height: 3),
                  Text('${_won.format(l.unitPrice)}원 × ${l.qty}',
                      style: FnType.caption1
                          .copyWith(color: FnColors.labelAlternative)),
                ],
              ),
            ),
            _qtyBtn(Icons.remove_rounded, () {
              setState(() {
                if (l.qty > 1) {
                  l.qty--;
                } else {
                  _lines.removeAt(i);
                }
              });
            }),
            SizedBox(
              width: 30,
              child: Text('${l.qty}',
                  textAlign: TextAlign.center, style: FnType.headline2),
            ),
            _qtyBtn(Icons.add_rounded, () => setState(() => l.qty++)),
            const SizedBox(width: 6),
            SizedBox(
              width: 72,
              child: Text('${_won.format(l.total)}원',
                  textAlign: TextAlign.right,
                  style: FnType.label1Normal
                      .copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: FnColors.fillNormal,
            borderRadius: FnRadius.br8,
          ),
          child: Icon(icon, size: 17, color: FnColors.labelNormal),
        ),
      );

  Widget _stepperRow(String label, double value, ValueChanged<double> onChange) {
    return Row(
      children: [
        Expanded(child: Text(label, style: FnType.body2)),
        _qtyBtn(Icons.remove_rounded,
            () => onChange((value - 1000).clamp(0, double.infinity))),
        const SizedBox(width: 4),
        SizedBox(
          width: 82,
          child: Text('${_won.format(value)}원',
              textAlign: TextAlign.center, style: FnType.headline2),
        ),
        const SizedBox(width: 4),
        _qtyBtn(Icons.add_rounded, () => onChange(value + 1000)),
      ],
    );
  }

  Widget _breakdown() {
    final data = [
      FnChartDatum(
          label: '재료비', value: _materialCost, color: FnColors.primaryNormal),
      FnChartDatum(label: '인건비', value: _laborCost, color: FnColors.rose70),
      FnChartDatum(
          label: '포장비', value: _packagingCost, color: FnColors.roseTint),
      FnChartDatum(label: '마진', value: _profit, color: FnColors.taxExempt),
    ].where((d) => d.value > 0).toList();

    if (data.isEmpty) return const SizedBox.shrink();

    return FnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('판매가 구성', style: FnType.headline1),
          const SizedBox(height: FnSpace.x16),
          Center(
            child: FnDonutChart(
              data: data,
              size: 150,
              thickness: 26,
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('판매가',
                      style: FnType.caption1
                          .copyWith(color: FnColors.labelAlternative)),
                  Text(_won.format(_sellPrice),
                      style: FnType.heading2),
                ],
              ),
            ),
          ),
          const SizedBox(height: FnSpace.x20),
          FnChartLegend(data: data, showPercent: true),
          FnDivider(height: 20),
          FnKeyValueRow(
              label: '재료비', value: '${_won.format(_materialCost)}원'),
          const SizedBox(height: 8),
          FnKeyValueRow(label: '인건비', value: '${_won.format(_laborCost)}원'),
          const SizedBox(height: 8),
          FnKeyValueRow(
              label: '포장 · 부자재', value: '${_won.format(_packagingCost)}원'),
          FnDivider(height: 16),
          FnKeyValueRow(
              label: '총원가',
              value: '${_won.format(_totalCost)}원',
              emphasize: true),
          const SizedBox(height: 8),
          FnKeyValueRow(
            label: '예상 이익',
            value: '${_won.format(_profit)}원',
            emphasize: true,
            valueColor: FnColors.taxExempt,
          ),
        ],
      ),
    );
  }

  Widget _resultBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: FnColors.lineNeutral)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('권장 판매가',
                        style: FnType.caption1
                            .copyWith(color: FnColors.labelAlternative)),
                    const SizedBox(width: 6),
                    FnBadge(
                      label: '마진 ${_marginRate.round()}%',
                      size: FnBadgeSize.xsmall,
                      color: FnBadgeColor.accent,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('${_won.format(_sellPrice)}원', style: FnType.title2),
              ],
            ),
            const Spacer(),
            FnButton(
              label: '저장',
              size: FnButtonSize.medium,
              onPressed: _lines.isEmpty ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  // ── actions ─────────────────────────────────────────

  void _pickItem(List receipts) {
    final summaries =
        InsightService.allItemSummaries(receipts.cast(), limit: 40);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: FnColors.lineNormal,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text('재료 선택', style: FnType.heading1),
                  const Spacer(),
                  Text('최근 단가 기준',
                      style: FnType.caption1
                          .copyWith(color: FnColors.labelAlternative)),
                ],
              ),
            ),
            Flexible(
              child: summaries.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: FnEmptyState(
                        message: '매입 기록이 없습니다',
                        icon: Icons.inbox_outlined,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: summaries.length,
                      separatorBuilder: (_, __) =>
                          FnDivider(indent: 20, endIndent: 20),
                      itemBuilder: (_, i) {
                        final s = summaries[i];
                        return FnListCell(
                          title: s.name,
                          subtitle: '평균 ${_won.format(s.average)}원',
                          trailing: Text('${_won.format(s.current)}원',
                              style: FnType.headline2),
                          showChevron: false,
                          onTap: () {
                            setState(() {
                              _lines.add(_CostLine(
                                  name: s.name, unitPrice: s.current, qty: 1));
                            });
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _save() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${_nameCtrl.text} 원가 ${_won.format(_totalCost)}원 / 판매가 ${_won.format(_sellPrice)}원 저장'),
      ),
    );
  }
}
