import 'package:flutter/material.dart';

import '../../design/fn_shell.dart';
import '../../design/fn_home_tokens.dart';
import '../../services/notification_prefs.dart';

/// 알림 설정 화면 — 요청 #141 시안 1:1 구현.
///
/// ## 시안 실측 (473x1024, 환산비 0.8245 -> 390 x 844.3dp)
///
/// ```
///   배경            #FEF9F5  (52.4%)
///   카드            #FFFFFF  좌우 19.8dp 대칭
///   서비스 알림 카드  y 224.3..521.9dp (h 298)
///   혜택 알림 카드    y 571.4..649.7dp (h  79)
///   토글            44.5 x 26.4dp
///     켜짐          #FF6D78
///     꺼짐          #E5E5E5
///   묶음 제목        y 131.9(제목) / 540.9(혜택) — 좌 24.7dp
/// ```
///
/// ## 기능
///
/// 시안 문구가 `설정은 변경하는 즉시 저장돼요.` 이므로 저장 버튼이
/// 없다. 토글을 누르는 즉시 [NotificationPrefs] 가 저장한다.
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
      bg: FnHome.bgWarm,
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
      color: FnHome.bgWarm,
      child: SizedBox.expand(
        child: SingleChildScrollView(
          // 시안 카드 좌우 19.8dp
          padding: const EdgeInsets.fromLTRB(_kPad, 10, _kPad, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 제목 두 줄 ──
              const Text(
                '필요한 알림만 받아보세요',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: _kTitle,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '설정은 변경하는 즉시 저장돼요.',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  color: _kMuted,
                ),
              ),
              const SizedBox(height: 22),

              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _kGroup,
                    ),
                  ),
                ),
                _card(entry.value),
                const SizedBox(height: 22),
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
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Divider(height: 1, thickness: 1, color: _kHair),
        ));
      }
      kids.add(_row(items[i]));
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kRadius),
        border: Border.all(color: _kLine),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: kids),
    );
  }

  Widget _row(NotificationOption o) {
    final on = NotificationPrefs.instance.isOn(o.key);
    return InkWell(
      onTap: () => NotificationPrefs.instance.set(o.key, !on),
      borderRadius: BorderRadius.circular(_kRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _kTitle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    o.desc,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12.5,
                      height: 1.35,
                      color: _kMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _FnToggle(on: on, onTap: () {
              NotificationPrefs.instance.set(o.key, !on);
            }),
          ],
        ),
      ),
    );
  }
}

/// 시안 토글 — 44.5 x 26.4dp, 켜짐 #FF6D78 / 꺼짐 #E5E5E5.
///
/// 🔴 `Switch` 를 쓰지 않았다. Material 스위치는 트랙이 더 얇고
///    썸(동그라미)이 트랙 밖으로 튀어나오는 모양이라 시안과 다르다.
///    실측한 치수를 그대로 쓰려면 직접 그리는 쪽이 정확하다.
class _FnToggle extends StatelessWidget {
  const _FnToggle({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const w = 45.0; // 시안 44.5
    const h = 26.0; // 시안 26.4
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
            color: on ? _kOn : _kOff,
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

// ── 시안 실측 토큰 ────────────────────────────────────────────────
/// 카드 좌우 여백. 시안 19.8dp.
const double _kPad = 20.0;

/// 카드 모서리.
const double _kRadius = 16.0;

/// 카드 테두리 — 홈/캘린더와 같은 연한 선.
const Color _kLine = Color(0x14C9A79B);

/// 항목 사이 구분선.
const Color _kHair = Color(0x12C9A79B);

/// 켜진 토글. 시안 실측 #FF6D78.
const Color _kOn = Color(0xFFFF6D78);

/// 꺼진 토글. 시안 실측 #E5E5E5.
const Color _kOff = Color(0xFFE5E5E5);

const Color _kTitle = Color(0xFF12110F);
const Color _kMuted = Color(0xFF8A8580);
const Color _kGroup = Color(0xFF9A948F);
