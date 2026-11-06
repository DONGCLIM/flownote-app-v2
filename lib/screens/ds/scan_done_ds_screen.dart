import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_scan_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_tab_intent.dart';
import '../scan/scan_draft.dart';
import 'fn_data.dart';

/// 저장 완료 화면 — 시안 `AppH7 scan-done` 1:1
///
/// ```js
/// Shell { navTitle:'' }
///   div { height:'100%', column, justifyContent:'center',
///         padding:24, gap:16, textAlign:'center' }
///     div 64x64 r32 bg green-95 center fontSize:30 color:green-50 margin:'0 auto' '✓'
///     div.wds-heading2 { 20/600 } '모두 저장 완료했어요'
///     div.wds-body2-normal { label-alternative, 600 } '매입 내역과 캘린더에 자동으로 반영되었어요'
///     Card bordered { textAlign:'left' }
///       row space-between padding:'4px 0'  span 600 '저장된 영수증' / span 600/18 '1장'
///       row space-between padding:'4px 0'  span 600 '총 합계'      / span 600/18 won(scanTotal)
///     div { row, gap:10 }
///       Button large outlined flex:1 '홈으로 가기'
///       Button large          flex:1 '캘린더 보기'
/// ```
///
/// 시안은 '1장' 고정이지만 실제 저장 결과([summary])를 반영한다.
/// 실패분이 있으면 한 줄 더 보여준다(기존 기능 유지).
class ScanDoneDsScreen extends StatefulWidget {
  const ScanDoneDsScreen({
    super.key,
    required this.summary,
    this.onGoHome,
    this.onGoCalendar,
  });

  final ScanSummary summary;

  /// '홈으로 가기' — 기본은 루트까지 pop.
  final VoidCallback? onGoHome;

  /// '캘린더 보기' — 기본은 루트까지 pop.
  final VoidCallback? onGoCalendar;

  @override
  State<ScanDoneDsScreen> createState() => _ScanDoneDsScreenState();
}

class _ScanDoneDsScreenState extends State<ScanDoneDsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 루트(5탭 화면)로 돌아가면서 [tabKey] 탭을 열어 달라고 남긴다.
  ///
  /// 🔴 예전에는 `_home()` 과 `_calendar()` 가 **똑같이** 루트까지
  ///    pop 만 했다. 그래서 '캘린더 보기' 를 눌러도 스캔 탭으로
  ///    되돌아갈 뿐, 캘린더로 전환되지 않았다.
  void _leaveTo(String tabKey, VoidCallback? override) {
    if (override != null) {
      override();
      return;
    }
    FnTabIntent.request(tabKey);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _home() => _leaveTo('home', widget.onGoHome);

  /// 시안 '매입 내역 보기' — 5탭 중 '내역'(settle) 탭으로 간다.
  ///
  /// 🔴 `onGoCalendar` 를 넘기지 않는다. 그건 캘린더로 가는 콜백이라
  ///    여기서 쓰면 '내역 보기' 를 눌렀는데 캘린더가 열린다.
  ///    시안에서 '캘린더 보기' 버튼이 '매입 내역 보기' 로 바뀌었으므로
  ///    `onGoCalendar` 는 더이상 이 화면에서 쓰이지 않는다.
  void _history() => _leaveTo('settle', null);

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;

    return PopScope(
      // 저장이 끝난 화면이라 뒤로가기는 홈으로 보낸다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _home();
      },
      child: FnShell(
        navTitle: '저장 완료',
        bg: FnScan.bg,
        onBack: _home,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              FnScan.donePad, 0, FnScan.donePad, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 180,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🔴 #163 ③ 시안 실측 — 코랄 원 지름 78.1dp, 면 #FF6C78.
                //    예전에는 64dp 연녹색(leaf95) 원이었다. 되돌리지 말 것.
                ScaleTransition(
                  scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
                  child: Container(
                    width: FnScan.doneCircle,
                    height: FnScan.doneCircle,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: FnScan.doneCircleBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 38, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  s.success > 1 ? '모두 저장 완료' : '저장 완료',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    color: FnScan.ink,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '매입 내역과 캘린더에 자동으로 반영되었어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: FnScan.sub,
                  ),
                ),
                const SizedBox(height: 30),
                // ── 요약 카드 (흰 바탕 + 옅은 그림자) ──
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: FnScan.card,
                    borderRadius: BorderRadius.circular(FnScan.listRadius),
                    boxShadow: FnScan.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _row('저장된 영수증', '${s.success}장'),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 13),
                        child: Divider(height: 1, color: Color(0xFFF0ECE9)),
                      ),
                      _row('총 합계', FnDemo.won(s.amount),
                          valueColor: FnScan.coral, valueSize: 19),
                      // 기존 기능 유지: 실패분이 있으면 숨기지 않고 알린다.
                      if (s.failed > 0) ...[
                        const SizedBox(height: 10),
                        _row('인식 실패', '${s.failed}장',
                            valueColor: FnColors.statusNegative),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                // ── 시안 버튼 2개: 코랄 채움 / 흰 바탕 코랄 테두리 ──
                _bigBtn('매입 내역 보기', filled: true, onTap: _history),
                const SizedBox(height: 10),
                _bigBtn('홈으로 가기', filled: false, onTap: _home),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bigBtn(String label,
      {required bool filled, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? FnScan.doneCircleBg : FnScan.card,
          borderRadius: BorderRadius.circular(FnScan.listRadius),
          border: filled
              ? null
              : Border.all(color: FnScan.doneCircleBg, width: 1.4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: filled ? Colors.white : FnScan.doneCircleBg,
          ),
        ),
      ),
    );
  }

  /// 시안 `row space-between`
  Widget _row(String label, String value,
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
}
