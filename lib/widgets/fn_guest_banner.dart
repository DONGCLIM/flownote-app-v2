import 'package:flutter/material.dart';

import '../services/guest_service.dart';
import '../theme/fn_ds.dart';
import 'fn_signup_sheet.dart';

/// 게스트에게만 보이는 **고정 띠**. (#192)
///
/// ```
///  ┌──────────────────────────────────────────────┐
///  │ 체험 중 · 남은 스캔 3장           로그인/가입 │   ← 코랄 띠
///  └──────────────────────────────────────────────┘
/// ```
///
/// ## 왜 필요한가
///
/// 게스트 화면과 회원 화면이 거의 똑같이 생겼다. 그래서 체험 중이신 분이
/// **자기가 가입한 줄 알고** 영수증을 쌓다가, 5장에서 막히거나 기기를
/// 바꿨을 때 "데이터가 날아갔다" 고 느끼신다. 지금 어떤 상태인지 화면
/// 맨 위에 늘 보이게 한다.
///
/// 🔴 **회원에게는 절대 안 보인다.** [GuestService.isGuest] 가 false 면
///    `SizedBox.shrink()` 라 높이도 0 이다. 회원 화면은 한 픽셀도
///    달라지지 않는다.
///
/// 🔴 [GuestService] 를 듣고 있다. 스캔을 한 장 찍으면 남은 장수가
///    바로 줄어든다. 안 들으면 화면을 나갔다 와야 숫자가 바뀐다.
class FnGuestBanner extends StatelessWidget {
  const FnGuestBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final g = GuestService.instance;
    if (!g.isGuest) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: g,
      builder: (context, _) {
        // 듣는 사이에 가입하셨을 수 있다. 그리기 직전에 한 번 더 본다.
        if (!g.isGuest) return const SizedBox.shrink();
        return Material(
          color: FnDs.coralFaint,
          child: InkWell(
            onTap: () => fnOpenSignIn(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: FnDs.gapM, vertical: 9),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: FnDs.coral, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.science_outlined,
                      size: 15, color: FnDs.coral),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '체험 중 · 남은 스캔 ${g.scansLeft}장',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: FnDs.font,
                        fontSize: FnDs.fontXs,
                        fontWeight: FontWeight.w700,
                        color: FnDs.coral,
                      ),
                    ),
                  ),
                  const Text(
                    '로그인/가입',
                    style: TextStyle(
                      fontFamily: FnDs.font,
                      fontSize: FnDs.fontXs,
                      fontWeight: FontWeight.w700,
                      color: FnDs.coral,
                      decoration: TextDecoration.underline,
                      decorationColor: FnDs.coral,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: FnDs.coral),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 체험 영수증이 **기존 계정으로 옮겨지지 않았을 때** 한 번만 보여 주는 줄.
///
/// 🔴 팝업이 아니라 **닫을 수 있는 안내 줄**이다. 사장님 지시 —
///    로그인 직후 팝업이 또 뜨면 피로하다.
///
/// 🔴 **새로 가입하신 분에게는 절대 안 뜬다.** 그분들은 영수증이 그대로
///    옮겨졌으므로 알릴 것이 없다. 띄울지 말지는
///    [GuestService.pendingSkipNotice] 하나가 정한다 — 서버가 "기존
///    회원이라 안 옮겼다" 고 답했을 때만 켜진다.
class FnMigrateSkippedNotice extends StatefulWidget {
  const FnMigrateSkippedNotice({super.key});

  @override
  State<FnMigrateSkippedNotice> createState() => _FnMigrateSkippedNoticeState();
}

class _FnMigrateSkippedNoticeState extends State<FnMigrateSkippedNotice> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GuestService.instance,
      builder: (context, _) {
        if (!GuestService.instance.pendingSkipNotice) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          color: FnDs.cautionBg,
          padding: const EdgeInsets.fromLTRB(FnDs.gapM, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline_rounded,
                    size: 16, color: FnDs.caution),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '체험으로 찍은 영수증은 기존 계정으로 옮겨지지 않아요. '
                  '필요한 영수증은 다시 스캔해 주세요.',
                  style: TextStyle(
                    fontFamily: FnDs.font,
                    fontSize: FnDs.fontXs,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: FnDs.title,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: GuestService.instance.dismissSkipNotice,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Icon(Icons.close_rounded,
                      size: 16, color: FnDs.caution),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
