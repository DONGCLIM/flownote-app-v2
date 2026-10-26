import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fn_scan_tokens.dart';

/// 금액 재확인 팝업 — 사장님 시안 ① 1:1
///
/// 영수증을 다 확인하고 **마지막으로 넘어갈 때** 한 번 더 묻는다.
/// 인식이 틀린 채로 저장되면 세무 신고 금액이 달라지기 때문이다.
///
/// 시안 실측(450x1024, 1.1450 px/dp)
///   카드   y 285.6-579.9 (h 294.3) / 좌우 24.5dp
///   제목   카드 위에서 25.3dp
///   부제   65.5 / 85.6dp (두 줄)
///   버튼1  117.0dp (h 60.3)   '이상 없어요'  면 #FF98A0
///   버튼2  187.8dp (h 60.3)   '다시 검토하기' 흰 바탕 + 코랄 테두리
///   안내   261.1dp            '이 안내는 하루에 한 번만 표시돼요'
///
/// 시안 문구대로 **하루에 한 번만** 뜬다. 매번 뜨면 여러 장을 저장할 때
/// 거슬리고, 거슬리면 읽지 않고 누르게 되어 애초 목적을 잃는다.
class FnAmountCheckDialog extends StatelessWidget {
  const FnAmountCheckDialog({super.key});

  /// 마지막으로 보여준 날짜를 적어 두는 칸.
  static const _prefsKey = 'fn.amountCheck.lastShownYmd';

  /// 오늘 이미 보여줬는지.
  static Future<bool> shownToday() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_prefsKey) == _todayKey();
  }

  /// 오늘 보여줬다고 적어 둔다.
  static Future<void> markShown() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, _todayKey());
  }

  /// 테스트와 '다시 보기' 용 초기화.
  static Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefsKey);
  }

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  /// 띄운다. 오늘 이미 봤으면 묻지 않고 바로 `true`(통과)를 돌려준다.
  ///
  /// 반환값
  ///   true  : '이상 없어요' — 그대로 저장으로 진행
  ///   false : '다시 검토하기' — 검토 화면에 머문다
  static Future<bool> ask(BuildContext context) async {
    if (await shownToday()) return true;
    if (!context.mounted) return true;
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: FnScan.askDim),
      builder: (_) => const FnAmountCheckDialog(),
    );
    // 닫혔으면(어느 쪽이든) 오늘은 더 묻지 않는다.
    await markShown();
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: FnScan.askPad),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 25, 24, 20),
        decoration: BoxDecoration(
          color: FnScan.card,
          borderRadius: BorderRadius.circular(FnScan.askRadius),
          boxShadow: FnScan.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '금액을 한 번 더 확인하셨나요?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: FnScan.ink,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '인식 오류가 있으면\n세무 신고 시 금액이 달라질 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13.5,
                height: 1.55,
                fontWeight: FontWeight.w400,
                color: FnScan.sub,
              ),
            ),
            const SizedBox(height: 24),
            _btn(
              context,
              label: '이상 없어요',
              filled: true,
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 10),
            _btn(
              context,
              label: '다시 검토하기',
              filled: false,
              onTap: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: 14),
            const Text(
              '이 안내는 하루에 한 번만 표시돼요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                color: FnScan.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(
    BuildContext context, {
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: FnScan.askBtnH,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? FnScan.askPrimary : FnScan.card,
          borderRadius: BorderRadius.circular(FnScan.askBtnRadius),
          border: filled
              ? null
              : Border.all(color: FnScan.askPrimary, width: 1.4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: filled ? Colors.white : FnScan.askPrimary,
          ),
        ),
      ),
    );
  }
}
