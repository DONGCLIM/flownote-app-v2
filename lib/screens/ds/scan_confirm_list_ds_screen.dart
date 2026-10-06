import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_card.dart';
import '../../design/fn_controls_ds.dart';
import '../scan/scan_draft.dart';
import 'fn_data.dart';

/// 저장 직전 **마지막 확인** 화면 — 시안 `10. 인식 결과 확인 목록`
///
/// ## 왜 필요한가 (#113)
///
/// 여러 장을 스캔하면 한 장씩 넘겨보며 검토(`ScanReviewDsScreen`)한 뒤
/// 곧바로 저장 다이얼로그가 떴다. 사장님 표현으로는
/// "내가 했던 것에 대해서 마지막으로 한번 더 확인" 할 자리가 없었다.
/// 4장을 찍으면 4번째를 확인하는 순간 1~3번째가 어떻게 됐는지
/// 다시 볼 방법이 없었던 것이다.
///
/// 그래서 검토를 마치면 이 목록을 한 번 보여준다.
/// 항목을 누르면 그 영수증으로 되돌아가 다시 고칠 수 있다.
///
/// ## 시안 매핑
///
/// ```
/// Shell { navTitle: '인식 결과 확인' }
///   Card bordered
///     row space-between  '인식된 영수증' / '4장'
///     divider
///     row space-between  '총 합계' / rose ₩583,000
///   div 13/700 '영수증 목록 4건'
///   Card × N  { thumb 44x56, 상호 / 'YYYY.MM.DD · 품목 N건', 금액, chevron }
///   Button large fill '모두 저장하기'
/// ```
///
/// 한 장만 스캔했을 때는 띄우지 않는다(누를 것이 하나뿐이라 방해만 된다).
class ScanConfirmListDsScreen extends StatelessWidget {
  const ScanConfirmListDsScreen({
    super.key,
    required this.drafts,
    required this.onSaveAll,
    this.onEdit,
  });

  /// 저장 대상 (제외된 건은 호출부에서 걸러 넣는다)
  final List<ScanDraft> drafts;

  /// '모두 저장하기'
  final VoidCallback onSaveAll;

  /// 항목을 눌렀을 때 — 해당 영수증으로 돌아가 수정
  final void Function(int index)? onEdit;

  double get _total => drafts.fold(0.0, (s, d) => s + d.total);

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '인식 결과 확인',
      // 뒤로가기 = 마지막 영수증 검토 화면으로 되돌아간다.
      // (시안에는 화살표가 없지만, 되돌아갈 길을 막으면 안 된다)
      onBack: () => Navigator.pop(context),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 요약 카드 ──
                  FnCard(
                    bordered: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _summaryRow('인식된 영수증', '${drafts.length}장'),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(
                              height: 1, color: FnColors.lineNeutral),
                        ),
                        _summaryRow('총 합계', FnDemo.won(_total),
                            valueColor: FnColors.rose50, valueSize: 19),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '영수증 목록 ${drafts.length}건',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: FnColors.labelNormal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < drafts.length; i++) ...[
                    _row(context, i),
                    if (i < drafts.length - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          // ── 저장 버튼 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FnDsButton(
              label: '모두 저장하기',
              size: FnDsButtonSize.large,
              expand: true,
              onPressed: onSaveAll,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {Color? valueColor, double valueSize = 16}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: FnColors.labelAlternative,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: valueSize,
            fontWeight: FontWeight.w700,
            color: valueColor ?? FnColors.labelNormal,
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, int i) {
    final d = drafts[i];
    final name = d.storeName.trim().isEmpty ? '매입처 미확인' : d.storeName.trim();
    final dt = '${d.date.year}.'
        '${d.date.month.toString().padLeft(2, '0')}.'
        '${d.date.day.toString().padLeft(2, '0')}';

    return FnCard(
      bordered: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      radius: 14,
      onTap: onEdit == null ? null : () => onEdit!(i),
      child: Row(
        children: [
          const _Thumb(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: FnColors.labelNormal,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$dt · 품목 ${d.items.length}건',
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
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: FnColors.labelNormal,
            ),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: FnColors.labelAssistive),
          ],
        ],
      ),
    );
  }
}

/// 시안의 영수증 종이 썸네일 (44×56, 분홍 줄 2개)
class _Thumb extends StatelessWidget {
  const _Thumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: FnColors.lineNeutral),
      ),
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bar(1.0),
          const SizedBox(height: 3),
          _bar(0.75),
          const SizedBox(height: 3),
          _bar(0.9),
          const Spacer(),
          _bar(0.55),
        ],
      ),
    );
  }

  Widget _bar(double f) => FractionallySizedBox(
        widthFactor: f,
        alignment: Alignment.centerLeft,
        child: Container(
          height: 4,
          decoration: BoxDecoration(
            color: FnColors.rose95,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}
