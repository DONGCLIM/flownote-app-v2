import 'package:flutter/material.dart';
import 'fn_tokens.dart';
import 'fn_home_tokens.dart';
import 'fn_brand.dart';

/// 시안 원본 `window.FN.Shell` 1:1 포팅
///
/// ```js
/// function Shell({ navTitle, onBack, tabs, activeTab, onTabChange, trailing, bg, children })
///   div  height:100% flex column  background: bg || var(--background-normal-normal)
///     div paddingTop:54 flexShrink:0            ← 상태바 영역
///       NavigationBar { title, leading, trailing }
///     div flex:1 overflow:auto                  ← 본문
///     BottomNavigation { tabs, activeKey, onChange }
/// ```
/// 배경이 어두운 경우(시안의 `--cool-neutral-10` 촬영 화면) 전경색을 흰색으로 바꾼다.
bool _onDark(Color c) => c.computeLuminance() < 0.35;

class FnShell extends StatelessWidget {
  const FnShell({
    super.key,
    this.navTitle,
    this.onBack,
    this.tabs,
    this.activeTab,
    this.onTabChange,
    this.trailing,
    this.bg,
    this.showNavBar = true,
    this.brandHeader = false,
    this.onBellTap,
    this.bellDot = false,
    this.floatingTabs = false,
    required this.child,
  });

  final String? navTitle;
  final VoidCallback? onBack;
  final List<FnTab>? tabs;
  final String? activeTab;
  final ValueChanged<String>? onTabChange;
  final List<Widget>? trailing;
  final Color? bg;
  final bool showNavBar;

  /// #136 시안 헤더 — 제목 대신 워드마크 + 알림 벨.
  ///
  /// 시안 실측(473x1024, 환산비 0.8245):
  ///   워드마크 h 17.3dp, 좌 24.7dp / 벨 19.0x21.4dp, 우 25.6dp
  ///   알림 점 지름 4.9dp #FB6E76
  /// 5탭 컨테이너에서만 켠다. 나머지 화면은 지금처럼 제목을 쓴다.
  final bool brandHeader;

  /// 벨을 눌렀을 때. null 이면 벨을 눌러도 아무 일도 없다.
  final VoidCallback? onBellTap;

  /// 벨 위 빨간 알림 점을 그릴지.
  final bool bellDot;

  /// #136 시안 탭바 — 바닥에 붙은 줄이 아니라 떠 있는 흰 카드.
  ///
  /// 시안 실측: 좌우 여백 9.9dp, 높이 71.7dp, r 27dp,
  /// 화면 아래로 33.8dp 띄움.
  final bool floatingTabs;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final background = bg ?? FnColors.backgroundNormal;
    // 시안은 paddingTop:54 고정(iOS 프레임). 실기기에서는 실제 상태바 높이를 사용한다.
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: background,
      body: Column(
        children: [
          if (showNavBar && brandHeader)
            // #136 시안 헤더 — 워드마크 + 알림 벨
            Container(
              padding: EdgeInsets.only(top: topInset),
              color: background,
              child: _FnBrandHeader(
                onBellTap: onBellTap,
                dot: bellDot,
              ),
            )
          else if (showNavBar)
            Container(
              padding: EdgeInsets.only(top: topInset),
              color: background,
              child: FnNavigationBar(
                title: navTitle,
                // 시안 Shell 은 배경색을 자식(NavigationBar)에도 그대로 물려준다.
                background: background,
                foreground: _onDark(background) ? Colors.white : null,
                leading: onBack == null
                    ? null
                    : _NavBackButton(
                        onTap: onBack!,
                        color: _onDark(background) ? Colors.white : null,
                      ),
                trailing: trailing,
              ),
            )
          else
            SizedBox(height: topInset),
          Expanded(child: child),
          if (tabs != null && floatingTabs)
            // #136 시안 탭바 — 떠 있는 흰 카드
            Padding(
              // 🔴 #137 시안 실측: 좌우 9.9dp / 바닥에서 34.6dp 떠 있다.
              //
              // 전에는 `bottomInset > 0 ? bottomInset : 10` 이어서 홈
              // 인디케이터가 없는 환경(웹·구형 안드로이드)에서는 10dp 만
              // 띄워 탭바가 화면 아래에 **붙어** 보였다.
              // 라이브 실측 10.0dp vs 시안 34.6dp.
              //
              // 인디케이터가 있으면 그 높이를 쓰되, 시안 간격보다 작으면
              // 시안 간격을 쓴다. (아래로 더 붙지 않게)
              padding: EdgeInsets.only(
                left: FnHome.tabBarSide,
                right: FnHome.tabBarSide,
                bottom: bottomInset > FnHome.tabBarBottom
                    ? bottomInset
                    : FnHome.tabBarBottom,
              ),
              child: FnBottomNavigation(
                tabs: tabs!,
                activeKey: activeTab,
                onChange: onTabChange,
                floating: true,
              ),
            )
          else if (tabs != null)
            Container(
              color: FnColors.backgroundNormal,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: FnBottomNavigation(
                tabs: tabs!,
                activeKey: activeTab,
                onChange: onTabChange,
              ),
            ),
        ],
      ),
    );
  }
}

