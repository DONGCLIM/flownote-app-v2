import 'package:flutter/material.dart';

/// FlowNote 통합 디자인 기준 (사장님 확정, #166).
///
/// ## 이 파일의 역할
///
/// 지금까지 토큰이 여섯 군데(`FnColors` / `FnHome` / `FnSignup` /
/// `FnScan` / `FnProfile` / `FnSpace`·`FnRadius`)에 흩어져 있었다.
/// 같은 코랄이 여덟 가지, 크림 배경이 세 가지였다.
/// 앞으로 만드는 화면과, 개편하며 옮기는 화면은 **이 파일 하나만** 본다.
///
/// ## 🔴 지금은 아무 화면도 이 파일을 쓰지 않는다
///
/// 사장님이 "기준 파일만 먼저" 라고 하셨다. 기존 화면은 사장님이
/// 개편하실 때 하나씩 옮긴다. 그래서 이 파일을 추가해도 화면은
/// 하나도 바뀌지 않는다.
///
/// ## 🔴 구 화면은 건드리지 않는다
///
/// `lib/screens/*.dart` (ds 폴더 밖)는 이 기준의 대상이 아니다.
/// 옮기지도, 고치지도 않는다.
///
/// ## 옮길 때 대응표
///
/// | 예전 | 지금 |
/// |---|---|
/// | `FnColors.rose50` `#EE7686` | `FnDs.coral` `#FF6D78` |
/// | `FnHome.coral` `#FF6E78` | `FnDs.coral` |
/// | `FnScan.coralBtn` `#E9777F` | `FnDs.coral` |
/// | `FnHome.bg` `#FFF9F6` | `FnDs.bg` `#FEF9F5` |
/// | `FnColors.backgroundApp` `#FFFCFA` | `FnDs.bg` |
/// | 좌우 여백 16 / 18.3 / 20 / 21.6 | `FnDs.pagePad` 24 |
/// | 버튼 48 / 50 / 54 / 56 / 57 / 66 | `FnDs.buttonH` 52 |
/// | 카드 모서리 20 / 22 | `FnDs.cardRadius` 18 |
/// | 카드 테두리 | **없앤다** — `FnDs.cardShadow` 로 |
/// | `₩0` 표기 | `FnDs.won()` → `0원` |
class FnDs {
  FnDs._();

  // ── 색: 메인 ───────────────────────────────────────────────
  /// 메인 코랄. 버튼, 배지, 토글 켜짐, 강조 숫자.
  ///
  /// 🔴 이제 코랄은 이것 하나다. 화면마다 다른 코랄을 새로 만들지 않는다.
  static const Color coral = Color(0xFFFF6D78);

  /// 눌렀을 때 / 진한 변형. 코랄을 검정 쪽으로 12% 민 값.
  static const Color coralPressed = Color(0xFFE0606A);

  /// 아주 연한 코랄 바탕. 선택된 칩, 강조 영역 바탕.
  static const Color coralFaint = Color(0xFFFFF1EE);

  // ── 색: 면 ────────────────────────────────────────────────
  /// 페이지 배경.
  static const Color bg = Color(0xFFFEF9F5);

  /// 카드 / 입력창 바탕.
  static const Color card = Color(0xFFFFFFFF);

  // ── 색: 글자 ───────────────────────────────────────────────
  /// 제목.
  static const Color title = Color(0xFF171717);

  /// 본문.
  static const Color body = Color(0xFF545454);

  /// 보조 — 설명, 날짜, 단위.
  static const Color sub = Color(0xFF8E8E93);

  /// 코랄 바탕 위 글자.
  static const Color onCoral = Color(0xFFFFFFFF);

  // ── 색: 선 ────────────────────────────────────────────────
  /// 카드 안 구분선.
  static const Color hair = Color(0xFFEAEAEA);

  /// 입력창 테두리 (평소).
  static const Color line = Color(0xFFE6E5E1);

  /// 목록 오른쪽 화살표.
  static const Color chevron = Color(0xFF999999);

  // ── 색: 상태 ───────────────────────────────────────────────
  /// 성공 · 면세(생화).
  static const Color positive = Color(0xFF86B06B);
  static const Color positiveBg = Color(0xFFEFF5E7);

  /// 경고.
  static const Color caution = Color(0xFFE0A45C);
  static const Color cautionBg = Color(0xFFFCF4E6);

  /// 오류 · 위험.
  static const Color negative = Color(0xFFE8697B);
  static const Color negativeBg = Color(0xFFFCEEEB);

  // ── 여백 ──────────────────────────────────────────────────
  /// 화면 좌우 여백. 모든 화면 공통.
  static const double pagePad = 24.0;

  /// 간격 단계. 이 값들 사이의 숫자를 새로 만들지 않는다.
  static const double gap2xs = 4.0;
  static const double gapXs = 8.0;
  static const double gapS = 12.0;
  static const double gapM = 16.0;
  static const double gapL = 24.0;
  static const double gapXl = 32.0;

  // ── 글자 크기 ──────────────────────────────────────────────
  //
  // 현재 화면들이 실제로 쓰는 값만 남겼다. 예전 `FnType` 의
  // display(56·40) / title(36·28) 은 어느 화면도 쓰지 않아 뺐다.
  static const double fontXs = 12.0; // 날짜, 배지, 각주
  static const double fontS = 13.5; // 목록 한 줄, 설명, 묶음 라벨
  static const double fontM = 15.0; // 본문
  static const double fontL = 16.0; // 버튼, 목록 제목, 소제목
  static const double fontXl = 19.0; // 화면 제목
  static const double font2xl = 24.0; // 금액 강조

