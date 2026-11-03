import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_feedback.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_sheet.dart';
import '../../design/fn_card.dart';
import '../../design/fn_badge_ds.dart';
import '../../design/fn_charts_ds.dart';
import '../../design/fn_avatar.dart';
import '../../providers/receipt_provider.dart';
import '../../services/flower_season_service.dart';
import '../../services/subscription_service.dart';
import '../../theme/fn_ds.dart';
import '../../widgets/fn_inquiry_parts.dart';
import 'fn_data.dart';
import 'season_ds_screen.dart';

/// 시안 `AppH3`의 서브 화면들을 1:1로 옮긴 파일.
/// trend / donut / price / insights / compare / guide(+season/cost/budget)

// ═══════════════════════════════════════════════════════════════════════
// trend — 월별 지출 추이
// ═══════════════════════════════════════════════════════════════════════
/// ```js
/// Shell(navTitle:'월별 지출 추이', onBack)
///   div p16 column gap:14
///     Card bordered
///       BarChart(recent6, w330 h130, onBar, activeIndex)
///       Divider margin '10px 0'
///       div space-between: [월] [금액 700]
///     Card bordered background: blue-99
///       div 13/700 mb6   '{월} 분석'
///       div 13 lh1.6     '최근 6개월 평균(₩X) 대비 ±N% 많이/적게 썼어요.'
///     div wds-body2-normal label-alternative  '최근 6개월 매입 지출 추이입니다...'
/// ```
class TrendDsScreen extends StatefulWidget {
  const TrendDsScreen({super.key});
  @override
  State<TrendDsScreen> createState() => _TrendDsScreenState();
}

class _TrendDsScreenState extends State<TrendDsScreen> {
  // 시안: activeBar 초기 11 → localActive = 11 - 6 = 5
  int _local = 5;

