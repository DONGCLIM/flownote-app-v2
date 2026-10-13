/// 구매 내역의 두 가지 보기 — **날짜별** / **업체별**.
///
/// ## 🔴 이 파일의 기준은 프로토타입 **원본 소스**다 (시안 이미지가 아니다)
///
/// 사용자가 준 `FlowNote MVP 프로토타입 (오프라인용).html` 안에는
/// `<script type="__bundler/manifest">` 로 207개 에셋이 base64+gzip 으로
/// 들어 있고, 그중 `b0b603b5-cad7-460e-b557-e23de591f81d` 가 구매 내역
/// 화면(`AppH10`)의 실제 소스다. 아래 치수·색·문구는 전부 그 소스에서
/// 그대로 옮긴 값이다.
///
/// ```js
/// ROSE      = '#EE7686'   ROSE_DEEP = '#C9566A'   INK  = '#171717'
/// MUTE      = 'rgba(45,46,52,.82)'
/// HAIR      = 'rgba(112,115,124,.16)'
/// CARD_BG   = '#FFF9F7'   CARD_LINE = 'rgba(238,118,134,.22)'
/// ```
///
/// ### 🔴 이전에 내가 틀렸던 이유 — 반드시 기억할 것
///
/// #98 에서는 시안 **이미지**를 픽셀로 재서 치수를 정했다. 그런데 그
/// 이미지들은 402x874 아이폰 목업을 **약 1.36배 확대 캡처**한 것이었다.
/// 그래서 실제 h36 칩이 h49 로, h6 바가 h7 로, gap 7 이 gap 24 로 읽혔다.
/// 배율이 섞인 실측을 그대로 코드에 넣었으니 전부 어긋난 값이 됐다.
///
/// **원본 소스가 있으면 이미지 실측보다 항상 원본이 우선이다.**
///
/// ## 반응형 ("이거 반응형이니까 그것도 살피고")
///
/// 프로토타입 템플릿에는 `@media` 쿼리가 **0개**다. 모든 화면이 고정
/// 402x874 `IOSDevice` 프레임 안에서 그려진다. 그럼에도 레이아웃이 폭에
/// 따라 안 깨지는 이유는 breakpoint 가 아니라 아래 세 가지다:
///
///   1. 늘어나는 칸은 `flex:1` + `minWidth:0`  → Flutter `Expanded`
///   2. 넘치는 글자는 `textOverflow:'ellipsis'` → `TextOverflow.ellipsis`
///   3. 줄어들면 안 되는 칸(금액·배지)은 `flexShrink:0` → 고정 위젯
///   4. 칩 줄은 `flexWrap:'wrap'` + `gap`  → `Wrap`
///
/// 🔴 그래서 **줄 수를 코드로 강제하지 않는다.** 폭이 좁으면 접히고
///    넓으면 펴지는 게 원본 동작이고, 그게 곧 반응형이다.
///    (#98 에서 `spacing: 24` 로 3개씩 강제한 건 정반대 짓이었다.)
///
/// ## 업체별 점유율의 분모
///
/// 원본은 `const total = FN10_TX.reduce(...)` — 즉 **필터 이전 전체 합**을
/// 분모로 쓴다. 검색·과세·전송 필터를 아무리 걸어도 개별 %가 흔들리지
/// 않는다는 뜻이다. 우리 구현도 같다 ([SettleLiveData.periodTotal] =
/// 조회 기간 전체 합). 원본 데모는 9건이 전부 7월이라 두 값이 같다.
///
/// ## 웹 / 앱 공통
///
/// 이 파일은 플랫폼 분기가 없다. Flutter 한 벌이 웹과 안드로이드에 그대로
/// 나가므로 여기 한 번 고치면 양쪽이 같이 바뀐다.
/// (`dart:io` 를 쓰지 않는다 — 웹에서 터지는 원인이 된다)
library;

import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../models/receipt_model.dart';
import '../../services/vendor_tax_service.dart';
import '../receipt_detail_screen.dart';
import 'fn_data.dart';
import 'settle_data_live.dart';

// ════════════════════════════════════════════════════════════════
//  ⓪ 프로토타입 원본 상수
// ════════════════════════════════════════════════════════════════

/// 카드 배경 — 원본 `CARD_BG = '#FFF9F7'`.
///
/// 🔴 디자인 토큰 `FnColors.rose99` 는 `#FFFAF8` 로 한 톤 다르다.
///    토큰으로 대충 맞추지 않고 원본 값을 그대로 쓴다.
const Color kSettleCardBg = Color(0xFFFFF9F7);

/// 카드 외곽선 — 원본 `CARD_LINE = 'rgba(238,118,134,.22)'`.
///
/// 즉 `rose50 #EE7686` 의 22% 다. `rose90`(불투명 연분홍)이 아니라
/// 반투명이므로 배경 위에서 자연스럽게 묻힌다.
const Color kSettleCardLine = Color(0x38EE7686);

/// 얇은 구분선 — 원본 `HAIR = 'rgba(112,115,124,.16)'`.
const Color kSettleHair = Color(0x2970737C);

/// 카드 모서리 — 원본 디자인 시스템 `Card` 의 `borderRadius: 20`.
///
/// 🔴 이전 구현은 12(날짜별) / 14(업체별) 로 서로 다르게 줬다.
///    원본은 두 카드 모두 같은 `Card` 컴포넌트이므로 20 하나다.
const double kSettleCardRadius = 20;

/// 원본 `INK = '#171717'` = [FnColors.labelNormal].
const Color kSettleInk = FnColors.labelNormal;

/// 원본 `MUTE = 'rgba(45,46,52,.82)'`.
///
/// 토큰 `labelAlternative` 는 `rgba(55,56,60,.61)` 로 원본보다 흐리다.
/// 날짜별 부제·건수·요일이 전부 이 색이라 차이가 눈에 보이므로 원본 값을 쓴다.
const Color kSettleMute = Color(0xD12D2E34);

/// 원본 `ROSE_DEEP = '#C9566A'` = [FnColors.rose30]. 날짜 기둥의 `N월`.
const Color kSettleRoseDeep = FnColors.rose30;

/// 접기 꺾쇠 색 — 원본 `'#C6CBD3'`.
const Color kSettleCaret = Color(0xFFC6CBD3);