/// 시안 `DS.NavigationBar` 1:1
/// height:56, padding:'0 8px', leading width:40 flex-start,
/// title flex:1 center fontSize:17 fontWeight:600 color:label-strong,
/// trailing minWidth:40 flex-end gap:4
class FnNavigationBar extends StatelessWidget {
  const FnNavigationBar({
    super.key,
    this.title,
    this.leading,
    this.trailing,
    this.background,
    this.foreground,
  });

  final String? title;
  final Widget? leading;
  final List<Widget>? trailing;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: background ?? FnColors.backgroundNormal,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Align(
              alignment: Alignment.centerLeft,
              child: leading ?? const SizedBox.shrink(),
            ),
          ),
          Expanded(
            child: Text(
              title ?? '',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: foreground ?? FnColors.labelStrong,
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: _withGap(trailing ?? const [], 4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBackButton extends StatelessWidget {
  const _NavBackButton({required this.onTap, this.color});
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // 시안: button 32x32, Icon ChevronLeft size 18
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          Icons.chevron_left_rounded,
          size: 22,
          color: color ?? FnColors.labelNormal,
        ),
      ),
    );
  }
}

/// #136 시안 헤더 — 워드마크 + 알림 벨.
///
/// 시안 실측 (473x1024, 환산비 0.8245):
///   워드마크  좌 24.7dp, y 65.1..81.6dp (h 17.3dp, 비율 6.095)
///   벨       우 25.6dp, 19.0 x 21.4dp
///   알림 점   지름 4.9dp, #FB6E76
///
/// 워드마크 비율은 `FnBrand.wordmarkRatio`(5.9571) 과 6.095 로 거의 같다.
/// 시안 쪽이 약간 넓은데, 글자 끝 안티앨리어싱까지 센 탓이다.
class _FnBrandHeader extends StatelessWidget {
  const _FnBrandHeader({this.onBellTap, this.dot = false});

  final VoidCallback? onBellTap;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            // #138 5탭 헤더는 'o' 꽃잎이 코랄인 판을 쓴다.
            // (로그인·스플래시·인트로 시안은 검정이라 flat 유지)
            const FnWordmark(height: 18, color: true),
            const Spacer(),
            // 벨 — 누를 수 있는 영역은 44x44 로 넉넉히 둔다.
            InkWell(
              onTap: onBellTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.notifications_none_rounded,
                        size: 23, color: FnHome.title),
                    if (dot)
                      const Positioned(
                        top: 11,
                        right: 11,
                        child: _BellDot(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 벨 위 알림 점 — 시안 지름 4.9dp, #FB6E76
class _BellDot extends StatelessWidget {
  const _BellDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Color(0xFFFB6E76),
          shape: BoxShape.circle,
        ),
      );
}

class FnTab {
  const FnTab({required this.key, required this.label, required this.icon});
  final String key;
  final String label;
  final IconData icon;
}

/// 시안 `tabs` 정의 그대로
/// [{home,홈},{settle,내역},{scan,스캔},{calendar,캘린더},{profile,프로필}]
/// TAB_ICON_NAME = { settle: BusinessBag, scan: Camera, calendar: Calendar, profile: MyPage }
const List<FnTab> fnTabs = [
  FnTab(key: 'home', label: '홈', icon: Icons.home_rounded),
  FnTab(key: 'settle', label: '내역', icon: Icons.business_center_outlined),
  FnTab(key: 'scan', label: '스캔', icon: Icons.photo_camera_outlined),
  FnTab(key: 'calendar', label: '캘린더', icon: Icons.calendar_today_outlined),
  FnTab(key: 'profile', label: '프로필', icon: Icons.person_outline_rounded),
];

/// 시안 `DS.BottomNavigation` 1:1
/// nav height:56, background:background-normal-normal,
/// boxShadow: inset 0 1px 0 var(--line-normal-neutral)   ← 상단 1px 선
/// button flex:1 column gap:2, icon span 24x24,
/// color: active ? var(--blue-50)[=#EE7686] : var(--label-assistive)
/// fontWeight: active ? 600 : 500, fontSize: 11
class FnBottomNavigation extends StatelessWidget {
  const FnBottomNavigation({
    super.key,
    required this.tabs,
    this.activeKey,
    this.onChange,
    this.floating = false,
  });

