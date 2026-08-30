import 'package:flutter/material.dart';
import '../design/fn_tokens.dart';

/// AppColors
///
/// 기존 화면들이 참조하는 이름은 그대로 유지하되, 값은 전부
/// Wanted Design System(프로토타입) 토큰으로 교체되었습니다.
/// -> 화면 코드를 한 줄도 고치지 않고 앱 전체가 새 디자인으로 리스킨됩니다.
///
/// 신규 화면에서는 AppColors 대신 [FnColors]를 직접 쓰는 것을 권장합니다.
class AppColors {
  AppColors._();

  // ── Surface / Background ───────────────────────────────
  /// #FFFCFA - paper
  static const Color background = Color(0xFFFFFCFA);
  static const Color surface = Color(0xFFFFFFFF);
  /// #FCEEEB - rose 95
  static const Color surfaceVariant = Color(0xFFFCEEEB);

  // ── Primary (Rose) ─────────────────────────────────────
  /// #EE7686 - rose 50 (primary-normal)
  static const Color primary = Color(0xFFEE7686);
  /// #F9A7A0 - rose 70
  static const Color primaryLight = Color(0xFFF9A7A0);
  /// #DD6376 - rose 40 (primary-heavy)
  static const Color primaryDark = Color(0xFFDD6376);

  // ── Secondary (Blush / Cream 계열) ──────────────────────
  /// #EBC9C3 - rose tint
  static const Color secondary = Color(0xFFEBC9C3);
  /// #F7E4DE - blush
  static const Color secondaryLight = Color(0xFFF7E4DE);
  /// #C9566A - rose 30
  static const Color secondaryDark = Color(0xFFC9566A);

  // ── Accent (Leaf / Sage) ───────────────────────────────
  /// #86B06B - leaf 50
  static const Color accent = Color(0xFF86B06B);
  /// #9DBA8C - sage
  static const Color accentLight = Color(0xFF9DBA8C);
  /// #5F8347 - leaf 30
  static const Color accentDark = Color(0xFF5F8347);

  // ── Text ───────────────────────────────────────────────
  /// #171717 - label-normal
  static const Color textPrimary = Color(0xFF171717);
  /// label-alternative (#37383C 61%) 를 불투명 근사치로
  static const Color textSecondary = Color(0xFF7C7D82);
  /// label-assistive (#37383C 28%) 를 불투명 근사치로
  static const Color textHint = Color(0xFFB6B7BB);

  // ── Line ───────────────────────────────────────────────
  /// line-normal (#70737C 22%) 근사치
  static const Color border = Color(0xFFE1E2E5);
  /// line-neutral (#70737C 16%) 근사치
  static const Color divider = Color(0xFFE8E9EB);

  // ── Calendar ───────────────────────────────────────────
  static const Color calendarSelected = primary;
  static const Color calendarToday = Color(0xFFF28190); // rose 55
  static const Color calendarMarker = accent;

  // ── Status ─────────────────────────────────────────────
  /// status-positive (면세)
  static const Color success = Color(0xFF86B06B);
  /// status-cautionary
  static const Color warning = Color(0xFFE0A45C);
  /// status-negative
  static const Color error = Color(0xFFE8697B);

  // ── Scan limit indicator ───────────────────────────────
  static const Color scanFree = success;
  static const Color scanLow = warning;
  static const Color scanEmpty = error;

  // ── 세금 구분 (신규 기능용 별칭) ────────────────────────
  /// 면세 - 생화
  static const Color taxExempt = success;
  /// 과세 - 부자재
  static const Color taxable = primary;

  // ── 추가 토큰 별칭 ──────────────────────────────────────
  static const Color ivory = Color(0xFFFBF6E1);
  static const Color cream = Color(0xFFFEF8EE);
  static const Color blush = Color(0xFFF7E4DE);
  static const Color rose95 = Color(0xFFFCEEEB);
  static const Color rose99 = Color(0xFFFFFAF8);
  static const Color leaf95 = Color(0xFFEFF5E7);
}

