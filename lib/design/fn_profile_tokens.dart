import 'package:flutter/material.dart';

/// #164 프로필 / 알림 설정 / 알림목록 시안 실측 토큰.
///
/// ## 실측 원본
///
/// | 시안 | 파일 | 픽셀 | 환산비(390dp 기준) |
/// |---|---|---|---|
/// | 프로필     | profile.png  | 425x1024 | 1.0897 |
/// | 알림 설정   | notifset.png | 473x1024 | 1.2128 |
/// | 알림목록    | notiflist.png| 472x1024 | 1.2103 |
///
/// 측정은 배경색 #FEF9F5 과의 채널합 차이 **6** 을 임계값으로 썼다.
/// 18 이상으로 잡으면 흰 카드(#FFFFFF, 차이 17)를 배경으로 오인한다.
///
/// 글자 크기는 세로 잉크 높이가 아니라 **가로 글자폭**을 실제
/// Pretendard 폰트로 역산해서 구했다. 세로로 재면 한글 받침 유무에
/// 따라 값이 널뛴다.
class FnProfile {
  FnProfile._();

  // ── 공통 ──────────────────────────────────────────────────────
  /// 페이지 배경. 세 시안 모두 동일.
  static const Color bg = Color(0xFFFEF9F5);

  /// 카드.
  static const Color card = Color(0xFFFFFFFF);

  /// 진한 글자. 실측 (18,17,15) / (19,18,14) / (17,17,15).
  static const Color ink = Color(0xFF17150F);

  /// 보조 글자. 실측 (118,114,111) / (117,113,110) / (112,111,109).
  static const Color sub = Color(0xFF76726F);

  /// 묶음 라벨. 실측 (82,78,75).
  static const Color group = Color(0xFF524E4B);

  /// 코랄. 실측 배지 (251,107,116) / 토글 (255,109,120) / 칩 (252,110,124).
  static const Color coral = Color(0xFFFF6D78);

  /// 카드 안 구분선. 실측 (234,234,234).
  static const Color hair = Color(0xFFEAEAEA);

  /// 화살표. 실측 (153,153,153).
  static const Color chevron = Color(0xFF999999);