// ── #140 내역 시안 실측 (399x1024, 환산비 0.9774) ─────────────────
//
//   총매입 카드   y 127.1..293.2dp (h 166)  흰색 #FFFFFF
//   카드 좌우     24.4dp (좌우 대칭)
//   코랄 배지     y 245.3..273.7dp (h 28)   #FF6D78
//   토글          y 310.8..351.9dp (h 41)   두 칸 각 168~170dp
//                 활성 #FF6D78 / 비활성 #FFFFFF, 좌우 23.5dp

/// 시안 내역 카드 배경 — **흰색**.
///
/// 🔴 예전 `kSettleCardBg`(#FFF9F7) 는 살짝 분홍빛이었다. 시안 카드
///    내부(x=200dp 세로 단면)는 전부 #FFFFFF 였다.
const Color kSettleWhite = Color(0xFFFFFFFF);

/// 시안 카드 테두리 — 홈/캘린더와 같은 연한 선.
const Color kSettleLine = Color(0x14C9A79B);

/// 시안 코랄. 배지와 활성 토글이 같은 색이다.
const Color kSettleCoral = Color(0xFFFF6D78);

/// 시안 카드 좌우 여백 24.4dp.
const double kSettlePagePad = 24.0;

/// 시안 토글 높이 41.1dp.
const double kSettleToggleH = 41.0;

// ── #142 그림자 실측 (시안 399x1024, 환산비 0.9774) ────────────────
//
// 배경 #FEF9F5 위에서 카드 아래쪽으로 어두워지는 양(Δ)을 1dp 간격으로
// 쟀다. 카드 종류마다 번지는 거리가 **다르다**.
//
//   총매입 카드   +1dp Δ18 -> +9dp Δ0    9dp 번짐  (크고 부드럽다)
//   영수증 카드   +1dp Δ16 -> +3dp Δ0    3dp 번짐  (작고 또렷하다)
//   검색창/칩     +1dp Δ10 -> +2dp Δ0    2dp 번짐  (아주 얕다)
//
// 방향: 위 2dp / 옆 6dp / 아래 9dp 로 **아래로 치우쳐** 있다.
// -> offset.dy 는 blur 의 1/3 쯤.
//
// 그림자 색: 가장 진한 픽셀 #ECE8E5 를 배경 #FEF9F5 와 역산하면
// 채널별 알파가 0.071 / 0.068 / 0.065 로 거의 같다. 즉 **순수 검정이
// 아니라 배경과 같은 계열의 따뜻한 회갈색**이다. 검정으로 깔면 사진에서
// 보이는 것보다 차갑게 보인다. 그래서 #8A7268 계열을 쓴다.

/// 시안 그림자 색 — 따뜻한 회갈색. 검정이 아니다.
const Color kSettleShadow = Color(0xFF8A7268);

/// 총매입 카드 그림자 — 가장 크고 부드럽다 (번짐 9dp).
///
/// 🔴 처음에 `blurRadius: 18, offset: (0,6)` 으로 줬더니 렌더 Δ 가
///    [20, 14, 14, 14, 14, 14, 0] 으로 **계단처럼 평평**했다.
///    offset 이 크면 카드 바로 아래가 그림자 '몸통'에 가려 감쇠가
///    보이지 않는다. 시안은 [18, 11, 8, 7, 5, 3, 2, 1, 0] 으로
///    매끄럽게 줄어든다. 그래서 offset 을 줄이고 blur 를 키웠다.
const List<BoxShadow> kSettleShadowLg = [
  BoxShadow(color: Color(0x268A7268), blurRadius: 10, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x118A7268), blurRadius: 20, offset: Offset(0, 5)),
];

/// 영수증 카드 그림자 — 작고 또렷하다 (번짐 3dp).
/// 시안 Δ [16, 6, 1, 0] — 빠르게 사라진다.
const List<BoxShadow> kSettleShadowMd = [
  BoxShadow(color: Color(0x1F8A7268), blurRadius: 4, offset: Offset(0, 1)),
];

/// 검색창·필터칩 그림자 — 아주 얕다 (번짐 2dp).
/// 시안 Δ [10, 1, 0].
const List<BoxShadow> kSettleShadowSm = [
  BoxShadow(color: Color(0x148A7268), blurRadius: 3, offset: Offset(0, 1)),
];

/// 시안 필터칩 **활성** 채움 — 검정.
///
/// 🔴 공용 `FnDsChip` 은 활성일 때 연분홍(`rose95`) 채움 + 코랄 글자였다.
///    시안을 재 보니 활성 칩 내부는 #171717 이 52%(글자 없는 우측 기준)로
///    **검정 채움 + 흰 글자**다. 완전히 다른 모습이었다.
const Color kSettleChipOn = Color(0xFF171717);

/// 시안 필터칩 **비활성** 채움 — 흰색.
///
/// 공용 칩은 `outlined` 일 때 투명 + 22% 회색 테두리였다. 시안 비활성 칩
/// 내부는 #FFFFFF 가 79% 이고, 가장자리는 테두리가 아니라 얕은 그림자다.
const Color kSettleChipOff = Color(0xFFFFFFFF);

/// 시안 필터칩 높이 — y 465.5..497.5dp.
const double kSettleChipH = 32.0;

/// 시안 필터칩 모서리.
const double kSettleChipRadius = 10.0;

/// 내역 화면 금액 표기 — `1,184,000원`.
///
/// 🔴 공용 [FnDemo.won] 은 `₩1,184,000` 처럼 **앞에 원화 기호**를 붙인다.
///    시안을 확대해 보면 내역 화면은 총매입도 영수증 줄도 전부
///    `256,000원` 처럼 **뒤에 '원' 글자**다. 기호가 아니라 글자다.
///
///    공용 함수를 바꾸면 홈·캘린더·정산서까지 전부 바뀐다. 금액 표기는
///    사장님이 숫자를 읽는 방식이라 화면마다 함부로 통일하면 안 된다.
///    그래서 내역 화면 전용 표기를 따로 둔다.
String settleWon(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$b원';
}

/// 종합소득세용(5월) 보기가 말하는 "소액 결제" 기준 금액.
///
/// 3만원 이하 결제는 적격증빙(세금계산서·카드전표) 없이도 비용으로
/// 인정된다. 그래서 5월 신고철에 따로 모아 볼 이유가 있는 금액대다.
/// 원본 `FN10_VENDOR_META[...].small` 이 담고 있던 것이 이 목록이다.
const double kSmallPayLimit = 30000;

