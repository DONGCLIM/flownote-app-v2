import 'package:flutter/material.dart';

import '../design/fn_tokens.dart';
import '../services/flower_price_service.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 항목 카드에 붙는 양재 경매 시세 한 줄
/// ═══════════════════════════════════════════════════════════════════════
///
/// ## 왜 드롭다운이 아니라 여기인가
/// 예전에는 자동완성 드롭다운 2행에 시세가 있었다. 그런데 그 시점은 아직
/// 이름을 **고치는 중**이라 시세를 볼 이유가 없고, 한 줄에 사실이 5개나 들어가
/// 복잡했다. 이름이 **확정된 뒤** 카드에 조용히 한 줄 붙는 게 맞다.
///
/// ## 표기 규칙
///   `양재 경매가 11,827원/단 · 지난주보다 41% 올랐어요 · 8/21 경매`
///
/// - **`양재 경매가`** 를 반드시 앞에 붙인다. 이건 도매시장 낙찰가라서 사장님이
///   도매상에서 실제로 지불하는 가격과 수준이 다르다. 그 사실을 숨기면
///   "내 매입가가 왜 이렇게 비싸냐"는 오해가 생긴다.
/// - **`단`** 만 쓴다. 사이트 표기가 `단(속)` 이므로 1속 = 1단이다. 송이 환산은
///   하지 않는다 (품목마다 다르고 검증한 값이 아니다).
/// - **날짜를 반드시 밝힌다.** 경매는 월·수·금만 열려서 오늘 값이 아닐 수 있다.
/// - **±5% 안이면 `지난주와 비슷해요`.** 처음엔 문턱 없이 그대로 썼는데
///   `해바라기 · 1% 올랐어요` 가 나왔다. 꽃값 주간 변동 중간값이 품목별로
///   9.5~19.6% 라서 1~2% 는 제자리인데, 그걸 "올랐다"고 하면 없는 신호를
///   보여주는 셈이다. 밴드 안에서는 화살표도 강조색도 쓰지 않는다.
/// - **계산 불가(`null`)와 `비슷해요` 는 다르다.** 관측 경매일이 부족하면
///   그 조각을 통째로 뺀다. 모르는 걸 "비슷하다"고 말하지 않는다.
/// - **`오를 것 같아요` 는 절대 쓰지 않는다.** 2년치 검증에서 오름/내림 판정이
///   다음 기간에도 유지될 확률은 51~53%(동전 던지기)였다. 예측은 거짓말이 된다.
///
/// ## 없으면 아무것도 안 그린다
/// 철 지난 꽃은 최근 6경매일 데이터가 없어서 변화를 못 낸다(실측 63%만 가능).
/// 요약이 묵었을 때도 마찬가지다. 그럴 때 억지로 채우면 거짓 정보가 되므로
/// `SizedBox.shrink()` 로 조용히 사라진다.
class FlowerPriceLine extends StatelessWidget {
  const FlowerPriceLine({super.key, required this.flowerName});

  /// 확정된 꽃 이름. `장미` 또는 `장미 하젤`.
  final String flowerName;

  @override
  Widget build(BuildContext context) {
    final q = FlowerPriceService.instance.lookup(flowerName);
    if (q == null) return const SizedBox.shrink();

    // 오름은 사장님에게 나쁜 소식(매입 원가 상승)이므로 경고색,
    // 내림은 좋은 소식이므로 긍정색. 색을 주가처럼 쓰면 의미가 뒤집힌다.
    final Color accent = q.isUp
        ? FnColors.statusCautionaryStrong
        : q.isDown
            ? FnColors.statusPositive
            : FnColors.labelAssistive;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 화살표는 실제로 움직였을 때만. `비슷해요` 에 화살표를 붙이면
          // 방향이 있는 것처럼 읽힌다.
          if (q.isUp || q.isDown) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1.5),
              child: Icon(
                q.isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 13,
                color: accent,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11.5,
                  height: 1.35,
                  color: FnColors.labelAssistive,
                ),
                children: [
                  TextSpan(text: q.priceText),
                  if (q.hasChange) ...[
                    const TextSpan(text: ' · '),
                    TextSpan(
                      text: q.changeText,
                      // `비슷해요` 는 강조하지 않는다 — 알릴 게 없다는 뜻이므로
                      // 본문과 같은 무게로 흘려보낸다.
                      style: q.isFlat
                          ? null
                          : TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                  ],
                  TextSpan(text: ' · ${q.dateText}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
