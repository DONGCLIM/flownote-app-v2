import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_badge_ds.dart';
import '../../design/fn_controls_ds.dart';

/// 시안 `AppH2Mvp` → `screen === 'paywall'` 1:1 포팅.
///
/// ```js
/// const plans = [
///   { id:'free',    name:'한달 무료 플랜',  price:'0원 / 30일', ... },
///   { id:'monthly', name:'PRO 월간 플랜',  price:'49,000원 / 월', ... },
///   { id:'annual',  name:'PRO 연간 플랜',  price:'490,000원 / 년', badge:'2개월 무료', ... },
/// ];
/// Shell({ navTitle:'구독 안내', onBack })
///   div padding16 column gap12
///     헤더 박스: center pad '16px 12px' r14 bg blue-99
///        17/600 lh1.4  '평소 찍어만 두면,\n세무 장부가 자동으로 완성됩니다'
///        14 alt mt8 lh1.5 '더 이상 영수증 정리로 스트레스받지 마세요!'
///     plans.map → Card bordered=!active
///        style: bg active? blue-99 : #fff,  boxShadow active? '0 0 0 2px blue-50' : none
///        head row spaceBetween gap8
///          left row gap8: 라디오 18x18 r9 border 2px, active→bg blue-50 + '✓' 11 #fff
///                         name 15/600
///          badge → ContentBadge accent
///        price 19/500  mt8  color active? blue-50 : label-normal
///        caption 13 alt mt2
///        Divider margin '10px 0'
///        items: gap7  [15x15 r8 bg active?blue-95:fill-normal color blue-50 10/700 '✓']  13
///     Button large  selectedPlan.cta
///     Button large text '나중에'
/// ```
class PaywallDsScreen extends StatefulWidget {
  const PaywallDsScreen({super.key});

  @override
  State<PaywallDsScreen> createState() => _PaywallDsScreenState();
}

class _Plan {
  const _Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.caption,
    this.badge,
    required this.cta,
    required this.items,
  });

  final String id;
  final String name;
  final String price;
  final String caption;
  final String? badge;
  final String cta;
  final List<String> items;
}

const _plans = <_Plan>[
  _Plan(
    id: 'free',
    name: '한달 무료 플랜',
    price: '0원 / 30일',
    caption: '30일 동안 부담 없이 경험해 보세요',
    cta: '무료로 시작하기',
    items: [
      '월 영수증 100장 스캔 (1회 최대 5장)',
      '최근 6개월 지출 추이 확인',
      '기본 정산서 내보내기 3회',
    ],
  ),
  _Plan(
    id: 'monthly',
    name: 'PRO 월간 플랜',
    price: '49,000원 / 월',
    caption: '하루 1,600원으로 시작하는 자동 정산 & 경영 관리',
    cta: 'PRO 월간 시작하기',
    items: [
      '영수증 무제한 OCR 스캔',
      '세무 제출용 장부 내보내기 무제한',
      '매월 다양한 경영 관리 리포트 제공',
    ],
  ),
  _Plan(
    id: 'annual',
    name: 'PRO 연간 플랜',
    price: '490,000원 / 년',
    caption: '월 40,800원 · 10개월 가격으로 1년 내내 세무 걱정 없이',
    badge: '2개월 무료',
    cta: 'PRO 연간 시작하기',
    items: [
      'PRO 월간의 모든 기능 무제한 이용',
      '연간 98,000원 즉시 절약',
    ],
  ),
];

class _PaywallDsScreenState extends State<PaywallDsScreen> {
  String _plan = 'monthly';

  @override
  Widget build(BuildContext context) {
    final selected = _plans.firstWhere((p) => p.id == _plan);

    return FnShell(
      navTitle: '구독 안내',
      onBack: () => Navigator.of(context).pop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                color: FnColors.rose99,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Column(
                children: [
                  Text(
                    '평소 찍어만 두면,\n세무 장부가 자동으로 완성됩니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      color: FnColors.labelNormal,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '더 이상 영수증 정리로 스트레스받지 마세요!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      height: 1.5,
                      color: FnColors.labelAlternative,
                    ),
                  ),
                ],
              ),
            ),
            for (final p in _plans) ...[
              const SizedBox(height: 12),
              _planCard(p),
            ],
            const SizedBox(height: 12),
            FnDsButton(
              label: selected.cta,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 12),
            FnDsButton(
              label: '나중에',
              expand: true,
              variant: FnDsButtonVariant.text,
              color: FnDsButtonColor.neutral,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _planCard(_Plan p) {
    final active = _plan == p.id;
    return GestureDetector(
      onTap: () => setState(() => _plan = p.id),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: active
              ? Border.all(color: FnColors.rose50, width: 2)
              : Border.all(color: FnColors.lineNeutral, width: 1),
          color: active ? FnColors.rose99 : FnColors.backgroundNormal,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? FnColors.rose50 : Colors.transparent,
                    border: Border.all(
                      color: active ? FnColors.rose50 : FnColors.lineNeutral,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: active
                      ? const Text(
                          '✓',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 11,
                            height: 1,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: FnColors.labelNormal,
                    ),
                  ),
                ),
                if (p.badge != null)
                  FnBadge(p.badge!, color: FnBadgeColor.accent),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              p.price,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 19,
                fontWeight: FontWeight.w500,
                color: active ? FnColors.rose50 : FnColors.labelNormal,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              p.caption,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: FnColors.labelAlternative,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: FnDsDivider(),
            ),
            for (var i = 0; i < p.items.length; i++) ...[
              if (i > 0) const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: active ? FnColors.rose95 : FnColors.fillNormal,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '✓',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: FnColors.rose50,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      p.items[i],
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        color: FnColors.labelNormal,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