// ════════════════════════════════════════════════════════════════
//  ① 영수증 타일 (원본 `FN10Tile`)
// ════════════════════════════════════════════════════════════════

/// 원본 `FN10Tile({ size = 40 })`.
///
/// ```js
/// div { width:size, height:size, borderRadius:size*0.3,
///       background:'#FDEEF0', flex center, flexShrink:0 }
///   svg size*0.52  영수증 path  stroke:'#EE7686' strokeWidth:1.4
/// ```
///
/// 업체별 카드는 기본 40, 날짜별 카드는 32 를 쓴다.
/// 🔴 이전 구현은 두 곳 모두 30 / radius 9 로 고정이었다.
class FnReceiptTile extends StatelessWidget {
  const FnReceiptTile({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // 원본 `#FDEEF0`. `rose95 #FCEEEB` 와 비슷하지만 같지 않다.
        color: const Color(0xFFFDEEF0),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.receipt_long_rounded,
        size: size * 0.52,
        color: FnColors.rose50,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  ② 상단 총 매입 헤더
// ════════════════════════════════════════════════════════════════

/// 원본 `header()` 의 첫 블록.
///
/// ```js
/// div { fontSize:12.5, color:MUTE, marginBottom:6 }  '2026년 7월 총 매입'
/// div { display:flex, alignItems:'baseline', gap:8 }
///   div  { fontSize:32, fontWeight:700,
///          letterSpacing:'-1.2px', lineHeight:1, color:INK }  금액
///   span { fontSize:12.5, color:MUTE }                        'N건'
/// ```
///
/// 🔴 이전 구현은 13 / 28 w800 / 13 이었다. 원본은 12.5 / 32 w700 / 12.5 다.
///    금액과 건수는 `baseline` 정렬이므로 여백으로 눈대중 맞추지 않는다.
class SettleTotalHeader extends StatelessWidget {
  const SettleTotalHeader({
    super.key,
    required this.label,
    required this.total,
    required this.count,
    this.onPrev,
    this.onNext,
  });

  final String label;
  final double total;
  final int count;

  /// 시안의 `‹` — 없으면 화살표를 그리지 않는다. (#140)
  final VoidCallback? onPrev;

  /// 시안의 `›` — 없으면 화살표를 그리지 않는다. (#140)
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    // 🔴 #140 시안은 **흰 카드 안 중앙 정렬**이다.
    //    위: ‹ 라벨 ›  /  가운데: 큰 금액  /  아래: 코랄 배지
    //    예전에는 카드 없이 좌측 정렬이고 건수가 회색 글자였다.
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: kSettleWhite,
        borderRadius: BorderRadius.circular(kSettleCardRadius),
        border: Border.all(color: kSettleLine),
        // #142 시안 실측 — 이 카드만 그림자가 9dp 번진다.
        boxShadow: kSettleShadowLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 기간 라벨 (좌우 화살표는 기능이 연결됐을 때만 보인다) ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onPrev != null)
                _MonthArrow(
                  icon: Icons.chevron_left_rounded,
                  onTap: onPrev,
                ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: kSettleInk,
                    ),
                  ),
                ),
              ),
              if (onNext != null)
                _MonthArrow(
                  icon: Icons.chevron_right_rounded,
                  onTap: onNext,
                ),
            ],
          ),
          const SizedBox(height: 14),
          // ── 금액 (중앙) ──
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              settleWon(total),
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -1.2,
                color: kSettleInk,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── 코랄 배지 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            decoration: BoxDecoration(
              color: kSettleCoral,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '총 매입 건수 $count건',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 시안 총매입 카드의 `‹` `›` 버튼.
class _MonthArrow extends StatelessWidget {
  const _MonthArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 19, color: kSettleInk),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  ③ 날짜별 / 업체별 세그먼트
// ════════════════════════════════════════════════════════════════

/// 원본 `segmented()` 를 치수까지 그대로 옮긴 것.
///
/// ```js
/// div { display:flex, padding:3, borderRadius:12,
///       background:'rgba(112,115,124,.08)', gap:2 }
///   button { flex:1, height:36, border:none, borderRadius:10,
///            fontSize:14, fontWeight: on?700:500,
///            color: on?INK:MUTE, background: on?'#fff':'transparent',
///            boxShadow: on?'0 1px 4px rgba(0,0,0,.10)':'none' }
/// ```
///
/// 🔴 공용 [FnSegmented] 를 쓰지 않는 이유:
///    그쪽은 height 38 / radius 10 / 내부 radius 8 이고 스캔 화면
///    (`scan_review_screen.dart`)에서도 쓴다. 여기 치수를 맞추려고
///    공용 위젯을 고치면 관계없는 화면이 같이 바뀐다.
///    요청이 "구매내역 날짜별 업체별 **거기만**" 이므로 지역 위젯을 둔다.
class SettleSegmented extends StatelessWidget {
  const SettleSegmented({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final String Function(String) labelOf;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final kids = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final e = items[i];
      final on = e == value;
      // 시안 칸 사이 간격 6.8dp
      if (i > 0) kids.add(const SizedBox(width: 7));
      kids.add(Expanded(
        child: GestureDetector(
          onTap: () => onChanged(e),
          behavior: HitTestBehavior.opaque,
          // 🔴 #140 시안은 회색 홈통 안의 세그먼트가 아니라, 배경 위에
          //    바로 놓인 **알약 두 칸**이다. 활성은 코랄 채움(흰 글자),
          //    비활성은 흰 채움 + 연한 테두리.
          //    실측: 높이 41.1dp, 각 칸 168~170dp, 좌우 23.5dp.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: kSettleToggleH,
            decoration: BoxDecoration(
              color: on ? kSettleCoral : kSettleWhite,
              borderRadius: BorderRadius.circular(kSettleToggleH / 2),
              border: on ? null : Border.all(color: kSettleLine),
            ),
            alignment: Alignment.center,
            child: Text(
              labelOf(e),
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                color: on ? Colors.white : kSettleMute,
              ),
            ),
          ),
        ),
      ));
    }

    // #140 시안은 회색 홈통이 없다. 알약 두 칸을 바로 놓는다.
    return Row(children: kids);
  }
}

// ════════════════════════════════════════════════════════════════
//  ④ 빈 목록
// ════════════════════════════════════════════════════════════════

