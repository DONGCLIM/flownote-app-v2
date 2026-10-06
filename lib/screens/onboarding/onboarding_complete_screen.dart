import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_button.dart';
import '../../design/fn_card.dart';
import '../../services/subscription_service.dart';
import '../ds/main_ds_screen.dart';

/// 가입 완료 화면.
class OnboardingCompleteScreen extends StatefulWidget {
  const OnboardingCompleteScreen({super.key, this.businessName});

  final String? businessName;

  @override
  State<OnboardingCompleteScreen> createState() =>
      _OnboardingCompleteScreenState();
}

class _OnboardingCompleteScreenState extends State<OnboardingCompleteScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainDsScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.businessName?.trim();
    final trial = SubscriptionService.instance.trialDaysLeft;

    return Scaffold(
      backgroundColor: FnColors.backgroundApp,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            ScaleTransition(
              scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: FnColors.rose95,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('🌸', style: TextStyle(fontSize: 44)),
                ),
              ),
            ),
            const SizedBox(height: FnSpace.x24),
            FadeTransition(
              opacity: _c,
              child: Column(
                children: [
                  Text(
                    name != null && name.isNotEmpty
                        ? '$name\n준비 다 됐어요'
                        : '준비 다 됐어요',
                    textAlign: TextAlign.center,
                    style: FnType.title2,
                  ),
                  const SizedBox(height: FnSpace.x10),
                  Text(
                    '이제 영수증을 찍기만 하면\n매입 장부가 알아서 만들어져요.',
                    textAlign: TextAlign.center,
                    style: FnType.body1
                        .copyWith(color: FnColors.labelAlternative),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FnSpace.x32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FnSpace.x20),
              child: FnCard(
                color: FnColors.leaf95,
                child: Row(
                  children: [
                    const Icon(Icons.card_giftcard_rounded,
                        size: 22, color: FnColors.statusPositiveStrong),
                    const SizedBox(width: FnSpace.x12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PRO 기능 $trial일 무료',
                              style: FnType.heading2),
                          const SizedBox(height: 2),
                          Text('시세 트래커·정산서 발행까지 전부 써보세요',
                              style: FnType.caption1
                                  .copyWith(color: FnColors.labelNeutral)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: FnSpace.x20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: FnSpace.x20),
              child: Column(
                children: [
                  _Step(
                      no: 1,
                      title: '영수증 촬영',
                      body: '한 번에 여러 장도 가능해요'),
                  _Step(
                      no: 2,
                      title: '자동 인식 · 검토',
                      body: '품목과 단가를 확인하고 저장'),
                  _Step(
                      no: 3,
                      title: '매입 분석',
                      body: '시세·원가·정산서까지 한 번에'),
                ],
              ),
            ),
            const Spacer(flex: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  FnSpace.x20, 0, FnSpace.x20, FnSpace.x20),
              child: FnButton(
                label: '시작하기',
                size: FnButtonSize.large,
                expand: true,
                onPressed: _go,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.no, required this.title, required this.body});

  final int no;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FnSpace.x12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: FnColors.rose95,
              shape: BoxShape.circle,
            ),
            child: Text('$no',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: FnColors.primaryNormal,
                )),
          ),
          const SizedBox(width: FnSpace.x12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(title,
                    style:
                        FnType.label1.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: FnSpace.x8),
                Expanded(
                  child: Text(body,
                      style: FnType.caption1
                          .copyWith(color: FnColors.labelAlternative)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