/// #112(B) 뒤로가기 반응 속도 — 화면 전환 시간
///
/// 🔴 왜 필요한가
///    기본 [ZoomPageTransitionsBuilder] 는 앞으로/뒤로 모두 300ms 다.
///    실측(테스트로 프레임을 셈)하면 뒤로가기 1회에 312ms 동안 화면이
///    애니메이션 중이어서, 그 사이에는 사장님 입력이 먹지 않는 것처럼
///    느껴진다.
///
///    ▶ 뒤로가기 소요: 기존 312ms  ->  줄인 후 176ms
///
///    참고로 `FadeForwardsPageTransitionsBuilder` 로 바꾸면 832ms 로
///    오히려 3배 가까이 느려진다(실측). 그래서 전환 방식은 그대로 두고
///    시간만 줄였다.
class FnFastPageTransitions extends ZoomPageTransitionsBuilder {
  const FnFastPageTransitions();

  /// 들어갈 때는 살짝만 줄인다(너무 빠르면 뚝 끊긴 느낌이 난다).
  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  /// 🔴 뒤로가기는 사장님이 "이미 본 화면" 으로 돌아가는 것이라
  ///    기다릴 이유가 없다. 절반 수준으로 줄인다.
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);
}

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Pretendard';

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      // #112(B) 뒤로가기 반응 — 전환 시간 312ms -> 176ms (실측)
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FnFastPageTransitions(),
          TargetPlatform.iOS: FnFastPageTransitions(),
          TargetPlatform.macOS: FnFastPageTransitions(),
          TargetPlatform.windows: FnFastPageTransitions(),
          TargetPlatform.linux: FnFastPageTransitions(),
          TargetPlatform.fuchsia: FnFastPageTransitions(),
        },
      ),
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.surfaceVariant,
        onPrimaryContainer: AppColors.primaryDark,
        secondary: AppColors.secondary,
        onSecondary: AppColors.textPrimary,
        secondaryContainer: AppColors.secondaryLight,
        tertiary: AppColors.accent,
        onTertiary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: AppColors.background,
        surfaceContainer: AppColors.surfaceVariant,
        surfaceContainerHighest: AppColors.surfaceVariant,
        outline: AppColors.border,
        outlineVariant: AppColors.divider,
        error: AppColors.error,
        onError: Colors.white,
      ),
      textTheme: _textTheme,
      primaryTextTheme: _textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.r20),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.textHint,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FnRadius.r12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.primary, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FnRadius.r12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FnRadius.r12),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FnRadius.r12),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FnRadius.r12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FnRadius.r12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FnRadius.r12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        hintStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.textHint,
          fontSize: 15,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textHint,
        selectedLabelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.surfaceVariant,
        elevation: 0,
        height: 62,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        highlightElevation: 3,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.surfaceVariant,
        labelStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.border,
        ),
        trackOutlineColor:
            const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.white,
        ),
        checkColor: const WidgetStatePropertyAll<Color>(Colors.white),
        side: const BorderSide(color: AppColors.border, width: 1.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.r6),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.border,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          color: Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.r12),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.r20),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: AppColors.divider,
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.divider,
        circularTrackColor: Colors.transparent,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
      ),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }

  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.28,
      letterSpacing: -0.6,
      color: AppColors.textPrimary,
    ),
    displayMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.5,
      color: AppColors.textPrimary,
    ),
    displaySmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.33,
      letterSpacing: -0.4,
      color: AppColors.textPrimary,
    ),
    headlineLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.36,
      letterSpacing: -0.4,
      color: AppColors.textPrimary,
    ),
    headlineMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.4,
      letterSpacing: -0.3,
      color: AppColors.textPrimary,
    ),
    headlineSmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.44,
      letterSpacing: -0.3,
      color: AppColors.textPrimary,
    ),
    titleLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.47,
      letterSpacing: -0.2,
      color: AppColors.textPrimary,
    ),
    titleMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.5,
      letterSpacing: -0.2,
      color: AppColors.textPrimary,
    ),
    titleSmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.46,
      letterSpacing: -0.2,
      color: AppColors.textPrimary,
    ),
    bodyLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
      letterSpacing: -0.2,
      color: AppColors.textPrimary,
    ),
    bodyMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
      letterSpacing: -0.1,
      color: AppColors.textPrimary,
    ),
    bodySmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.46,
      color: AppColors.textSecondary,
    ),
    labelLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.43,
      color: AppColors.textPrimary,
    ),
    labelMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.33,
      color: AppColors.textSecondary,
    ),
    labelSmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.27,
      color: AppColors.textHint,
    ),
  );
}