  /// 글꼴. 이 앱은 Pretendard 하나만 쓴다.
  static const String font = 'Pretendard';

  // ── 글자 모양 (바로 쓰는 완성형) ─────────────────────────────
  static const TextStyle tsTitle = TextStyle(
      fontFamily: font,
      fontSize: fontXl,
      fontWeight: FontWeight.w700,
      color: title);
  static const TextStyle tsSection = TextStyle(
      fontFamily: font,
      fontSize: fontL,
      fontWeight: FontWeight.w700,
      color: title);
  static const TextStyle tsRow = TextStyle(
      fontFamily: font,
      fontSize: fontS,
      fontWeight: FontWeight.w600,
      color: title);
  static const TextStyle tsBody = TextStyle(
      fontFamily: font, fontSize: fontM, height: 1.45, color: body);
  static const TextStyle tsSub = TextStyle(
      fontFamily: font, fontSize: fontXs, height: 1.4, color: sub);
  static const TextStyle tsAmount = TextStyle(
      fontFamily: font,
      fontSize: font2xl,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: title);

  // ── 버튼 ──────────────────────────────────────────────────
  /// 메인 버튼 높이.
  static const double buttonH = 52.0;

  /// 메인 버튼 모서리.
  static const double buttonRadius = 14.0;

  /// 버튼 글자.
  static const double buttonFont = fontL;
  static const FontWeight buttonWeight = FontWeight.w700;

  /// 꺼진 버튼 바탕 / 글자.
  static const Color buttonOffBg = Color(0xFFE5E5E5);
  static const Color buttonOffFg = Color(0xFF9A9A9A);

  /// 메인 버튼 꾸밈.
  static BoxDecoration buttonFilled({bool enabled = true}) => BoxDecoration(
        color: enabled ? coral : buttonOffBg,
        borderRadius: BorderRadius.circular(buttonRadius),
      );

  /// 보조 버튼 — 흰 바탕 + 코랄 테두리.
  static BoxDecoration buttonOutlined() => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(buttonRadius),
        border: Border.all(color: coral, width: 1.4),
      );

  /// 글자만 있는 버튼은 배경·테두리가 없다. 색은 [coral] 또는 [sub].

  // ── 카드 ──────────────────────────────────────────────────
  /// 카드 모서리.
  static const double cardRadius = 18.0;

  /// 카드 안쪽 여백.
  static const double cardPad = 20.0;

  /// 카드 그림자. 연하게 한 겹만.
  ///
  /// 🔴 카드에 테두리를 같이 두르지 않는다. 그림자와 테두리를 함께 쓰면
  ///    가장자리가 두 번 보여서 지저분해진다. 예전 화면들이 테두리파와
  ///    그림자파로 갈려 있던 것을 그림자 쪽으로 통일한다.
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 4)),
  ];

  /// 카드 꾸밈.
  static BoxDecoration cardDeco() => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(cardRadius),
        boxShadow: cardShadow,
      );

  // ── 입력창 ─────────────────────────────────────────────────
  /// 입력창 높이.
  static const double inputH = 48.0;

  /// 입력창 모서리.
  static const double inputRadius = 12.0;

  /// 입력창 좌우 안쪽 여백.
  static const double inputPadH = 14.0;

  /// 입력창 글자 / 안내 글자 색.
  static const double inputFont = fontM;
  static const Color inputHint = Color(0xFF7D7D7D);

  /// 입력창 테두리 두께.
  static const double inputBorderW = 1.0;

  /// 입력창 테두리. 상태에 따라 색만 바뀐다.
  static OutlineInputBorder inputBorder({
    bool focused = false,
    bool error = false,
  }) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: BorderSide(
          color: error ? negative : (focused ? coral : line),
          width: focused || error ? 1.4 : inputBorderW,
        ),
      );

  // ── 금액 ──────────────────────────────────────────────────
  /// 금액 표기. 세 자리마다 쉼표 + `원`.
  ///
  /// 🔴 `₩` 기호를 쓰지 않는다. 예전에는 홈·캘린더가 `₩0`,
  ///    내역·정산서가 `0원` 이라 같은 금액이 두 모습으로 보였다.
  ///    앞으로는 어느 화면이든 이 함수만 쓴다.
  ///
  /// ```
  /// FnDs.won(0)        // '0원'
  /// FnDs.won(1234567)  // '1,234,567원'
  /// FnDs.won(-5000)    // '-5,000원'
  /// FnDs.won(1200.7)   // '1,201원'  (반올림)
  /// ```
  static String won(num value) => '${comma(value)}원';

  /// 단위 없이 숫자만. 표 안에서 `원` 을 머리글로 뺄 때 쓴다.
  static String comma(num value) {
    final n = value.round();
    final neg = n < 0;
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return neg ? '-$b' : b.toString();
  }

  // ── 기타 ──────────────────────────────────────────────────
  /// 켜짐/꺼짐 토글. 알림 설정과 같은 모양.
  static const double toggleW = 44.0;
  static const double toggleH = 25.0;
  static const Color toggleOff = Color(0xFFE5E5E5);

  /// 목록 한 줄 높이.
  static const double rowH = 52.0;

  /// 애니메이션 길이.
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 250);
}
