import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_card.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_badge_ds.dart';
import '../../design/fn_controls_ds.dart';
import '../../design/fn_feedback.dart';
import '../../providers/receipt_provider.dart';
import 'fn_data.dart';
import 'settle_data_live.dart';
import 'settle_preview_ds_screen.dart';

/// 시안 `AppH2Mvp` → `screen === 'history'` 1:1 포팅.
///
/// ```js
/// const history = [
///   { vendorId:'v1', vendor:'대한꽃도매', period:'2026.07', saved:'07.24', status:'전송완료', color:'positive' },
///   { vendorId:'v2', vendor:'화람원예',   period:'2026.06', saved:'-',     status:'미전송',   color:'negative' },
///   { vendorId:'v3', vendor:'그린플러스', period:'2026.06', saved:'-',     status:'미전송',   color:'negative' },
/// ];
/// Shell({ navTitle:'정산서 내보내기 이력', onBack, tabs, activeTab:'settle' })
///   div padding16 column gap10
///     select  width100% pad'10px 12px' r10 border 1px  → '전체 연월' | period
///     Card bordered (click → preview)
///       row spaceBetween gap8
///         left flex1: row spaceBetween mb6 [vendor 17/600] [ContentBadge color 14 status]
///                     13 alt  `${period} · 전송일 ${saved}`
///         ChevronRight 16 label-assistive
///     filtered.length === 0 → '해당 연월의 내역이 없어요'
///     Button large outlined '구매내역으로 돌아가기'
/// ```
class SettleHistoryDsScreen extends StatefulWidget {
  const SettleHistoryDsScreen({super.key});

  @override
  State<SettleHistoryDsScreen> createState() => _SettleHistoryDsScreenState();
}

/// 시안 `history[]` 한 줄에 대응하는 **실제** 이력 행.
///
/// 시안은 데모 배열이었으나, 여기서는 `SettleHistoryStore` 에 저장된
/// 실제 내보내기 이력(`SettleHistoryEntry`)을 그대로 사용한다.
class _HistoryRow {
  const _HistoryRow(this.entry);

  final SettleHistoryEntry entry;

  /// 시안 `vendor` — 거래처 1곳이면 이름, 여러 곳이면 `'A 외 2곳'`
  String get vendor => entry.vendorLabel;

  /// 시안 `period` — `'2026.07'`
  String get period => entry.period;

  /// 시안 `saved` — `'07.24'`
  String get saved => entry.savedLabel;

  /// 시안은 `'전송완료' | '미전송'` 두 상태였다. 실제 이력은 **저장된 것 자체가
  /// 내보내기를 완료한 기록**이므로 항상 '전송완료' 이고,
  /// 대신 내보낸 방식(Excel/PDF)을 함께 보여준다.
  String get status => entry.method == null ? '전송완료' : '${entry.method} 전송완료';

  FnBadgeColor get color => FnBadgeColor.positive;

  /// 이 이력이 다룬 거래처명 목록 (미리보기 복원에 사용)
  List<String> get vendors => entry.vendors;

  /// 이력에 기록된 연도 (`'2026'`)
  String? get year {
    final parts = entry.month.split('-');
    return parts.isEmpty ? null : parts.first;
  }
}

class _SettleHistoryDsScreenState extends State<SettleHistoryDsScreen> {
  String _period = '전체';

  /// 실제 저장소에서 읽어온 이력
  List<_HistoryRow> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// `SettleHistoryStore` (레거시와 동일한 SharedPreferences 키) 에서 이력을 읽는다.
  Future<void> _load() async {
    final list = await SettleHistoryStore.load();
    if (!mounted) return;
    setState(() {
      _rows = list.map(_HistoryRow.new).toList();
      _loading = false;
    });
  }

  List<String> get _periods => ['전체', ..._rows.map((h) => h.period).toSet()];

  List<_HistoryRow> get _filtered => _period == '전체'
      ? _rows
      : _rows.where((h) => h.period == _period).toList();

  /// 이력 행을 눌렀을 때 그 시점의 정산서를 **실제 영수증으로 재구성**해서 보여준다.
  ///
  /// 이력에는 거래처명과 연월만 들어 있으므로, 현재 보유한 영수증에서
  /// 같은 거래처·같은 연도를 다시 집계한다. 영수증이 이미 삭제된 경우에는
  /// 복원할 수 없으므로 안내만 띄운다.
  void _goPreview(_HistoryRow h) {
    final all = context.read<ReceiptProvider>().allReceipts;
    final live = SettleLiveData.build(all, year: h.year);

    FnVendor? v;
    for (final name in h.vendors) {
      final hit = live.vendors.where((x) => x.name == name);
      if (hit.isNotEmpty) {
        v = hit.first;
        break;
      }
    }

    if (v == null) {
      showFnToast(
        context,
        '이 이력의 영수증을 찾을 수 없어요.\n영수증이 삭제되었을 수 있습니다.',
        type: FnToastType.warning,
      );
      return;
    }

    final months =
        FnSettleData.months.where((m) => (v!.months[m] ?? 0) > 0).toList();

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettlePreviewDsScreen(
        vendor: v!,
        selectedMonths: months,
        year: h.year,
        receipts: live.receiptsOf(v.name, months),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return FnShell(
      navTitle: '정산서 내보내기 이력',
      onBack: () => Navigator.of(context).pop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: FnColors.backgroundNormal,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: FnColors.lineNeutral, width: 1),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _period,
                  isExpanded: true,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    color: FnColors.labelNormal,
                  ),
                  items: [
                    for (final p in _periods)
                      DropdownMenuItem(
                        value: p,
                        child: Text(p == '전체' ? '전체 연월' : p),
                      ),
                  ],
                  onChanged: (v) => setState(() => _period = v ?? '전체'),
                ),
              ),
            ),
            for (final h in filtered) ...[
              const SizedBox(height: 10),
              FnCard(
                bordered: true,
                onTap: () => _goPreview(h),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  h.vendor,
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: FnColors.labelNormal,
                                  ),
                                ),
                              ),
                              FnBadge(h.status, color: h.color),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${h.period} · 전송일 ${h.saved}'
                            ' · 영수증 ${h.entry.receiptCount}건',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 13,
                              color: FnColors.labelAlternative,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded,
                        size: 16, color: FnColors.labelAssistive),
                  ],
                ),
              ),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: FnSpinner()),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  // 이력이 아예 없는 경우와, 필터로 걸러져 없는 경우를 구분한다.
                  _rows.isEmpty
                      ? '아직 내보낸 정산서가 없어요.\n구매내역에서 정산서를 만들어 보세요.'
                      : '해당 연월의 내역이 없어요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    height: 1.6,
                    color: FnColors.labelAssistive,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            FnDsButton(
              label: '구매내역으로 돌아가기',
              expand: true,
              variant: FnDsButtonVariant.outlined,
              color: FnDsButtonColor.neutral,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
