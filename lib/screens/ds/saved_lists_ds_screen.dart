import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_feedback.dart';
import '../../design/fn_sheet.dart';
import '../../design/fn_shell.dart';
import '../../models/purchase_list_model.dart';
import '../../providers/receipt_provider.dart';
import '../../services/cost_calc.dart';
import '../../services/purchase_list_service.dart';
import '../../theme/fn_ds.dart';
import '../../widgets/fn_inquiry_parts.dart';
import 'insight_ds_screens.dart';
import 'purchase_memo_ds_screen.dart';

/// 저장된 사입 리스트 — 지난 사입을 돌아보고 그대로 다시 만든다. (시안 #187)
///
/// ## 배치 (시안 순서)
///
/// ```
///   [←] 저장된 사입 리스트
///   날짜별 사입 리스트를 확인하고,
///   같은 구성으로 새 리스트를 만들 수 있어요.
///   ┌ 저장된 리스트            3건 ┐  _SavedSummaryCard
///   │ 합계              414,900원 │
///   └ 1회 평균          138,300원 ┘
///   ┌ 2026.07.24 (금)   262,000원 ┐  _SavedListCard (펼친 상태)
///   │ 주말 부케 3건 대비 · 3개 품목 │
///   │ ───────────────────────── │
///   │ 장미(레드)        160,000원 │
///   │ 20단 · 8,000원              │
///   │ …                            │
///   │ [ 이 리스트로 새로 만들기 ]   │
///   └ 삭제                         ┘
///   ┌ 2026.07.17 (금)    42,500원 ⌄┐  (접힌 상태)
/// ```
///
/// 🔴 저장 구조를 새로 만들지 않았다. 사장님 지시(#187): "1단계
///    PurchaseList 와 purchase_list_service.dart 를 그대로 써줘."
///
/// 🔴 사입 메모장 연동은 **다음 작업**이다. 여기서는 예산 검토와만 잇는다.
class SavedListsDsScreen extends StatefulWidget {
  const SavedListsDsScreen({super.key, this.openId, this.lists});

  /// 처음부터 펼쳐 둘 리스트. 예산 검토에서 저장하고 오면 그 리스트다.
  final String? openId;

  /// 미리 넣어 줄 목록. 비워 두면 저장된 것을 읽는다.
  ///
  /// 🔴 테스트에서 Hive 없이 띄우려고 열어 두었다. (다른 화면과 같은 방식)
  final List<PurchaseList>? lists;

  @override
  State<SavedListsDsScreen> createState() => _SavedListsDsScreenState();
}

class _SavedListsDsScreenState extends State<SavedListsDsScreen> {
  /// 펼쳐 둔 리스트 id.
  final Set<String> _open = {};

  /// 화면에서 지운 리스트. 미리 넣어 준 목록일 때만 쓴다(테스트).
  final Set<String> _removed = {};

  @override
  void initState() {
    super.initState();
    final id = widget.openId;
    if (id != null) {
      _open.add(id);
    } else {
      // 방금 저장한 게 없으면 맨 위 하나를 펼쳐 둔다. 다 접혀 있으면
      // 무엇이 들었는지 보려고 한 번 더 눌러야 한다.
      final first = _lists();
      if (first.isNotEmpty) _open.add(first.first.id);
    }
  }

  List<PurchaseList> _lists() {
    final given = widget.lists;
    final all = given ??
        (() {
          try {
            // 🔴 `all` 이 아니라 `saved` 다(#189). 아직 저장을 안 누른
            //    임시 메모장이 목록에 섞이면 안 된다.
            return PurchaseListService.instance.saved;
          } catch (_) {
            return const <PurchaseList>[];
          }
        })();
    final kept = all.where((e) => !_removed.contains(e.id)).toList()
      // 최신순. 서비스도 이미 그렇게 주지만, 넣어 준 목록은 모른다.
      ..sort((a, b) => b.date.compareTo(a.date));
    return kept;
  }

