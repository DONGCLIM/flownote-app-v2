import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_card.dart';
import '../../design/fn_icons.dart';
import '../../design/fn_button.dart';
import '../../design/fn_home_tokens.dart';
import '../../providers/receipt_provider.dart';
import '../../services/subscription_service.dart';
import 'fn_data.dart';
import 'insight_ds_screens.dart';

/// 홈 화면 — #135 시안(PNG) 기준으로 톤앤톤/컬러를 다시 맞춘 버전.
///
/// 시안을 그림으로 붙이지 않고 전부 위젯으로 다시 그렸다. 데이터는 예전과
/// 똑같이 `FnDemo.resolve(ReceiptProvider)` 에서 오고, 누르면 열리던 화면도
/// 하나도 빼지 않았다.
///
/// | 시안 블록            | 눌렀을 때            | 예전 위치           |
/// |----------------------|---------------------|---------------------|
/// | 이번 달 총 지출(코랄) | TrendDsScreen       | _totalCard          |
/// | 지출 추이 막대        | TrendDsScreen       | _chartsCard 왼쪽     |
/// | 품목 비중 / 상세 분석 | DonutDsScreen (Pro) | _chartsCard 오른쪽   |
/// | 스마트 사입 가이드    | GuideDsScreen (Pro) | _guideCard          |
/// | 여름철 팁 / 시세      | PriceDsScreen       | _priceCard          |
/// | 맞춤 사입 리포트 보기 | InsightsDsScreen(Pro)| _insightCard 더보기 |
/// | 알림 카드의 인사이트  | _openInsight(첫 항목)| _insightCard 본문   |
class HomeDsScreen extends StatefulWidget {
  const HomeDsScreen({super.key});

  @override
  State<HomeDsScreen> createState() => _HomeDsScreenState();
}

class _HomeDsScreenState extends State<HomeDsScreen> {
  int? _activeSlice;

  bool get _isPro => SubscriptionService.instance.isPro;

