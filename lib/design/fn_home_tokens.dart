import 'package:flutter/material.dart';

/// #135 홈 시안(PNG) 실측 토큰.
///
/// 시안 원본 334x1024 에서 검은 기기 프레임을 걷어낸 316x1009 을 기준으로
/// 재측정했다. 가로 316px 가 390dp 이므로 환산비는 **1.2342**.
/// 아래 값은 전부 그 환산을 거친 dp / 샘플링한 실제 픽셀값이다.
///
/// | 항목            | 실측                                   |
/// |-----------------|----------------------------------------|
/// | 페이지 배경      | #FFF9F6                                |
/// | 카드 배경        | #FFFFFF (전체의 35.6%)                  |
/// | 카드 좌우 여백   | 19.7dp (좌/우 동일)                     |
/// | 코랄 카드        | #FF6E78 → #FFAC92 대각, r 19.5dp        |
/// | 막대             | #FFD4C2, 폭 27.2dp, 간격 24.7dp         |
/// | 강조 막대        | 폭 42.0dp, 코랄 그라디언트               |
/// | 누적 바          | 높이 13.6dp                             |
class FnHome {
  const FnHome._();

  // ── 바탕 ────────────────────────────────────────────────────────────
  /// 페이지 배경 — 시안 전체의 21.3% 를 차지하는 따뜻한 크림.
  static const Color bg = Color(0xFFFFF9F6);

  /// 카드 배경 — 시안 전체의 35.6%.
  static const Color card = Color(0xFFFFFFFF);

  /// 카드 테두리 — 시안에는 또렷한 선이 없고 아주 옅은 음영만 있다.
  static const Color cardLine = Color(0x14C9A79B);

  // ── 코랄 ────────────────────────────────────────────────────────────
  /// 그라디언트 시작(좌상). 시안 3.6% 를 차지하는 대표색.
  static const Color coral = Color(0xFFFF6E78);

  /// 그라디언트 끝(우하). 좌상에서 우하로 내려가며 살구빛으로 번진다.
  static const Color coralEnd = Color(0xFFFFAC92);

  /// 강조 글자 — "55% 권장", "7월", 칩 글자에서 공통으로 뽑힌 값.
  static const Color coralText = Color(0xFFE8555E);

  /// 연한 살구 — 비강조 막대 / 칩 배경.
  static const Color peach = Color(0xFFFFD4C2);

  /// 칩·팁 카드 배경.
  static const Color coralFaint = Color(0xFFFFF1EE);

  // ── 글자 ────────────────────────────────────────────────────────────
  /// 제목 — 시안에서 뽑힌 가장 진한 본문색.
  static const Color title = Color(0xFF171717);

  /// 본문 — 가이드 부제 / 팁 본문.
  static const Color body = Color(0xFF545454);

  /// 보조 — "상세 분석 보기", "권장 사입 주기" 같은 라벨.
  static const Color muted = Color(0xFFA3A3A3);

  /// 차트 x축 라벨.
  static const Color axis = Color(0xFF525252);

  // ── 품목 비중 스택 ──────────────────────────────────────────────────
  /// 절화(꽃) / 부자재 / 화분·식물 / 기타 순.
  static const List<Color> stack = [
    Color(0xFFFFA38B),
    Color(0xFFFFD4C2),
    Color(0xFFFFE4DE),
    Color(0xFFF5C872),
  ];

  // ── 치수 (dp) ───────────────────────────────────────────────────────
  /// 카드 좌우 여백. 시안 좌 19.7 / 우 19.7 로 완전히 대칭이었다.
  static const double pagePad = 20;

  /// 카드 사이 세로 간격.
  static const double gap = 14;

  /// 일반 카드 반경. 원호 맞춤 RMS 1.25px.
  static const double radius = 22;

  /// 코랄 카드 반경. 원호 맞춤 RMS 0.34px — 시안에서 가장 또렷한 값.
  static const double coralRadius = 20;

  /// 막대 폭 / 간격 / 강조 막대 폭.
  static const double barW = 27;
  static const double barGap = 25;
  static const double barActiveW = 42;

  /// 막대 100% 기준 높이. 48/56/60/72/64% 다섯 개에서 역산한 평균 151.0dp 를
  /// 화면에 들어가도록 0.62 로 줄여 썼다. (비율은 그대로 유지)
  static const double barFull = 94;

  /// 품목 비중 누적 바 높이.
  static const double stackH = 13;

  /// 그라디언트 방향 — 시안 네 모서리 샘플이 좌상(#FF6E78) 우상(#FF7B7E)
  /// 좌하(#FF9C8B) 우하(#FFAA91) 로, 세로 성분이 가로보다 약 2배 강했다.
  static const Gradient coralGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [coral, coralEnd],
  );

  // ── #136 스캔 시안에서 추가 실측 ────────────────────────────────────
  //
  // 스캔 시안은 473x1024 (환산비 0.8245) 로 로그인 시안과 같은 규격이고,
  // 배경·코랄이 로그인 화면과 **완전히 같은 색**이었다.
  //   페이지 배경 #FEF9F5 (37.8%) / 흰 카드 #FFFFFF (24.7%) / 코랄 #FF6D78 (3.2%)
  // 그래서 홈(#FFF9F6)과 아주 미세하게 다른 이 값을 따로 둔다.

  /// 로그인·스캔 시안의 페이지 배경. 홈(#FFF9F6)보다 한 톤 더 따뜻하다.
  static const Color bgWarm = Color(0xFFFEF9F5);

  /// 로그인·스캔 시안의 코랄 단색 버튼. (홈 그라디언트 시작값과 1 차이)
  static const Color coralFlat = Color(0xFFFF6D78);

  /// 테두리 없는 보조 버튼 배경 — 스캔 시안 '앨범에서 가져오기'.
  static const Color surfaceSoft = Color(0xFFFEFDFB);

  /// 스캔 팁 카드의 번호 색 (01 / 02 / 03).
  static const Color tipIndex = Color(0xFFC76769);

  /// 팁 설명 글자색.
  static const Color tipDesc = Color(0xFF55514E);

  /// 스캔 시안 치수.
  /// 팁 카드 좌우 여백 23.9dp · r 14.2dp
  /// 버튼 높이 52.8 / 54.4dp — 둘 다 알약(모서리 = 높이/2)
  static const double scanPad = 24;
  static const double tipRadius = 14;
  static const double buttonH = 54;
}