  @override
  Widget build(BuildContext context) {
    // 실데이터가 있으면 최근 6개월 실지출, 없으면 시안 수치.
    final d = FnDemo.resolve(context.watch<ReceiptProvider>());
    final months = d.months.sublist(d.months.length - 6);
    final spend = d.spend.sublist(d.spend.length - 6);

    // 선택 인덱스가 범위를 벗어나면 마지막 달로 보정
    final idx = _local.clamp(0, months.length - 1);

    final avg = spend.reduce((a, b) => a + b) / spend.length;
    // 평균이 0이면(전부 0원) 나눗셈이 NaN/Infinity → 0으로 처리
    final vsAvg = avg == 0 ? 0 : ((spend[idx] - avg) / avg * 100).round();

    return FnShell(
      navTitle: '월별 지출 추이',
      onBack: () => Navigator.of(context).pop(),
      child: FnColumn(
        gap: 14,
        children: [
          FnCard(
            bordered: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: FnBarChart(
                    data: List.generate(
                      months.length,
                      (i) => FnChartDatum(label: months[i], value: spend[i]),
                    ),
                    width: 330,
                    height: 130,
                    activeIndex: idx,
                    onBar: (i) => setState(() => _local = i),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: FnDsDivider(),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(months[idx], style: _t14),
                    Text(
                      FnDemo.won(spend[idx]),
                      style: _t14.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
          FnCard(
            bordered: true,
            color: FnColors.rose99, // blue-99 → 로즈 오버라이드
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${months[idx]} 분석',
                    style: _t13.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  '최근 6개월 평균(${FnDemo.won(avg.round())}) 대비 '
                  '${vsAvg >= 0 ? '+' : ''}$vsAvg% '
                  '${vsAvg >= 0 ? '많이 썼어요' : '적게 썼어요'}.',
                  style: _t13.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
          Text(
            '최근 6개월 매입 지출 추이입니다. 막대를 탭해 월별 금액과 분석을 확인하세요.',
            style: _t14.copyWith(color: FnColors.labelAlternative, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// donut — 면세 / 과세 비중
// ═══════════════════════════════════════════════════════════════════════
/// ```js
/// Shell(navTitle:'면세 / 과세 비중', onBack)
///   div p16 column gap:16 alignItems:center
///     Donut(size:180, thickness:30, rotate:DONUT_ROTATE)
///     div width:100% column gap:8
///       각 항목: [●10px  label]  ...  [%  label-alternative] [금액 700]
///                padding '8px 4px', active면 background fill-normal, radius 8
///     activeSlice===0 && Card bordered violet-95  '부자재 지출 비율이 전월 대비 5% 증가했어요.'
/// ```
class DonutDsScreen extends StatefulWidget {
  const DonutDsScreen({super.key});
  @override
  State<DonutDsScreen> createState() => _DonutDsScreenState();
}

class _DonutDsScreenState extends State<DonutDsScreen> {
  int? _active;

  @override
  Widget build(BuildContext context) {
    // 실데이터가 있으면 실제 과세/면세 금액, 없으면 시안 수치.
    final data = FnDemo.resolve(context.watch<ReceiptProvider>()).taxData;
    final total = data.fold<double>(0, (s, d) => s + d.value);

    return FnShell(
      navTitle: '면세 / 과세 비중',
      onBack: () => Navigator.of(context).pop(),
      child: FnColumn(
        gap: 16,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FnDonut(
            data: data,
            size: 180,
            thickness: 30,
            rotate: FnDemo.donutRotate,
            activeIndex: _active,
            onSlice: (i) => setState(() => _active = i),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(data.length, (i) {
              final v = data[i];
              final active = _active == i;
              return GestureDetector(
                onTap: () => setState(() => _active = i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: EdgeInsets.only(top: i == 0 ? 0 : 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? FnColors.fillNormal : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: v.color,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(v.label, style: _t14),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            '${(v.value / total * 100).round()}%',
                            style:
                                _t14.copyWith(color: FnColors.labelAlternative),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            FnDemo.won(v.value),
                            style: _t14.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          if (_active == 0)
            FnCard(
              bordered: true,
              color: const Color(0xFFFCEEEB), // violet-95
              child: Text('부자재 지출 비율이 전월 대비 5% 증가했어요.', style: _t13),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// price — 시세 트래커
// ═══════════════════════════════════════════════════════════════════════
/// ```js
/// Shell(navTitle:'시세 트래커', onBack)
///   div p16 column gap:14
///     chipRow  (품목 Chip들, locked && !isPro → ' 🔒' + proModal)
///     Card bordered
///       div space-between baseline mb10: [₩8,000 /단 22/700] [Badge +12% 전월대비]
///       isRose ? LineChart(dates, 320x100) : BarChart(months, 320x100, orange-50)
///       isRose && 거래처별 단가 비교 (borderTop 1px, gap 6)
///     note
/// ```
class PriceDsScreen extends StatefulWidget {
  const PriceDsScreen({super.key});
  @override
  State<PriceDsScreen> createState() => _PriceDsScreenState();
}

class _PriceDsScreenState extends State<PriceDsScreen> {
  /// 선택된 품목명. null이면 첫 품목(무료 공개 품목)을 쓴다.
  ///
  /// 실데이터에서는 품목명이 무엇일지 알 수 없으므로 `'장미(레드)'` 처럼
  /// 하드코딩하면 `priceData[_item]!` 이 null 역참조로 크래시한다.
  String? _item;

  bool get _isPro => SubscriptionService.instance.isPro;

  @override
  Widget build(BuildContext context) {
    // 실데이터가 있으면 실제 품목 시세, 없으면 시안 수치.
    final priceData =
        FnDemo.resolve(context.watch<ReceiptProvider>()).priceData;
    final keys = priceData.keys.toList();

    // 품목이 하나도 없으면(이론상 불가하지만 방어) 빈 안내
    if (keys.isEmpty) {
      return FnShell(
        navTitle: '시세 트래커',
        onBack: () => Navigator.of(context).pop(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text(
            '아직 시세를 계산할 품목이 없어요.\n영수증을 스캔하면 품목별 단가 추이를 보여드려요.',
            textAlign: TextAlign.center,
            style: _t14.copyWith(
                color: FnColors.labelAssistive, height: 1.6),
          ),
        ),
      );
    }

    // 선택 품목이 사라졌거나 아직 없으면 첫 품목으로
    final item = (_item != null && priceData.containsKey(_item))
        ? _item!
        : keys.first;
    final d = priceData[item]!;

    // 시안에서 '장미(레드)'만 상세(라인차트 + 거래처 비교)를 보여줬다.
    // 실데이터에서는 **무료 공개 품목(첫 번째)** 이 그 역할을 한다.
    final isRose = item == keys.first;

    return FnShell(
      navTitle: '시세 트래커',
      onBack: () => Navigator.of(context).pop(),
      child: FnColumn(
        gap: 14,
        children: [
          // chipRow — flexWrap
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: keys.map((k) {
              final locked = priceData[k]!.locked && !_isPro;
              return FnChip(
                label: k + (locked ? ' 🔒' : ''),
                selected: item == k,
                onTap: () {
                  if (locked) {
                    _showPro(context);
                    return;
                  }
                  setState(() => _item = k);
                },
              );
            }).toList(),
          ),
          FnCard(
            bordered: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${FnDemo.won(d.unit)} /단',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: FnColors.labelNormal,
                      ),
                    ),
                    FnBadge(
                      '${d.chg >= 0 ? '+' : ''}${d.chg}% 전월대비',
                      color: d.chg >= 0
                          ? FnBadgeColor.cautionary
                          : FnBadgeColor.positive,
                      size: FnBadgeSize.small,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: (isRose && d.dates.isNotEmpty)
                      ? FnLineChart(
                          data: d.dates
                              .map((e) =>
                                  FnChartDatum(label: e.label, value: e.value))
                              .toList(),
                          width: 300,
                          height: 100,
                        )
                      : d.months.isEmpty
                          ? const SizedBox(height: 100)
                          : FnBarChart(
                              data: List.generate(
                                d.months.length,
                                (i) => FnChartDatum(
                                    label: '${i + 2}월', value: d.months[i]),
                              ),
                              width: 300,
                              height: 100,
                              barColor:
                                  FnColors.statusCautionary, // orange-50
                            ),
                ),
                if (isRose && d.vendorPrices.length >= 2) ...[
                  const SizedBox(height: 12),
                  const FnDsDivider(),
                  const SizedBox(height: 12),
                  Text(
                    '거래처별 단가 비교',
                    style: _t13.copyWith(
                        fontSize: 12.5, color: FnColors.labelAlternative),
                  ),
                  const SizedBox(height: 8),
                  ...d.vendorPrices.map(
                    (vp) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(vp.vendor, style: _t14),
                          Text(FnDemo.won(vp.price),
                              style:
                                  _t14.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            (isRose && d.vendorPrices.length >= 2)
                ? '동일 품목의 거래처별 단가 차이를 사입 시 참고해보세요.'
                : '단가가 전월 대비 ±10% 이상 변동하면 알림을 보내드려요.',
            style: _t14.copyWith(color: FnColors.labelAlternative, height: 1.5),
          ),
        ],
      ),
    );
  }

  void _showPro(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _Pro(
        title: '🔒 다른 품목 시세는 Pro 전용이에요',
        // 실데이터의 품목명은 매장마다 다르므로 특정 꽃 이름을 넣지 않는다.
        desc: '매입한 전체 품목의 단가 추이와 거래처별 비교는 Pro 구독시 확인할 수 있어요',
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// insights — 월별 인사이트
// ═══════════════════════════════════════════════════════════════════════
/// ```js
/// Shell(navTitle:'월별 인사이트', onBack)
///   div p16 column gap:10
///     insights.map → Card bordered onClick
///       ContentBadge color mb8   '단가 변동' | '비교 안내' | '지출 점검'
///       div 15                    text
///     div 12 label-assistive padding '8px 4px'  '인사이트는 참고 정보이며...'
/// ```
class InsightsDsScreen extends StatelessWidget {
  const InsightsDsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 실데이터가 있으면 실제 매입 내역에서 계산한 인사이트, 없으면 시안 문구.
    final insights =
        FnDemo.resolve(context.watch<ReceiptProvider>()).insights;

    return FnShell(
      navTitle: '월별 인사이트',
      onBack: () => Navigator.of(context).pop(),
      child: FnColumn(
        gap: 10,
        children: [
          // 계절 패턴은 매입 내역이 없어도 항상 말할 수 있는 유일한 인사이트다.
          // 다른 카드들은 사장님이 찍은 영수증이 있어야 계산되는데, 이건 2년치
          // 양재 경매 실적에서 나오므로 첫 사용자에게도 보여줄 게 있다.
          _seasonCard(context),
          ...insights.map(
            (it) => FnCard(
              bordered: true,
              onTap: () => _go(context, it.target),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FnBadge(it.badge, color: _badgeColor(it.color)),
                  const SizedBox(height: 8),
                  Text(it.text, style: _t15.copyWith(height: 1.45)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              '인사이트는 참고 정보이며, 세무·회계 판단은 전문가 확인이 필요합니다.',
              style: _t13.copyWith(
                  fontSize: 12, color: FnColors.labelAssistive, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  /// 꽃별 계절 시세로 들어가는 카드.
  ///
  /// 검증을 통과한 품목이 하나도 없거나 자산 로드가 실패했으면 아예 그리지
  /// 않는다. 눌러도 빈 화면이 나오는 카드는 없는 게 낫다.
  static Widget _seasonCard(BuildContext context) {
    final svc = FlowerSeasonService.instance;
    if (!svc.isReady) return const SizedBox.shrink();

    final month = svc.currentMonth;
    final notes = svc.notesForMonth(limit: 2);

    // 이번 달에 평소와 다른 꽃이 없으면 그 사실 자체를 알려준다.
    final preview = notes.isEmpty
        ? '$month월은 대부분의 꽃이 연평균과 비슷한 수준이에요.'
        : notes.map((n) => n.lineText).join('\n');

    return FnCard(
      bordered: true,
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SeasonDsScreen())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const FnBadge('계절 패턴', color: FnBadgeColor.accent),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: FnColors.labelAssistive),
            ],
          ),
          const SizedBox(height: 8),
          Text(preview, style: _t15.copyWith(height: 1.45)),
          const SizedBox(height: 6),
          Text(
            // 근거 기간과 성격(예측 아님)을 한 줄로 밝힌다.
            '최근 2년 양재 경매에서 매년 반복된 흐름이에요',
            style: _t13.copyWith(
                fontSize: 12, color: FnColors.labelAssistive, height: 1.45),
          ),
        ],
      ),
    );
  }

  static FnBadgeColor _badgeColor(String c) => switch (c) {
        'cautionary' => FnBadgeColor.cautionary,
        'accent' => FnBadgeColor.accent,
        'positive' => FnBadgeColor.positive,
        _ => FnBadgeColor.negative,
      };

  static void _go(BuildContext context, FnInsightTarget t) {
    final page = switch (t) {
      FnInsightTarget.price => const PriceDsScreen(),
      FnInsightTarget.compare => const CompareDsScreen(),
      FnInsightTarget.donut => const DonutDsScreen(),
      FnInsightTarget.trend => const TrendDsScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

// ═══════════════════════════════════════════════════════════════════════
// compare — 단가 비교
// ═══════════════════════════════════════════════════════════════════════
/// ```js
/// rows = [{대한꽃도매,8000},{그린플러스,8700},{미림화훼,8300}]; min = 8000
/// Shell(navTitle: compareItem + ' 단가 비교', onBack → insights)
///   div p16 column gap:10
///     rows.map → Card bordered  space-between
///       span 업체명 / span 700 (최저가면 green-50 + ' · 최저가')
///     Card background blue-95   div 13 blue-50  '동일 품목의 거래처별 단가차를 협상 근거로 활용해보세요.'
/// ```
class CompareDsScreen extends StatelessWidget {
  const CompareDsScreen({super.key, this.item = '거베라'});
  final String item;

  static const _rows = [
    (vendor: '대한꽃도매', price: 8000.0),
    (vendor: '그린플러스', price: 8700.0),
    (vendor: '미림화훼', price: 8300.0),
  ];

  @override
  Widget build(BuildContext context) {
    final min = _rows.map((r) => r.price).reduce((a, b) => a < b ? a : b);

    return FnShell(
      navTitle: '$item 단가 비교',
      onBack: () => Navigator.of(context).pop(),
      child: FnColumn(
        gap: 10,
        children: [
          ..._rows.map(
            (r) => FnCard(
              bordered: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(r.vendor, style: _t14),
                  Text(
                    FnDemo.won(r.price) + (r.price == min ? ' · 최저가' : ''),
                    style: _t14.copyWith(
                      fontWeight: FontWeight.w700,
                      color: r.price == min
                          ? FnColors.leaf50
                          : FnColors.labelNormal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          FnCard(
            color: FnColors.rose95, // blue-95
            child: Text(
              '동일 품목의 거래처별 단가차를 협상 근거로 활용해보세요.',
              style: _t13.copyWith(color: FnColors.primaryNormal, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// guide — 스마트 사입 가이드 (+ season / cost / budget)
// ═══════════════════════════════════════════════════════════════════════
/// ```js
/// menu = [
///  {guide-season,'① 시즌 매입 비교','지난 시즌 및 전년 동월 대비 사입 지출 금액을 비교해요.'},
///  {guide-cost,  '② 원가 계산기','꽃 조합·수량으로 레시피 원가를 산출하고, 목표 마진율에 맞는 판매가를 계산해요.'},
///  {guide-budget,'③ 예산 검토','다음 사입에 필요한 꽃 리스트를 입력하면, 최근 시세로 예상 구매 예산을 검토해요.'},
/// ]
/// Card bordered onClick: [title 15/700] [ChevronRight 16 label-assistive]
///                        desc 13 label-alternative mt6 lh1.5
/// ```
class GuideDsScreen extends StatelessWidget {
  const GuideDsScreen({super.key});

  /// 🔴 지금 보이는 숫자는 전부 **예시값**이다.
  ///    사장님 지시: "데이터는 예시값으로 채우고, 실제 기능은 만들지 마."
  ///    실제 계산을 붙일 자리는 `docs/TODO_기능연결.md` 에 적어 두었다.
  static const String budgetSpend = '27.4만원';
  static const String budgetPlan = '금요일 사입 예정 · 3개 품목';
  static const String budgetCap = '한도 400,000원';
  static const String budgetLeft = '12.6만원';

  /// 막대 채움 비율. 27.4 / 40.0
  static const double budgetRatio = 0.685;

  static const _menu = <_GuideRow>[
    _GuideRow(
      icon: Icons.receipt_long_outlined,
      title: '시즌 매입 비교',
      desc: '올해 매입을 전년 동기·월 평균과 비교해요.',
      left: '1~7월 +7.5%',
      right: '전년 동기 대비',
      highlight: false,
      page: 'season',
    ),
    _GuideRow(
      icon: Icons.calculate_outlined,
      title: '원가 계산기',
      desc: '꽃 조합과 수량으로 판매가와 마진을 계산해요.',
      left: '권장가 307,200원',
      right: '마진 60%',
      highlight: true,
      page: 'cost',
    ),
    _GuideRow(
      icon: Icons.account_balance_wallet_outlined,
      title: '예산 검토',
      desc: '직전 매입 단가로 예상 예산을 계산해요.',
      left: '한도 40만원 중 27.4만원',
      right: '69% 사용',
      highlight: true,
      page: 'budget',
    ),
    // 아래 두 가지는 아직 화면이 없다. 눌러도 넘어가지 않고 안내만 띄운다.
    _GuideRow(
      icon: Icons.fact_check_outlined,
      title: '저장된 사입 리스트',
      desc: '날짜별 사입 리스트와 예산을 확인해요.',
      left: '3건 저장 · 1회 평균 13.8만원',
      right: '최근 07.24',
      highlight: false,
      page: 'saved',
    ),
    _GuideRow(
      icon: Icons.edit_note_outlined,
      title: '사입 메모장',
      desc: '사입 메모와 부케 스케치를 함께 기록해요.',
      left: '마지막 기록 07.24',
      right: '메모 2줄',
      highlight: false,
      page: 'memo',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '스마트 사입 가이드',
      bg: FnDs.bg,
      onBack: () => Navigator.of(context).pop(),
      child: ColoredBox(
        color: FnDs.bg,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              FnDs.pagePad, 18, FnDs.pagePad, FnDs.gapXl),
          children: [
            const _GuideBudgetCard(),
            const SizedBox(height: FnDs.gapS),
            for (final m in _menu) ...[
              _GuideMenuCard(row: m, onTap: () => _open(context, m.page)),
              const SizedBox(height: FnDs.gapS),
            ],
            const SizedBox(height: FnDs.gap2xs),
            const Text(
              '내 영수증의 매입 단가를 기준으로 계산해요.\n'
              '저장하면 다음 사입에 이어서 쓸 수 있어요.',
              style: FnDs.tsSub,
            ),
          ],
        ),
      ),
    );
  }

  /// 🔴 아직 없는 화면은 넘어가지 않고 안내만 띄운다.
  ///    빈 화면으로 보내면 사장님이 "고장났나" 하게 된다.
  void _open(BuildContext context, String page) {
    final screen = switch (page) {
      'season' => const GuideSeasonDsScreen(),
      'cost' => const GuideCostDsScreen(),
      'budget' => const GuideBudgetDsScreen(),
      _ => null,
    };
    if (screen == null) {
      showFnToast(context, '곧 준비해서 알려드릴게요.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

/// 가이드 목록 한 줄에 들어가는 값.
@immutable
class _GuideRow {
  const _GuideRow({
    required this.icon,
    required this.title,
    required this.desc,
    required this.left,
    required this.right,
    required this.highlight,
    required this.page,
  });

  final IconData icon;
  final String title;
  final String desc;

  /// 아래 줄 왼쪽 — 진하게.
  final String left;

  /// 아래 줄 오른쪽.
  final String right;

  /// 오른쪽 글자를 코랄로 쓸지. (마진·사용률처럼 눈여겨볼 값)
  final bool highlight;

  final String page;
}

/// 맨 위 "이번 주 사입 준비" 카드.
class _GuideBudgetCard extends StatelessWidget {
  const _GuideBudgetCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: FnDs.cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이번 주 사입 준비', style: FnDs.tsSection),
          const SizedBox(height: FnDs.gapS),
          const Text('예상 예산', style: FnDs.tsSub),
          const SizedBox(height: FnDs.gap2xs),
          const Text(
            GuideDsScreen.budgetSpend,
            style: TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.font2xl,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: FnDs.coral,
            ),
          ),
          const SizedBox(height: FnDs.gapS),
          Row(
            children: [
              const Expanded(
                child: Text(
                  GuideDsScreen.budgetPlan,
                  style: TextStyle(
                    fontFamily: FnDs.font,
                    fontSize: FnDs.fontS,
                    color: FnDs.title,
                  ),
                ),
              ),
              const Text(GuideDsScreen.budgetCap, style: FnDs.tsSub),
            ],
          ),
          const SizedBox(height: FnDs.gapXs),
          // 막대. 🔴 Stack 으로 겹치지 않고 Row 로 비율을 나눈다 —
          //    Stack 은 부모 폭을 모를 때 0 으로 찌그러진다.
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: (GuideDsScreen.budgetRatio * 1000).round(),
                    child: const ColoredBox(color: FnDs.coral),
                  ),
                  Expanded(
                    flex: 1000 - (GuideDsScreen.budgetRatio * 1000).round(),
                    child: const ColoredBox(color: FnDs.coralFaint),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: FnDs.gapXs),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.fontS,
                fontWeight: FontWeight.w600,
                color: FnDs.title,
              ),
              children: const [
                TextSpan(text: '한도까지 '),
                TextSpan(
                    text: GuideDsScreen.budgetLeft,
                    style: TextStyle(color: FnDs.coral)),
                TextSpan(text: ' 남았어요'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 가이드 목록 카드 한 장.
class _GuideMenuCard extends StatelessWidget {
  const _GuideMenuCard({required this.row, required this.onTap});

  final _GuideRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(FnDs.cardPad),
        decoration: FnDs.cardDeco(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(row.icon, size: 17, color: FnDs.coral),
                const SizedBox(width: FnDs.gapXs),
                Expanded(
                  child: Text(
                    row.title,
                    style: const TextStyle(
                      fontFamily: FnDs.font,
                      fontSize: FnDs.fontL,
                      fontWeight: FontWeight.w700,
                      color: FnDs.title,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: FnDs.chevron),
              ],
            ),
            const SizedBox(height: FnDs.gapXs),
            Text(row.desc, style: FnDs.tsSub),
            const SizedBox(height: FnDs.gapS),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    row.left,
                    style: const TextStyle(
                      fontFamily: FnDs.font,
                      fontSize: FnDs.fontS,
                      fontWeight: FontWeight.w700,
                      color: FnDs.title,
                    ),
                  ),
                ),
                Text(
                  row.right,
                  style: TextStyle(
                    fontFamily: FnDs.font,
                    fontSize: FnDs.fontXs,
                    fontWeight: row.highlight ? FontWeight.w700 : FontWeight.w400,
                    color: row.highlight ? FnDs.coral : FnDs.sub,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 시즌 매입 비교 — 사장님 시안 1:1.
///
/// ## 배치 (시안 순서)
///
/// ```
///   [←] 시즌 매입 비교
///   기간을 설정하면 올해 매입을 전년 동기 또는
///   올해 월평균과 비교할 수 있어요.
///   ┌ 시작 월 [1월]   종료 월 [7월]              ┐  _SeasonFilterCard
///   └ (전년 동기) (올해 월평균)                   ┘
///   ┌ 선택 기간 매입 / [전년 대비 +7.5%]         ┐  _SeasonTotalCard
///   │ 27,890,000원                               │
///   └ 전년 동기            25,940,000원          ┘
///   ┌ 기간 비교 — 묶음 막대 7쌍                   ┐  _SeasonBarsCard
///   ┌ 품목군별 증감 — 4줄                         ┐  _SeasonItemsCard
///   ┌ 성수기 지도 — 7칸 진하기                    ┐  _SeasonHeatCard
///   ┌ 월별 매입 추이 — 실선/점선                  ┐  _SeasonTrendCard
///   ┌ 2026년 1~7월 / 전년 동기 / 증감             ┐  _SeasonSumCard
///   ┌ 데이터 분석                                 ┐  _SeasonNoteCard
/// ```
///
/// 🔴 여기 숫자는 전부 **예시값**이다. 사장님 지시: "데이터는 예시값으로
///    채우고, 실제 기능은 만들지 마." 붙일 자리는 `docs/TODO_기능연결.md`.
///
/// 🔴 시작/종료 월과 비교 기준 두 가지는 **눌리기는 한다.** 누르면 화면이
///    바뀌지만 숫자는 그대로다. 아예 안 눌리면 고장으로 보이고, 숫자까지
///    바뀌면 거짓말이 된다. 그래서 고른 값만 표시하고 안내를 띄운다.
class GuideSeasonDsScreen extends StatefulWidget {
  const GuideSeasonDsScreen({super.key});

  // ── 예시값 ────────────────────────────────────────────────
  static const String total = '27,890,000원';
  static const String prevTotal = '25,940,000원';
  static const String diffPct = '전년 대비 +7.5%';
  static const String diffAmount = '+1,950,000원';
  static const String rangeLabel = '2026년 1~7월';

  /// 묶음 막대 — (달, 올해, 전년). 단위 만원.
  static const List<(String, double, double)> bars = [
    ('1월', 352, 331),
    ('2월', 298, 312),
    ('3월', 436, 398),
    ('4월', 389, 423),
    ('5월', 472, 404),
    ('6월', 904, 766),
    ('7월', 538, 560),
  ];

  /// 성수기 진하기 0~1.
  static const List<(String, double)> heat = [
    ('1월', 0.28),
    ('2월', 0.20),
    ('3월', 0.52),
    ('4월', 0.14),
    ('5월', 0.64),
    ('6월', 0.42),
    ('7월', 1.00),
  ];

  /// 월별 추이 — (올해, 전년).
  static const List<double> trendNow = [352, 298, 436, 389, 472, 904, 538];
  static const List<double> trendPrev = [331, 312, 398, 423, 404, 766, 560];

  static const List<(String, String, String)> items = [
    ('절화(꽃)', '전년 대비 +2%', '18,965,200원'),
    ('부자재', '전년 대비 +34%', '5,578,000원'),
    ('화분·식물', '전년 대비 -4%', '2,231,200원'),
    ('기타', '전년 대비 +43%', '1,115,600원'),
  ];

  static const List<String> months = [
    '1월', '2월', '3월', '4월', '5월', '6월', '7월',
    '8월', '9월', '10월', '11월', '12월',
  ];

  @override
  State<GuideSeasonDsScreen> createState() => _GuideSeasonDsScreenState();
}

class _GuideSeasonDsScreenState extends State<GuideSeasonDsScreen> {
  String _from = '1월';
  String _to = '7월';

  /// 0 = 전년 동기, 1 = 올해 월평균.
  int _basis = 0;

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '시즌 매입 비교',
      bg: FnDs.bg,
      onBack: () => Navigator.of(context).pop(),
      child: ColoredBox(
        color: FnDs.bg,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              FnDs.pagePad, 14, FnDs.pagePad, FnDs.gapXl),
          children: [
            const Text(
              '기간을 설정하면 올해 매입을 전년 동기 또는\n'
              '올해 월평균과 비교할 수 있어요.',
              style: FnDs.tsSub,
            ),
            const SizedBox(height: FnDs.gapM),
            _SeasonFilterCard(
              from: _from,
              to: _to,
              basis: _basis,
              onFrom: (v) => setState(() => _from = v),
              onTo: (v) => setState(() => _to = v),
              onBasis: (v) => setState(() => _basis = v),
            ),
            const SizedBox(height: FnDs.gapS),
            const _SeasonTotalCard(),
            const SizedBox(height: FnDs.gapS),
            const _SeasonBarsCard(),
            const SizedBox(height: FnDs.gapS),
            const _SeasonItemsCard(),
            const SizedBox(height: FnDs.gapS),
            const _SeasonHeatCard(),
            const SizedBox(height: FnDs.gapS),
            const _SeasonTrendCard(),
            const SizedBox(height: FnDs.gapS),
            const _SeasonSumCard(),
            const SizedBox(height: FnDs.gapS),
            const _SeasonNoteCard(),
          ],
        ),
      ),
    );
  }
}

/// 카드 공통 껍데기 — 제목 + 선택 부제 + 내용.
class _SeasonCard extends StatelessWidget {
  const _SeasonCard({this.title, this.subtitle, required this.child});

  final String? title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: FnDs.cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: FnDs.tsSection),
            const SizedBox(height: FnDs.gap2xs),
          ],
          if (subtitle != null) ...[
            Text(subtitle!, style: FnDs.tsSub),
            const SizedBox(height: FnDs.gapS),
          ],
          child,
        ],
      ),
    );
  }
}

/// 기간·비교 기준 고르기.
class _SeasonFilterCard extends StatelessWidget {
  const _SeasonFilterCard({
    required this.from,
    required this.to,
    required this.basis,
    required this.onFrom,
    required this.onTo,
    required this.onBasis,
  });

  final String from;
  final String to;
  final int basis;
  final ValueChanged<String> onFrom;
  final ValueChanged<String> onTo;
  final ValueChanged<int> onBasis;

  @override
  Widget build(BuildContext context) {
    return _SeasonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('시작 월', style: FnDs.tsSub),
                    const SizedBox(height: 6),
                    FnCategoryPicker(
                      value: from,
                      onTap: () => _pickMonth(context, from, onFrom, '시작 월'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FnDs.gapS),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('종료 월', style: FnDs.tsSub),
                    const SizedBox(height: 6),
                    FnCategoryPicker(
                      value: to,
                      onTap: () => _pickMonth(context, to, onTo, '종료 월'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FnDs.gapS),
          Row(
            children: [
              _BasisPill(
                label: '전년 동기',
                selected: basis == 0,
                onTap: () => onBasis(0),
              ),
              const SizedBox(width: FnDs.gapXs),
              _BasisPill(
                label: '올해 월평균',
                selected: basis == 1,
                onTap: () => onBasis(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickMonth(BuildContext context, String now,
      ValueChanged<String> onPick, String title) async {
    final picked = await showFnOptionSheet<String>(
      context,
      title: title,
      selected: now,
      options: [
        for (final m in GuideSeasonDsScreen.months)
          FnSheetOption<String>(value: m, label: m),
      ],
    );
    if (picked != null) onPick(picked);
  }
}

/// 비교 기준 알약 버튼.
class _BasisPill extends StatelessWidget {
  const _BasisPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? FnDs.coral : FnDs.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? FnDs.coral : FnDs.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.fontXs,
            fontWeight: FontWeight.w700,
            color: selected ? FnDs.onCoral : FnDs.sub,
          ),
        ),
      ),
    );
  }
}

/// 선택 기간 매입 — 가운데 정렬 큰 숫자.
class _SeasonTotalCard extends StatelessWidget {
  const _SeasonTotalCard();

  @override
  Widget build(BuildContext context) {
    return _SeasonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('선택 기간 매입', style: FnDs.tsSub),
          const SizedBox(height: FnDs.gapXs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: FnDs.coral,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              GuideSeasonDsScreen.diffPct,
              style: TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.fontXs,
                fontWeight: FontWeight.w700,
                color: FnDs.onCoral,
              ),
            ),
          ),
          const SizedBox(height: FnDs.gapXs),
          const Text(GuideSeasonDsScreen.total, style: FnDs.tsAmount),
          const SizedBox(height: FnDs.gapM),
          const Divider(height: 1, thickness: 1, color: FnDs.hair),
          const SizedBox(height: FnDs.gapS),
          Row(
            children: [
              const Expanded(child: Text('전년 동기', style: FnDs.tsBody)),
              const Text(
                GuideSeasonDsScreen.prevTotal,
                style: TextStyle(
                  fontFamily: FnDs.font,
                  fontSize: FnDs.fontM,
                  fontWeight: FontWeight.w700,
                  color: FnDs.title,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 기간 비교 — 달마다 두 개씩 묶음 막대.
///
/// 🔴 그림(CustomPaint)이 아니라 네모를 쌓아 만들었다. 테스트에서 높이를
///    바로 잴 수 있고, 글꼴 크기를 키워도 안 깨진다.
class _SeasonBarsCard extends StatelessWidget {
  const _SeasonBarsCard();

  static const double _h = 120;

  @override
  Widget build(BuildContext context) {
    const rows = GuideSeasonDsScreen.bars;
    final top = rows
        .map((e) => e.$2 > e.$3 ? e.$2 : e.$3)
        .reduce((a, b) => a > b ? a : b);

    return _SeasonCard(
      title: '기간 비교',
      subtitle: '2026년 · 전년 동기 · 단위: 만원',
      child: Column(
        children: [
          SizedBox(
            height: _h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final r in rows)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _bar(r.$3 / top, FnDs.hair),
                          const SizedBox(width: 3),
                          _bar(r.$2 / top, FnDs.coral),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final r in rows)
                Expanded(
                  child: Text(r.$1,
                      textAlign: TextAlign.center, style: FnDs.tsSub),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(double ratio, Color color) => Expanded(
        child: Container(
          // 값이 0 이어도 막대가 보이도록 최소 높이를 준다.
          height: (_h * ratio).clamp(4.0, _h),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      );
}

/// 품목군별 증감.
class _SeasonItemsCard extends StatelessWidget {
  const _SeasonItemsCard();

  @override
  Widget build(BuildContext context) {
    const rows = GuideSeasonDsScreen.items;
    return _SeasonCard(
      title: '품목군별 증감',
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: FnDs.gapS),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rows[i].$1,
                        style: const TextStyle(
                          fontFamily: FnDs.font,
                          fontSize: FnDs.fontM,
                          fontWeight: FontWeight.w700,
                          color: FnDs.title,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(rows[i].$2, style: FnDs.tsSub),
                    ],
                  ),
                ),
                Text(
                  rows[i].$3,
                  style: const TextStyle(
                    fontFamily: FnDs.font,
                    fontSize: FnDs.fontM,
                    fontWeight: FontWeight.w700,
                    color: FnDs.title,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 성수기 지도 — 진하기로 달을 비교.
class _SeasonHeatCard extends StatelessWidget {
  const _SeasonHeatCard();

  @override
  Widget build(BuildContext context) {
    const cells = GuideSeasonDsScreen.heat;
    return _SeasonCard(
      title: '성수기 지도',
      child: Column(
        children: [
          Row(
            children: [
              for (final c in cells)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          // 진할수록 그 달 매입이 많았다는 뜻.
                          color: Color.lerp(
                              FnDs.coralFaint, FnDs.coral, c.$2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final c in cells)
                Expanded(
                  child: Text(c.$1,
                      textAlign: TextAlign.center, style: FnDs.tsSub),
                ),
            ],
          ),
          const SizedBox(height: FnDs.gapS),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '6월이 올해 최대 성수기예요. 지난해보다 18% 늘었어요.\n'
              '내년 예산은 904만원 단위로 계획해 보세요.',
              style: FnDs.tsSub,
            ),
          ),
        ],
      ),
    );
  }
}

/// 월별 매입 추이 — 올해 실선, 전년 점선.
class _SeasonTrendCard extends StatelessWidget {
  const _SeasonTrendCard();

  @override
  Widget build(BuildContext context) {
    return _SeasonCard(
      title: '월별 매입 추이',
      subtitle: '2026년 실선 · 2025년 점선',
      child: Column(
        children: [
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: _SeasonTrendPainter(
                now: GuideSeasonDsScreen.trendNow,
                prev: GuideSeasonDsScreen.trendPrev,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final b in GuideSeasonDsScreen.bars)
                Expanded(
                  child: Text(b.$1,
                      textAlign: TextAlign.center, style: FnDs.tsSub),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 두 줄을 겹쳐 그린다. 올해는 실선, 전년은 점선.
class _SeasonTrendPainter extends CustomPainter {
  const _SeasonTrendPainter({required this.now, required this.prev});

  final List<double> now;
  final List<double> prev;

  @override
  void paint(Canvas canvas, Size size) {
    if (now.isEmpty) return;
    final top = [...now, ...prev].reduce((a, b) => a > b ? a : b);
    if (top <= 0) return;

    Offset at(List<double> v, int i) {
      // 양 끝이 테두리에 붙지 않게 안쪽으로 조금 들인다.
      final dx = now.length == 1
          ? size.width / 2
          : size.width * i / (now.length - 1);
      final dy = size.height - (size.height - 8) * (v[i] / top) - 4;
      return Offset(dx, dy);
    }

    // 전년 — 점선.
    final dashed = Paint()
      ..color = FnDs.hair
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < prev.length - 1; i++) {
      _dashLine(canvas, at(prev, i), at(prev, i + 1), dashed);
    }

    // 올해 — 실선.
    final line = Paint()
      ..color = FnDs.coral
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(at(now, 0).dx, at(now, 0).dy);
    for (var i = 1; i < now.length; i++) {
      path.lineTo(at(now, i).dx, at(now, i).dy);
    }
    canvas.drawPath(path, line);

    final dot = Paint()..color = FnDs.coral;
    for (var i = 0; i < now.length; i++) {
      canvas.drawCircle(at(now, i), 2.6, dot);
    }
  }

  void _dashLine(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 4.0, gap = 3.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final step = (b - a) / total;
    var done = 0.0;
    while (done < total) {
      final end = (done + dash).clamp(0.0, total);
      canvas.drawLine(a + step * done, a + step * end, p);
      done = end + gap;
    }
  }

  @override
  bool shouldRepaint(_SeasonTrendPainter old) =>
      old.now != now || old.prev != prev;
}

/// 합계 — 올해 / 전년 / 증감.
class _SeasonSumCard extends StatelessWidget {
  const _SeasonSumCard();

  @override
  Widget build(BuildContext context) {
    return _SeasonCard(
      child: Column(
        children: [
          _row(GuideSeasonDsScreen.rangeLabel, GuideSeasonDsScreen.total,
              bold: true),
          const SizedBox(height: FnDs.gapXs),
          _row('전년 동기', GuideSeasonDsScreen.prevTotal),
          const SizedBox(height: FnDs.gapS),
          const Divider(height: 1, thickness: 1, color: FnDs.hair),
          const SizedBox(height: FnDs.gapS),
          _row('증감', GuideSeasonDsScreen.diffAmount,
              bold: true, valueColor: FnDs.coral),
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, Color? valueColor}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.fontS,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: bold ? FnDs.title : FnDs.body,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.fontM,
            fontWeight: FontWeight.w700,
            color: valueColor ?? FnDs.title,
          ),
        ),
      ],
    );
  }
}

/// 데이터 분석 — 문장으로 풀어 준다.
class _SeasonNoteCard extends StatelessWidget {
  const _SeasonNoteCard();

  @override
  Widget build(BuildContext context) {
    return _SeasonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: FnDs.coral,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: FnDs.gapXs),
              const Text('데이터 분석', style: FnDs.tsSection),
            ],
          ),
          const SizedBox(height: FnDs.gapS),
          const Text(
            '선택 기간 매입은 전년 동기보다 7.5% 늘었어요.\n'
            '6월 증가폭이 가장 크고(+18%), 4월 지출은 8% 줄었어요.\n'
            '기간 중 한 달 평균 매입은 3,984,286원이에요.',
            style: FnDs.tsBody,
          ),
          const SizedBox(height: FnDs.gapS),
          const Text(
            '최근 3개월은 감소세예요.\n'
            '재고가 부족하지 않은지 함께 확인해 보세요.',
            style: FnDs.tsBody,
          ),
          const SizedBox(height: FnDs.gapS),
          const Text(
            '품목군 중 기타의 변동이 +43%로 가장 컸어요.',
            style: FnDs.tsBody,
          ),
        ],
      ),
    );
  }
}

/// 원가 계산기 — 사장님 시안 1:1.
///
/// ## 배치 (시안 순서)
///
/// ```
///   [←] 원가 계산기
///   최근 영수증의 매입 단가에
///   로스율과 직접비를 더해 판매가와 마진율을 계산해요.
///   (꽃다발)(꽃바구니)(화병꽂이)(플라워박스)(직접입력) _CostPresetChips
///   ┌ 상품 구성            3개 품목 · 111,000원 ┐ _CostItemsCard
///   │  품목명 [장미(레드)]                        │
///   │  수량 [10단]  단가 [8,000원]                │
///   │  직전 영수증 단가 기준          80,000원    │
///   │  … 3개 …                                    │
///   └  + 항목 추가                                ┘
///   ┌ 작업비·부대비용 [3,000원]  로스율 [8%]     ┐ _CostExtraCard
///   └ 판매 배수  (×2)(×2.5)(×3)                  ┘
///   ┌ 원가 구성 — 꽃/부자재/로스/작업비/총 원가  ┐ _CostBreakdownCard
///   ┌ 권장 판매가 307,200원 / 마진율 / 대당 이익 ┐ _CostPriceCard
///   ┌ 가격대 제안 — 기본·추천·프리미엄           ┐ _CostTiersCard
///   동일 구성으로 최근 30일간 …
/// ```
///
/// 🔴 여기 숫자는 전부 **예시값**이다. 사장님 지시: "데이터는 예시값,
///    실제 기능은 만들지 마." 붙일 자리는 `docs/TODO_기능연결.md`.
///
/// 🔴 입력칸은 **보여주기만** 한다. 글자를 고쳐도 아래 숫자는 안 바뀐다.
///    상품 구성 칩과 판매 배수만 눌러서 바뀐다(칠해지는 것까지).
///    아예 안 눌리면 고장으로 보이고, 숫자까지 따라 바뀌면 거짓말이 된다.
class GuideCostDsScreen extends StatefulWidget {
  const GuideCostDsScreen({super.key});

  // ── 예시값 ────────────────────────────────────────────────
  /// 상품 묶음 칩. (사장님 지정, #176)
  ///
  /// 🔴 마지막 `직접입력` 은 아직 **고르기만** 된다. 누르면 칠해지지만
  ///    이름을 적는 칸은 안 나온다. 사장님 지시로 입력 기능은 뒤로 미뤘다.
  ///    할 일은 `docs/TODO_기능연결.md` 의 원-4 에 적어 두었다.
  static const List<String> presets = [
    '꽃다발',
    '꽃바구니',
    '화병꽂이',
    '플라워박스',
    '직접입력',
  ];

  /// 직접입력 칩의 자리. 이 번호를 눌렀을 때만 이름 칸이 필요하다.
  static const int customPresetIndex = 4;

  /// (품목명, 수량, 단가, 금액)
  static const List<(String, String, String, String)> items = [
    ('장미(레드)', '10단', '8,000원', '80,000원'),
    ('거베라', '5단', '6,000원', '30,000원'),
    ('포장지', '2장', '500원', '1,000원'),
  ];

  static const String itemsSummary = '3개 품목 · 111,000원';
  static const String directCost = '3,000원';
  static const String lossRate = '8%';

  static const List<String> multipliers = ['×2', '×2.5', '×3'];

  /// (이름, 금액)
  static const List<(String, String)> breakdown = [
    ('꽃', '110,000원'),
    ('부자재', '1,000원'),
    ('로스', '8,880원'),
    ('작업비', '3,000원'),
  ];

  static const String totalCost = '122,880원';
  static const String suggestPrice = '307,200원';
  static const String priceNote = '총 원가 × 2.5배 · 100원 단위 반올림';
  static const String marginRate = '60%';
  static const String marginAmount = '184,320원';

  /// (이름, 마진, 금액, 추천인가)
  static const List<(String, String, String, bool)> tiers = [
    ('기본 ×2', '마진 50%', '245,800원', false),
    ('추천 ×2.5', '마진 60%', '307,200원', true),
    ('프리미엄 ×3.2', '마진 69%', '393,200원', false),
  ];

  @override
  State<GuideCostDsScreen> createState() => _GuideCostDsScreenState();
}

class _GuideCostDsScreenState extends State<GuideCostDsScreen> {
  /// 고른 상품 구성. 처음에는 가장 흔한 '꽃다발'이 켜져 있다.
  int _preset = 0;

  /// 고른 판매 배수. 시안은 ×2.5(가운데).
  int _mult = 1;

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '원가 계산기',
      bg: FnDs.bg,
      onBack: () => Navigator.of(context).pop(),
      child: ColoredBox(
        color: FnDs.bg,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              FnDs.pagePad, 14, FnDs.pagePad, FnDs.gapXl),
          children: [
            const Text(
              '최근 영수증의 매입 단가에\n'
              '로스율과 직접비를 더해 판매가와 마진율을 계산해요.',
              style: FnDs.tsSub,
            ),
            const SizedBox(height: FnDs.gapS),
            _CostPresetChips(
              selected: _preset,
              onTap: (i) => setState(() => _preset = i),
            ),
            const SizedBox(height: FnDs.gapM),
            const _CostItemsCard(),
            const SizedBox(height: FnDs.gapS),
            _CostExtraCard(
              mult: _mult,
              onMult: (i) => setState(() => _mult = i),
            ),
            const SizedBox(height: FnDs.gapS),
            const _CostBreakdownCard(),
            const SizedBox(height: FnDs.gapS),
            const _CostPriceCard(),
            const SizedBox(height: FnDs.gapS),
            const _CostTiersCard(),
            const SizedBox(height: FnDs.gapS),
            const Text(
              '동일 구성으로 최근 30일간 12건 판매했고,\n'
              '평균 판매가는 318,500원이었어요.',
              style: FnDs.tsSub,
            ),
          ],
        ),
      ),
    );
  }
}

/// 상품 구성 칩 줄. 가로로 넘치면 밀어서 본다.
class _CostPresetChips extends StatelessWidget {
  const _CostPresetChips({required this.selected, required this.onTap});

  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const names = GuideCostDsScreen.presets;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: names.length,
        separatorBuilder: (_, __) => const SizedBox(width: FnDs.gapXs),
        itemBuilder: (_, i) => _CostPill(
          label: names[i],
          selected: i == selected,
          onTap: () => onTap(i),
        ),
      ),
    );
  }
}

/// 칠해지는 알약 버튼. 칩과 판매 배수가 같이 쓴다.
class _CostPill extends StatelessWidget {
  const _CostPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? FnDs.coral : FnDs.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? FnDs.coral : FnDs.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.fontXs,
            fontWeight: FontWeight.w700,
            color: selected ? FnDs.onCoral : FnDs.sub,
          ),
        ),
      ),
    );
  }
}

/// 보여주기만 하는 입력칸.
///
/// 🔴 진짜 `TextField` 를 쓰지 않았다. 고칠 수 있게 해 두면 사장님이
///    값을 바꿨는데 아래 숫자가 안 따라오는 걸 보게 된다. 그게 더 나쁘다.
///    기능을 붙일 때 이 위젯만 `TextField` 로 갈아 끼우면 된다.
class _CostField extends StatelessWidget {
  const _CostField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FnDs.tsSub),
        const SizedBox(height: 6),
        Container(
          height: FnDs.inputH,
          width: double.infinity,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: FnDs.inputPadH),
          decoration: BoxDecoration(
            color: FnDs.card,
            borderRadius: BorderRadius.circular(FnDs.inputRadius),
            border: Border.all(color: FnDs.line, width: FnDs.inputBorderW),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.inputFont,
              color: FnDs.title,
            ),
          ),
        ),
      ],
    );
  }
}

/// 상품 구성 — 품목 세 개.
class _CostItemsCard extends StatelessWidget {
  const _CostItemsCard();

  @override
  Widget build(BuildContext context) {
    const rows = GuideCostDsScreen.items;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: FnDs.cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('상품 구성', style: FnDs.tsSection)),
              const Text(
                GuideCostDsScreen.itemsSummary,
                style: TextStyle(
                  fontFamily: FnDs.font,
                  fontSize: FnDs.fontS,
                  fontWeight: FontWeight.w700,
                  color: FnDs.title,
                ),
              ),
            ],
          ),
          const SizedBox(height: FnDs.gapM),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: FnDs.gapM),
              const Divider(height: 1, thickness: 1, color: FnDs.hair),
              const SizedBox(height: FnDs.gapM),
            ],
            _CostField(label: '품목명', value: rows[i].$1),
            const SizedBox(height: FnDs.gapS),
            Row(
              children: [
                Expanded(child: _CostField(label: '수량', value: rows[i].$2)),
                const SizedBox(width: FnDs.gapS),
                Expanded(child: _CostField(label: '단가', value: rows[i].$3)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text('직전 영수증 단가 기준', style: FnDs.tsSub),
                ),
                Text(
                  rows[i].$4,
                  style: const TextStyle(
                    fontFamily: FnDs.font,
                    fontSize: FnDs.fontS,
                    fontWeight: FontWeight.w700,
                    color: FnDs.title,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: FnDs.gapM),
          // 🔴 아직 품목을 더할 수 없다. 누르면 안내만 띄운다.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showFnToast(context, '곧 준비해서 알려드릴게요.'),
            child: const SizedBox(
              height: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: 16, color: FnDs.coral),
                  SizedBox(width: 4),
                  Text(
                    '항목 추가',
                    style: TextStyle(
                      fontFamily: FnDs.font,
                      fontSize: FnDs.fontS,
                      fontWeight: FontWeight.w700,
                      color: FnDs.coral,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 작업비·로스율·판매 배수.
class _CostExtraCard extends StatelessWidget {
  const _CostExtraCard({required this.mult, required this.onMult});

  final int mult;
  final ValueChanged<int> onMult;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: FnDs.cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: _CostField(
                  label: '작업비 · 부대비용',
                  value: GuideCostDsScreen.directCost,
                ),
              ),
              SizedBox(width: FnDs.gapS),
              Expanded(
                child: _CostField(
                  label: '로스율',
                  value: GuideCostDsScreen.lossRate,
                ),
              ),
            ],
          ),
          const SizedBox(height: FnDs.gapM),
          const Text('판매 배수', style: FnDs.tsSub),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: Row(
              children: [
                for (var i = 0;
                    i < GuideCostDsScreen.multipliers.length;
                    i++) ...[
                  if (i > 0) const SizedBox(width: FnDs.gapXs),
                  _CostPill(
                    label: GuideCostDsScreen.multipliers[i],
                    selected: i == mult,
                    onTap: () => onMult(i),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 원가 구성 — 네 줄 + 총 원가.
class _CostBreakdownCard extends StatelessWidget {
  const _CostBreakdownCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: FnDs.cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('원가 구성', style: FnDs.tsSection),
          const SizedBox(height: FnDs.gapM),
          for (final r in GuideCostDsScreen.breakdown) ...[
            _CostRow(label: r.$1, value: r.$2),
            const SizedBox(height: FnDs.gapS),
          ],
          const Divider(height: 1, thickness: 1, color: FnDs.hair),
          const SizedBox(height: FnDs.gapS),
          const _CostRow(
            label: '총 원가',
            value: GuideCostDsScreen.totalCost,
            strong: true,
          ),
        ],
      ),
    );
  }
}

/// 왼쪽 이름 · 오른쪽 금액 한 줄.
class _CostRow extends StatelessWidget {
  const _CostRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.fontS,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
              color: strong ? FnDs.title : FnDs.body,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.fontM,
            fontWeight: FontWeight.w700,
            color: FnDs.title,
          ),
        ),
      ],
    );
  }
}

/// 권장 판매가 — 가운데 큰 숫자.
class _CostPriceCard extends StatelessWidget {
  const _CostPriceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: BoxDecoration(
        // 가장 중요한 숫자라 바탕을 연한 코랄로 깔았다.
        color: FnDs.coralFaint,
        borderRadius: BorderRadius.circular(FnDs.cardRadius),
      ),
      child: Column(
        children: [
          const Text('권장 판매가', style: FnDs.tsSub),
          const SizedBox(height: FnDs.gap2xs),
          const Text(
            GuideCostDsScreen.suggestPrice,
            style: TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.font2xl,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: FnDs.coral,
            ),
          ),
          const SizedBox(height: FnDs.gap2xs),
          const Text(GuideCostDsScreen.priceNote, style: FnDs.tsSub),
          const SizedBox(height: FnDs.gapM),
          const Divider(height: 1, thickness: 1, color: FnDs.hair),
          const SizedBox(height: FnDs.gapS),
          const _CostRow(label: '마진율', value: GuideCostDsScreen.marginRate),
          const SizedBox(height: FnDs.gapXs),
          const _CostRow(
            label: '대당 이익',
            value: GuideCostDsScreen.marginAmount,
          ),
        ],
      ),
    );
  }
}

/// 가격대 제안 — 기본 / 추천 / 프리미엄.
class _CostTiersCard extends StatelessWidget {
  const _CostTiersCard();

  @override
  Widget build(BuildContext context) {
    const rows = GuideCostDsScreen.tiers;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: FnDs.cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('가격대 제안', style: FnDs.tsSection),
          const SizedBox(height: FnDs.gapM),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: FnDs.gapS),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rows[i].$1,
                        style: const TextStyle(
                          fontFamily: FnDs.font,
                          fontSize: FnDs.fontM,
                          fontWeight: FontWeight.w700,
                          color: FnDs.title,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(rows[i].$2, style: FnDs.tsSub),
                    ],
                  ),
                ),
                Text(
                  rows[i].$3,
                  style: TextStyle(
                    fontFamily: FnDs.font,
                    fontSize: FnDs.fontM,
                    fontWeight: FontWeight.w700,
                    // 추천 가격만 코랄로 눈에 띄게 한다.
                    color: rows[i].$4 ? FnDs.coral : FnDs.title,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 예산 검토 — 시안 `guide-budget`
class GuideBudgetDsScreen extends StatelessWidget {
  const GuideBudgetDsScreen({super.key});

  static const _plan = [
    ('장미(레드)', '10단', 80000.0),
    ('거베라', '5단', 30000.0),
    ('카네이션', '8단', 41600.0),
  ];

  @override
  Widget build(BuildContext context) {
    final total = _plan.fold<double>(0, (s, e) => s + e.$3);
    return FnShell(
      navTitle: '예산 검토',
      onBack: () => Navigator.of(context).pop(),
      child: FnColumn(
        gap: 14,
        children: [
          FnCard(
            bordered: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('다음 사입 리스트',
                    style: _t13.copyWith(color: FnColors.labelAlternative)),
                const SizedBox(height: 8),
                ..._plan.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${p.$1} ${p.$2}', style: _t13),
                        Text(FnDemo.won(p.$3),
                            style: _t13.copyWith(
                                color: FnColors.labelAlternative)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          FnCard(
            bordered: true,
            color: FnColors.rose99,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _KV('예상 구매 예산', FnDemo.won(total), strong: true),
                const SizedBox(height: 8),
                _KV('최근 3개월 평균 사입액', FnDemo.won(1520000)),
              ],
            ),
          ),
          Text(
            '최근 시세를 기준으로 계산한 예상 금액이에요. 실제 단가는 시장 상황에 따라 달라질 수 있어요.',
            style: _t14.copyWith(color: FnColors.labelAlternative, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 공통 소품
// ═══════════════════════════════════════════════════════════════════════
class _KV extends StatelessWidget {
  const _KV(this.k, this.v, {this.strong = false});
  final String k;
  final String v;
  final bool strong;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: _t14),
          Text(
            v,
            style: _t14.copyWith(
              fontWeight: FontWeight.w700,
              color: strong ? FnColors.primaryNormal : FnColors.labelNormal,
            ),
          ),
        ],
      );
}

class _Pro extends StatelessWidget {
  const _Pro({required this.title, required this.desc});
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
              Text(title,
                  textAlign: TextAlign.center,
                  style: _t15.copyWith(
                      fontSize: 18, fontWeight: FontWeight.w700, height: 1.4)),
              const SizedBox(height: 12),
              Text(desc,
                  textAlign: TextAlign.center,
                  style: _t14.copyWith(
                      color: FnColors.labelAlternative, height: 1.6)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: FnColors.primaryNormal,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('닫기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _t13 = TextStyle(
    fontFamily: 'Pretendard', fontSize: 13, color: FnColors.labelNormal);
const _t14 = TextStyle(
    fontFamily: 'Pretendard', fontSize: 14, color: FnColors.labelNormal);
const _t15 = TextStyle(
    fontFamily: 'Pretendard', fontSize: 15, color: FnColors.labelNormal);