  Future<void> _delete(PurchaseList e) async {
    final ok = await showFnAlert(
      context,
      title: '이 사입 리스트를 지울까요?',
      message: '${_dateLabel(e.date)} · ${e.purpose.isEmpty ? '사입 리스트' : e.purpose}\n'
          '지우면 되돌릴 수 없어요.',
      confirmLabel: '삭제',
      cancelLabel: '취소',
      destructive: true,
    );
    if (!ok || !mounted) return;

    if (widget.lists != null) {
      setState(() => _removed.add(e.id));
    } else {
      await PurchaseListService.instance.remove(e.id);
      if (!mounted) return;
      setState(() {});
    }
    showFnToast(context, '사입 리스트를 지웠어요.');
  }

  /// 같은 품목으로 새 리스트를 만들어 예산 검토를 연다.
  ///
  /// 🔴 날짜는 **내일**, 단가는 **최신 영수증 기준**으로 다시 잡는다.
  ///    사장님 지시(#187). 두 달 전 단가를 그대로 들고 가면 시장에서
  ///    돈이 모자란다.
  void _reuse(PurchaseList src) {
    final copy = PurchaseListService.instance.duplicate(src);
    final book = _book();

    for (final it in copy.items) {
      final e = book.lookup(it.name);
      if (e == null) continue;
      // 단위가 섞인 품목은 단가를 덮어쓰지 않는다. 열 배 틀릴 수 있다.
      if (e.mixedUnit) continue;
      it
        ..unitPrice = e.unitPrice
        ..unit = e.unit
        ..basisDate = e.date;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GuideBudgetDsScreen(initial: copy)),
    );
  }

  /// 이 리스트의 메모장을 연다. (#189)
  ///
  /// 🔴 `listId` 를 꼭 넘긴다. 안 넘기면 **새 메모장(임시 작성분)** 이
  ///    열려서, 저장된 리스트의 메모가 안 보인다.
  Future<void> _openMemo(PurchaseList e) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseMemoDsScreen(listId: e.id),
      ),
    );
    // 고치고 돌아오면 줄 수가 달라져 있다.
    if (mounted) setState(() {});
  }

  PriceBook _book() {
    try {
      return PriceBook.fromReceipts(
          context.read<ReceiptProvider>().allReceipts);
    } catch (_) {
      return PriceBook.empty;
    }
  }

  static const _dow = ['월', '화', '수', '목', '금', '토', '일'];

  static String _dateLabel(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.'
      '${d.day.toString().padLeft(2, '0')} (${_dow[d.weekday - 1]})';

  @override
  Widget build(BuildContext context) {
    // 저장이 바뀌면 다시 그린다. 테스트에서는 넣어 준 목록을 쓴다.
    if (widget.lists == null) {
      try {
        context.watch<ReceiptProvider>();
      } catch (_) {/* Provider 없는 자리 */}
    }
    final lists = _lists();
    final summary = PurchaseListService.summarize(lists);

    return FnShell(
      navTitle: '저장된 사입 리스트',
      bg: FnDs.bg,
      onBack: () => Navigator.of(context).pop(),
      child: ColoredBox(
        color: FnDs.bg,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              FnDs.pagePad, 14, FnDs.pagePad, FnDs.gapXl),
          children: [
            const Text(
              '날짜별 사입 리스트를 확인하고,\n같은 구성으로 새 리스트를 만들 수 있어요.',
              style: FnDs.tsSub,
            ),
            const SizedBox(height: FnDs.gapM),
            if (lists.isEmpty) ...[
              const _SavedEmpty(),
            ] else ...[
              _SavedSummaryCard(summary: summary),
              for (final e in lists) ...[
                const SizedBox(height: FnDs.gapS),
                _SavedListCard(
                  list: e,
                  dateLabel: _dateLabel(e.date),
                  expanded: _open.contains(e.id),
                  onToggle: () => setState(() {
                    if (!_open.remove(e.id)) _open.add(e.id);
                  }),
                  onReuse: () => _reuse(e),
                  onDelete: () => unawaited(_delete(e)),
                  onMemo: () => _openMemo(e),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 맨 위 요약 — 건수 / 합계 / 1회 평균.
class _SavedSummaryCard extends StatelessWidget {
  const _SavedSummaryCard({required this.summary});

  final PurchaseSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: FnDs.cardDeco(),
      child: Column(
        children: [
          _row('저장된 리스트', '${summary.count}건'),
          const SizedBox(height: FnDs.gapS),
          _row('합계', CostCalc.won(summary.total)),
          const SizedBox(height: FnDs.gapS),
          _row('1회 평균', CostCalc.won(summary.average)),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.fontS,
              fontWeight: FontWeight.w600,
              color: FnDs.body,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.fontM,
              fontWeight: FontWeight.w700,
              color: FnDs.title,
            ),
          ),
        ],
      );
}

/// 리스트 한 장. 접었다 펼 수 있다.
class _SavedListCard extends StatelessWidget {
  const _SavedListCard({
    required this.list,
    required this.dateLabel,
    required this.expanded,
    required this.onToggle,
    required this.onReuse,
    required this.onDelete,
    required this.onMemo,
  });

  final PurchaseList list;
  final String dateLabel;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onReuse;
  final VoidCallback onDelete;

  /// 이 리스트의 메모장을 연다. (#189)
  final VoidCallback onMemo;

  /// 펼쳤을 때 보여 줄 메모 미리보기. 글이 있는 줄만 **세 줄까지**.
  ///
  /// 🔴 전부 보여 주지 않는 이유: 카드가 길어지면 아래 리스트가 안 보인다.
  ///    자세히 보려면 '메모장 열기' 를 누른다. (사장님 지시 #189)
  List<MemoLine> get _memoPreview {
    final lines = MemoText.parse(list.memo)
        .where((e) => e.text.trim().isNotEmpty)
        .toList();
    return lines.length <= 3 ? lines : lines.sublist(0, 3);
  }

  /// 둘째 줄. `주말 부케 3건 대비 · 3개 품목` / `메모 리스트 · 2줄`
  String get _sub {
    if (list.isMemoOnly) {
      // 🔴 품목이 없으면 금액을 말할 수 없다. 메모가 몇 줄인지만 알린다.
      return '메모 리스트 · ${list.memoLineCount}줄';
    }
    final purpose = list.purpose.trim();
    final items = '${list.items.length}개 품목';
    return purpose.isEmpty ? items : '$purpose · $items';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: FnDs.cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          fontFamily: FnDs.font,
                          fontSize: FnDs.fontM,
                          fontWeight: FontWeight.w700,
                          color: FnDs.title,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(_sub, style: FnDs.tsSub),
                    ],
                  ),
                ),
                const SizedBox(width: FnDs.gapXs),
                // 메모 리스트는 금액 칸을 비운다. (사장님 지시 #187)
                if (!list.isMemoOnly)
                  Text(
                    CostCalc.won(list.plannedTotal),
                    style: const TextStyle(
                      fontFamily: FnDs.font,
                      fontSize: FnDs.fontM,
                      fontWeight: FontWeight.w700,
                      color: FnDs.title,
                    ),
                  ),
                if (!expanded) ...[
                  const SizedBox(width: FnDs.gap2xs),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: FnDs.chevron),
                ],
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: FnDs.gapS),
            const Divider(height: 1, thickness: 1, color: FnDs.hair),
            const SizedBox(height: FnDs.gapS),
            if (list.isMemoOnly) ...[
              // 🔴 메모로 만든 리스트. 품목 대신 메모 줄을 보여 준다. (#189)
              if (_memoPreview.isEmpty)
                const Text('적어 둔 품목이 없어요. 메모만 남긴 리스트예요.',
                    style: FnDs.tsSub)
              else
                for (var i = 0; i < _memoPreview.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  _SavedMemoRow(line: _memoPreview[i]),
                ],
              if (list.memoLineCount > _memoPreview.length) ...[
                const SizedBox(height: 6),
                Text(
                  '외 ${list.memoLineCount - _memoPreview.length}줄',
                  style: FnDs.tsSub,
                ),
              ],
              const SizedBox(height: FnDs.gapM),
              FnOutlineButton(label: '메모장 열기', onTap: onMemo),
            ] else ...[
              for (var i = 0; i < list.items.length; i++) ...[
                if (i > 0) const SizedBox(height: FnDs.gapS),
                _SavedItemRow(item: list.items[i]),
              ],
              const SizedBox(height: FnDs.gapM),
              FnOutlineButton(label: '이 리스트로 새로 만들기', onTap: onReuse),
            ],
            const SizedBox(height: FnDs.gapXs),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDelete,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 24),
                  child: Text(
                    '삭제',
                    style: TextStyle(
                      fontFamily: FnDs.font,
                      fontSize: FnDs.fontS,
                      fontWeight: FontWeight.w600,
                      color: FnDs.sub,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 품목 한 줄 — 이름 / 수량 · 단가 / 금액.
class _SavedItemRow extends StatelessWidget {
  const _SavedItemRow({required this.item});

  final PurchaseItem item;

  @override
  Widget build(BuildContext context) {
    final unit = item.unit.trim().isEmpty ? '단' : item.unit.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontFamily: FnDs.font,
                  fontSize: FnDs.fontS,
                  fontWeight: FontWeight.w700,
                  color: FnDs.title,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '${CostCalc.comma(item.qty)}$unit · '
                '${CostCalc.won(item.unitPrice)}',
                style: FnDs.tsSub,
              ),
            ],
          ),
        ),
        const SizedBox(width: FnDs.gapXs),
        Text(
          CostCalc.won(item.plannedAmount),
          style: const TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.fontS,
            fontWeight: FontWeight.w700,
            color: FnDs.title,
          ),
        ),
      ],
    );
  }
}

