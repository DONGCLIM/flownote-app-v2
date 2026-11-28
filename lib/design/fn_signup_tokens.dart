import 'package:flutter/material.dart';

/// 🔴 #155 — 회원가입(이메일 단계) 시안 토큰.
///
/// 사장님이 준 시안 4장(473x1024)을 픽셀 단위로 실측해 뽑은 값이다.
/// 추정하지 않았다. 측정 방법과 원본 수치를 아래에 남긴다.
///
/// ## 배율
/// 시안 폭 473px 을 논리폭 375dp(iPhone 기준)로 보면 배율은
/// `473 / 375 = 1.26133` 이고, 이때 주요 값이 **정수로 떨어진다**.
///
/// | 항목 | 시안 px | ÷1.26133 | 채택 |
/// |---|---|---|---|
/// | 좌우 여백 | 31 | 24.58 | **24** |
/// | 본문 폭 | 411 | 325.85 | (여백에서 유도) |
/// | 입력창 높이 | 59 | 46.78 | **47** |
/// | 버튼 높이 | 63 | 49.95 | **50** |
/// | 카드 높이 | 106 | 84.04 | **84** |
///
/// 390dp·393dp 로 보면 48.65 / 49.02 처럼 어중간한 값이 나와서 375dp 로
/// 확정했다. ⚠️ 이 배율을 바꾸면 모든 수치가 흔들린다.
///
/// ## 색 (실측, 추정 아님)
/// 네 장 모두 배경 최빈색이 `#FEF9F5`, 코랄이 `#FF6D78` 로 나왔고 이는
/// 기존 홈 토큰 `FnHome.bgWarm` / `FnHome.coralFlat` 과 **정확히 같다**.
/// 즉 같은 디자인 시스템이다. 그래서 색은 새로 만들지 않고 재사용한다.
///
/// 나머지 실측치:
/// - 헤드라인 `#141210`
/// - 부제 / 필드 라벨 `#575350`
/// - 플레이스홀더 `#7D7D7D`
/// - 입력창 테두리 `#E6E5E1` (1px)
/// - 비활성 버튼 바탕 `#E5E5E5`, 글자 `#737373`
/// - 카드 라벨/값 `#515151` / `#545454`
class FnSignup {
  const FnSignup._();

  // ── 레이아웃 ────────────────────────────────────────────────

  /// 좌우 여백. 시안 x=31px ÷ 1.26133 = 24.58
  static const double pagePad = 24.0;

  /// 헤드라인 첫 줄 위 여백. 시안 y=171px → 135.6dp.
  /// 앱바(56) 를 뺀 본문 기준 오프셋으로 쓴다.
  static const double headlineTop = 80.0;

  /// 헤드라인 두 줄 사이. 시안 171→212 = 41px ÷ 1.26133 = 32.5
  /// 글자 20.6dp 에 대해 height 1.38 로 맞춘다.
  static const double headlineSize = 21.0;
  static const double headlineHeight = 1.38;

  /// 부제. 시안 y=265px(210.1dp), 글자 높이 11.1dp.
  static const double subtitleSize = 13.5;

  /// 헤드라인 아래 ~ 부제 위. 237→265 = 28px → 22.2dp
  static const double gapHeadlineToSub = 14.0;

  /// 부제 아래 ~ 필드 라벨 위. 278→323 = 45px → 35.7dp
  static const double gapSubToLabel = 30.0;

  /// 필드 라벨. 시안 글자 높이 11.1dp.
  static const double labelSize = 13.5;

  /// 라벨 아래 ~ 입력창 위. 336→354 = 18px → 14.3dp
  static const double gapLabelToField = 10.0;

  /// 입력창 높이. 시안 59px ÷ 1.26133 = 46.78
  static const double fieldHeight = 47.0;

  /// 입력창 모서리. 시안 코너 inset 이 10행에서 0 → 약 10px → 7.9dp
  static const double fieldRadius = 8.0;

  /// 입력창 글자 좌여백. 시안 x=49px, 박스 x=31px → 18px → 14.3dp
  static const double fieldPadH = 14.0;

  /// 입력창 글자 크기. 시안 11.1dp.
  static const double fieldTextSize = 14.5;

  /// 입력창 아래 ~ 버튼 위 (정상). 412→450 = 38px → 30.1dp
  static const double gapFieldToButton = 30.0;

