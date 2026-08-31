import 'package:flutter/material.dart';
import 'fn_tokens.dart';

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
          if (showNavBar)
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
          if (tabs != null)
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
  });

  final List<FnTab> tabs;
  final String? activeKey;
  final ValueChanged<String>? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: FnColors.backgroundNormal,
        border: Border(
          top: BorderSide(color: FnColors.lineNeutral, width: 1),
        ),
      ),
      child: Row(
        children: tabs.map((t) {
          final active = t.key == activeKey;
          final color =
              active ? FnColors.primaryNormal : FnColors.labelAssistive;
          return Expanded(
            child: InkWell(
              onTap: onChange == null ? null : () => onChange!(t.key),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
              ),
            ),
          );
        }).toList(),
      ),
    );
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