  /// 카드 그림자.
  ///
  /// 시안 카드 아래쪽 번짐을 실측했다. 카드 바깥 8px(≈6.6dp) 구간에서
  /// 배경 #FEF9F5 가 최대 (238,234,233) 까지 내려간다 → 알파 약 6%.
  /// 위쪽은 거의 번지지 않으므로 y 오프셋을 준다.
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 4)),
  ];

  /// 카드 모서리. TL 코너 추적 결과 약 18dp.
  static const double cardRadius = 18.0;

  /// 좌우 바깥 여백. 세 시안 모두 카드 좌 23.9~24.1dp.
  static const double pad = 24.0;

  // ── 프로필 화면 ────────────────────────────────────────────────
  /// 무료 플랜 배지. 실측 y 127.6~153.2dp (h 26.6), x 92.7~296.4 (w 204.6).
  static const double planBadgeH = 27.0;
  static const double planBadgeFont = 12.5;

  /// 아바타 지름. 실측 98.2dp.
  static const double avatar = 98.0;

  /// 아바타 그라디언트. 대각(좌상→우하) 실측 (255,111,124) → (241,175,153).
  static const Color avatarFrom = Color(0xFFFF6F7C);
  static const Color avatarTo = Color(0xFFF5AF99);

  /// 편집 배지. 실측 지름 약 24dp, 흰 테두리 2dp, 살구색 바탕.
  static const double editBadge = 24.0;
  static const Color editBadgeBg = Color(0xFFFFD4C4);

  /// 상호명. 실측 글자폭 68.8dp / '플로우노트' → 15.9dp.
  static const double shopFont = 16.0;

  /// 대표자 줄. 실측 184.4dp → 11.7dp.
  static const double ownerFont = 12.0;

  /// 섹션 제목. 실측 103.7dp / '계정/서비스 관리' → 15.4dp.
  static const double sectionFont = 15.5;

  /// 목록 한 줄 높이. 실측 카드1 h 209.2dp / 4줄 = 52.3.
  static const double rowH = 52.0;

  /// 목록 글자. 실측 89.0dp / '사업자 정보 수정' → 13.7dp.
  static const double rowFont = 13.5;

  /// 목록 좌우 안쪽 여백. 글자 시작 45.0dp - 카드 좌 23.9dp = 21.1.
  static const double rowPadH = 21.0;

  // ── 알림 설정 화면 ─────────────────────────────────────────────
  /// 큰 제목. 실측 158.3dp / '필요한 알림만 받아보세요' → 15.9dp.
  static const double nsTitleFont = 16.0;

  /// 부제. 실측 169.0dp → 13.7dp.
  static const double nsSubFont = 13.5;

  /// 묶음 라벨. 실측 61.8dp / '서비스 알림' → 13.4dp.
  static const double nsGroupFont = 13.5;

  /// 항목 제목. 실측 89.9dp / '영수증 처리 알림' → 13.7dp.
  static const double nsItemFont = 13.5;

  /// 항목 설명. 실측 168.2dp → 11.7dp.
  static const double nsDescFont = 11.5;

  /// 항목 한 칸 높이. 카드1 h 279.2dp / 4항목 = 69.8.
  static const double nsRowH = 70.0;

  /// 토글. 실측 켜짐 43.2 x 24.9dp.
  static const double toggleW = 44.0;
  static const double toggleH = 25.0;

  /// 꺼진 토글. 실측 (229,229,229).
  static const Color toggleOff = Color(0xFFE5E5E5);

  // ── 알림목록 화면 ──────────────────────────────────────────────
  /// 필터 칩 높이. 실측 26.4dp.
  static const double chipH = 27.0;

  /// 칩 글자. 실측 '전체' 글자폭 43.0dp → 15.9… 는 칩 전체폭이라
  /// 잉크만 재면 '알림' 19.0dp → 10.9dp.
  static const double chipFont = 11.0;

  /// 칩 사이 간격. 실측 72.7-65.3 = 7.4dp.
  static const double chipGap = 7.5;

  /// 칩 테두리. 실측 (239,238,234).
  static const Color chipLine = Color(0xFFEFEEEA);

  /// 칩 끄기 글자. 실측 (93,93,93).
  static const Color chipOffFg = Color(0xFF5D5D5D);

  /// 목록 칸 세로 여백. 실측 간격 11.6~12.4dp.
  static const double listGap = 12.0;

  /// 한 줄 제목일 때 칸 높이 100.0dp / 두 줄이면 125.6dp.
  static const double listRow1H = 100.0;
  static const double listRow2H = 125.5;

  /// 칸 배경. 🔴 흰색이 아니다. 실측 (254,253,251) / (255,250,247) 로
  /// 배경보다 아주 살짝 밝다. 카드가 아니라 **띠**에 가깝다.
  static const Color listTile = Color(0xFFFEFDFB);

  /// 칸 사이 틈에 보이는 배경.
  static const Color listGapBg = Color(0xFFFEF9F5);

  /// 분류 배지. 실측 h 18.3dp, '공지' w 35.0 / '이벤트' w 42.5.
  static const double listBadgeH = 18.5;
  static const double listBadgeFont = 10.0;
  static const double listBadgeRadius = 9.5;

  /// 목록 제목. 실측 160.7dp / '플로우노트 업데이트 안내' → 15.9dp.
  static const double listTitleFont = 16.0;

  /// 날짜. 실측 46.6dp / '26.09.18' → 12.2dp.
  static const double listDateFont = 12.0;

  /// 읽지 않음 점. 실측 지름 8.3dp, 오른쪽 끝 369.3dp.
  static const double listDot = 8.5;

  /// 목록 좌우 여백. 실측 글자 시작 40.0dp.
  static const double listPadH = 40.0;
}
