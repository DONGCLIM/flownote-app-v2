import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_card.dart';
import '../../design/fn_badge_ds.dart';
import '../../services/flower_season_service.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 꽃별 계절 시세 — 인사이트 탭
/// ═══════════════════════════════════════════════════════════════════════
///
/// ## 왜 인사이트인가
/// 영수증 카드의 `FlowerPriceLine` 은 **지금**을 말한다
/// (`양재 경매가 11,827원/단 · 지난주보다 41% 올랐어요`). 이 화면은
/// **평소**를 말한다 (`장미는 7월이 가장 싸고 12월이 가장 비싸요`).
/// 영수증 찍는 중에 필요한 정보가 아니라서 따로 뺐다.
///
/// ## 여기 있는 숫자는 예측이 아니다
/// 문구를 전부 `보통 …한 편이에요` 로 맞췄다. 지난 2년이 그랬다는 사실이고
/// 올해를 약속하는 게 아니다. 단기 추세(`요즘 오르는 중`)는 실측 재현율이
/// 51~53%(동전 던지기)라서 아예 금지했지만, 계절은 73%로 재현된다.
/// 검증 세부는 `FlowerSeasonService` 주석에 있다.
///
/// ## 32품목만 나온다
/// 재현율 70% · 상관 0.6 문턱을 못 넘은 품목은 아무 말도 하지 않는다.
/// 국화(62%)·백합(56%)·유칼립투스(60%)처럼 흔한 꽃도 빠졌다. 흔한 것과
/// 예측 가능한 것은 다르다. 그 사실을 화면 아래에 밝힌다.
class SeasonDsScreen extends StatefulWidget {
  const SeasonDsScreen({super.key});

  @override
  State<SeasonDsScreen> createState() => _SeasonDsScreenState();
}

class _SeasonDsScreenState extends State<SeasonDsScreen> {
  final _svc = FlowerSeasonService.instance;

  /// 펼쳐서 12개월 막대를 보는 품목. 한 번에 하나만.
  String? _open;

