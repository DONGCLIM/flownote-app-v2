import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_button.dart';
import '../../design/fn_card.dart';
import '../../design/fn_list.dart';
import '../../design/fn_scaffold.dart';
import '../../models/receipt_model.dart';
import '../../services/insight_service.dart';
import '../../services/subscription_service.dart';
import '../../services/vendor_tax_service.dart';

/// 정산서 미리보기 → 발송
class SettlementPreviewScreen extends StatefulWidget {
  final DateTime month;
  final List<String> vendors;
  final List<ReceiptModel> receipts;

  const SettlementPreviewScreen({
    super.key,
    required this.month,
    required this.vendors,
    required this.receipts,
  });

  static const historyKey = 'fn_settlement_history';

  @override
  State<SettlementPreviewScreen> createState() =>
      _SettlementPreviewScreenState();
}

class _SettlementPreviewScreenState extends State<SettlementPreviewScreen> {
  final _won = NumberFormat('#,###');
  final _dateFmt = DateFormat('MM.dd');
  bool _sending = false;
  bool _sent = false;

  @override
  Widget build(BuildContext context) {
    final vendors = InsightService.vendorSummaries(widget.receipts);
    var supply = 0.0, vat = 0.0, total = 0.0;
    for (final v in vendors) {
      final s = VendorTaxService.instance.split(v.name, v.total);
      supply += s.supply;
      vat += s.vat;
      total += s.total;
    }

    if (_sent) return _doneView(total);

    return FnScaffold(
      title: '정산서 미리보기',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ── 문서 헤더 ──
          FnCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      Text('매 입 정 산 서', style: FnType.title2),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.month.year}년 ${widget.month.month}월',
                        style: FnType.body2
                            .copyWith(color: FnColors.labelAlternative),
                      ),
                    ],
                  ),
                ),
                const FnDivider(height: 20),
                FnKeyValueRow(
                    label: '작성일',
                    value: DateFormat('yyyy.MM.dd')
                        .format(DateTime.now())),
                const SizedBox(height: 8),
                FnKeyValueRow(
                    label: '매입처 수', value: '${vendors.length}곳'),
                const SizedBox(height: 8),
                FnKeyValueRow(
                    label: '매입 건수', value: '${widget.receipts.length}건'),
              ],
            ),
          ),
          const SizedBox(height: FnSpace.x12),

          // ── 매입처별 명세 ──
          ...vendors.map((v) {
            final s = VendorTaxService.instance.split(v.name, v.total);
            final rows = widget.receipts
                .where((r) => r.storeName == v.name)
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date));

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FnCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(v.name,
                              style: FnType.heading1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 6),
                        v.taxType == TaxType.exempt
                            ? const FnBadge.taxExempt(
                                size: FnBadgeSize.xsmall)
                            : const FnBadge.taxable(size: FnBadgeSize.xsmall),
                        const Spacer(),
                        Text('${rows.length}건',
                            style: FnType.caption1
                                .copyWith(color: FnColors.labelAlternative)),
                      ],
                    ),
                    const FnDivider(height: 16),
                    ...rows.map((r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 46,
                                child: Text(_dateFmt.format(r.date),
                                    style: FnType.caption1.copyWith(
                                        color: FnColors.labelAssistive)),
                              ),
                              Expanded(
                                child: Text(
                                  r.items.isEmpty
                                      ? '매입'
                                      : r.items.length == 1
                                          ? r.items.first.name
                                          : '${r.items.first.name} 외 ${r.items.length - 1}건',
                                  style: FnType.body2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text('${_won.format(r.totalAmount)}원',
                                  style: FnType.label1Normal),
                            ],
                          ),
                        )),
                    const FnDivider(height: 16),
                    FnKeyValueRow(
                        label: '공급가액',
                        value: '${_won.format(s.supply)}원'),
                    const SizedBox(height: 6),
                    FnKeyValueRow(
                      label: '부가세',
                      value: s.exempt ? '면세' : '${_won.format(s.vat)}원',
                      valueColor:
                          s.exempt ? FnColors.taxExempt : FnColors.labelNormal,
                    ),
                    const SizedBox(height: 6),
                    FnKeyValueRow(
                      label: '합계',
                      value: '${_won.format(s.total)}원',
                      emphasize: true,
                    ),
                  ],
                ),
              ),
            );
          }),

          // ── 총계 ──
          FnHighlightCard(
            child: Column(
              children: [
                FnKeyValueRow(
                    label: '공급가액 합계',
                    value: '${_won.format(supply)}원'),
                const SizedBox(height: 8),
                FnKeyValueRow(
                    label: '부가세 합계', value: '${_won.format(vat)}원'),
                const FnDivider(height: 16),
                Row(
                  children: [
                    Text('총 합계', style: FnType.heading1),
                    const Spacer(),
                    Text('${_won.format(total)}원',
                        style: FnType.title2
                            .copyWith(color: FnColors.primaryNormal)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: FnColors.lineNeutral)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: FnButton(
                  label: '수정',
                  variant: FnButtonVariant.outlined,
                  expand: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FnButton(
                  label: '정산서 발송',
                  expand: true,
                  loading: _sending,
                  leadingIcon: Icons.send_rounded,
                  onPressed: _sending ? null : () => _send(total, vendors.length),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _doneView(double total) {
    return FnScaffold(
      title: '발송 완료',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: FnColors.leaf95,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    size: 44, color: FnColors.taxExempt),
              ),
              const SizedBox(height: FnSpace.x24),
              Text('정산서를 발송했습니다', style: FnType.title3),
              const SizedBox(height: 8),
              Text(
                '${widget.month.year}년 ${widget.month.month}월 · ${_won.format(total)}원',
                style:
                    FnType.body2.copyWith(color: FnColors.labelAlternative),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FnSpace.x32),
              FnButton.cta(
                label: '확인',
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send(double total, int vendorCount) async {
    setState(() => _sending = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));

    // 이력 저장
    try {
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList(SettlementPreviewScreen.historyKey) ?? [];
      list.insert(
        0,
        jsonEncode({
          'month': '${widget.month.year}-${widget.month.month}',
          'vendors': widget.vendors,
          'vendorCount': vendorCount,
          'receiptCount': widget.receipts.length,
          'total': total,
          'sentAt': DateTime.now().toIso8601String(),
        }),
      );
      await p.setStringList(SettlementPreviewScreen.historyKey, list.take(50).toList());
    } catch (_) {}

    await SubscriptionService.instance.recordExport();

    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = true;
    });
  }
}
