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

  // ── #137 스캔 시안 재실측 (473x1024, 환산비 0.8245) ──────────────
  //
  // 떠 있는 탭바:
  //   y 738.8..809.7dp (높이 70.9)   <- 최하단 행 기준
  //   x 9.9..379.3dp   (좌우 9.9 대칭)
  //   화면 바닥까지 34.6dp 떠 있다.  <- 전에는 10dp 만 띄워서 붙어 보였다
  //   최대폭 행(y 747.0): x 22.3..366.9 -> 모서리 반경이 크다
  //
  // 앨범 버튼: y 659.6..716.5dp (높이 56.9)

  /// 떠 있는 탭바 높이.
  static const double tabBarH = 71;

  /// 떠 있는 탭바 좌우 여백.
  static const double tabBarSide = 10;

  /// 떠 있는 탭바가 화면 바닥에서 떠 있는 거리.
  ///
  /// 🔴 전에는 `bottomInset > 0 ? bottomInset : 10` 이었다. 홈 인디케이터가
  ///    없는 환경(웹·구형 안드로이드)에서는 10dp 만 띄워서 탭바가 화면
  ///    아래에 붙어 보였다. 라이브 실측 10.0dp vs 시안 34.6dp.
  static const double tabBarBottom = 34;

  /// 떠 있는 탭바 모서리 반경.
  static const double tabBarRadius = 28;

  /// 앨범 버튼(흰 알약) 높이. 시안 56.9dp.
  static const double buttonH2 = 57;

  // ── #143 탭바 활성 알약 실측 (시안 352x1024, 환산비 1.108) ──────
  //
  //   탭바      y 1042.6..1114.6dp (h 72.0)  x 11.1..377.8
  //   활성 알약  x  88.6..158.4dp (w 69.8)   y 1052.6..1105.7 (h 53.2)
  //   알약 색   #FEF0EF
  //
  // 🔴 지금까지 활성 탭은 **글자·아이콘 색만** 코랄이었다.
  //    시안에는 활성 탭 뒤에 연분홍 알약이 깔려 있다.

  /// 탭바 활성 탭 뒤 알약 색. 시안 #FEF0EF.
  static const Color tabPill = Color(0xFFFEF0EF);

  /// 탭바 활성 알약 폭. 시안 69.8dp.
  static const double tabPillW = 70;

  /// 탭바 활성 알약 높이. 시안 53.2dp.
  static const double tabPillH = 53;

  // ── #146 홈 시안 재실측 (334x1024 -> 검은 프레임 걷은 316x1009, 환산비 1.2342)
  //
  // 🔴 사장님 지적: "카드마다 컬러도 다르고 그림자 효과도 들어가 있다"
  //    실제로 맞았다. 측정해 보니 카드 내부색이 2종이고, 그림자는 3종이었다.
  //
  // 카드 내부색 (텍스트/아이콘 없는 영역에서 뽑음):
  //   카드1 '이번 달 영수증 정리 완료'  #FFFDFC  (94%)  ← 아주 미세하게 따뜻하다
  //   카드3 '지출 추이'                #FFFFFF         ← 순백
  //   카드4 '스마트 사입 가이드'        #FFFFFF         ← 순백
  //   탭바                            #FFFFFF         ← 순백
  //
  // 카드 아래 그림자 Δ (1px = 1.234dp, 카드 폭 중앙부 평균):
  //   카드1   [ 9.4,  7.1, 5.4, 3.2, 2.6, 1.6, 0]        -> 약 6dp 번짐 (가장 약함)
  //   카드3   [19.4, 11.8, 6.7, 3.4, 1.8, 0]             -> 약 5dp 번짐 (가장 진함)
  //   카드4   [15.9, 11.9, 6.6, 2.9, 0.6, 0]             -> 약 5dp 번짐
  //   코랄카드 위/아래 모두 Δ≈0 — **그림자 없음** (그라디언트 자체가 입체감)
  //
  // 🔴 그림자 색: 채널별 감소율이 R/G/B = 0.0261/0.0261/0.0261 로 **완전히 균일**.
  //    즉 #142 내역 화면의 따뜻한 회갈색(#8A7268)과 달리 여기는 **무채색 검정**이다.
  //    같은 토큰을 재사용하지 않고 따로 둔다. (역산 결과를 그대로 따른다)

  /// 카드1(영수증 정리 완료) 내부색. 순백이 아니라 한 톤 따뜻하다.
  static const Color cardWarm = Color(0xFFFFFDFC);

  /// 홈 카드 그림자 — 가장 진한 단계(지출 추이 / 사업 가이드).
  /// Δ 19.4 를 bg #FFF9F6 에 역산하면 검정 α≈0.026, 번짐 5dp.
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x08000000), blurRadius: 20, offset: Offset(0, 6)),
  ];

  /// 알림 카드(카드1) 그림자 — Δ 9.4 로 위 카드의 절반 수준.
  static const List<BoxShadow> shadowSoft = [
    BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x05000000), blurRadius: 16, offset: Offset(0, 5)),
  ];

  /// 떠 있는 탭바 그림자 — 위쪽으로도 번진다(Δ위 14.9, Δ아래 15.0 대칭).
  static const List<BoxShadow> shadowTabBar = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 28, offset: Offset(0, 8)),
  ];

  /// 코랄 버튼('7월 맞춤 사입 리포트 보기') 그림자.
  /// 시안 Δ 15.0 이 버튼 아래로 6dp 이상 길게 깔린다.
  static const List<BoxShadow> shadowCoralBtn = [
    BoxShadow(color: Color(0x2EFF6E78), blurRadius: 14, offset: Offset(0, 5)),
  ];

  // ── #146 카드1 책 아이콘 실측 ───────────────────────────────────────
  //
  // 🔴 사장님 지적: "맨 위에 있는 카드에 아이콘은 오른쪽에 있는 아이콘으로 바꿔줘"
  //    지금 앱은 `Icons.menu_book_rounded` 를 **분홍 둥근 사각 박스** 안에 넣어 뒀다.
  //    시안에는 박스가 **없다**. 펼친 책만 떠 있고, 주변에 분홍 글로우가 번진다.
  //
  //   책 크기   y 145.6..166.6dp (h 22.2) · x 48.1..72.8dp (w 25.9)
  //   왼쪽 페이지 #FF787C (진한 코랄)
  //   오른쪽 페이지 #FF9385 (연한 살구)   ← 투톤이다
  //   글로우   아이콘 바깥으로 약 16dp 번짐. 바로 옆 #FFF0EE -> 먼 쪽 #FFFCFB

  /// 책 아이콘 왼쪽 페이지색.
  static const Color bookLeft = Color(0xFFFF787C);

  /// 책 아이콘 오른쪽 페이지색.
  static const Color bookRight = Color(0xFFFF9385);

  /// 책 아이콘 뒤 분홍 글로우. 시안 바로 옆 픽셀 #FFF0EE.
  static const List<BoxShadow> bookGlow = [
    BoxShadow(color: Color(0x30FF8A8A), blurRadius: 16),
    BoxShadow(color: Color(0x18FF8A8A), blurRadius: 28),
  ];

  /// 책 아이콘 크기. 시안 25.9 x 22.2dp.
  static const double bookW = 26;
  static const double bookH = 22;

  // ── #146 탭바 아이콘 실측 ───────────────────────────────────────────
  //
  // 🔴 사장님 지적: "하단 바에 있는 아이콘들도 내가 준 이미지랑 동일하게"
  //    시안 아이콘은 **Material 기본 아이콘이 아니다.** 전부 커스텀이다.
  //      홈     오각형 집 + 안에 웃는 입 곡선   (현재 Icons.home_rounded = 꽉 찬 집)
  //      내역   체크 3개 + 옆 막대 3개          (현재 business_center = 서류가방)
  //      스캔   카메라 몸통 + 위 돌출 + 렌즈 원  (현재 photo_camera 와 비슷하나 돌출 위치 다름)
  //      캘린더 달력 + 위 고리 2개 + 안에 새싹   (현재 calendar_today = 빈 달력)
  //      프로필 원 테두리 + 안에 머리/어깨      (현재 person_outline = 테두리 원 없음)
  //
  //   탭 중심 x = 47.5 / 124.0 / 194.4 / 264.1 / 334.5dp  (균등 5분할)
  //   아이콘 영역 y 1182..1210dp (약 23dp)
  //   라벨      y 1216..1235dp
  //   색: 비활성 #D4D4D4 계열 / 활성 코랄

  /// 탭 아이콘 한 변. 시안 글리프 폭 19.7~22.2dp 에서 선 두께까지 고려한 값.
  static const double tabIconSize = 23;

  /// 탭 아이콘 선 두께. 시안 아이콘 폭의 7~8%.
  static const double tabIconStroke = 1.7;

  /// 비활성 탭 아이콘 색. 시안 연회색.
  static const Color tabIconOff = Color(0xFFD9D9D9);

  /// 비활성 탭 라벨 색.
  static const Color tabLabelOff = Color(0xFFBDBDBD);

  // ── #146 헤더 벨 실측 ───────────────────────────────────────────────
  //
  // 🔴 사장님 지적: "오른쪽 맨 위에 알림 종 같은 모양이 지금 앱 화면에는 안 보인다"
  //    코드에는 `Icons.notifications_none_rounded` 로 **이미 있었다.**
  //    라이브를 직접 찍어 확인했다 — 벨은 실제로 그려진다.
  //    (#145 캐시 문제로 옛 화면을 보고 계셨다)
  //    다만 **모양이 시안과 다르다.** 시안 벨은:
  //      돔(위) + 바깥으로 벌어진 스커트 + 아래 **납작한 가로 바**
  //      + 바 아래 **분리된 작은 추**
  //    Material 벨은 스커트가 바로 바닥까지 내려오고 추가 둥근 점이다.
  //
  //   벨 크기 y 60.5..87.6dp · 폭 약 19.8dp, 선 두께 약 2.2dp

  /// 벨 아이콘 한 변.
  static const double bellSize = 22;

  /// 벨 선 두께. 시안 벨 폭의 10~12%.
  static const double bellStroke = 2.1;

  /// 벨 색.
  static const Color bellInk = Color(0xFF1A1A1A);

  // ── #147 코랄 카드 우상단 데코 실측 ────────────────────────────────
  //
  // 🔴 사장님 지적: "두번째 카드에도 세번째 이미지처럼 데코가 들어가 있거든"
  //    맞았다. #146 에서는 이 데코를 아예 빠뜨렸다.
  //
  // 코랄 카드 안 그라데이션 배경 위에, 행별 중간값보다 밝은 픽셀만 골라
  // 뽑아냈다(그라데이션이라 단순 임계값으로는 안 잡힌다).
  // 연결 요소 3개 + 꼬리 끝 점으로 이뤄져 있다.
  //
  // 카드(340.6 x 182.7dp) 좌상단 기준 dp:
  //   ① 꼬리 끝 점   중심 (244.4,  77.8)  지름 3.7
  //   ② 큰 고리      중심 (284.5,  30.9)  반지름 (11.1, 11.7)
  //   ③ 작은 고리    중심 (306.1,  14.8)  반지름 ( 8.0, 11.7)  ← 카드 위로 잘린다
  //   ④ 작은 점      중심 (331.4,  46.9)  지름 4.9
  //   꼬리 곡선 경유 (244.4,77.8) (245.0,70.3) (246.2,62.9)
  //                  (248.1,55.5) (251.2,48.1) -> 큰 고리로 이어진다
  //
  // 획 두께 2.47dp 측정 but 안티앨리어싱 번짐 포함 -> 실제 약 1.2dp.
  // 색: 흰색 반투명. 획 코어 #FFD6D4 를 배경 #FF7F7F 에 역산하면
  //     알파 G 0.680 / B 0.666. 가장 밝은 단일 픽셀로는 0.89.
  //     얇은 선이라 픽셀 평균이 알파를 과소평가하므로 그 사이인 0.75 를 쓴다.

  /// 데코 선 색. 흰색 75%.
  static const Color decoLine = Color(0xBFFFFFFF);

  /// 데코 점 색. 선보다 또렷하다.
  static const Color decoDot = Color(0xE6FFFFFF);

  /// 데코 선 두께.
  static const double decoStroke = 1.2;

  /// 데코 자체 크기. 시안 실측 82.7 x 76.0dp.
  /// 🔴 처음엔 카드 폭에 비례해 확대했는데, 그러면 우측 여백도 같이
  ///    늘어나 데코가 오른쪽으로 밀렸다(시안 6.2dp -> 렌더 0.3dp).
  ///    그래서 고정 크기 + Positioned 로 바꿨다.
  /// 🔴 그리고 확대 클로즈업 이미지의 배율을 모서리 반지름 20dp 로
  ///    가정했다가 13% 크게 그렸다. 홈 시안 본체에서 모서리 반지름이
  ///    17.64dp 로 나와, 클로즈업 1px = 17.64/18.23 dp 로 바로잡았다.
  static const Size decoSize = Size(82.7, 76.0);

  /// 데코 bbox 우측 여백. 카드 오른쪽 끝에서 12.3dp.
  static const double decoRight = 12.3;

  /// 데코 bbox 상단 여백. 리본 끝이 카드 위로 빠져나가므로 0.
  static const double decoTop = 0.0;
}
