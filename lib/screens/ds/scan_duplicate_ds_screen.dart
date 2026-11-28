import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_card.dart';
import '../../design/fn_controls_ds.dart';
import '../../services/receipt_duplicate_service.dart';
import 'fn_data.dart';

/// 중복 영수증 확인 화면 (#118)
///
/// ## 왜 만들었는가
///
/// 지금까지 `addReceipt` 는 그냥 `_box.put(id, receipt)` 였다. id 는
/// 저장할 때마다 새 UUID 라, **같은 가게의 같은 영수증을 두 번 찍으면
/// 두 건이 그대로 쌓였다.** 매입 합계가 부풀고 정산서가 틀어진다.
///
/// ## 어떻게 판단하는가
///
/// 사진 해시도, OCR 원문 해시도 쓰지 않는다. 이유는
/// `ReceiptDuplicateService` 주석에 적어 두었다. 사람이 눈으로 볼 때
/// 쓰는 값 — **매입처 · 날짜 · 금액 · 품목** — 으로 지문을 만들어 견준다.
///
/// - `확실` : 넷이 전부 같다 → 기본으로 **저장 제외**해 둔다.
/// - `의심` : 매입처 · 날짜가 같고 금액이나 품목 중 하나가 같다
///            → 기본으로 **저장**한다. 같은 날 두 번 사는 일이 실제로 있다.
///
/// 🔴 어느 쪽도 저장을 **막지는** 않는다. 사장님이 고르신다.
class ScanDuplicateDsScreen extends StatefulWidget {
  const ScanDuplicateDsScreen({
    super.key,
    required this.hits,
    required this.totalCount,
    required this.onContinue,
  });

  /// 찾아낸 중복들
  final List<DuplicateHit> hits;

  /// 이번에 저장하려던 전체 건수 (중복이 아닌 것 포함)
  final int totalCount;

  /// 사장님이 고른 **제외할 draft id 목록**을 받아 저장을 이어간다.
  final void Function(Set<String> skipIds) onContinue;

  @override
  State<ScanDuplicateDsScreen> createState() => _ScanDuplicateDsScreenState();
}

class _ScanDuplicateDsScreenState extends State<ScanDuplicateDsScreen> {
  late Set<String> _skip =
      ReceiptDuplicateService.defaultSkipIds(widget.hits);

  int get _exactCount => widget.hits.where((h) => h.isExact).length;
  int get _saveCount => widget.totalCount - _skip.length;

  void _toggle(String id) => setState(() {
        if (!_skip.remove(id)) _skip.add(id);
      });

  @override
  Widget build(BuildContext context) {
    final n = widget.hits.length;
    return FnShell(
      navTitle: '중복 영수증 확인',
      onBack: () => Navigator.pop(context),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _banner(n),
                  const SizedBox(height: 18),
                  Text(
                    '중복 의심 $n건',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: FnColors.labelNormal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < n; i++) ...[
                    _hitCard(widget.hits[i]),
                    if (i < n - 1) const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    '체크를 풀면 그 영수증은 저장하지 않아요.\n'
                    '같은 날 같은 가게에서 두 번 사셨다면 그대로 두시면 돼요.',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12.5,
                      height: 1.5,
                      color: FnColors.labelAlternative,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FnDsButton(
              label: _saveCount > 0 ? '$_saveCount건 저장하기' : '저장할 영수증이 없어요',
              size: FnDsButtonSize.large,
              expand: true,
              disabled: _saveCount <= 0,
              onPressed:
                  _saveCount <= 0 ? null : () => widget.onContinue(_skip),
            ),
          ),
        ],
      ),
    );
  }

  /// 상단 경고 배너
  Widget _banner(int n) {
    final exact = _exactCount;
    return FnCard(
      bordered: true,
      color: FnColors.statusCautionaryBg,
      borderColor: FnColors.statusCautionary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.copy_all_rounded,
              size: 22, color: FnColors.statusCautionaryStrong),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exact > 0
                      ? '이미 넣은 영수증 같아요'
                      : '같은 날 같은 매입처가 있어요',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: FnColors.statusCautionaryStrong,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  exact > 0
                      ? '$n건 중 $exact건은 매입처·날짜·금액·품목이 모두 같아요.\n'
                          '중복 저장하면 매입 합계가 부풀어요.'
                      : '$n건이 기존 영수증과 일부 같아요. 확인해 주세요.',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12.5,
                    height: 1.5,
                    color: FnColors.labelNeutral,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 중복 한 건 카드 — 위: 이번에 찍은 것 / 아래: 겹친 상대
  Widget _hitCard(DuplicateHit h) {
    final d = h.draft;
    final on = !_skip.contains(d.id);
    final store = d.storeName.trim().isEmpty ? '매입처 미확인' : d.storeName.trim();

    return FnCard(
      bordered: true,
      radius: 14,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      onTap: () => _toggle(d.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Check(on: on, onTap: () => _toggle(d.id)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            store,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: on
                                  ? FnColors.labelNormal
                                  : FnColors.labelAssistive,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _LevelTag(exact: h.isExact),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_ymd(d.date)} · 품목 ${d.items.length}건',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12.5,
                        color: FnColors.labelAlternative,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                FnDemo.won(d.total),
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  decoration: on ? null : TextDecoration.lineThrough,
                  color: on ? FnColors.labelNormal : FnColors.labelAssistive,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: FnColors.lineNeutral),
          ),
          _against(h),
        ],
      ),
    );
  }

  /// 겹친 상대 한 줄
  Widget _against(DuplicateHit h) {
    final saved = h.saved;
    final sib = h.sibling;
    final name = saved != null
        ? saved.storeName
        : (sib!.storeName.trim().isEmpty ? '매입처 미확인' : sib.storeName.trim());
    final date = saved != null ? saved.date : sib!.date;
    final amount = saved != null ? saved.totalAmount : sib!.total;
    final count = saved != null ? saved.items.length : sib!.items.length;

    return Row(
      children: [
        const Icon(Icons.subdirectory_arrow_right_rounded,
            size: 16, color: FnColors.labelAssistive),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                h.againstLabel,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: FnColors.labelAssistive,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$name · ${_ymd(date)} · 품목 $count건',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12.5,
                  color: FnColors.labelAlternative,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          FnDemo.won(amount),
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: FnColors.labelAlternative,
          ),
        ),
      ],
    );
  }

  static String _ymd(DateTime d) => '${d.year}.'
      '${d.month.toString().padLeft(2, '0')}.'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 저장 여부 체크박스
class _Check extends StatelessWidget {
  const _Check({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: on,
      label: '저장',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: on ? FnColors.rose50 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: on ? FnColors.rose50 : FnColors.lineNormal,
              width: 1.4,
            ),
          ),
          child: on
              ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// `확실` / `의심` 배지
class _LevelTag extends StatelessWidget {
  const _LevelTag({required this.exact});

  final bool exact;

  @override
  Widget build(BuildContext context) {
    final bg = exact ? FnColors.statusNegativeBg : FnColors.statusCautionaryBg;
    final fg =
        exact ? FnColors.statusNegativeStrong : FnColors.statusCautionaryStrong;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        exact ? '중복 확실' : '중복 의심',
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}