/// 원본의 두 빈 상태.
///
/// ```js
/// div { textAlign:'center', color:MUTE, padding:'28px 0', fontSize:14 }
///   '조건에 맞는 거래처가 없어요'   // byVendor
///   '조건에 맞는 내역이 없어요'     // byDate
/// ```
///
/// 🔴 원본에는 부제(두 번째 줄)가 없다. 한 줄이 전부다.
///    필터를 직접 건 사람은 왜 비었는지 이미 알고 있으므로
///    "검색어나 필터를 바꿔보세요" 같은 설명을 덧붙이지 않는다.
class SettleListEmpty extends StatelessWidget {
  const SettleListEmpty({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          color: kSettleMute,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  ⑤ 날짜별 타임라인 (원본 `screen === 'byDate'`)
// ════════════════════════════════════════════════════════════════

/// 원본 `byDate` 의 날짜 묶음 목록.
///
/// ```js
/// div { padding:'0 18px 24px' }
///   days.map(d => div { display:flex, gap:12 } [ 날짜기둥, 본문 ])
/// ```
///
/// 좌우 패딩(18)은 화면 쪽에서 준다. 여기서는 묶음만 쌓는다.
class SettleDayTimeline extends StatelessWidget {
  const SettleDayTimeline({super.key, required this.groups});

  final List<SettleDayGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups) _DayBlock(group: g),
      ],
    );
  }
}

/// 하루 묶음 — 날짜 기둥 + 그 날의 카드들.
///
/// ```js
/// div { display:flex, gap:12 }
///   div { width:44, flexShrink:0, column, alignItems:'center', paddingTop:4 }
///     div { fontSize:11, fontWeight:600, color:ROSE_DEEP }        'N월'
///     div { fontSize:19, fontWeight:700, color:INK, lineHeight:1.1 } 'DD'
///     div { fontSize:11, color:MUTE, marginTop:2 }                 요일
///     div { flex:1, width:2, borderRadius:1, background:HAIR, marginTop:8 }
///   div { flex:1, minWidth:0, paddingBottom:16 }
///     div { fontSize:12, color:MUTE, marginBottom:8, paddingTop:6 } 'N건 · ₩...'
///     div { column, gap:8 }  카드들
/// ```
///
/// 🔴 이전 구현과 다른 점(전부 원본에 맞춘 것):
///      기둥 폭        44 (같음) 이지만 `gap` 이 8 → **12**
///      `N월`          rose50 → **rose30 (`#C9566A`)**
///      `DD`           21 w800 → **19 w700**
///      요일 위 여백   0 → **marginTop 2**
///      세로선         width 1 / lineAlternative(8%) → **width 2 / HAIR(16%)**
///      본문 부제      12.5 → **12**, 아래 여백 6 → **8**, 위 여백 2 → **6**
///      카드 사이      8 (같음)
///      묶음 아래      6+8 → **paddingBottom 16** 한 곳으로
class _DayBlock extends StatelessWidget {
  const _DayBlock({required this.group});

  final SettleDayGroup group;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    for (var i = 0; i < group.receipts.length; i++) {
      if (i > 0) cards.add(const SizedBox(height: 8)); // 원본 `gap: 8`
      cards.add(_ReceiptCard(receipt: group.receipts[i]));
    }

    // 🔴 `IntrinsicHeight` 가 반드시 필요하다.
    //
    //    원본 CSS 는 `display:flex` 기본값이 `align-items: stretch` 이고,
    //    오늘천 기둥의 새로선은 `flex:1` 로 하루 분량만큼 늘어난다.
    //    Flutter 에서 이걸 `Row(crossAxisAlignment: stretch)` + `Expanded` 로
    //    짜면, 이 Row 가 `SingleChildScrollView`(높이 무한) 어래에
    //    있기 때문에 `h=Infinity` 제재조건이 그대로 기둥에
    //    전달되어 레이아웃이 통짜로 실패한다.
    //
    //    debug 모드에선 assert 가 잡아내지만, **release 바이너리는
    //    assert 가 삭제되어 있어 조용하 깨진다** — 그러면 첫 달로릭만
    //    남고 뒤의 날짜들이 사라진다. 실제로 그 상황이 불러졌다.
    //
    //    `IntrinsicHeight` 로 한 번 높이를 계산해 주면, stretch 가
    //    무한이 아닌 실제 하루 높이를 받아 원본과 동일하게 동작한다.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 왼쪽 날짜 기둥 (원본 width 44) ──────────────────
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 4), // 원본 `paddingTop: 4`
              child: Column(
                children: [
                  Text(
                    group.monthLabel,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kSettleRoseDeep,
                    ),
                  ),
                  Text(
                    group.dayLabel,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: kSettleInk,
                    ),
                  ),
                  const SizedBox(height: 2), // 원본 요일 `marginTop: 2`
                  Text(
                    group.weekdayLabel,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11,
                      color: kSettleMute,
                    ),
                  ),
                  const SizedBox(height: 8), // 원본 선 `marginTop: 8`
                  // 다음 날짜까지 이어지는 세로선. 원본 `flex:1, width:2`.
                  Expanded(
                    child: Container(width: 2, color: kSettleHair),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12), // 원본 `gap: 12`

          // ── 오른쪽 본문 ────────────────────────────────────
          //
          // 반응형: 원본 `flex:1, minWidth:0` → `Expanded`.
          // 폭이 좁아지면 카드 안 글자가 ellipsis 로 잘리고, 기둥(44)과
          // 간격(12)은 그대로 유지된다.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16), // `paddingBottom: 16`
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Text(
                      '${group.count}건 · ${settleWon(group.total)}',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        color: kSettleMute,
                      ),
                    ),
                  ),
                  ...cards,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 날짜별 영수증 카드.