  void _proModal(String title, String desc) {
    showDialog<void>(
      context: context,
      builder: (_) => _ProModal(title: title, desc: desc),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 실제 데이터가 있으면 사용, 없으면 시안 데모 데이터로 렌더
    final rp = context.watch<ReceiptProvider>();
    final d = FnDemo.resolve(rp);

    return Container(
      color: FnHome.bg,
      child: FnColumn(
        gap: FnHome.gap,
        padding: const EdgeInsets.fromLTRB(
          FnHome.pagePad,
          8,
          FnHome.pagePad,
          20,
        ),
        children: [
          _noticeCard(d),
          _totalCard(d),
          _chartsCard(d),
          _guideSection(d),
          _ctaButton(d),
        ],
      ),
    );
  }

  /// 지출 추이 막대 개수 — 최대 6개, 데이터가 적으면 있는 만큼.
  int _tailCount(FnDemoData d) {
    final n = d.months.length < d.spend.length ? d.months.length : d.spend.length;
    return n < 6 ? n : 6;
  }

  /// 시안 막대 라벨은 퍼센트다. 최댓값을 100 으로 두고 환산한다.
  List<({String label, double pct, double value})> _bars(FnDemoData d) {
    final n = _tailCount(d);
    if (n == 0) return const [];
    final from = d.spend.length - n;
    final vals = d.spend.sublist(from);
    final labels = d.months.sublist(d.months.length - n);
    var max = 0.0;
    for (final v in vals) {
      if (v > max) max = v;
    }
    // 시안의 마지막 막대가 76% 였다. 최댓값을 76% 에 맞춰야 같은 인상이 된다.
    const topPct = 76.0;
    return List.generate(n, (i) {
      final pct = max <= 0 ? 0.0 : vals[i] / max * topPct;
      return (label: labels[i], pct: pct, value: vals[i]);
    });
  }

  // ── 1 : 알림 카드 ─────────────────────────────────────────────────
  /// 시안의 "이번 달 영수증 정리 완료!" 줄. 책 아이콘 + 두 줄 글.
  /// 누르면 예전 `_insightCard` 본문과 똑같이 첫 인사이트로 간다.
  Widget _noticeCard(FnDemoData d) {
    final first = d.insights.isEmpty ? null : d.insights.first;
    final sub = first == null
        ? '영수증을 모으면 맞춤 분석을 보여드릴게요.'
        : first.text;
    return _Tappable(
      onTap: first == null ? null : () => _openInsight(first),
      radius: FnHome.radius,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: BoxDecoration(
          // 🔴 #146 시안 실측: 카드1 내부색은 순백이 아니라 #FFFDFC 다.
          //    (카드3·4 는 순백 #FFFFFF) 사장님이 "카드마다 컬러가 다르다"고
          //    하신 게 이 차이였다.
          color: FnHome.cardWarm,
          borderRadius: BorderRadius.circular(FnHome.radius),
          border: Border.all(color: FnHome.cardLine),
          // 시안 Δ 9.4 — 다른 카드(19.4)의 절반 수준으로 가장 옅다.
          boxShadow: FnHome.shadowSoft,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔴 #146 사장님 지시: "맨 위에 있는 카드에 아이콘은 오른쪽에
            //    있는 아이콘으로 바꿔줘"
            //    전에는 분홍 둥근 사각(38x38, #FFF1EE) 안에
            //    `Icons.menu_book_rounded` 를 넣었다.
            //    시안·원본 아이콘에는 **박스가 없다.** 펼친 책만 떠 있고
            //    주변으로 분홍 글로우가 번진다. 책은 좌/우 페이지가
            //    다른 색인 투톤이다.
            SizedBox(
              width: 38,
              height: 38,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: FnHome.bookGlow,
                  ),
                  child: const FnBookIcon(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${d.receiptCount}매 영수증 정리 완료!',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: FnHome.title,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12.5,
                      height: 1.35,
                      color: FnHome.body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 2 : 이번 달 총 지출 (코랄 그라디언트) ─────────────────────────
  /// 예전 `_totalCard` 와 같은 수치(총지출/전월/영수증수/변동폭)를 쓰되,
  /// 시안처럼 코랄 그라디언트 카드 + 흰 통계 패널로 그린다.
  Widget _totalCard(FnDemoData d) {
    final up = d.pctUp >= 0;
    return _Tappable(
      onTap: () => _push(const TrendDsScreen()),
      radius: FnHome.coralRadius,
      // 🔴 #147 사장님 지적: "두번째 카드에도 데코가 들어가 있거든"
      //    #146 에서 이 데코를 빠뜨렸다. 시안 우상단에 손그림 획
      //    (꼬리 점 + 고리 2개 + 떨어진 점)이 그라데이션 위에 얹혀 있다.
      //
      //    구조: ClipRRect(모서리) > Stack [ 그라데이션+데코, 내용 ]
      //    - 데코 고리 하나가 카드 **위쪽 경계 밖으로 잘려** 있어서
      //      ClipRRect 가 반드시 필요하다.
      //    - 데코는 `IgnorePointer` 로 감싸 터치를 가로막지 않게 한다.
      //      (카드 전체가 `_Tappable` 로 추이 화면으로 가는 버튼이다)
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FnHome.coralRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: FnHome.coralGradient,
            borderRadius: BorderRadius.circular(FnHome.coralRadius),
          ),
          child: Stack(
            children: [
              // 데코는 고정 크기로 우상단에 붙인다(시안 여백 우 6.2 / 상 2.5dp).
              const Positioned(
                top: FnHome.decoTop,
                right: FnHome.decoRight,
                child: IgnorePointer(child: FnCoralDeco()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: FnHome.coralFaint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '이번 달 총 지출',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: FnHome.coralText,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                FnDemo.won(d.thisMonth),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    _stat('전월 지출', FnDemo.won(d.lastMonth), FnHome.title),
                    const _StatDivider(),
                    _stat('영수증', '${d.receiptCount}매', FnHome.title),
                    const _StatDivider(),
                    _stat(
                      '변동폭',
                      '${up ? '+' : ''}${d.pctUp}%',
                      up ? FnHome.coralText : FnColors.statusPositive,
                    ),
                  ],
                ),
              ),
            ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color valueColor) {
    // 🔴 가로 패딩이 없으면 긴 금액(₩2,620,000)의 오른쪽 끝이 구분선에
    //    딱 붙는다. 320/360/390 전부에서 간격이 정확히 0.0px 였다.
    //    시안은 패널 안쪽 여백이 14.8dp 였으므로 좌우 7 씩 둔다.
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11,
              color: FnHome.muted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  // ── 3 : 지출 추이 + 품목 비중 (흰 카드) ───────────────────────────
  /// 예전 `_chartsCard` 의 두 기능을 시안 배치로 옮겼다.
  ///  - 왼쪽 막대 그래프 → 세로 막대 6개 (마지막만 코랄 강조)
  ///  - 오른쪽 도넛      → 가로 누적 바 + 범례
  /// `_activeSlice`, Pro 모달, `상세 분석 보기` 전부 그대로다.
  Widget _chartsCard(FnDemoData d) {
    const proTitle = '🔒 면세/과세 상세 분석은 Pro 전용이에요';
    const proDesc = '꽃값과 부자재 지출 비율을 비교해\n부가세 신고와 지출 관리를 쉽게 도와드려요.';
    final bars = _bars(d);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        // 시안 실측 순백. 그림자 Δ 19.4 로 홈에서 가장 진하다.
        color: FnHome.card,
        borderRadius: BorderRadius.circular(FnHome.radius),
        border: Border.all(color: FnHome.cardLine),
        boxShadow: FnHome.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _SectionTitle('지출 추이'),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: FnHome.coralFaint,
                  borderRadius: BorderRadius.circular(20),
                ),
                // 🔴 #153 bars 가 비면 "최근 0개월" 이 떠서 고장처럼 보인다.
                child: Text(
                  bars.isEmpty ? '기록 없음' : '최근 ${bars.length}개월',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: FnHome.coralText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _push(const TrendDsScreen()),
            child: _BarRow(bars: bars),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _SectionTitle('품목 비중'),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _isPro
                    ? _push(const DonutDsScreen())
                    : _proModal(proTitle, proDesc),
                child: const Text(
                  '상세 분석 보기 >',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: FnHome.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StackBar(
            parts: _mix(d),
            onTap: (i) {
              if (_isPro) {
                setState(() => _activeSlice = i);
              } else {
                _proModal(proTitle, proDesc);
              }
            },
            activeIndex: _activeSlice,
          ),
          const SizedBox(height: 12),
          _Legend(parts: _mix(d)),
          if (_isPro && _activeSlice == 0)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: FnHome.coralFaint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '부자재 지출 비율이 전월 대비 5% 증가했어요',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12.5,
                  color: FnHome.title,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 품목 비중 — 실데이터의 과세/면세 집계(`d.taxData`)를 시안 색으로 칠한다.
  /// 시안은 네 칸(절화/부자재/화분·식물/기타)이지만 실집계는 두 칸이라,
  /// 있는 만큼만 그리고 색만 시안 순서대로 쓴다.
  List<({String label, double value, Color color})> _mix(FnDemoData d) {
    final src = d.taxData;
    if (src.isEmpty) return const [];
    return List.generate(src.length, (i) {
      return (
        label: src[i].label,
        value: src[i].value,
        color: FnHome.stack[i % FnHome.stack.length],
      );
    });
  }

  // ── 4 : 스마트 사입 가이드 ─────────────────────────────────────────
  /// 예전 `_guideCard` + `_priceCard` 를 시안의 한 묶음으로 합쳤다.
  /// 제목/부제는 카드 밖, 본문은 흰 카드 안 — 시안과 같은 구성이다.
  Widget _guideSection(FnDemoData d) {
    // 🔴 제목·부제·카드가 한 덩어리로 눌린다.
    //    예전에는 흰 카드만 눌렸다. 사장님이 제목을 눌렀을 때 아무 일도
    //    안 일어나면 "고장났나" 하게 된다. 그래서 묶음 전체를 감쌌다.
    //
    // 🔴 `behavior: opaque` 를 준다. Column 의 글자 사이 빈 곳은 기본값
    //    (`deferToChild`)이면 터치를 안 받아서, 여백을 누르면 반응이 없다.
    return _Tappable(
      onTap: _openGuide,
      radius: FnHome.radius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 2),
            child: Text(
              '스마트 사입 가이드',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: FnHome.title,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 12),
            child: Text(
              '지난 매입 데이터로 올해 시즌과 월별 사입 기준을 세워요',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                height: 1.4,
                color: FnHome.body,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              // 시안 실측 순백. 그림자 Δ 15.9.
              color: FnHome.card,
              borderRadius: BorderRadius.circular(FnHome.radius),
              border: Border.all(color: FnHome.cardLine),
              boxShadow: FnHome.shadowCard,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _guideStat(
                          Icons.event_repeat_rounded,
                          '권장 사입 주기',
                          '주 3회 분할',
                          '회수 분산 권장일 분산',
                          FnHome.title,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _guideStat(
                          Icons.local_florist_rounded,
                          '권장 절화 비중',
                          _exemptPct(d),
                          '현재 ${_exemptPct(d)} · 기본 소재 추천',
                          FnHome.coralText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _tipBox(d),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 스마트 사입 가이드 열기.
  ///
  /// 제목·부제·카드 어디를 눌러도 같은 곳으로 간다. 분기가 두 군데로
  /// 갈라지면 한쪽만 고쳐 놓고 다른 쪽을 잊게 되므로 함수로 모았다.
  void _openGuide() {
    if (_isPro) {
      _push(const GuideDsScreen());
      return;
    }
    _proModal(
      '🔒 스마트 사입 가이드는\nPro 전용이에요',
      '지난 시즌과 월별 흐름을 분석해\n다음 사입을 더 알뜰하게 준비하도록 도와드려요.',
    );
  }

  Widget _guideStat(
      IconData icon, String label, String value, String sub, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: FnHome.muted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: FnHome.muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 10.5,
            color: FnHome.muted,
          ),
        ),
      ],
    );
  }

  /// 시안의 "현재 68%" 자리 — 실집계의 면세(생화) 비중을 쓴다.
  String _exemptPct(FnDemoData d) {
    final list = d.taxData;
    if (list.isEmpty) return '-';
    var total = 0.0;
    for (final e in list) {
      total += e.value;
    }
    if (total <= 0) return '-';
    // 면세(생화) 항목을 찾는다. 없으면 첫 항목.
    var target = list.first;
    for (final e in list) {
      if (e.label.contains('면세')) target = e;
    }
    return '${(target.value / total * 100).round()}%';
  }

  /// 시안의 "여름철 절화 수명 관리 팁" 카드.
  /// 예전 `_priceCard` 가 보여주던 품목 시세로 이어진다.
  Widget _tipBox(FnDemoData d) {
    final name = d.priceData.isEmpty ? null : d.priceData.keys.first;
    final item = name == null ? null : d.priceData[name]!;
    final line = item == null
        ? '영수증이 쌓이면 품목별 단가 흐름을 알려드려요.'
        : '$name 단가가 ${FnDemo.won(item.unit)}/단으로 '
            '전월 대비 ${item.chg >= 0 ? '+' : ''}${item.chg}% 입니다.';
    return _Tappable(
      onTap: name == null ? null : () => _push(const PriceDsScreen()),
      radius: 14,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: FnHome.coralFaint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '여름철 절화 수명 관리 팁',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: FnHome.coralText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              line,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                height: 1.5,
                color: FnHome.body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 5 : CTA ───────────────────────────────────────────────────────
  /// 시안의 코랄 버튼. 예전 `_insightCard` 의 '더보기' 와 같은 곳으로 간다.
  Widget _ctaButton(FnDemoData d) {
    final month = d.months.isEmpty ? '' : '${d.months.last} ';
    return _Tappable(
      onTap: () => _isPro
          ? _push(const InsightsDsScreen())
          : _proModal('🔒 전체 인사이트는 Pro 전용이에요',
              '이번 달 모든 인사이트를 확인하려면 Pro 구독이 필요해요'),
      radius: 18,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: FnHome.coralGradient,
          borderRadius: BorderRadius.circular(18),
          // 시안 Δ 15.0 이 버튼 아래로 6dp 넘게 길게 깔린다.
          boxShadow: FnHome.shadowCoralBtn,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                '$month맞춤 사입 리포트 보기',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded,
                size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }

  void _openInsight(FnInsight it) {
    switch (it.target) {
      case FnInsightTarget.price:
        _push(const PriceDsScreen());
      case FnInsightTarget.compare:
        _push(const CompareDsScreen());
      case FnInsightTarget.donut:
        _push(const DonutDsScreen());
      case FnInsightTarget.trend:
        _push(const TrendDsScreen());
    }
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

/// 카드 전체를 누를 수 있게 감싸는 공통 래퍼.
/// `FnCard` 는 그림자/테두리를 같이 들고 있어서, 시안처럼 그라디언트나
/// 커스텀 테두리를 쓰는 블록에는 맞지 않는다. 그래서 눌림만 담당한다.
class _Tappable extends StatelessWidget {
  const _Tappable({required this.child, this.onTap, this.radius = 16});
  final Widget child;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        // 🔴 글자 사이 빈 곳도 눌리게 한다. 기본값이면 자식 위젯이
        //    있는 자리만 터치를 받아서, 여백을 누르면 아무 일도 안 난다.
        child: Container(color: Colors.transparent, child: child),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: FnHome.title,
        ),
      );
}

/// 코랄 카드 안 통계 패널의 세로 구분선. 시안에서 아주 옅은 회색이었다.
class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: const Color(0x14000000),
      );
}

/// 시안의 세로 막대 그래프.
///
/// 막대 위에 퍼센트, 아래에 월 라벨. 마지막(이번 달)만 폭이 넓고
/// 코랄 그라디언트로 강조된다. 좁은 화면에서는 `Expanded` 로 폭을
/// 나눠 가지므로 6개가 넘쳐 잘리지 않는다.
class _BarRow extends StatelessWidget {
  const _BarRow({required this.bars});
  final List<({String label, double pct, double value})> bars;

  @override
  Widget build(BuildContext context) {
    // 🔴 #153 예전에는 여기서 `SizedBox(height: barFull)` 을 돌려줬다.
    //    그러면 아무것도 없는 94dp 빈칸이 카드 안에 남는다(#136 지적).
    //
    //    지금 데이터 경로상 `months`/`spend` 는 항상 12개라 이 분기는
    //    사실상 타지 않는다(직접 확인했다). 하지만 들어오면 **빈칸이
    //    아니라 안내문**을 보여주는 게 맞다. 빈칸은 고장처럼 보인다.
    if (bars.isEmpty) {
      return const SizedBox(
        height: FnHome.barFull,
        child: Center(
          child: Text(
            '아직 지출 기록이 없어요',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: FnHome.muted,
            ),
          ),
        ),
      );
    }
    final last = bars.length - 1;
    return SizedBox(
      height: FnHome.barFull + 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(bars.length, (i) {
          final b = bars[i];
          final active = i == last;
          final h = (b.pct / 100 * FnHome.barFull).clamp(6.0, FnHome.barFull);
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${b.pct.round()}%',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: active ? FnHome.coralText : FnHome.title,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  height: h,
                  width: active ? FnHome.barActiveW : FnHome.barW,
                  decoration: BoxDecoration(
                    color: active ? null : FnHome.peach,
                    gradient: active
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [FnHome.coral, FnHome.coralEnd],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(FnHome.barW / 2),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  b.label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? FnHome.coralText : FnHome.axis,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// 시안의 가로 누적 바 (품목 비중).
/// 예전 도넛과 같은 데이터를 쓰고, 조각을 누르면 같은 콜백이 돈다.
class _StackBar extends StatelessWidget {
  const _StackBar({
    required this.parts,
    required this.onTap,
    this.activeIndex,
  });

  final List<({String label, double value, Color color})> parts;
  final ValueChanged<int> onTap;
  final int? activeIndex;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    var total = 0.0;
    for (final p in parts) {
      total += p.value;
    }
    if (total <= 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(FnHome.stackH / 2),
      child: SizedBox(
        height: FnHome.stackH,
        child: Row(
          children: List.generate(parts.length, (i) {
            final p = parts[i];
            // flex 는 정수라 소수 비율을 1000 배로 키워 정밀도를 지킨다.
            final flex = (p.value / total * 1000).round().clamp(1, 1000);
            return Expanded(
              flex: flex,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Container(
                  color: p.color,
                  foregroundDecoration: activeIndex == i
                      ? BoxDecoration(
                          border: Border.all(color: FnHome.coralText, width: 2),
                        )
                      : null,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// 누적 바 범례 — 2열. 점 + 이름 + 퍼센트.
class _Legend extends StatelessWidget {
  const _Legend({required this.parts});
  final List<({String label, double value, Color color})> parts;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    var total = 0.0;
    for (final p in parts) {
      total += p.value;
    }
    if (total <= 0) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var i = 0; i < parts.length; i += 2) {
      final left = parts[i];
      final right = i + 1 < parts.length ? parts[i + 1] : null;
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
        child: Row(
          children: [
            Expanded(child: _item(left, total)),
            const SizedBox(width: 12),
            Expanded(
              child: right == null
                  ? const SizedBox.shrink()
                  : _item(right, total),
            ),
          ],
        ),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _item(
      ({String label, double value, Color color}) p, double total) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: p.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            p.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11.5,
              color: FnHome.body,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${(p.value / total * 100).round()}%',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: FnHome.title,
          ),
        ),
      ],
    );
  }
}

/// 시안 `proModalEl`
/// ```js
/// div absolute inset0 rgba(0,0,0,.4) center padding:24
///   Card maxWidth:320 column gap:12 textAlign:center
///     div 18/700 lh1.4    title (\n → br)
///     div 14 label-alternative lh1.6 pre-line   desc
///     Button size large   '닫기'
/// ```
class _ProModal extends StatelessWidget {
  const _ProModal({required this.title, required this.desc});
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: FnCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  color: FnColors.labelNormal,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                desc,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  height: 1.6,
                  color: FnColors.labelAlternative,
                ),
              ),
              const SizedBox(height: 12),
              FnButton(
                label: '닫기',
                size: FnButtonSize.large,
                expand: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
