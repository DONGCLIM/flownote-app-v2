import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_card.dart';
import '../../design/fn_list.dart';
import '../../design/fn_scaffold.dart';
import 'settlement_preview_screen.dart';

/// 정산서 발송 이력
class SettlementHistoryScreen extends StatefulWidget {
  const SettlementHistoryScreen({super.key});

  @override
  State<SettlementHistoryScreen> createState() =>
      _SettlementHistoryScreenState();
}

class _SettlementHistoryScreenState extends State<SettlementHistoryScreen> {
  final _won = NumberFormat('#,###');
  final _fmt = DateFormat('yyyy.MM.dd HH:mm');

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final out = <Map<String, dynamic>>[];
    try {
      final p = await SharedPreferences.getInstance();
      for (final s
          in p.getStringList(SettlementPreviewScreen.historyKey) ?? []) {
        try {
          out.add(jsonDecode(s) as Map<String, dynamic>);
        } catch (_) {}
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _items = out;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FnScaffold(
      title: '발송 이력',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const FnEmptyState(
                  message: '발송한 정산서가 없습니다',
                  subMessage: '정산서를 발행하면 이곳에 기록됩니다',
                  icon: Icons.history_rounded,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  itemCount: _items.length,
                  itemBuilder: (_, i) => _tile(_items[i]),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> m) {
    final parts = (m['month'] as String? ?? '-').split('-');
    final vendors = (m['vendors'] as List?)?.cast<String>() ?? const [];
    DateTime? sentAt;
    try {
      sentAt = DateTime.parse(m['sentAt'] as String);
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FnCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: FnColors.rose95,
                    borderRadius: FnRadius.br12,
                  ),
                  child: const Icon(Icons.description_outlined,
                      size: 20, color: FnColors.primaryNormal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parts.length >= 2
                            ? '${parts[0]}년 ${parts[1]}월 정산서'
                            : '정산서',
                        style: FnType.heading2,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        sentAt != null ? _fmt.format(sentAt) : '',
                        style: FnType.caption1
                            .copyWith(color: FnColors.labelAlternative),
                      ),
                    ],
                  ),
                ),
                const FnBadge(
                  label: '발송완료',
                  size: FnBadgeSize.xsmall,
                  color: FnBadgeColor.positive,
                ),
              ],
            ),
            const FnDivider(height: 16),
            FnKeyValueRow(
              label: '매입처',
              value: vendors.isEmpty
                  ? '${m['vendorCount'] ?? 0}곳'
                  : vendors.length == 1
                      ? vendors.first
                      : '${vendors.first} 외 ${vendors.length - 1}곳',
            ),
            const SizedBox(height: 6),
            FnKeyValueRow(
                label: '매입 건수', value: '${m['receiptCount'] ?? 0}건'),
            const SizedBox(height: 6),
            FnKeyValueRow(
              label: '총 합계',
              value: '${_won.format((m['total'] as num?) ?? 0)}원',
              emphasize: true,
            ),
          ],
        ),
      ),
    );
  }
}