///
/// ```js
/// Card { bordered, padding:13, cursor:'pointer',
///        background:CARD_BG, boxShadow:'inset 0 0 0 1px '+CARD_LINE }
///   div { display:flex, alignItems:'center', gap:9 }
///     FN10Tile { size:32 }
///     span { flex:1, minWidth:0, fontSize:15.5, fontWeight:600,
///            color:INK, ellipsis }                          거래처명
///     taxTag(t.tax)
///     span { fontSize:15.5, fontWeight:700, color:INK, flexShrink:0 }  금액
///   div { fontSize:12.5, color:MUTE, marginTop:6, paddingLeft:41,
///         ellipsis }        t.items.map(i => i[0]).join(' · ')
/// ```
///
/// 🔴 이전 구현과 다른 점:
///      패딩         12 → **13**
///      타일         30 → **32** (`FnReceiptTile`)
///      타일 뒤 간격 10 → **9**
///      정렬         `start` → **`center`** (한 줄 안에서 가운데 맞춤)
///      거래처명     15 → **15.5**
///      금액         15 w800 labelStrong → **15.5 w700 INK**
///      부제 왼여백  타일 안쪽 Column → **paddingLeft 41** (타일 32 + 간격 9)
///      부제 위여백  5 → **6**
///      품목         `외 N건` → **전체 나열 `A · B · C`**
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt});

  final ReceiptModel receipt;

  @override
  Widget build(BuildContext context) {
    final tax = SettleLiveData.taxOf(receipt.storeName);
    final name = receipt.storeName.trim().isEmpty
        ? '거래처 미확인'
        : receipt.storeName.trim();

    // 🔴 `Material` 은 `shape` 와 `borderRadius` 를 동시에 주면 assert 로
    //    죽는다. 외곽선이 필요하므로 `shape` 쪽만 쓴다.
    // #142 시안 실측 — 영수증 카드는 **흰색**이고, 아래로 3dp 번지는
    //      작고 또렷한 그림자가 있다. (총매입 카드의 9dp 와 다르다)
    //      예전 `kSettleCardBg`(#FFF9F7) 는 분홍빛이라 시안과 달랐다.
    //
    // 🔴 `Material` 자체에는 그림자 색을 자유롭게 줄 수 없어서
    //    (elevation 은 검정 계열 고정) 바깥을 `DecoratedBox` 로 감싼다.
    //    `Material` 은 잉크 효과를 위해 투명으로 남긴다.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kSettleWhite,
        borderRadius: BorderRadius.circular(kSettleCardRadius),
        boxShadow: kSettleShadowMd,
      ),
      child: Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kSettleCardRadius),
        side: const BorderSide(color: kSettleLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(kSettleCardRadius),
        // 원본도 `cursor:'pointer'` + `setScreen('detail')` 로 상세로 간다.
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReceiptDetailScreen(receipt: receipt),
        )),
        child: Padding(
          padding: const EdgeInsets.all(13), // 원본 `padding: 13`
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                // 원본 `alignItems: 'center'`.
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const FnReceiptTile(size: 32),
                  const SizedBox(width: 9), // 원본 `gap: 9`
                  // 반응형: 원본 `flex:1, minWidth:0` + ellipsis.
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: kSettleInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  // 원본 `flexShrink: 0` — 폭이 좁아도 배지는 줄지 않는다.
                  SettleTaxBadge(tax: tax),
                  const SizedBox(width: 9),
                  // 🔴 #140 좌우 여백을 시안 24dp 로 넓히자 좁은 기기에서
                  //    이 줄이 넘쳤다. 실측: 320dp 화면에서 이 Row 의
                  //    제약이 190dp 가 되어 30px 오버플로.
                  //
                  //    금액은 절대 자르지 않는다(원본 `flexShrink:0`).
                  //    대신 들어갈 자리가 없을 때만 **같은 비율로** 줄인다.
                  //    FittedBox(scaleDown) 은 공간이 충분하면 아무 일도
                  //    하지 않으므로 넓은 화면의 모습은 그대로다.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        settleWon(receipt.totalAmount),
                        maxLines: 1,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: kSettleInk,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6), // 원본 `marginTop: 6`
              Padding(
                // 원본 `paddingLeft: 41` = 타일 32 + 간격 9.
                padding: const EdgeInsets.only(left: 41),
                child: Text(
                  // 🔴 원본은 `t.items.map(i => i[0]).join(' · ')` —
                  //    품목을 **전부** 나열하고 넘치면 ellipsis 로 자른다.
                  //    `외 N건` 으로 줄이지 않는다. 자르는 판단은 폭이
                  //    하는 것이지 우리가 미리 개수로 정하지 않는다.
                  receiptFullItemList(receipt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12.5,
                    color: kSettleMute,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  ⑥ 업체별 점유율 (원본 `screen === 'byVendor'`)
// ════════════════════════════════════════════════════════════════

/// 원본 `byVendor` 의 거래처 카드 목록.
///
/// ```js
/// div { padding:'0 18px 24px', column, gap:10 }
/// ```
class SettleVendorShareList extends StatelessWidget {
  const SettleVendorShareList({
    super.key,
    required this.shares,
    required this.expandedName,
    required this.onToggle,
    required this.onExport,
    this.exportedAt = const {},
    this.smallOnly = false,
  });

  final List<SettleVendorShare> shares;
  final String? expandedName;
  final ValueChanged<String> onToggle;
  final void Function(SettleVendorShare) onExport;

  /// 거래처별 최근 내보내기 날짜 (`MM.dd`)
  final Map<String, String> exportedAt;

  /// 종합소득세용(5월) 보기가 켜져 있는가.
  ///
  /// 원본 `smallOnly` 와 같다. 켜져 있고 그 거래처에 3만원 이하 결제가
  /// 있으면 펼친 카드 안에 `3만원 이하 결제` 블록이 하나 더 붙는다.
  final bool smallOnly;

  @override
  Widget build(BuildContext context) {
    final kids = <Widget>[];
    for (var i = 0; i < shares.length; i++) {
      if (i > 0) kids.add(const SizedBox(height: 10)); // 원본 `gap: 10`
      final s = shares[i];
      kids.add(_VendorShareCard(
        share: s,
        open: expandedName == s.name,
        onToggle: () => onToggle(s.name),
        onExport: () => onExport(s),
        exportedAt: exportedAt[s.name],
        smallOnly: smallOnly,
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: kids,
    );
  }
}

/// 거래처 카드.
///
/// ```js
/// Card { bordered, padding:16, background:CARD_BG,
///        boxShadow:'inset 0 0 0 1px '+CARD_LINE }
///   div { flex, alignItems:'center', gap:12, cursor:'pointer' }   // 머리
///     FN10Tile                                                   // 40
///     div { flex:1, minWidth:0 }
///       div { fontSize:16.5, fontWeight:600, color:INK }          거래처명
///       div { flex, alignItems:'center', gap:6, marginTop:4, wrap }
///         span { fontSize:12.5, color:MUTE }        'N건 · 최근 MM.DD'
///         taxTag(v.tax)
///         v.sent && span { 11, w600, '1px 6px', r5,
///                          bg:'#EFF5E7', color:'#5F8347' }  '전송 MM.DD'
///     div { textAlign:'right', flexShrink:0 }
///       div { fontSize:17, fontWeight:700, color:INK,
///             letterSpacing:'-.3px' }                              금액
///       div { fontSize:15, color:'#C6CBD3', lineHeight:1,
///             marginTop:3, transform: open?'rotate(90deg)':'none' }  '›'
///   open ? 펼친 내용 : 점유율 바
/// ```
///
/// 🔴 이전 구현과 다른 점:
///      패딩          14/14/14/12 → **16 균일**
///      모서리        14 → **20**
///      타일          30 → **40**
///      타일 뒤 간격  10 → **12**
///      정렬          `start` → **`center`**
///      거래처명      15 → **16.5**
///      부제          12 → **12.5**
///      금액          17 w800 labelStrong → **17 w700 INK, letterSpacing -0.3**
///      전송 배지     별도 줄 / r6 / pad 7,3 → **부제와 같은 줄 / r5 / pad 6,1**
///      🔴 접힘/펼침  이전엔 바와 펼친 내용이 **둘 다** 보였다.
///                    원본은 **배타적**이다 — 펼치면 바가 사라진다.
class _VendorShareCard extends StatelessWidget {
  const _VendorShareCard({
    required this.share,
    required this.open,
    required this.onToggle,
    required this.onExport,
    this.exportedAt,
    this.smallOnly = false,
  });

  final SettleVendorShare share;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onExport;
  final String? exportedAt;
  final bool smallOnly;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(kSettleCardRadius);

    return Container(
      decoration: BoxDecoration(
        color: kSettleCardBg,
        borderRadius: radius,
        border: Border.all(color: kSettleCardLine),
      ),
      // 원본 `Card { padding: 16 }` — 카드 전체가 하나의 16 패딩이다.
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 머리 (누르면 접기/펼치기) ──────────────────────
          //
          // `InkWell` 을 패딩 안에 두므로 잉크가 카드 밖으로 새지 않는다.
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle,
              child: Row(
                // 원본 `alignItems: 'center'`.
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const FnReceiptTile(), // 원본 기본 size 40
                  const SizedBox(width: 12), // 원본 `gap: 12`
                  // 반응형: 원본 `flex:1, minWidth:0`.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          share.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                            color: kSettleInk,
                          ),
                        ),
                        const SizedBox(height: 4), // 원본 `marginTop: 4`
                        // 원본 `flexWrap:'wrap', gap:6` — 배지가 많아
                        // 한 줄을 넘치면 다음 줄로 접힌다. 반응형의 핵심.
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${share.count}건 · 최근 ${share.lastDateLabel}',
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 12.5,
                                color: kSettleMute,
                              ),
                            ),
                            SettleTaxBadge(tax: share.tax),
                            // 원본 `v.sent ? span(...) : null` — 같은 줄이다.
                            if (exportedAt != null) _SentBadge(at: exportedAt!),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 원본 `textAlign:'right', flexShrink:0`.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        settleWon(share.total),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: kSettleInk,
                        ),
                      ),
                      const SizedBox(height: 3), // 원본 `marginTop: 3`
                      // 원본 `transform: open ? 'rotate(90deg)' : 'none'`
                      // — 접힘 `›` → 펼침 `v` (시계방향 90도).
                      AnimatedRotation(
                        turns: open ? 0.25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: kSettleCaret,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── 🔴 원본은 접힘/펼침이 **배타적**이다 ────────────
          //
          //   open ? (거래 목록 + 정산서 버튼) : (점유율 바 + 캡션)
          //
          // 펼쳤으면 바를 감춘다. 카드를 연 사람은 이미 "이 거래처가
          // 뭘 샀나"를 보려는 것이고, 그 순간 점유율은 관심 밖이다.
          // (이전 구현은 둘을 동시에 보여줘서 카드가 세로로 길어졌다.)
          if (open) _expandedBody() else _collapsedBar(),
        ],
      ),
    );
  }

  /// 접힌 상태 — 점유율 바.
  ///
  /// ```js
  /// div { marginTop: 12 }
  ///   div { height:6, borderRadius:3,
  ///         background:'rgba(112,115,124,.10)', overflow:'hidden' }
  ///     div { width: pct+'%', height:'100%', borderRadius:3,
  ///           background:'linear-gradient(90deg,#EE7686 0%,#F9A7A0 100%)' }
  ///   div { fontSize:11.5, color:MUTE, marginTop:6 }  '전체 매입의 N%'
  /// ```
  Widget _collapsedBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12), // 원본 `marginTop: 12`
        SettleShareBar(share: share.share),
        const SizedBox(height: 6), // 캡션 `marginTop: 6`
        Text(
          // 원본 문구 `'전체 매입의 ' + pct + '%'`.
          // "전체" 는 헤더에 찍힌 조회 기간을 말한다. 헤더 금액이 곧
          // 분모이므로 두 숫자가 항상 서로 맞는다.
          share.shareLabel,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 11.5,
            color: kSettleMute,
          ),
        ),
      ],
    );
  }

  /// 펼친 상태 — 거래 목록 (+ 소액 결제) + 정산서 버튼.
  ///
  /// ```js
  /// div { marginTop:14, paddingTop:12, borderTop:'1px solid '+HAIR,
  ///       column, gap:2 }
  ///   v.tx.map(...)                                        // 거래 줄
  ///   smallOnly && v.small.length ? 소액 블록 : null
  ///   Button { size:'small', variant:'outlined',
  ///            marginTop:8, alignSelf:'flex-start' } '이 업체 정산서 만들기'
  /// ```
  Widget _expandedBody() {
    // 원본 `smallOnly && (v.small || []).length` — 3만원 이하 결제.
    final small = smallOnly
        ? share.receipts
            .where((r) => r.totalAmount > 0 && r.totalAmount <= kSmallPayLimit)
            .toList()
        : const <ReceiptModel>[];

    final rows = <Widget>[];
    for (var i = 0; i < share.receipts.length; i++) {
      if (i > 0) rows.add(const SizedBox(height: 2)); // 원본 `gap: 2`
      rows.add(_VendorReceiptRow(receipt: share.receipts[i]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14), // 원본 `marginTop: 14`
        // 원본 `borderTop: '1px solid ' + HAIR`.
        Container(height: 1, color: kSettleHair),
        const SizedBox(height: 12), // 원본 `paddingTop: 12`
        ...rows,

        // #115: 이제 상위(`SettleLiveData.scopedReceipts`)에서 3만원
        //    이하만 남기므로, 칩을 켜면 `small` 이 `share.receipts` 와
        //    완전히 같아진다. 그대로 둔으면 또같은 내역이 밑에 한번 더
        //    반복된다. 목록과 달라질 때만 별도 바록으로 보여준다.
        if (small.isNotEmpty && small.length != share.receipts.length)
          _smallBlock(small),

        const SizedBox(height: 8), // 원본 버튼 `marginTop: 8`
        // 원본 `alignSelf: 'flex-start'`.
        Align(
          alignment: Alignment.centerLeft,
          child: _OutlinedSmallButton(
            label: '이 업체 정산서 만들기',
            onPressed: onExport,
          ),
        ),
      ],
    );
  }

  /// 종합소득세용(5월) 보기의 소액 결제 블록.
  ///
  /// ```js
  /// div { marginTop:8, paddingTop:8, borderTop:'1px solid '+HAIR }
  ///   div { fontSize:12, fontWeight:700, color:MUTE, marginBottom:4 }
  ///     '3만원 이하 결제'
  ///   v.small.map(p => div { flex, justifyContent:'space-between',
  ///                          fontSize:14, padding:'4px 0' }
  ///     span { color:MUTE } p[0]          // 날짜
  ///     span { w600, color:INK } won(p[1]) // 금액
  /// ```
  ///
  /// 🔴 왜 3만원인가: 3만원 이하 결제는 적격증빙(세금계산서·카드전표)
  ///    없이도 비용으로 인정된다. 5월 종합소득세 신고 때 따로 모아
  ///    봐야 하는 금액대라서 원본이 이 블록을 둔 것이다.
  Widget _smallBlock(List<ReceiptModel> small) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8), // 원본 `marginTop: 8`
        Container(height: 1, color: kSettleHair),
        const SizedBox(height: 8), // 원본 `paddingTop: 8`
        const Text(
          '3만원 이하 결제',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: kSettleMute,
          ),
        ),
        const SizedBox(height: 4), // 원본 `marginBottom: 4`
        for (final r in small)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4), // `'4px 0'`
            child: Row(
              // 원본 `justifyContent: 'space-between'`.
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${r.date.month.toString().padLeft(2, '0')}.'
                  '${r.date.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    color: kSettleMute,
                  ),
                ),
                Text(
                  settleWon(r.totalAmount),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: kSettleInk,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 전송 완료 배지.
///
/// ```js
/// span { fontSize:11, fontWeight:600, padding:'1px 6px', borderRadius:5,
///        background:'#EFF5E7', color:'#5F8347' }  '전송 ' + v.sent
/// ```
class _SentBadge extends StatelessWidget {
  const _SentBadge({required this.at});

  final String at;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        // 원본 `#EFF5E7` = `FnColors.leaf95`.
        color: FnColors.leaf95,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '전송 $at',
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.4,
          // 원본 `#5F8347` = `FnColors.leaf30`.
          color: FnColors.leaf30,
        ),
      ),
    );
  }
}

