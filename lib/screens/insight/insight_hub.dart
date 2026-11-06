import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_card.dart';
import '../../design/fn_scaffold.dart';
import '../../services/subscription_service.dart';
import '../paywall_screen.dart';
import '../settlement/settlement_screen.dart';
import 'budget_review_screen.dart';
import 'cost_calculator_screen.dart';
import 'monthly_insight_screen.dart';
import 'price_tracker_screen.dart';
import 'purchase_guide_screen.dart';
import 'season_compare_screen.dart';
import 'tax_ratio_screen.dart';
import 'unit_price_compare_screen.dart';

/// 신규 기능 진입점 정의
class FnFeature {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bg;
  final bool proOnly;
  final WidgetBuilder builder;

  const FnFeature({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bg,
    required this.builder,
    this.proOnly = false,
  });
}

/// 전체 신규 기능 목록 (홈 허브 · 프로필에서 공용으로 사용)
class FnFeatures {
  FnFeatures._();

  static const analysis = <FnFeature>[
    FnFeature(
      title: '스마트 사입 가이드',
      subtitle: '지금 사기 좋은 품목 추천',
      icon: Icons.auto_awesome_rounded,
      color: FnColors.primaryNormal,
      bg: FnColors.rose95,
      builder: _guide,
    ),
    FnFeature(
      title: '시세 트래커',
      subtitle: '품목별 단가 추이',
      icon: Icons.trending_up_rounded,
      color: FnColors.leaf40,
      bg: FnColors.leaf95,
      proOnly: true,
      builder: _tracker,
    ),
    FnFeature(
      title: '단가 비교',
      subtitle: '매입처별 최저가 찾기',
      icon: Icons.compare_arrows_rounded,
      color: FnColors.rose40,
      bg: FnColors.rose95,
      builder: _compare,
    ),
    FnFeature(
      title: '월별 인사이트',
      subtitle: '한 달 매입 리포트',
      icon: Icons.insights_rounded,
      color: FnColors.leaf30,
      bg: FnColors.leaf95,
      builder: _monthly,
    ),
    FnFeature(
      title: '시즌 매입 비교',
      subtitle: '작년 같은 달과 비교',
      icon: Icons.calendar_month_rounded,
      color: FnColors.statusCautionary,
      bg: FnColors.cream,
      builder: _season,
    ),
    FnFeature(
      title: '면세 / 과세 비중',
      subtitle: '부가세 환급액 확인',
      icon: Icons.pie_chart_outline_rounded,
      color: FnColors.taxExempt,
      bg: FnColors.leaf95,
      builder: _tax,
    ),
  ];

  static const management = <FnFeature>[
    FnFeature(
      title: '원가 계산기',
      subtitle: '상품 원가 · 판매가 산출',
      icon: Icons.calculate_outlined,
      color: FnColors.primaryNormal,
      bg: FnColors.rose95,
      builder: _cost,
    ),
    FnFeature(
      title: '예산 검토',
      subtitle: '이번 달 집행률 · 월말 예측',
      icon: Icons.account_balance_wallet_outlined,
      color: FnColors.rose30,
      bg: FnColors.blush,
      builder: _budget,
    ),
    FnFeature(
      title: '정산서 발행',
      subtitle: '매입처별 정산서 만들기',
      icon: Icons.description_outlined,
      color: FnColors.leaf40,
      bg: FnColors.leaf95,
      builder: _settle,
    ),
  ];

  static List<FnFeature> get all => [...analysis, ...management];

  // const 컨텍스트에서 쓰기 위한 top-level builder 참조
  static Widget _guide(BuildContext c) => const PurchaseGuideScreen();
  static Widget _tracker(BuildContext c) => const PriceTrackerScreen();
  static Widget _compare(BuildContext c) => const UnitPriceCompareScreen();
  static Widget _monthly(BuildContext c) => const MonthlyInsightScreen();
  static Widget _season(BuildContext c) => const SeasonCompareScreen();
  static Widget _tax(BuildContext c) => const TaxRatioScreen();
  static Widget _cost(BuildContext c) => const CostCalculatorScreen();
  static Widget _budget(BuildContext c) => const BudgetReviewScreen();
  static Widget _settle(BuildContext c) => const SettlementScreen();
}

/// 기능 실행 (PRO 전용이면 페이월로)
Future<void> openFeature(BuildContext context, FnFeature f) async {
  if (f.proOnly && !SubscriptionService.instance.isPro) {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PaywallScreen(reason: '${f.title}은(는) PRO 전용 기능입니다'),
      ),
    );
    if (ok != true) return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: f.builder));
}

/// 전체 기능 목록 화면
class InsightHubScreen extends StatelessWidget {
  const InsightHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FnScaffold(
      title: '분석 · 관리',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          const FnSectionHeader(title: '매입 분석'),
          const SizedBox(height: FnSpace.x8),
          ...FnFeatures.analysis.map((f) => _tile(context, f)),
          const SizedBox(height: FnSpace.x20),
          const FnSectionHeader(title: '경영 관리'),
          const SizedBox(height: FnSpace.x8),
          ...FnFeatures.management.map((f) => _tile(context, f)),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, FnFeature f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FnCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        onTap: () => openFeature(context, f),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: f.bg,
                borderRadius: FnRadius.br12,
              ),
              child: Icon(f.icon, size: 21, color: f.color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(f.title,
                            style: FnType.headline1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (f.proOnly &&
                          !SubscriptionService.instance.isPro) ...[
                        const SizedBox(width: 6),
                        const FnBadge.pro(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(f.subtitle,
                      style: FnType.caption1
                          .copyWith(color: FnColors.labelAlternative)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: FnColors.labelAssistive),
          ],
        ),
      ),
    );
  }
}

/// 홈에 얹는 가로 스크롤 퀵 진입 바
class FeatureQuickBar extends StatelessWidget {
  const FeatureQuickBar({super.key});

  @override
  Widget build(BuildContext context) {
    final items = FnFeatures.all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(
            children: [
              Text('분석 · 관리', style: FnType.heading1),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const InsightHubScreen()),
                ),
                child: Row(
                  children: [
                    Text('전체',
                        style: FnType.label2
                            .copyWith(color: FnColors.labelAlternative)),
                    const Icon(Icons.chevron_right_rounded,
                        size: 16, color: FnColors.labelAssistive),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FnSpace.x12),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final f = items[i];
              return GestureDetector(
                onTap: () => openFeature(context, f),
                child: SizedBox(
                  width: 78,
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: f.bg,
                              borderRadius: FnRadius.br16,
                            ),
                            child: Icon(f.icon, size: 26, color: f.color),
                          ),
                          if (f.proOnly &&
                              !SubscriptionService.instance.isPro)
                            const Positioned(
                              right: -4,
                              top: -4,
                              child: FnBadge.pro(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        f.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FnType.caption1
                            .copyWith(color: FnColors.labelNeutral),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
