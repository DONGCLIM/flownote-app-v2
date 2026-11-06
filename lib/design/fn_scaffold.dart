import 'package:flutter/material.dart';
import 'fn_tokens.dart';

/// Wanted DS — NavigationBar (상단)
///
/// 프로토타입 FN.Shell 의 상단 영역. 제목 중앙 정렬, 좌측 back, 우측 액션.
class FnAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FnAppBar({
    super.key,
    this.title,
    this.onBack,
    this.actions,
    this.backgroundColor,
    this.centerTitle = true,
    this.titleWidget,
    this.showBack,
    this.bottom,
    this.elevation = false,
  });

  final String? title;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final bool centerTitle;
  final Widget? titleWidget;
  final bool? showBack;
  final PreferredSizeWidget? bottom;
  final bool elevation;

  static const double _height = 56;

  @override
  Size get preferredSize =>
      Size.fromHeight(_height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final canPop = showBack ?? (onBack != null || Navigator.canPop(context));
    final bg = backgroundColor ?? FnColors.backgroundApp;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        boxShadow: elevation ? FnShadow.normal : null,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _height,
              child: Stack(
                children: [
                  if (canPop)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: FnSpace.x8),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 18),
                          color: FnColors.labelNormal,
                          onPressed:
                              onBack ?? () => Navigator.maybePop(context),
                          splashRadius: 22,
                        ),
                      ),
                    ),
                  if (actions != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: FnSpace.x8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: actions!,
                        ),
                      ),
                    ),
                  Align(
                    alignment:
                        centerTitle ? Alignment.center : Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: centerTitle ? 56 : FnSpace.x20),
                      child: titleWidget ??
                          (title == null
                              ? const SizedBox.shrink()
                              : Text(
                                  title!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: centerTitle
                                      ? TextAlign.center
                                      : TextAlign.start,
                                  style: FnType.headline1.copyWith(
                                    color: FnColors.labelNormal,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )),
                    ),
                  ),
                ],
              ),
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }
}

/// 화면 기본 골격
///
/// 프로토타입 FN.Shell 대응. 배경·앱바·하단탭을 일관되게 묶는다.
class FnScaffold extends StatelessWidget {
  const FnScaffold({
    super.key,
    required this.body,
    this.title,
    this.appBar,
    this.bottomNav,
    this.backgroundColor,
    this.onBack,
    this.actions,
    this.floatingActionButton,
    this.bottomBar,
    this.resizeToAvoidBottomInset,
    this.showAppBar = true,
  });

  final Widget body;
  final String? title;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNav;
  final Color? backgroundColor;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// 하단 고정 CTA 영역
  final Widget? bottomBar;
  final bool? resizeToAvoidBottomInset;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? FnColors.backgroundApp,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: !showAppBar
          ? null
          : (appBar ??
              FnAppBar(
                title: title,
                onBack: onBack,
                actions: actions,
                backgroundColor: backgroundColor,
              )),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar != null
          ? _BottomBarWrap(child: bottomBar!)
          : bottomNav,
    );
  }
}

class _BottomBarWrap extends StatelessWidget {
  const _BottomBarWrap({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FnColors.backgroundElevated,
        border: Border(top: BorderSide(color: FnColors.lineAlternative)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              FnSpace.x20, FnSpace.x12, FnSpace.x20, FnSpace.x12),
          child: child,
        ),
      ),
    );
  }
}

/// 빈 상태 표시
class FnEmptyState extends StatelessWidget {
  const FnEmptyState({
    super.key,
    required this.message,
    this.icon,
    this.subMessage,
    this.action,
  });

  final String message;
  final IconData? icon;
  final String? subMessage;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FnSpace.x40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: FnColors.rose95,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: FnColors.rose50),
              ),
              const SizedBox(height: FnSpace.x16),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: FnType.body1.copyWith(
                color: FnColors.labelAlternative,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subMessage != null) ...[
              const SizedBox(height: FnSpace.x6),
              Text(
                subMessage!,
                textAlign: TextAlign.center,
                style:
                    FnType.caption1.copyWith(color: FnColors.labelAssistive),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: FnSpace.x20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