/// 원본 디자인 시스템 `Button { size:'small', variant:'outlined' }`.
///
/// ```js
/// small: { height:32, radius:8, padX:14, font:14 }
/// outlined → background transparent,
///            boxShadow 'inset 0 0 0 1px var(--line-normal-normal)',
///            color primary(= ROSE, 템플릿이 --blue-50 을 #EE7686 로 덮어씀)
/// fontWeight 600
/// ```
///
/// 🔴 이전 구현은 font 13 / padding 12,8 / 외곽선을 카드선(분홍)으로 줬다.
///    원본 외곽선은 분홍이 아니라 중립 회색 `rgba(112,115,124,.22)` 다.
class _OutlinedSmallButton extends StatelessWidget {
  const _OutlinedSmallButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            // 원본 `inset 0 0 0 1px var(--line-normal-normal)` = 22% 회색.
            border: Border.all(color: FnColors.lineNormal),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: FnColors.rose50,
            ),
          ),
        ),
      ),
    );
  }
}

/// 펼친 카드 안의 거래 한 줄.
///
/// ```js
/// div { flex, alignItems:'center', gap:10, padding:'9px 0', cursor:'pointer' }
///   span { fontSize:12.5, color:MUTE, width:44, flexShrink:0 }   'MM.DD'
///   span { flex:1, minWidth:0, fontSize:14.5, color:INK, ellipsis }
///        t.items[0][0] + (len>1 ? ' 외 '+(len-1)+'건' : '')
///   span { fontSize:14.5, fontWeight:600, color:INK, flexShrink:0 }  금액
/// ```
///
/// 🔴 이전 구현과 다른 점:
///      날짜 칸 폭   42 → **44**
///      간격         6 / 8 → **10 균일**
///      품목·금액    14 → **14.5**
///      위아래 여백  7 → **9**
///
/// 🔴 여기서는 날짜별 카드와 달리 `외 N건` 이 **맞다.**
///    원본이 이 줄에서만 `items[0][0] + ' 외 N건'` 을 쓴다. 카드 안쪽
///    이라 폭이 더 좁아서다. 두 곳의 규칙이 다른 게 원본의 의도다.
class _VendorReceiptRow extends StatelessWidget {
  const _VendorReceiptRow({required this.receipt});

