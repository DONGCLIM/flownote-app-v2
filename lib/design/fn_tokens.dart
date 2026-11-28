import 'package:flutter/material.dart';

/// FlowNote 디자인 토큰
///
/// Genspark Design(Figma) 프로토타입에서 추출한 값을 그대로 옮긴 것.
/// 원본: `--fn-*` / Wanted Design System semantic tokens
///
/// 여기 값은 절대 화면에서 하드코딩하지 말고 항상 이 클래스를 통해 참조할 것.
class FnColors {
  FnColors._();

  // ─────────────────────────────────────────────
  // Brand — Rose (primary)
  // ─────────────────────────────────────────────
  static const rose30 = Color(0xFFC9566A);
  static const rose40 = Color(0xFFDD6376);
  static const rose45 = Color(0xFFE56D7E);
  static const rose50 = Color(0xFFEE7686); // ★ primary
  static const rose55 = Color(0xFFF28190);
  static const rose60 = Color(0xFFF4796E);
  static const rose70 = Color(0xFFF9A7A0);
  static const rose90 = Color(0xFFF7DCD8);
  static const rose95 = Color(0xFFFCEEEB);
  static const rose99 = Color(0xFFFFFAF8);

  // Brand — 보조 (로고 파생)
  static const blush = Color(0xFFF7E4DE);
  static const roseTint = Color(0xFFEBC9C3);
  static const ivory = Color(0xFFFBF6E1);
  static const cream = Color(0xFFFEF8EE);
  static const paper = Color(0xFFFFFCFA);

  // Brand — Sage / Leaf (면세·긍정)
  static const sage = Color(0xFF9DBA8C);
  static const leaf30 = Color(0xFF5F8347);
  static const leaf40 = Color(0xFF6F9455);
  static const leaf50 = Color(0xFF86B06B);
  static const leaf95 = Color(0xFFEFF5E7);
  static const leaf99 = Color(0xFFF9FBF5);

  // ─────────────────────────────────────────────
  // Semantic — Primary
  // ─────────────────────────────────────────────
  static const primaryNormal = rose50;
  static const primaryStrong = rose45;
  static const primaryHeavy = rose40;

  // ─────────────────────────────────────────────
  // Semantic — Status
  // ─────────────────────────────────────────────
  static const statusPositive = leaf50;
  static const statusPositiveStrong = leaf30;
  static const statusPositiveBg = leaf95;

  static const statusCautionary = Color(0xFFE0A45C);
  static const statusCautionaryStrong = Color(0xFFA9762F);
  static const statusCautionaryBg = Color(0xFFFCF4E6);

  static const statusNegative = Color(0xFFE8697B);
  static const statusNegativeStrong = Color(0xFFC9566A);
  static const statusNegativeBg = Color(0xFFFCEEEB);

  // ─────────────────────────────────────────────
  // Label (텍스트)
  // 원본은 rgba — Flutter 에선 withValues 로 표현
  // ─────────────────────────────────────────────
  static const labelNormal = Color(0xFF171717);
  static const labelStrong = Color(0xFF000000);
  // base: rgb(55,56,60) = #37383C
  // const 컨텍스트(위젯 트리)에서 자유롭게 쓰기 위해 알파를 리터럴로 고정
  static const labelNeutral = Color(0xE037383C); // 88%
  static const labelAlternative = Color(0x9C37383C); // 61%
  static const labelAssistive = Color(0x4737383C); // 28%
  static const labelDisable = Color(0x2937383C); // 16%

  // ─────────────────────────────────────────────
  // Background
  // ─────────────────────────────────────────────
  static const backgroundNormal = Color(0xFFFFFFFF);
  static const backgroundAlternative = Color(0xFFF7F7F8);
  static const backgroundElevated = Color(0xFFFFFFFF);

  /// 앱 전체 바탕 — 프로토타입의 크림 톤
  static const backgroundApp = paper;

  // ─────────────────────────────────────────────
  // Line (테두리·구분선)
  // ─────────────────────────────────────────────
  // base: rgb(112,115,124) = #70737C
  static const lineAlternative = Color(0x1470737C); // 8%
  static const lineNeutral = Color(0x2970737C); // 16%
  static const lineNormal = Color(0x3870737C); // 22%
  static const lineStrong = Color(0x8570737C); // 52%

  // ─────────────────────────────────────────────
  // Fill (연한 채움)
  // ─────────────────────────────────────────────
  static const fillAlternative = Color(0x0D70737C); // 5%
  static const fillNormal = Color(0x1470737C); // 8%
  static const fillStrong = Color(0x2970737C); // 16%

  // ─────────────────────────────────────────────
  // Cool neutral scale (원본 그대로)
  // ─────────────────────────────────────────────
  static const neutral10 = Color(0xFF171719);
  static const neutral20 = Color(0xFF292A2D);
  static const neutral30 = Color(0xFF46474C);
  static const neutral40 = Color(0xFF5A5C63);
  static const neutral50 = Color(0xFF70737C);
  static const neutral60 = Color(0xFF878A93);
  static const neutral70 = Color(0xFF989BA2);
  static const neutral80 = Color(0xFFAEB0B6);
  static const neutral90 = Color(0xFFC2C4C8);
  static const neutral95 = Color(0xFFDBDCDF);
  static const neutral97 = Color(0xFFEAEBEC);
  static const neutral98 = Color(0xFFF4F4F5);
  static const neutral99 = Color(0xFFF7F7F8);