  /// 오류문 글자. 시안 s3 y=417 영역, 8.7dp 안팎.
  static const double errorSize = 11.5;

  /// 입력창 아래 ~ 오류문 위. 411→417 = 6px → 4.8dp
  static const double gapFieldToError = 6.0;

  /// 오류문 아래 ~ 버튼 위. 시안 s3 에서 버튼이 479 부터 → 약 22.2dp
  static const double gapErrorToButton = 16.0;

  /// 버튼 높이. 시안 63px ÷ 1.26133 = 49.95
  static const double buttonHeight = 50.0;

  /// 버튼 모서리. 시안 코너 inset 이 12행에서 0 → 약 14px → 11.1dp
  static const double buttonRadius = 11.0;

  /// 버튼 글자.
  static const double buttonTextSize = 15.0;

  /// 버튼 사이 간격(4번 화면). 522→546 = 24px → 19.0dp
  static const double gapBetweenButtons = 12.0;

  // ── 가입된 이메일 카드 (4번 화면) ──────────────────────────

  /// 카드 높이. 시안 106px ÷ 1.26133 = 84.04
  static const double cardHeight = 84.0;

  /// 카드 모서리. 시안 코너 inset 이 21행 부근까지 이어짐 → 약 22px → 17.4dp
  static const double cardRadius = 18.0;

  /// 카드 안쪽 좌여백. 시안 글자 x=55px, 카드 x=29px → 26px → 20.6dp
  static const double cardPadH = 20.0;

  /// 카드 라벨 / 값 글자 크기. 시안 11.9dp / 8.7dp 역전은 안티앨리어싱
  /// 때문이고, 실제로는 라벨이 작고 값이 크다(시각 확인).
  static const double cardLabelSize = 12.5;
  static const double cardValueSize = 14.5;

  /// 라벨과 값 사이. 361→383 = 22px → 17.4dp
  static const double cardGap = 8.0;

  /// 부제 아래 ~ 카드 위(4번 화면). 278→318 = 40px → 31.7dp
  static const double gapSubToCard = 26.0;

  /// 카드 아래 ~ 첫 버튼 위. 423→460 = 37px → 29.3dp
  static const double gapCardToButton = 24.0;

  // ── 색 (전부 실측) ─────────────────────────────────────────

  /// 페이지 배경. 네 장 모두 최빈색 `#FEF9F5`.
  static const Color bg = Color(0xFFFEF9F5);

  /// 활성 버튼 / 오류 강조 코랄. 실측 `#FF6D78`.
  static const Color coral = Color(0xFFFF6D78);

  /// 헤드라인. 실측 `#141210`.
  static const Color headline = Color(0xFF141210);

  /// 부제 · 필드 라벨. 실측 `#575350`.
  static const Color subtle = Color(0xFF575350);

  /// 플레이스홀더. 실측 `#7D7D7D`.
  static const Color placeholder = Color(0xFF7D7D7D);

  /// 입력창 테두리. 실측 `#E6E5E1`.
  static const Color fieldBorder = Color(0xFFE6E5E1);

  /// 비활성 버튼 바탕 / 글자. 실측 `#E5E5E5` / `#737373`.
  static const Color disabledFill = Color(0xFFE5E5E5);
  static const Color disabledFg = Color(0xFF737373);

  /// 카드 라벨 / 값. 실측 `#515151` / `#545454`.
  static const Color cardLabel = Color(0xFF515151);
  static const Color cardValue = Color(0xFF545454);

  /// 입력창 테두리 두께 (평상시 / 오류).
  static const double fieldBorderWidth = 1.0;
  static const double fieldBorderWidthError = 1.4;

  // ── 🔴 #156 비밀번호 단계 / 인증 / 완료 (시안 5장 실측) ──────
  //
  // | 항목 | 시안 px | ÷1.26133 | 채택 |
  // |---|---|---|---|
  // | 1차 입력창 top | 354 | 280.7 | (#155 와 동일) |
  // | 2차 입력창 top | 475 | 376.6 | 간격 50 |
  // | 2차 라벨(오류시) | 473 | 375.0 | — |
  // | p3 버튼 top | 630 | 499.5 | — |
  // | 워드마크 | 244x41 | 193.4x32.5 | 높이 32 |
  //
  // 워드마크 비율 실측 5.951 은 기존 자산(971/163 = 5.957)과 0.1% 차이라
  // `FnBrand.wordmarkRatio` 를 그대로 쓴다. 꽃잎이 코랄이므로 `color: true`.

