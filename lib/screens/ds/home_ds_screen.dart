import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_card.dart';
import '../../design/fn_badge_ds.dart';
import '../../design/fn_charts_ds.dart';
import '../../design/fn_button.dart';
import '../../providers/receipt_provider.dart';
import '../../services/subscription_service.dart';
import 'fn_data.dart';
import 'insight_ds_screens.dart';

/// 시안 `AppH3 / screen === 'home'` 1:1 포팅
///
/// 원본 구조
/// ```
/// Shell(navTitle:'홈', tabs, activeTab:'home')
///   div padding:16 column gap:14
///     [dev toggle chip]  flex-end
///     Card bordered  ── 이번 달 총 지출
///     Card bordered  ── 2열 그리드: 지출 추이 / 면세·과세 도넛 + Divider + 상세 분석 보기
///     Card bordered  ── 스마트 사입 가이드 (🔒 Pro)
///     Card bordered  ── 품목 시세 트래커
///     Card bordered  ── 이번 달 인사이트
/// ```
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

    return FnColumn(
      gap: 14,
      children: [
        _totalCard(d),
        _chartsCard(d),
        _guideCard(),
        _priceCard(d),
        _insightCard(d),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Card 1 : 이번 달 총 지출 ───────────────────────────────────────────
  /// ```js
  /// Card bordered
  ///   div 15 / 600 / label-alternative   '이번 달 총 지출'
  ///   div flex baseline gap:8 margin:'4px 0 10px'
  ///     div 24 / 700                      won(thisMonth)
  ///     ContentBadge color: pctUp>=0 ? negative : positive     '+16%'
  ///   div 13 / label-alternative          '영수증 8매 · 전월 ₩262만'
  /// ```
  Widget _totalCard(FnDemoData d) {
    final up = d.pctUp >= 0;
    return FnCard(
      bordered: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '이번 달 총 지출',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: FnColors.labelAlternative,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  FnDemo.won(d.thisMonth),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: FnColors.labelNormal,
                  ),
                ),
                const SizedBox(width: 8),
                FnBadge(
                  '${up ? '+' : ''}${d.pctUp}%',
                  color: up ? FnBadgeColor.negative : FnBadgeColor.positive,
                ),
              ],
            ),
          ),
          Text(
            '영수증 ${d.receiptCount}매 · 전월 ${FnDemo.won(d.lastMonth)}',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              color: FnColors.labelAlternative,
            ),
          ),
        ],
      ),
    );
  }

  // ── Card 2 : 지출 추이 + 면세/과세 도넛 (2열 그리드) ──────────────────
  /// ```js
  /// Card bordered
  ///   div grid 1fr 1fr gap:14
  ///     ├ 지출 추이  (15/600, mb 8) + BarChart(spend.slice(6), w140 h60)
  ///     └ 면세 / 과세 비중 (15/600 self-start mb8) + Donut(size76 thickness14 rotate -57.6)
  ///   [isPro && slice==0] 힌트 박스
  ///   Divider margin '12px 0'
  ///   div center 13/700 blue-50   '상세 분석 보기 >'
  /// ```
  Widget _chartsCard(FnDemoData d) {
    const proTitle = '🔒 면세/과세 상세 분석은 Pro 전용이에요';
    const proDesc = '꽃값과 부자재 지출 비율을 비교해\n부가세 신고와 지출 관리를 쉽게 도와드려요.';

    return FnCard(
      bordered: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 좌: 지출 추이
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _GridTitle('지출 추이'),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _push(const TrendDsScreen()),
                        child: FnBarChart(
                          // 실데이터 집계가 12개월보다 짧아도 인덱스 초과로
                          // 크래시하지 않도록 뒤에서 최대 6개만 잘라 쓴다.
                          data: List.generate(
                            _tailCount(d),
                            (i) => FnChartDatum(
                              label: d.months[d.months.length - _tailCount(d) + i],
                              value: d.spend[d.spend.length - _tailCount(d) + i],
                            ),
                          ),
                          width: 140,
                          height: 60,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // 우: 면세 / 과세 비중
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: _GridTitle('면세 / 과세 비중'),
                      ),
                      const SizedBox(height: 8),
                      FnDonut(
                        data: d.taxData,
                        size: 76,
                        thickness: 14,
                        rotate: -57.6,
                        activeIndex: _activeSlice,
                        onSlice: (i) {
                          if (_isPro) {
                            setState(() => _activeSlice = i);
                          } else {
                            _proModal(proTitle, proDesc);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isPro && _activeSlice == 0)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: FnColors.fillNormal,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '부자재 지출 비율이 전월 대비 5% 증가했어요',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12.5,
                  color: FnColors.labelNormal,
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: FnDsDivider(),
          ),
          GestureDetector(
            onTap: () => _isPro
                ? _push(const DonutDsScreen())
                : _proModal(proTitle, proDesc),
            child: const Text(
              '상세 분석 보기 >',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: FnColors.primaryNormal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 지출 추이 막대 개수 — 최대 6개, 데이터가 적으면 있는 만큼.
  int _tailCount(FnDemoData d) {
    final n = d.months.length < d.spend.length ? d.months.length : d.spend.length;
    return n < 6 ? n : 6;
  }

  // ── Card 3 : 스마트 사입 가이드 ───────────────────────────────────────
  /// ```js
  /// Card bordered onClick
  ///   div flex gap:6 mb:4
  ///     div wds-heading2 fontSize:15   '스마트 사입 가이드'
  ///     ContentBadge accent fontSize:12  '🔒 Pro'
  ///   div 13 label-alternative mb:12 lh1.5  '지난 매입 데이터로 ...'
  ///   div padding:12 radius:10 background: blue-99  flex gap:6
  ///     Icon CircleInfo 16 blue-50
  ///     div 13/400  '쌓인 영수증 데이터로<br>다양한 스마트 사입 리포트를 만들어 드려요'
  /// ```
  Widget _guideCard() {
    return FnCard(
      bordered: true,
      onTap: () => _isPro
          ? _push(const GuideDsScreen())
          : _proModal(
              '🔒 스마트 사입 가이드는\nPro 전용이에요',
              '지난 시즌과 월별 흐름을 분석해\n다음 사입을 더 알뜰하게 준비하도록 도와드려요.',
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                '스마트 사입 가이드',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: FnColors.labelNormal,
                ),
              ),
              const SizedBox(width: 6),
              const FnBadge('🔒 Pro',
                  color: FnBadgeColor.accent, size: FnBadgeSize.small),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '지난 매입 데이터로 올해 시즌과 월별 사입 기준을 세워요',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              height: 1.5,
              color: FnColors.labelAlternative,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FnColors.rose99,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.info_outline_rounded,
                      size: 16, color: FnColors.primaryNormal),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '쌓인 영수증 데이터로\n다양한 스마트 사입 리포트를 만들어 드려요',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.45,
                      color: FnColors.labelNormal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Card 4 : 품목 시세 트래커 ─────────────────────────────────────────
  /// ```js
  /// Card bordered onClick  flex space-between center
  ///   div
  ///     div 15/600  '품목 시세 트래커'
  ///     div 13 label-alternative  '장미(레드) ₩8,000/단'
  ///   ContentBadge cautionary  '+12%'
  /// ```
  Widget _priceCard(FnDemoData d) {
    // 시안은 `priceData['장미(레드)']` 를 하드코딩했지만, 실데이터에서는
    // 품목명이 실제 매입한 꽃 이름(상위 8개)이라 '장미(레드)' 가 없을 수 있다.
    // `!` 로 강제 역참조하면 build() 가 throw 하고, **릴리즈 빌드에서는
    // 화면 전체가 회색 ErrorWidget** 으로 덮인다. (홈 화면 회색 버그)
    // → 항상 첫 품목(무료 공개 품목)을 쓰고, 품목이 없으면 카드를 숨긴다.
    if (d.priceData.isEmpty) return const SizedBox.shrink();
    final name = d.priceData.keys.first;
    final rose = d.priceData[name]!;
    return FnCard(
      bordered: true,
      onTap: () => _push(const PriceDsScreen()),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '품목 시세 트래커',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelNormal,
                ),
              ),
              Text(
                '$name ${FnDemo.won(rose.unit)}/단',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  color: FnColors.labelAlternative,
                ),
              ),
            ],
          ),
          FnBadge(
            '${rose.chg >= 0 ? '+' : ''}${rose.chg}%',
            color: rose.chg >= 0
                ? FnBadgeColor.cautionary
                : FnBadgeColor.positive,
          ),
        ],
      ),
    );
  }

  // ── Card 5 : 이번 달 인사이트 ─────────────────────────────────────────
  /// ```js
  /// Card bordered
  ///   div flex space-between center mb:8
  ///     div wds-heading2 15  '이번 달 인사이트'
  ///     Button variant text size small  '더보기'
  ///   div onClick 13 padding '6px 0'   '· ' + insights[0].text
  /// ```
  Widget _insightCard(FnDemoData d) {
    // 실데이터에서 인사이트가 하나도 계산되지 않을 수 있다 → `.first` 크래시 방어
    if (d.insights.isEmpty) return const SizedBox.shrink();
    final first = d.insights.first;
    return FnCard(
      bordered: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '이번 달 인사이트',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: FnColors.labelNormal,
                ),
              ),
              FnTextButton(
                label: '더보기',
                fontSize: 13,
                onPressed: () => _isPro
                    ? _push(const InsightsDsScreen())
                    : _proModal('🔒 전체 인사이트는 Pro 전용이에요',
                        '이번 달 모든 인사이트를 확인하려면 Pro 구독이 필요해요'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _openInsight(first),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '· ${first.text}',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  color: FnColors.labelNormal,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
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

class _GridTitle extends StatelessWidget {
  const _GridTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: FnColors.labelNormal,
        ),
      );
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
