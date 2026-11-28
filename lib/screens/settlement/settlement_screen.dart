import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_button.dart';
import '../../design/fn_card.dart';
import '../../design/fn_list.dart';
import '../../design/fn_scaffold.dart';
import '../../models/receipt_model.dart';
import '../../providers/receipt_provider.dart';
import '../../services/insight_service.dart';
import '../../services/subscription_service.dart';
import '../../services/vendor_tax_service.dart';
import '../paywall_screen.dart';
import 'settlement_preview_screen.dart';
import 'settlement_history_screen.dart';

/// 정산서 발행 — 월 선택 후 매입처별 정산서 생성
class SettlementScreen extends StatefulWidget {
  const SettlementScreen({super.key});

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen> {
  final _won = NumberFormat('#,###');
  DateTime? _month;
  final Set<String> _selectedVendors = {};

  @override
  Widget build(BuildContext context) {
    final receipts = context.watch<ReceiptProvider>().allReceipts;
    final months = InsightService.monthlyStats(receipts).reversed.toList();

    if (_month == null && months.isNotEmpty) {
      _month = DateTime(months.first.year, months.first.month);
    }

    final monthReceipts = _month == null
        ? <ReceiptModel>[]
        : receipts
            .where((r) =>
                r.date.year == _month!.year && r.date.month == _month!.month)
            .toList();

    final vendors = InsightService.vendorSummaries(monthReceipts);
    final selected =
        vendors.where((v) => _selectedVendors.contains(v.name)).toList();
    final selTotal = selected.fold<double>(0, (s, v) => s + v.total);

    return FnScaffold(
      title: '정산서 발행',
      actions: [
        FnIconButton(
          icon: Icons.history_rounded,
          tooltip: '발송 이력',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettlementHistoryScreen()),
          ),
        ),
      ],
      body: months.isEmpty
          ? const FnEmptyState(
              message: '정산할 매입 내역이 없습니다',
              subMessage: '영수증을 스캔하면 정산서를 만들 수 있어요',
              icon: Icons.description_outlined,
            )
          : Column(
              children: [
                // ── 월 선택 ──
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: Colors.white,
                  child: SizedBox(
                    height: 66,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: months.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final m = months[i];
                        final sel = _month != null &&
                            m.year == _month!.year &&
                            m.month == _month!.month;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _month = DateTime(m.year, m.month);
                            _selectedVendors.clear();
                          }),
                          child: AnimatedContainer(
                            duration: FnDuration.fast,
                            width: 86,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: sel
                                  ? FnColors.primaryNormal
                                  : FnColors.fillNormal,
                              borderRadius: FnRadius.br12,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${m.year}',
                                    style: FnType.caption2.copyWith(
                                      color: sel
                                          ? Colors.white70
                                          : FnColors.labelAssistive,
                                    )),
                                Text('${m.month}월',
                                    style: FnType.headline1.copyWith(
                                      color: sel
                                          ? Colors.white
                                          : FnColors.labelNormal,
                                    )),
                                Text('${m.count}건',
                                    style: FnType.caption2.copyWith(
                                      color: sel
                                          ? Colors.white70
                                          : FnColors.labelAssistive,
                                    )),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const FnDivider(),

                Expanded(
                  child: vendors.isEmpty
                      ? const FnEmptyState(
                          message: '이 달의 매입처가 없습니다',
                          icon: Icons.storefront_outlined,
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          children: [
                            Row(
                              children: [
                                Text('매입처 선택', style: FnType.heading1),
                                const Spacer(),
                                FnTextButton(
                                  label: _selectedVendors.length ==
                                          vendors.length
                                      ? '전체 해제'
                                      : '전체 선택',
                                  onPressed: () => setState(() {
                                    if (_selectedVendors.length ==
                                        vendors.length) {
                                      _selectedVendors.clear();
                                    } else {
                                      _selectedVendors
                                        ..clear()
                                        ..addAll(vendors.map((v) => v.name));
                                    }
                                  }),
                                ),
                              ],
                            ),
                            const SizedBox(height: FnSpace.x10),
                            ...vendors.map((v) {
                              final split = VendorTaxService.instance
                                  .split(v.name, v.total);
                              final checked =
                                  _selectedVendors.contains(v.name);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: FnCard(
                                  bordered: checked,
                                  borderColor: FnColors.primaryNormal,
                                  onTap: () => setState(() {
                                    if (checked) {
                                      _selectedVendors.remove(v.name);
                                    } else {
                                      _selectedVendors.add(v.name);
                                    }
                                  }),
                                  child: Row(
                                    children: [
                                      FnCheckbox(
                                        value: checked,
                                        onChanged: (b) => setState(() {
                                          if (b == true) {
                                            _selectedVendors.add(v.name);
                                          } else {
                                            _selectedVendors.remove(v.name);
                                          }
                                        }),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(v.name,
                                                      style: FnType.heading2,
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                ),
                                                const SizedBox(width: 6),
                                                v.taxType == TaxType.exempt
                                                    ? const FnBadge.taxExempt(
                                                        size: FnBadgeSize
                                                            .xsmall)
                                                    : const FnBadge.taxable(
                                                        size: FnBadgeSize
                                                            .xsmall),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${v.count}건 · 공급가 ${_won.format(split.supply)}원'
                                              '${split.vat > 0 ? ' · 부가세 ${_won.format(split.vat)}원' : ''}',
                                              style: FnType.caption1.copyWith(
                                                  color: FnColors
                                                      .labelAlternative),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('${_won.format(v.total)}원',
                                          style: FnType.headline1),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                ),
              ],
            ),
      bottomBar: vendors.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: FnColors.lineNeutral)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('${selected.length}개 매입처 선택',
                            style: FnType.body2
                                .copyWith(color: FnColors.labelAlternative)),
                        const Spacer(),
                        Text('${_won.format(selTotal)}원',
                            style: FnType.title3),
                      ],
                    ),
                    const SizedBox(height: FnSpace.x12),
                    FnButton.cta(
                      label: '정산서 미리보기',
                      onPressed: selected.isEmpty
                          ? null
                          : () => _preview(monthReceipts),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _preview(List<ReceiptModel> monthReceipts) {
    final sub = SubscriptionService.instance;
    if (!sub.canExport) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const PaywallScreen(
            reason: '무료 플랜의 정산서 발송 3회를 모두 사용했습니다',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettlementPreviewScreen(
          month: _month!,
          vendors: _selectedVendors.toList(),
          receipts: monthReceipts
              .where((r) => _selectedVendors.contains(r.storeName))
              .toList(),
        ),
      ),
    );
  }
}