  final ReceiptModel receipt;

  @override
  Widget build(BuildContext context) {
    final d = receipt.date;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReceiptDetailScreen(receipt: receipt),
        )),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9), // `'9px 0'`
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 원본 `width: 44, flexShrink: 0`.
              SizedBox(
                width: 44,
                child: Text(
                  '${d.month.toString().padLeft(2, '0')}.'
                  '${d.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12.5,
                    color: kSettleMute,
                  ),
                ),
              ),
              const SizedBox(width: 10), // 원본 `gap: 10`
              // 반응형: 원본 `flex:1, minWidth:0` + ellipsis.
              Expanded(
                child: Text(
                  receiptShortSummary(receipt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14.5,
                    color: kSettleInk,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 원본 `flexShrink: 0`.
              Text(
                settleWon(receipt.totalAmount),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: kSettleInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  ⑦ 공용 조각
// ════════════════════════════════════════════════════════════════

/// 점유율 바.
///
/// ```js
/// div { height:6, borderRadius:3,
///       background:'rgba(112,115,124,.10)', overflow:'hidden' }
///   div { width: pct+'%', height:'100%', borderRadius:3,
///         background:'linear-gradient(90deg, #EE7686 0%, #F9A7A0 100%)' }
/// ```
///
/// 🔴 `widthFactor` 는 0~1 을 벗어나면 예외가 난다. NaN 도 안 된다.
///    금액 데이터에서 온 값이므로 반드시 막아둔다.
///
/// 🔴 #98 에서 시안 이미지를 픽셀로 재서 "높이 7, 색
///    (236,123,141)→(255,166,162)" 로 넣었다. 이미지가 약 1.36배 확대
///    캡처였기 때문에 높이가 6→7 로 부풀고 색도 보간 때문에 어긋난
///    값이었다. 원본은 높이 **6**, 색 **#EE7686 → #F9A7A0** 이다.
class SettleShareBar extends StatelessWidget {
  const SettleShareBar({super.key, required this.share});

  final double share;

  @override
  Widget build(BuildContext context) {
    final f = share.isFinite ? share.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 6,
        // 원본 `rgba(112,115,124,.10)`.
        color: const Color(0x1A70737C),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            // 값이 아주 작아도 막대가 보이게 최소 폭을 준다.
            // 0 이면 "데이터가 없다" 로 오해한다.
            widthFactor: f > 0 && f < 0.015 ? 0.015 : f,
            child: Container(
              decoration: BoxDecoration(
                // 원본 `linear-gradient(90deg, #EE7686 0%, #F9A7A0 100%)`.
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFFEE7686), Color(0xFFF9A7A0)],
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 과세 / 면세 배지 — 원본 `taxTag(tax)`.
///
/// ```js
/// span { fontSize:11, fontWeight:500, padding:'1px 6px', borderRadius:5,
///        background:'rgba(112,115,124,.06)', color:MUTE, flexShrink:0 }
///   tax === 'exempt' ? '면세' : '과세'
/// ```
///
/// 🔴 면세/과세 **둘 다 같은 회색**이다. 초록/분홍으로 칠하면 "면세는
///    좋고 과세는 위험" 같은 뜻이 생기는데, 둘 다 그냥 사실 표기일
///    뿐이다. 색으로 판단을 유도하지 않는다.
///
/// 🔴 값 자체(어느 거래처가 면세인가)는 [VendorTaxService] 가 정한다.
///    이번 요청에서 면세 판정 로직은 건드리지 않았다 ("일단 면세 문제는 두고").
class SettleTaxBadge extends StatelessWidget {
  const SettleTaxBadge({super.key, required this.tax});

  final TaxType tax;

  @override
  Widget build(BuildContext context) {
    final exempt = tax == TaxType.exempt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        // 원본 `rgba(112,115,124,.06)`. `fillNormal`(8%)보다 옅다.
        color: const Color(0x0F70737C),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        exempt ? '면세' : '과세',
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: kSettleMute,
        ),
      ),
    );
  }
}


// ════════════════════════════════════════════════════════════════
//  #142 내역 전용 필터칩
// ════════════════════════════════════════════════════════════════

/// 시안 내역 화면의 필터칩.
///
/// 🔴 공용 [FnDsChip] 을 쓰지 않는 이유.
///    공용 칩은 `outlined` 비활성 = 투명 + 회색 테두리,
///    `active` = 연분홍 채움 + 코랄 글자다.
///    시안을 픽셀로 재 보니 내역 화면 칩은
///      비활성 = 흰 채움 + 얕은 그림자(테두리 없음)
///      활성   = 검정(#171717) 채움 + 흰 글자
///    로 **완전히 다른 모습**이었다.
///
///    공용 칩을 바꾸면 이 칩을 쓰는 다른 화면이 전부 같이 바뀐다.
///    그래서 내역 화면만 쓰는 칩을 따로 둔다.
///
/// 실측: 높이 32dp, 모서리 10dp, 좌우 여백 11dp, 글자 13.
class SettleFilterChip extends StatelessWidget {
  const SettleFilterChip({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kSettleChipRadius),
        // 🔴 `Wrap` 안에서는 자식이 느슨한 제약을 받는다. `alignment` 를
        //    주면 `AnimatedContainer` 가 **줄 폭 전체로 늘어나** 칩이
        //    한 줄에 하나씩 쌓였다. 글자 크기만큼만 차지하도록
        //    `alignment` 를 빼고 `IntrinsicWidth` 대신 자연 폭에 맡긴다.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: kSettleChipH,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: active ? kSettleChipOn : kSettleChipOff,
            borderRadius: BorderRadius.circular(kSettleChipRadius),
            // 눌린 칩은 검정이라 그림자가 보이지 않는다. 시안도 그렇다.
            boxShadow: active ? null : kSettleShadowSm,
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? Colors.white : kSettleInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// 시안 내역 화면 검색창.
///
/// 🔴 공용 [FnSearchBar] 를 쓰지 않는 이유.
///    공용 검색창 채움은 `FnColors.fillNormal`(8% 회색 반투명)이라
///    따뜻한 배경 위에서 #F4F4F5 로 보인다. 시안 검색창 내부는
///    #FFFFFF 가 90% 인 **완전한 흰색 + 얕은 그림자**다.
///
///    공용 부품을 고치면 이 검색창을 쓰는 다른 화면이 전부 바뀐다.
///    그래서 내역 화면 전용으로 따로 둔다. 동작은 공용과 같다.
///
/// 실측: 높이 48dp(y 397.8..445.7), 모서리 12dp, 좌우 여백 14dp.
class SettleSearchBar extends StatelessWidget {
  const SettleSearchBar({
    super.key,
    required this.controller,
    this.placeholder = '검색',
    this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: kSettleWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: kSettleShadowSm,
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              size: 19, color: FnColors.labelAlternative),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                color: kSettleInk,
              ),
              cursorColor: kSettleCoral,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: placeholder,
                hintStyle: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  color: FnColors.labelAssistive,
                ),
              ),
            ),
          ),
          // 입력이 있을 때만 지우기 단추를 보인다 (공용과 같은 동작).
          if (controller.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClear,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: FnColors.fillStrong,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.close_rounded,
                    size: 11, color: FnColors.labelAlternative),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