  /// 입력창 두 개 사이 간격. 1차 아래(412) → 2차 라벨(444) = 32px → 25.4dp
  static const double gapFieldToLabel2 = 24.0;

  /// 비밀번호 단계 버튼 높이. 시안 64px ÷ 1.26133 = 50.74
  /// (#155 의 63px→49.95 와 사실상 같다. 같은 값으로 통일한다.)
  static const double gapField2ToButton = 30.0;

  /// 완료 화면 워드마크 높이. 시안 41px ÷ 1.26133 = 32.5
  static const double doneWordmarkHeight = 32.0;

  /// 완료 화면 워드마크 아래 ~ 헤드라인. 465→514 = 49px → 38.8dp
  static const double gapWordmarkToHeadline = 34.0;

  /// 휴대폰 인증 화면: 부제 두 줄 아래 ~ 버튼. 302→343 = 41px → 32.5dp
  static const double gapSubToVerifyButton = 30.0;

  /// 보조(두 번째) 버튼 — 완료 화면의 '사업자등록증 등록하기'.
  ///
  /// 🔴 시안에는 코랄 버튼 하나뿐이고 사장님이 "다른 컬러로" 요청하셨다.
  ///    코랄 연보라/연회색은 톤이 깨지므로, 같은 코랄 계열의 **연한 배경 +
  ///    코랄 글자** 로 간다. 배경은 코랄을 8% 로 깐 값이다.
  static const Color secondaryFill = Color(0x14FF6D78);
  static const Color secondaryFg = Color(0xFFE85C68);

  // ── 🔴 #157 사업자등록증 등록 흐름 (시안 5장 실측) ──────────
  //
  // 🔴 b4(정보 확인)만 시안 폭이 **388px** 이고 나머지는 473px 이다.
  //    배율을 따로 계산해야 한다: 388/375 = 1.03467
  //    그렇게 환산하니 입력창 47.4dp, 버튼 49.3dp 로 다른 화면과 정확히
  //    맞아떨어져 375dp 기준이 교차검증됐다.
  //
  // | 항목 | 시안 | 환산 | 채택 |
  // |---|---|---|---|
  // | b1 버튼1 top | 585px/473 | 463.8dp | — |
  // | b1 버튼2(외곽선) | 671px | 532.0dp | 간격 19 → 12 |
  // | b3 진행바 높이 | 7px | 5.5dp | **6** |
  // | b3 진행바 채움 | 0.739 | — | 80% 표기와 맞음 |
  // | b4 입력칸 간격 | 96px/388 | 92.8dp | 라벨+칸+여백 |
  // | b5 체크카드 | 188px | 149.0dp | — |
  //
  // 색 실측
  // - 진행바 트랙 `#FFE4DB`
  // - 카드 그림자: 카드 아래 10px 가 `#EDE9E6` 까지 어두워진다 → 아주 연함
  // - b5 체크 아이콘은 코랄

  /// 진행바 높이. 시안 7px ÷ 1.26133 = 5.55
  static const double progressHeight = 6.0;

  /// 진행바 트랙(안 채워진 부분). 실측 `#FFE4DB`.
  static const Color progressTrack = Color(0xFFFFE4DB);

  /// 카드 그림자 — 시안에서 카드 아래 약 10px 가 `#EDE9E6` 까지 내려간다.
  /// 진하게 넣으면 시안보다 떠 보이므로 아주 연하게 간다.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 12,
      offset: Offset(0, 3),
    ),
  ];

  /// b4 필수 표시 `*` 와 안내문 색 (코랄과 같다).
  static const Color requiredMark = coral;

  /// b4 각 입력 묶음 사이 간격. 시안 96px ÷ 1.03467 = 92.8
  /// (라벨 11.6 + 간격 + 칸 47.4 를 빼면 순수 여백은 약 22dp)
  static const double gapBetweenFieldGroups = 22.0;

  /// b5 체크 목록 줄 간격. 시안 39px ÷ 1.26133 = 30.9
  static const double checkRowGap = 18.0;

  /// b5 체크 아이콘 크기.
  static const double checkIconSize = 16.0;
}