/// 펼친 카드 안의 메모 한 줄. 산 줄은 가운데줄을 긋는다. (#189)
class _SavedMemoRow extends StatelessWidget {
  const _SavedMemoRow({required this.line});

  final MemoLine line;

  @override
  Widget build(BuildContext context) {
    final done = line.checked;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(
            done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 15,
            color: done ? FnDs.coral : FnDs.line,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            line.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.fontS,
              color: done ? FnDs.sub : FnDs.body,
              decoration: done ? TextDecoration.lineThrough : null,
              decorationColor: FnDs.sub,
            ),
          ),
        ),
      ],
    );
  }
}

/// 아직 아무것도 없을 때. (#188 단순하게)
///
/// 🔴 사장님 지시(#188): 문구 한 줄, 버튼 **하나만**, 그 아래 작은 글씨 링크.
///    예전에는 안내 카드와 버튼 글자가 서로 다른 말을 해서 헷갈렸다.
class _SavedEmpty extends StatelessWidget {
  const _SavedEmpty();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: FnDs.cardPad, vertical: 36),
          decoration: FnDs.cardDeco(),
          child: const Text(
            '아직 저장한 사입 리스트가 없어요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.fontM,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: FnDs.body,
            ),
          ),
        ),
        const SizedBox(height: FnDs.gapM),
        FnPrimaryButton(
          label: '새 사입 리스트 만들기',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const GuideBudgetDsScreen()),
          ),
        ),
        const SizedBox(height: FnDs.gapS),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PurchaseMemoDsScreen()),
          ),
          child: const SizedBox(
            height: 28,
            child: Center(
              child: Text(
                '메모로 빠르게 적기',
                style: TextStyle(
                  fontFamily: FnDs.font,
                  fontSize: FnDs.fontS,
                  fontWeight: FontWeight.w600,
                  color: FnDs.sub,
                  decoration: TextDecoration.underline,
                  decorationColor: FnDs.sub,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
