import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_card.dart';
import '../../design/fn_controls_ds.dart';
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

  void _home() {
    if (widget.onGoHome != null) {
      widget.onGoHome!();
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  void _calendar() {
    if (widget.onGoCalendar != null) {
      widget.onGoCalendar!();
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

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
        navTitle: '',
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 180,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 64x64 r32 green-95 / ✓ 30 green-50
                ScaleTransition(
                  scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: FnColors.leaf95,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 30, color: FnColors.leaf50),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  s.success > 1 ? '${s.success}장 모두 저장 완료했어요' : '모두 저장 완료했어요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: FnColors.labelStrong,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '매입 내역과 캘린더에 자동으로 반영되었어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: FnColors.labelAlternative,
                  ),
                ),
                const SizedBox(height: 16),
                FnCard(
                  bordered: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _row('저장된 영수증', '${s.success}장'),
                      _row('총 합계', FnDemo.won(s.amount)),
                      // 기존 기능 유지: 품목 수 / 실패분 안내
                      if (s.itemCount > 0) _row('품목', '${s.itemCount}개'),
                      if (s.failed > 0)
                        _row('인식 실패', '${s.failed}장',
                            valueColor: FnColors.statusNegative),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FnDsButton(
                        label: '홈으로 가기',
                        size: FnDsButtonSize.large,
                        variant: FnDsButtonVariant.outlined,
                        expand: true,
                        onPressed: _home,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FnDsButton(
                        label: '캘린더 보기',
                        size: FnDsButtonSize.large,
                        expand: true,
                        onPressed: _calendar,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 시안 `row space-between padding:'4px 0'`
  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: FnColors.labelNormal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: valueColor ?? FnColors.labelStrong,
            ),
          ),
        ],
      ),
    );
  }
}
