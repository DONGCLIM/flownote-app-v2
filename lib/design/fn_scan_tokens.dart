import 'package:flutter/widgets.dart';

/// 스캔 4화면 시안 토큰 — 사장님이 주신 네 장을 **픽셀 단위로 실측**한 값.
///
/// 시안 원본
///   갤러리     473x1024  (환산 1.2036 px/dp)
///   영수증 촬영 473x1024  (환산 1.2036 px/dp)
///   인식 중     473x1024  (환산 1.2036 px/dp)
///   결과 확인   440x1024  (환산 1.1196 px/dp)
///
/// 측정 방법은 홈/가입 토큰과 같다. 배경색을 빼고 남는 픽셀의
/// 행·열 밴드를 뽑아 경계를 잡은 뒤 dp 로 환산했다.
///
/// ⚠️ 흰색(#FFFFFF)과 페이지 배경(#FEF9F5)의 채널 합 차이는 **17** 밖에
///    안 된다. 임계값을 18 이상으로 두면 흰 영역이 배경으로 오판되어
///    타일 폭이 들쑥날쑥해진다. 실측 때 임계값 6 을 썼다.
class FnScan {
  FnScan._();

  // ───────────────────────── 공통 ─────────────────────────

  /// 페이지 배경. 네 장 중 세 장의 최빈색이 정확히 이 값이다.
  /// (홈 `FnHome.bgWarm`, 가입 `FnSignup.bg` 와 같은 값)
  static const Color bg = Color(0xFFFEF9F5);

  /// 카메라 화면만 어둡다. 실측 `rgb(23,23,23)`.
  static const Color camBg = Color(0xFF171717);

  /// 카드/버튼 흰색.
  static const Color card = Color(0xFFFFFFFF);

  /// 제목·본문 진한 글자. 실측 `rgb(26,26,26)` 부근.
  static const Color ink = Color(0xFF1A1A1A);

  /// 보조 글자(회색). 비활성 버튼 글자와 같은 톤.
  static const Color muted = Color(0xFFA2A2A2);

  /// 표 머리글·단위 라벨 회색.
  static const Color sub = Color(0xFF8E8E93);

  /// 코랄 강조. 진행바 채움 실측 `rgb(251,111,122)`.
  static const Color coral = Color(0xFFFB6F7A);

  /// 코랄 버튼 면. 실측 `rgb(233,119,127)`.
  static const Color coralBtn = Color(0xFFE9777F);

  /// 진행바 트랙. 실측 `rgb(255,227,223)`.
  static const Color track = Color(0xFFFFE3DF);

  /// 카드 밑 그림자 — 시안은 아주 옅다.
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  // ───────────────────────── 갤러리 ─────────────────────────

  /// 페이지 좌우 여백. 하단 버튼 실측 26px/1.2036 = 21.6dp.
  /// 사진 타일의 좌측(48px)은 **사진이 타일 안에서 contain 되어 생긴
  /// 여백** 때문이지 페이지 여백이 아니다. 헷갈리지 말 것.
  static const double galPad = 21.6;

  /// 3열 그리드. 실측 pitch 142px(118.0dp) 에서 역산한 조합이
  /// 여백 26px·간격 5px·타일 137px 일 때 정확히 맞아떨어진다.
  static const int galCols = 3;

  /// 타일 사이 가로 간격.
  static const double galGapX = 4.2;

  /// 타일 사이 세로 간격. 행 pitch 180px - 타일 171px = 9px.
  static const double galGapY = 7.5;

  /// 타일 가로/세로 비율. 실측 137x171px → 0.80.
  static const double galTileAspect = 0.80;

  /// 선택 동그라미 지름. 실측 23px/1.2036 = 19.1dp.
  static const double galCheck = 19.1;

  /// 동그라미를 타일 모서리에서 띄우는 거리.
  static const double galCheckInset = 7.0;

  /// '최근 항목' 줄의 글자 크기.
  static const double galSectionSize = 15.0;

  /// 하단 '선택 완료' 버튼 높이. 실측 y561-640 중 버튼 몸통 ≈ 52dp.
  static const double galBtnH = 52.0;

  /// 하단 버튼 모서리.
  static const double galBtnRadius = 16.0;

  // ───────────────────────── 인식 중 ─────────────────────────

  /// 좌우 여백. 카드와 버튼 모두 22px/1.2036 = 18.3dp.
  static const double procPad = 18.3;

  /// 진행 카드 높이. 실측 y635-745 = 110px → 91.4dp.
  static const double procCardH = 91.4;

  /// 진행 카드 모서리.
  static const double procCardRadius = 18.0;

  /// CTA 버튼 높이. 실측 y752-831 = 79px → 65.6dp 중 몸통 ≈ 56dp.
  static const double procBtnH = 56.0;

  /// CTA 버튼 모서리.
  static const double procBtnRadius = 16.0;

  /// 진행바 두께.
  static const double procBarH = 8.0;

  // ───────────────────────── 결과 확인 ─────────────────────────

  /// 사진 카드 좌우 여백. 실측 25px/1.1196 = 22.3dp.
  static const double resPhotoPad = 22.3;

  /// 사진 카드 높이. 실측 y141-464 = 323px → 288.5dp.
  static const double resPhotoH = 288.5;

  /// 사진 카드 모서리.
  static const double resPhotoRadius = 18.0;

  /// 흰 정보 카드 좌우 여백. 실측 21px/1.1196 = 18.8dp.
  static const double resCardPad = 18.8;

  /// 흰 정보 카드 모서리.
  static const double resCardRadius = 20.0;

  /// 줌 알약 높이. 실측 43.8dp 중 몸통 ≈ 40dp.
  static const double resZoomH = 40.0;

  /// 줌 알약을 사진 카드 바닥에서 띄우는 거리.
  static const double resZoomBottom = 14.0;

  /// 줌 알약 배경(반투명 검정).
  static const Color resZoomBg = Color(0xCC000000);

  /// 하단 버튼 높이.
  static const double resBtnH = 52.0;

  /// 하단 버튼 모서리.
  static const double resBtnRadius = 14.0;

  /// 하단 버튼 사이 간격. 실측 214-220px → 5.4dp.
  static const double resBtnGap = 5.4;
}
