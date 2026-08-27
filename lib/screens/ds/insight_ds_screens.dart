import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_card.dart';
import '../../design/fn_badge_ds.dart';
import '../../design/fn_charts_ds.dart';
import '../../design/fn_avatar.dart';
import '../../providers/receipt_provider.dart';
import '../../services/flower_season_service.dart';
import '../../services/subscription_service.dart';
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

  static const _menu = [
    (
      title: '① 시즌 매입 비교',
      desc: '지난 시즌 및 전년 동월 대비 사입 지출 금액을 비교해요.',
      page: 'season',
    ),
    // 꽃별 계절 시세는 내 매입 내역이 아니라 양재 경매 2년치에서 나온다.
    // 그래서 '내 지출을 비교'하는 ①과 성격이 다르고, 따로 둔다.
    (
      title: '② 꽃별 계절 시세',
      desc: '어떤 꽃이 몇 월에 비싸고 싼지, 최근 2년 양재 경매에서 반복된 흐름을 알려드려요.',
      page: 'flowerSeason',
    ),
    (
      title: '③ 원가 계산기',
      desc: '꽃 조합·수량으로 레시피 원가를 산출하고, 목표 마진율에 맞는 판매가를 계산해요.',
      page: 'cost',
    ),
    (
      title: '④ 예산 검토',
      desc: '다음 사입에 필요한 꽃 리스트를 입력하면, 최근 시세로 예상 구매 예산을 검토해요.',
      page: 'budget',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '스마트 사입 가이드',
      onBack: () => Navigator.of(context).pop(),
      child: FnColumn(
        gap: 12,
        children: _menu
            .map(
              (m) => FnCard(
                bordered: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => switch (m.page) {
                      'season' => const GuideSeasonDsScreen(),
                      'flowerSeason' => const SeasonDsScreen(),
                      'cost' => const GuideCostDsScreen(),
                      _ => const GuideBudgetDsScreen(),
                    },
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(m.title,
                            style: _t15.copyWith(fontWeight: FontWeight.w700)),
                        const Icon(Icons.chevron_right_rounded,
                            size: 18, color: FnColors.labelAssistive),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      m.desc,
                      style: _t13.copyWith(
                          color: FnColors.labelAlternative, height: 1.5),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// ```js
/// Shell('시즌 매입 비교')
///   Card bordered: '상반기 사입 지출 추이' 13 label-alternative mb8 + BarChart(6개월, 320x90)
///   Card bordered: [전년 동월 대비  +9% (700, blue-50)] / [지난 시즌 평균 대비  +4%]
///   div wds-body2-normal label-alternative '같은 달·같은 시즌 지출과 비교해...'
/// ```
class GuideSeasonDsScreen extends StatelessWidget {
  const GuideSeasonDsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '시즌 매입 비교',
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
                Text('상반기 사입 지출 추이',
                    style: _t13.copyWith(color: FnColors.labelAlternative)),
                const SizedBox(height: 8),
                Center(
                  child: FnBarChart(
                    data: List.generate(
                      6,
                      (i) => FnChartDatum(
                          label: FnDemo.demoMonths[i],
                          value: FnDemo.demoSpend[i]),
                    ),
                    width: 300,
                    height: 90,
                  ),
                ),
              ],
            ),
          ),
          FnCard(
            bordered: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _KV('전년 동월 대비', '+9%'),
                const SizedBox(height: 8),
                _KV('지난 시즌 평균 대비', '+4%'),
              ],
            ),
          ),
          Text(
            '같은 달·같은 시즌 지출과 비교해 사입 규모가 적정한지 확인해보세요.',
            style: _t14.copyWith(color: FnColors.labelAlternative, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 원가 계산기 — 시안 `guide-cost`
class GuideCostDsScreen extends StatelessWidget {
  const GuideCostDsScreen({super.key});

  static const _recipe = [
    ('장미(레드) 10단', '₩8,000/단'),
    ('거베라 5단', '₩6,000/단'),
    ('포장재', '₩3,000'),
  ];

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '원가 계산기',
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
                Text('꽃다발 레시피',
                    style: _t13.copyWith(color: FnColors.labelAlternative)),
                const SizedBox(height: 8),
                ..._recipe.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(r.$1, style: _t13),
                        Text(r.$2,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _KV('레시피 원가 (대당)', FnDemo.won(113000)),
                const SizedBox(height: 8),
                _KV('목표 마진율', '35%'),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: FnDsDivider(),
                ),
                _KV('권장 판매가', FnDemo.won(173846), strong: true),
              ],
            ),
          ),
          Text(
            '레시피별 원가를 저장해두면 다음 주문에서도 바로 계산할 수 있어요.',
            style: _t14.copyWith(color: FnColors.labelAlternative, height: 1.5),
          ),
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
