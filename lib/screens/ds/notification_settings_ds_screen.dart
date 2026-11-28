import 'package:flutter/material.dart';

import '../../design/fn_profile_tokens.dart';
import '../../design/fn_shell.dart';
import '../../services/notification_prefs.dart';

/// 알림 설정 화면 — 요청 #164 시안 1:1 (#141 판을 실측값으로 다시 맞춤).
///
/// ## 시안 실측 (473x1024, 환산비 1.2128 → 390dp)
///
/// ```
///   배경            #FEF9F5
///   제목            y 132.1dp  '필요한 알림만 받아보세요'  16dp/w700
///   부제            y 159.5dp  '설정은 변경하는 즉시 저장돼요.' 13.5dp
///   묶음 라벨        y 195.3dp(서비스) / 545.0dp(혜택)  13.5dp/w500 #524E4B
///   카드1           y 224.3..515.1dp (h 290.8)  좌 24.1 우 24.1dp
///   카드2           y 569.7..648.9dp (h  79.2)
///   항목 한 칸       290.8 / 4 = 72.7dp
///   토글            43.2 x 24.9dp   켜짐 #FF6D78 / 꺼짐 #E5E5E5
///   그림자          카드 아래 6.6dp 번짐, 알파 약 6%
/// ```
///
/// ## 기능
///
/// 시안 문구가 `설정은 변경하는 즉시 저장돼요.` 이므로 저장 버튼이
/// 없다. 토글을 누르는 즉시 [NotificationPrefs] 가 기기에 저장한다.
/// 저장 서비스는 이미 만들어져 있던 것을 그대로 쓴다 — 저장 키
/// (`notif_pref_<key>`) 를 바꾸면 쓰던 분들 설정이 초기화되기 때문에
/// 손대지 않았다.
class NotificationSettingsDsScreen extends StatefulWidget {
  const NotificationSettingsDsScreen({super.key});

  @override
  State<NotificationSettingsDsScreen> createState() =>
      _NotificationSettingsDsScreenState();
}

class _NotificationSettingsDsScreenState
    extends State<NotificationSettingsDsScreen> {
  @override
  void initState() {
    super.initState();
    // 저장된 값을 읽어 온다. 읽기 전에는 기본값이 보인다.
    NotificationPrefs.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '알림 설정',
      bg: FnProfile.bg,
      onBack: () => Navigator.of(context).maybePop(),
      child: ListenableBuilder(
        listenable: NotificationPrefs.instance,
        builder: (context, _) => _body(),
      ),
    );
  }

  Widget _body() {
    // 묶음별로 나눈다. 시안은 `서비스 알림` / `혜택 알림` 두 묶음.
    final groups = <String, List<NotificationOption>>{};
    for (final o in NotificationPrefs.options) {
      groups.putIfAbsent(o.group, () => []).add(o);
    }

    return ColoredBox(
      color: FnProfile.bg,
      child: SizedBox.expand(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              FnProfile.pad, 14, FnProfile.pad, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '필요한 알림만 받아보세요',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: FnProfile.nsTitleFont,
                  fontWeight: FontWeight.w700,
                  color: FnProfile.ink,
                ),
              ),
              // 시안 제목 132.1 → 부제 159.5 = 27.4dp 간격(글자 높이 포함)
              const SizedBox(height: 8),
              const Text(
                '설정은 변경하는 즉시 저장돼요.',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: FnProfile.nsSubFont,
                  color: FnProfile.sub,
                ),
              ),
              // 부제 159.5 → 묶음 라벨 195.3
              const SizedBox(height: 22),

              for (var gi = 0; gi < groups.length; gi++) ...[
                if (gi > 0) const SizedBox(height: 26),
                Padding(
                  padding: const EdgeInsets.only(left: 1, bottom: 11),
                  child: Text(
                    groups.keys.elementAt(gi),
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: FnProfile.nsGroupFont,
                      fontWeight: FontWeight.w500,
                      color: FnProfile.group,
                    ),
                  ),
                ),
                _card(groups.values.elementAt(gi)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 한 묶음의 흰 카드. 항목 사이에 연한 구분선을 넣는다.
  Widget _card(List<NotificationOption> items) {
    final kids = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        kids.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Divider(height: 1, thickness: 1, color: FnProfile.hair),
        ));
      }
      kids.add(_row(items[i]));
    }
    return Container(
      decoration: BoxDecoration(
        color: FnProfile.card,
        borderRadius: BorderRadius.circular(FnProfile.cardRadius),
        boxShadow: FnProfile.cardShadow,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: kids),
    );
  }

  Widget _row(NotificationOption o) {
    final on = NotificationPrefs.instance.isOn(o.key);
    return InkWell(
      onTap: () => NotificationPrefs.instance.set(o.key, !on),
      borderRadius: BorderRadius.circular(FnProfile.cardRadius),
      child: Container(
        // 시안 카드1 290.8dp / 4항목 = 72.7
        constraints: const BoxConstraints(minHeight: FnProfile.nsRowH),
        padding: const EdgeInsets.fromLTRB(20, 14, 18, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    o.title,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: FnProfile.nsItemFont,
                      fontWeight: FontWeight.w700,
                      color: FnProfile.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    o.desc,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: FnProfile.nsDescFont,
                      height: 1.35,
                      color: FnProfile.sub,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FnToggle(
              on: on,
              onTap: () => NotificationPrefs.instance.set(o.key, !on),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시안 토글 — 43.2 x 24.9dp, 켜짐 #FF6D78 / 꺼짐 #E5E5E5.
///
/// 🔴 `Switch` 를 쓰지 않았다. Material 스위치는 트랙이 더 얇고
///    썸(동그라미)이 트랙 밖으로 튀어나오는 모양이라 시안과 다르다.
///    실측한 치수를 그대로 쓰려면 직접 그리는 쪽이 정확하다.
class FnToggle extends StatelessWidget {
  const FnToggle({super.key, required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const w = FnProfile.toggleW;
    const h = FnProfile.toggleH;
    const pad = 2.5;
    const knob = h - pad * 2;

    return Semantics(
      toggled: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: on ? FnProfile.coral : FnProfile.toggleOff,
            borderRadius: BorderRadius.circular(h / 2),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: pad),
              child: Container(
                width: knob,
                height: knob,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