  @override
  Widget build(BuildContext context) {
    final month = _svc.currentMonth;
    // 이번 달에 "말할 게 있는" 품목만. 밴드(±10%) 안이면 빠진다.
    final notes = _svc.notesForMonth(limit: 8);

    return FnShell(
      navTitle: '꽃별 계절 시세',
      onBack: () => Navigator.of(context).pop(),
      child: FnColumn(
        gap: 10,
        children: [
          _header(month, notes.length),
          if (!_svc.isReady)
            FnCard(
              bordered: true,
              child: Text(
                '계절 자료를 아직 불러오지 못했어요.',
                style: _t14.copyWith(color: FnColors.labelAlternative),
              ),
            )
          else if (notes.isEmpty)
            FnCard(
              bordered: true,
              child: Text(
                '$month월은 특별히 비싸거나 싼 꽃이 없어요. '
                '대부분 연평균과 비슷한 수준이에요.',
                style: _t14.copyWith(height: 1.5),
              ),
            )
          else
            ...notes.map(_noteCard),
          _footer(),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────
  //  머리말
  // ───────────────────────────────────────────────────────────────────

  Widget _header(int month, int n) => FnCard(
        color: FnColors.rose95,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$month월엔 이런 꽃들이 평소와 달라요',
              style: _t15.copyWith(
                  fontWeight: FontWeight.w700,
                  color: FnColors.primaryNormal,
                  height: 1.4),
            ),
            const SizedBox(height: 6),
            Text(
              // 근거를 숨기지 않는다. 2년치 양재 경매 실적이라는 걸 밝혀야
              // 사장님이 이 숫자를 어디까지 믿을지 스스로 판단할 수 있다.
              '최근 2년 양재 경매 실적에서 매년 반복된 패턴이에요. '
              '연평균보다 ${_svc.band}% 이상 차이 나는 꽃만 보여드려요.',
              style: _t13.copyWith(
                  color: FnColors.primaryNormal, height: 1.55, fontSize: 12.5),
            ),
          ],
        ),
      );

  // ───────────────────────────────────────────────────────────────────
  //  품목 카드
  // ───────────────────────────────────────────────────────────────────

  Widget _noteCard(FlowerSeasonNote n) {
    final open = _open == n.itemName;
    // 비싼 달은 매입 원가가 올라가는 달이므로 경고색, 싼 달은 긍정색.
    // 주식처럼 빨강/파랑을 쓰면 사장님 입장에서 의미가 뒤집힌다.
    final accent =
        n.isPricey ? FnColors.statusCautionaryStrong : FnColors.statusPositive;

    return FnCard(
      bordered: true,
      onTap: () => setState(() => _open = open ? null : n.itemName),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(n.itemName,
                    style: _t15.copyWith(fontWeight: FontWeight.w700)),
              ),
              FnBadge(
                n.isPricey ? '비싼 달' : '싼 달',
                color: n.isPricey
                    ? FnBadgeColor.cautionary
                    : FnBadgeColor.positive,
              ),
              const SizedBox(width: 4),
              Icon(
                open
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: FnColors.labelAssistive,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            n.verdictText,
            style: _t14.copyWith(
                color: accent, fontWeight: FontWeight.w600, height: 1.4),
          ),
          const SizedBox(height: 3),
          Text(
            '${n.yearAvgText} · ${n.rangeText}',
            style: _t13.copyWith(
                fontSize: 12, color: FnColors.labelAssistive, height: 1.45),
          ),
          if (open) ...[
            const SizedBox(height: 12),
            _MonthStrip(note: n),
            const SizedBox(height: 8),
            Text(
              // 재현율을 숨기지 않는다. 88%와 70%는 믿을 만한 정도가 다르고,
              // 그 차이를 사장님이 알 권리가 있다.
              '연평균을 100으로 본 달별 수준이에요. '
              '이 패턴은 지난 2년 중 ${(n.repeatRate * 100).round()}% 반복됐어요.',
              style: _t13.copyWith(
                  fontSize: 11.5,
                  color: FnColors.labelAssistive,
                  height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────
  //  꼬리말
  // ───────────────────────────────────────────────────────────────────

  Widget _footer() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '양재 화훼공판장 경매 낙찰가 기준이에요. '
              '도매상에서 실제로 사오시는 가격과는 수준이 다를 수 있어요.',
              style: _t13.copyWith(
                  fontSize: 12, color: FnColors.labelAssistive, height: 1.55),
            ),
            const SizedBox(height: 6),
            Text(
              // 왜 내 꽃이 없냐는 질문에 미리 답한다. 침묵의 이유를 밝히지
              // 않으면 사장님은 앱이 고장난 줄 안다.
              '매년 같은 흐름이 반복된 ${_svc.itemCount}개 품목만 담았어요. '
              '해마다 들쭉날쭉한 꽃은 섣불리 말씀드리지 않아요.',
              style: _t13.copyWith(
                  fontSize: 12, color: FnColors.labelAssistive, height: 1.55),
            ),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════
//  12개월 막대
// ═══════════════════════════════════════════════════════════════════════
/// `FnBarChart` 를 쓰지 않고 직접 그린다. 이번 달만 강조하고, 밴드 밖으로
/// 벗어난 달을 색으로 구분해야 하는데 공용 차트는 막대별 색 규칙이 없다.
class _MonthStrip extends StatelessWidget {
  const _MonthStrip({required this.note});
  final FlowerSeasonNote note;

  @override
  Widget build(BuildContext context) {
    final idx = note.monthlyIndex;
    final maxV = idx.values.fold<int>(100, (a, b) => b > a ? b : a);

    return SizedBox(
      height: 74,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(12, (i) {
          final m = i + 1;
          final v = idx[m];
          final isNow = m == note.month;

          // 관측이 부족해 지수가 없는 달은 빈칸으로 둔다. 0으로 그리면
          // "그 달엔 공짜"처럼 보인다.
          if (v == null) {
            return Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: FnColors.lineNeutral,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('$m', style: _tinyLabel(false)),
                ],
              ),
            );
          }

          final h = (v / maxV * 48).clamp(3.0, 48.0);
          final Color c = v > 100 + note.band
              ? FnColors.statusCautionaryStrong
              : v < 100 - note.band
                  ? FnColors.statusPositive
                  : FnColors.labelAssistive;

          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('$v',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 8.5,
                      height: 1.1,
                      fontWeight: isNow ? FontWeight.w700 : FontWeight.w400,
                      color: isNow ? c : FnColors.labelAssistive,
                    )),
                const SizedBox(height: 2),
                Container(
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: isNow ? c : c.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(3),
                    // 이번 달은 테두리로 한 번 더 표시한다. 색만으로는
                    // 같은 색 막대들 사이에서 찾기 어렵다.
                    border: isNow
                        ? Border.all(color: FnColors.labelNormal, width: 1)
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$m', style: _tinyLabel(isNow)),
              ],
            ),
          );
        }),
      ),
    );
  }

  static TextStyle _tinyLabel(bool now) => TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 9.5,
        height: 1.1,
        fontWeight: now ? FontWeight.w700 : FontWeight.w400,
        color: now ? FnColors.labelNormal : FnColors.labelAssistive,
      );
}

const _t13 = TextStyle(
    fontFamily: 'Pretendard', fontSize: 13, color: FnColors.labelNormal);
const _t14 = TextStyle(
    fontFamily: 'Pretendard', fontSize: 14, color: FnColors.labelNormal);
const _t15 = TextStyle(
    fontFamily: 'Pretendard', fontSize: 15, color: FnColors.labelNormal);