  // ─────────────────────────────────────────────
  // 도메인 색상 (면세/과세)
  // ─────────────────────────────────────────────
  /// 생화 = 면세
  static const taxExempt = leaf50;
  static const taxExemptBg = leaf95;

  /// 부자재/식물 = 과세
  static const taxable = rose50;
  static const taxableBg = rose95;
}

/// 간격 — 4px 그리드
class FnSpace {
  FnSpace._();
  static const double x2 = 2;
  static const double x4 = 4;
  static const double x6 = 6;
  static const double x8 = 8;
  static const double x10 = 10;
  static const double x12 = 12;
  static const double x14 = 14;
  static const double x16 = 16;
  static const double x20 = 20;
  static const double x24 = 24;
  static const double x32 = 32;
  static const double x40 = 40;
  static const double x48 = 48;
  static const double x64 = 64;
}

/// 모서리 반경 — 12가 기본
class FnRadius {
  FnRadius._();
  static const double r4 = 4;
  static const double r6 = 6;
  static const double r8 = 8;
  static const double r10 = 10;
  static const double r12 = 12; // ★ 기본
  static const double r14 = 14;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double full = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
  static final br8 = BorderRadius.circular(r8);
  static final br10 = BorderRadius.circular(r10);
  static final br12 = BorderRadius.circular(r12);
  static final br14 = BorderRadius.circular(r14);
  static final br16 = BorderRadius.circular(r16);
  static final br20 = BorderRadius.circular(r20);
  static final brFull = BorderRadius.circular(full);
}

/// 그림자 — 원본 4단계
class FnShadow {
  FnShadow._();

  static const normal = <BoxShadow>[
    BoxShadow(color: Color(0x0F171717), blurRadius: 4, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x12171717), blurRadius: 1),
  ];

  static const emphasize = <BoxShadow>[
    BoxShadow(color: Color(0x1A171717), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x1A171717), blurRadius: 1),
  ];

  static const strong = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x1F000000), blurRadius: 1),
  ];

  static const heavy = <BoxShadow>[
    BoxShadow(color: Color(0x1F000000), blurRadius: 28, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x1F000000), blurRadius: 1),
  ];
}

/// 타이포그래피 — Wanted Design System 스케일
///
/// 원본 CSS 클래스(.wds-*)와 1:1 대응.
class FnType {
  FnType._();

  static const _f = 'Pretendard';

  // Display
  static const display1 = TextStyle(
      fontFamily: _f,
      fontSize: 56,
      height: 72 / 56,
      fontWeight: FontWeight.w700,
      letterSpacing: 56 * -0.0231);
  static const display2 = TextStyle(
      fontFamily: _f,
      fontSize: 40,
      height: 52 / 40,
      fontWeight: FontWeight.w700,
      letterSpacing: 40 * -0.0224);

  // Title
  static const title1 = TextStyle(
      fontFamily: _f,
      fontSize: 36,
      height: 48 / 36,
      fontWeight: FontWeight.w700,
      letterSpacing: 36 * -0.0202);
  static const title2 = TextStyle(
      fontFamily: _f,
      fontSize: 28,
      height: 38 / 28,
      fontWeight: FontWeight.w700,
      letterSpacing: 28 * -0.017);
  static const title3 = TextStyle(
      fontFamily: _f,
      fontSize: 24,
      height: 32 / 24,
      fontWeight: FontWeight.w700,
      letterSpacing: 24 * -0.015);

  // Heading
  static const heading1 = TextStyle(
      fontFamily: _f,
      fontSize: 22,
      height: 30 / 22,
      fontWeight: FontWeight.w700,
      letterSpacing: 22 * -0.012);
  static const heading2 = TextStyle(
      fontFamily: _f,
      fontSize: 20,
      height: 28 / 20,
      fontWeight: FontWeight.w700,
      letterSpacing: 20 * -0.012);

  // Headline
  static const headline1 = TextStyle(
      fontFamily: _f,
      fontSize: 18,
      height: 26 / 18,
      fontWeight: FontWeight.w600,
      letterSpacing: 18 * -0.01);
  static const headline2 = TextStyle(
      fontFamily: _f,
      fontSize: 17,
      height: 24 / 17,
      fontWeight: FontWeight.w600,
      letterSpacing: 17 * -0.01);

  // Body
  static const body1 = TextStyle(
      fontFamily: _f,
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 16 * -0.005);
  static const body1Reading = TextStyle(
      fontFamily: _f,
      fontSize: 16,
      height: 26 / 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 16 * -0.005);
  static const body2 = TextStyle(
      fontFamily: _f,
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w400,
      letterSpacing: 15 * -0.003);
  static const body2Reading = TextStyle(
      fontFamily: _f,
      fontSize: 15,
      height: 24 / 15,
      fontWeight: FontWeight.w400,
      letterSpacing: 15 * -0.003);

  // Label
  static const label1 = TextStyle(
      fontFamily: _f, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600);
  static const label1Normal = TextStyle(
      fontFamily: _f, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400);
  static const label2 = TextStyle(
      fontFamily: _f, fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w600);

  // Caption
  static const caption1 = TextStyle(
      fontFamily: _f, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400);
  static const caption2 = TextStyle(
      fontFamily: _f, fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w400);

  /// 숫자 강조용 (금액)
  static const numberLarge = TextStyle(
      fontFamily: _f,
      fontSize: 28,
      height: 36 / 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5);
}

/// 애니메이션 지속시간
class FnDuration {
  FnDuration._();
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
}
