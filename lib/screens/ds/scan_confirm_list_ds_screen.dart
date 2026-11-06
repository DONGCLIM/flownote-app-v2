import 'package:flutter/material.dart';

import '../../design/fn_scan_tokens.dart';
import '../../design/fn_shell.dart';
import '../scan/scan_draft.dart';
import 'fn_data.dart';

/// 저장 직전 **마지막 확인** 화면 — 사장님 시안 ② 1:1
///
/// ## 왜 필요한가 (#113)
///
/// 여러 장을 스캔하면 한 장씩 넘겨보며 검토(`ScanReviewDsScreen`)한 뒤
/// 곧바로 저장 다이얼로그가 떴다. 사장님 표현으로는
/// "내가 했던 것에 대해서 마지막으로 한번 더 확인" 할 자리가 없었다.
/// 그래서 검토를 마치면 이 목록을 한 번 보여준다.
/// 항목을 누르면 그 영수증으로 되돌아가 다시 고칠 수 있다.
///
/// ## 시안 실측 (470x1024, 1.1959 px/dp)
///
/// ```
///   요약 카드   y 125.4-246.7 (h 121.2)   좌우 18.4dp, 흰 카드
///     '인식된 영수증' / '4장'
///     구분선
///     '총 합계' / 코랄 '583,000원'
///   '영수증 목록 4건'  y 260.0-280.1
///   항목 카드 x4      y 291.8 / 388.8 / 485.8 / 582.0  (각 h 92.0, 간격 5.0)
///     가게명 / 'YYYY.MM.DD · 품목 N건' ... 금액 ... 화살표
///   '모두 저장하기'   y 679.0-745.0   면 #FE717A
/// ```
///
/// 🔴 시안에는 **썸네일이 없다.** 예전에는 44x56 종이 그림을 왼쪽에
///    뒀는데 시안에서 빠졌다. 되살리지 말 것.
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
      bg: FnScan.bg,
      // 뒤로가기 = 마지막 영수증 검토 화면으로 되돌아간다.
      // (시안에는 화살표가 없지만, 되돌아갈 길을 막으면 안 된다)
      onBack: () => Navigator.pop(context),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              // 시안 실측: 앱바끝(87) → 요약 카드(125) = 38dp
              padding: const EdgeInsets.fromLTRB(
                  FnScan.listPad, 38, FnScan.listPad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _summaryCard(),
                  // 시안: 요약 카드 끝(247) → 목록 제목(260) = 13dp
                  const SizedBox(height: 13),
                  Text(
                    '영수증 목록 ${drafts.length}건',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: FnScan.ink,
                    ),
                  ),
                  // 시안: 제목 끝(280) → 첫 카드(292) = 12dp
                  const SizedBox(height: 12),
                  for (var i = 0; i < drafts.length; i++) ...[
                    _row(context, i),
                    if (i < drafts.length - 1)
                      const SizedBox(height: FnScan.listGap),
                  ],
                ],
              ),
            ),
          ),
          // ── 저장 버튼 (시안 코랄 #FE717A) ──
          Padding(
            // 시안: 마지막 카드 끝(674) → 버튼(679) = 5dp,
            //       버튼 끝(745) → 탭바(755) = 10dp
            padding: const EdgeInsets.fromLTRB(
                FnScan.listPad, 5, FnScan.listPad, 10),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSaveAll,
              child: Container(
                // 시안 실측 버튼 높이 66dp
                height: 66,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: FnScan.listSaveBtn,
                  borderRadius: BorderRadius.circular(FnScan.listRadius),
                ),
                child: const Text(
                  '모두 저장하기',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 시안 요약 카드 — 흰 바탕, 테두리 없이 옅은 그림자.
  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: FnScan.card,
        borderRadius: BorderRadius.circular(FnScan.listRadius),
        boxShadow: FnScan.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryRow('인식된 영수증', '${drafts.length}장'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 13),
            child: Divider(height: 1, color: Color(0xFFF0ECE9)),
          ),
          _summaryRow('총 합계', FnDemo.won(_total),
              valueColor: FnScan.coral, valueSize: 19),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {Color? valueColor, double valueSize = 15}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14.5,
            fontWeight: valueColor == null ? FontWeight.w500 : FontWeight.w700,
            color: valueColor == null ? FnScan.sub : FnScan.ink,
          ),
        ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: valueSize,
                fontWeight: FontWeight.w700,
                color: valueColor ?? FnScan.ink,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 시안 항목 카드 — 썸네일 없음. 가게명 / 날짜·품목수 / 금액 / 화살표.
  Widget _row(BuildContext context, int i) {
    final d = drafts[i];
    final name = d.storeName.trim().isEmpty ? '매입처 미확인' : d.storeName.trim();
    final dt = '${d.date.year}.'
        '${d.date.month.toString().padLeft(2, '0')}.'
        '${d.date.day.toString().padLeft(2, '0')}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onEdit == null ? null : () => onEdit!(i),
      child: Container(
        height: FnScan.listItemH,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: FnScan.card,
          borderRadius: BorderRadius.circular(FnScan.listRadius),
          boxShadow: FnScan.cardShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: FnScan.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$dt · 품목 ${d.items.length}건',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: FnScan.sub,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              FnDemo.won(d.total),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: FnScan.ink,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                size: 24, color: Color(0xFFBFBFBF)),
          ],
        ),
      ),
    );
  }
}