  final List<FnTab> tabs;
  final String? activeKey;
  final ValueChanged<String>? onChange;

  /// #136 시안 — 떠 있는 흰 카드로 그린다.
  /// 시안 실측: 높이 71.7dp, r 27dp, 좌우 여백 9.9dp.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    if (floating) {
      return Container(
        // 시안 실측 70.9dp (y 738.8..809.7)
        height: FnHome.tabBarH,
        decoration: BoxDecoration(
          color: FnColors.backgroundNormal,
          borderRadius: BorderRadius.circular(FnHome.tabBarRadius),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8A5C57).withValues(alpha: 0.10),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(children: _items(coral: true)),
      );
    }
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: FnColors.backgroundNormal,
        border: Border(
          top: BorderSide(color: FnColors.lineNeutral, width: 1),
        ),
      ),
      child: Row(children: _items()),
    );
  }

  /// 탭 5칸. `coral` 이면 #136 시안의 코랄 강조색을 쓴다.
  ///
  /// 두 모드가 같은 위젯을 쓰게 뽑아냈다. 예전에는 이 코드가 build() 안에
  /// 인라인으로 있었고, 떠 있는 탭바를 넣으면서 복사하면 둘이 갈라졌다.
  List<Widget> _items({bool coral = false}) {
    return tabs.map((t) {
      final active = t.key == activeKey;
      final color = active
          ? (coral ? FnHome.coralFlat : FnColors.primaryNormal)
          : FnColors.labelAssistive;
      final content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Icon(t.icon, size: 20, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            t.label,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      );
      return Expanded(
        child: InkWell(
          onTap: onChange == null ? null : () => onChange!(t.key),
          borderRadius: BorderRadius.circular(coral ? 20 : 0),
          child: Center(
            // 🔴 #143 시안에는 **활성 탭 뒤에 연분홍 알약**이 깔려 있다.
            //    지금까지는 글자·아이콘 색만 코랄로 바꿨을 뿐이라
            //    "지금 어느 탭인지" 가 시안만큼 또렷하지 않았다.
            //    실측: 70 x 53dp, #FEF0EF.
            //
            //    `coral`(= 떠 있는 탭바) 일 때만 그린다. 옛 스타일
            //    탭바는 높이 56dp 라 53dp 알약이 들어가지 않는다.
            child: (coral && active)
                ? Container(
                    width: FnHome.tabPillW,
                    height: FnHome.tabPillH,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FnHome.tabPill,
                      borderRadius:
                          BorderRadius.circular(FnHome.tabPillH / 2),
                    ),
                    child: content,
                  )
                : content,
          ),
        ),
      );
    }).toList();
  }
}

List<Widget> _withGap(List<Widget> items, double gap) {
  if (items.length <= 1) return items;
  final out = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    if (i > 0) out.add(SizedBox(width: gap));
    out.add(items[i]);
  }
  return out;
}

/// 시안 화면 본문에서 반복되는
/// `div { padding: 16, display:flex, flexDirection:column, gap: N }`
class FnColumn extends StatelessWidget {
  const FnColumn({
    super.key,
    required this.children,
    this.gap = 14,
    this.padding = const EdgeInsets.all(16),
    this.scrollable = true,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final double gap;
  final EdgeInsets padding;
  final bool scrollable;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final kids = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) kids.add(SizedBox(height: gap));
      kids.add(children[i]);
    }
    final col = Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: kids,
    );
    if (!scrollable) return Padding(padding: padding, child: col);
    return SingleChildScrollView(
      padding: padding,
      child: col,
    );
  }
}
