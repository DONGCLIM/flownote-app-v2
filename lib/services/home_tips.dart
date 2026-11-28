import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 홈 "스마트 사입 가이드" 카드 아래에 날마다 바뀌는 팁. (#186)
///
/// ## 어디에 담았나
///
/// 🔴 **앱 안 목록**이다. Firestore 가 아니다. 사장님 지시(#186).
///    팁은 모든 사장님께 똑같이 보이는 글이라 서버에 둘 까닭이 없고,
///    인터넷이 없어도 떠야 한다.
///
/// ## 팁을 더하거나 고치는 법 (세 줄)
///
/// ```
///   ① 이 파일 맨 아래 kHomeTips 목록에 HomeTip(...) 한 덩어리를 더한다.
///      ID 는 겹치지 않게(S=시즌달 · C=관리 · O=운영), when 은 그 달이면
///      TipWhen.month + month: 9, 아무 때나면 TipWhen.allYear 를 쓴다.
///   ② 본문에 신고 기한 날짜가 있으면 deadline: (7, 25) 처럼 적는다.
///      그 날이 지나면 그 해에는 안 보인다.
///   ③ 저장하고 `flutter test test/home_render_test.dart` 를 돌려 본다.
/// ```
///
/// ## 보여주는 규칙 (사장님 확정 #186)
///
/// ```
///   오늘 보여줄 수 있는 팁 = 이번 달 팁 + 연중 팁
///   하루에 하나. 날짜가 바뀌면 다음 팁으로 넘어간다
///   이번 달 팁을 먼저 다 보여주고, 그 다음 연중 팁
///   한 번 본 팁은 30일 동안 다시 안 나온다 (이 기기에만 기록)
///   세무 팁은 본문에 적힌 신고 기한이 지나면 그 해에는 안 보인다
///   추석 팁은 추석 3주 전부터 추석 당일까지만
/// ```
///
/// 🔴 데이터 팁(`D01`~`D10` — 영수증을 보고 "장미 단가가 올랐어요" 처럼
///    말하는 것)은 **아직 안 넣었다.** 다음 작업으로 미뤘다.
///    `docs/TODO_기능연결.md` 에 적어 두었다.
enum TipWhen {
  /// 그 달에만. [HomeTip.month] 를 함께 본다.
  month,

  /// 아무 때나.
  allYear,

  /// 추석 3주 전 ~ 추석 당일.
  chuseok,
}

/// 팁 한 줄.
@immutable
class HomeTip {
  const HomeTip({
    required this.id,
    required this.group,
    required this.when,
    required this.title,
    required this.body,
    this.month = 0,
    this.deadline,
  });

  /// `S01` · `C07` · `O12`. 본 팁을 기억할 때 열쇠로 쓴다.
  final String id;

  /// 시즌 · 세무 · 관리 · 운영.
  final String group;

  final TipWhen when;

  /// [TipWhen.month] 일 때의 달. 1~12.
  final int month;

  final String title;
  final String body;

  /// 본문에 적힌 신고 기한 `(월, 일)`. 이 날이 지나면 그 해에는 안 보인다.
  ///
  /// 🔴 "1월 25일까지 신고" 라고 적어 놓고 1월 28일에 보여주면 거짓말이다.
  final (int, int)? deadline;

  /// 오늘 보여줄 수 있는 팁인가.
  bool showsOn(DateTime today, {DateTime? chuseok}) {
    // 기한이 지난 세무 팁은 뺀다.
    final d = deadline;
    if (d != null) {
      final last = DateTime(today.year, d.$1, d.$2);
      if (today.isAfter(last)) return false;
    }

    switch (when) {
      case TipWhen.allYear:
        return true;
      case TipWhen.month:
        return month == today.month;
      case TipWhen.chuseok:
        if (chuseok == null) return false;
        // 3주 전부터 당일까지. 추석이 지나면 안 보인다.
        final from = chuseok.subtract(const Duration(days: 21));
        final t = DateTime(today.year, today.month, today.day);
        return !t.isBefore(from) && !t.isAfter(chuseok);
    }
  }

  /// 이번 달 팁을 연중 팁보다 먼저 보여준다. (사장님 지시 #186)
  int get priority => when == TipWhen.allYear ? 1 : 0;
}

/// 연도별 추석·수능 날짜.
///
/// 🔴 음력을 코드로 셈하지 않는다. 음력 변환을 직접 짜면 틀리기 쉽고,
///    그러려고 패키지를 하나 더 넣을 일도 아니다. **사장님께 확인받은
///    날짜**를 표로 박아 둔다. (#186 확인 완료)
///
/// | 연도 | 추석 | 수능 |
/// |---|---|---|
/// | 2026 | 9월 25일 (금) | 11월 19일 (목) — 2027학년도 |
/// | 2027 | 9월 15일 (수) | 11월 18일 (목) — 2028학년도 |
/// | 2028 | 10월 3일 (화) | 11월 16일 (목) — 2029학년도 |
///
/// 🔴 2029년부터는 비어 있다. 표에 없는 해에는 추석 팁이 그냥 안 보인다
///    (틀린 날짜로 보여주는 것보다 낫다). 그때 한 줄씩 더하면 된다.
class KoreanDates {
  KoreanDates._();

  static const Map<int, (int, int)> chuseokByYear = {
    2026: (9, 25),
    2027: (9, 15),
    2028: (10, 3),
  };

  static const Map<int, (int, int)> suneungByYear = {
    2026: (11, 19),
    2027: (11, 18),
    2028: (11, 16),
  };

  /// 그 해 추석. 표에 없으면 null.
  static DateTime? chuseok(int year) {
    final e = chuseokByYear[year];
    return e == null ? null : DateTime(year, e.$1, e.$2);
  }

  /// 그 해 수능. 표에 없으면 null.
  static DateTime? suneung(int year) {
    final e = suneungByYear[year];
    return e == null ? null : DateTime(year, e.$1, e.$2);
  }
}

/// 오늘의 팁을 고른다.
///
/// 🔴 "본 팁" 기록은 **이 기기에만** 남긴다. 클라우드에 올리지 않는다.
///    사장님 지시(#186). 폰을 바꾸면 처음부터 다시 도는데, 팁은 잃어도
///    아쉽지 않은 값이라 그게 더 단순하다.
class HomeTipPicker {
  HomeTipPicker._();

  /// 한 번 본 팁을 며칠 동안 다시 안 보여주나.
  static const int cooldownDays = 30;

  /// 오늘 보여줄 수 있는 팁을 고른다. 이번 달 팁이 앞, 연중 팁이 뒤.
  static List<HomeTip> candidates(
    DateTime today, {
    List<HomeTip> all = kHomeTips,
  }) {
    final chuseok = KoreanDates.chuseok(today.year);
    final out = all.where((e) => e.showsOn(today, chuseok: chuseok)).toList();
    // 🔴 `sort` 는 같은 값끼리 순서를 보장하지 않는다. 우선순위가 같으면
    //    ID 순으로 고정해, 같은 날 두 번 열어도 같은 팁이 나오게 한다.
    out.sort((a, b) {
      final p = a.priority.compareTo(b.priority);
      return p != 0 ? p : a.id.compareTo(b.id);
    });
    return out;
  }

  /// 오늘의 팁 하나. 보여줄 게 없으면 null.
  ///
  /// [seen] 은 `팁 ID → 마지막으로 본 날`. 30일이 안 지난 것은 건너뛴다.
  /// 전부 건너뛰게 되면(팁보다 날이 적을 때) **가장 오래전에 본 것**을
  /// 꺼낸다. 빈 칸을 보여주는 것보다 낫다.
  static HomeTip? pick(
    DateTime today, {
    Map<String, DateTime> seen = const {},
    List<HomeTip> all = kHomeTips,
  }) {
    final list = candidates(today, all: all);
    if (list.isEmpty) return null;

    final fresh = <HomeTip>[];
    for (final t in list) {
      final last = seen[t.id];
      if (last == null) {
        fresh.add(t);
        continue;
      }
      if (today.difference(last).inDays >= cooldownDays) fresh.add(t);
    }

    if (fresh.isEmpty) {
      // 다 봤다. 본 지 가장 오래된 것부터 다시 돈다.
      final again = List<HomeTip>.from(list)
        ..sort((a, b) => seen[a.id]!.compareTo(seen[b.id]!));
      return again.first;
    }

    // 하루에 하나, 날짜가 바뀌면 다음 팁으로.
    //
    // 🔴 날짜를 **번호로** 바꿔 고른다. 아무거나 뽑으면(random) 같은 날
    //    화면을 두 번 열었을 때 팁이 달라져서 고장처럼 보인다.
    final day = DateTime(today.year, today.month, today.day)
            .difference(DateTime(2026, 1, 1))
            .inDays %
        fresh.length;
    return fresh[day.abs()];
  }
}

/// 본 팁을 **이 기기에만** 기억한다. (#186)
///
/// 🔴 클라우드에 올리지 않는다. 사장님 지시: "이 기기에만 기록,
///    클라우드 저장 안 함." 폰을 바꾸면 처음부터 다시 돌지만, 팁은
///    잃어도 아쉽지 않은 값이라 그게 더 단순하다.
///
/// 🔴 계정을 가르지 않는다. 영수증과 달리 팁에는 사장님 돈 이야기가
///    없어서, 한 폰을 둘이 써도 서로 볼까 걱정할 게 없다.
class HomeTipStore extends ChangeNotifier {
  HomeTipStore._();
  static final HomeTipStore instance = HomeTipStore._();

  static const String prefsKey = 'fn_home_tips_seen';

  /// 팁 ID → 마지막으로 본 날.
  final Map<String, DateTime> _seen = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  Map<String, DateTime> get seen => Map.unmodifiable(_seen);

  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          final d = DateTime.tryParse(v as String? ?? '');
          if (d != null) _seen[k] = d;
        });
      }
    } catch (e) {
      // 읽기에 실패해도 팁은 떠야 한다. 처음 보는 것처럼 돈다.
      if (kDebugMode) debugPrint('[HomeTip] 읽기 실패: $e');
    }
    _prune();
    _loaded = true;
    notifyListeners();
  }

  /// 오래된 기록을 버린다.
  ///
  /// 🔴 안 버리면 몇 해가 지나도록 쌓인다. 30일이 지나면 어차피 다시
  ///    보여줄 팁이라 들고 있을 까닭이 없다. 넉넉히 두 배만 남긴다.
  void _prune() {
    final now = DateTime.now();
    _seen.removeWhere((_, d) =>
        now.difference(d).inDays > HomeTipPicker.cooldownDays * 2);
  }

  /// 오늘 이 팁을 봤다고 적는다. 같은 날 두 번 적지 않는다.
  Future<void> markSeen(String id, {DateTime? today}) async {
    final t = today ?? DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final old = _seen[id];
    if (old != null && old.isAtSameMomentAs(day)) return;
    _seen[id] = day;
    _prune();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefsKey,
        jsonEncode({
          for (final e in _seen.entries)
            e.key: e.value.toIso8601String(),
        }),
      );
    } catch (e) {
      // 못 적어도 넘어간다. 다음에 같은 팁이 한 번 더 보일 뿐이다.
      if (kDebugMode) debugPrint('[HomeTip] 저장 실패: $e');
    }
  }

  /// 오늘의 팁. 화면이 이걸 부른다.
  HomeTip? today({DateTime? now, List<HomeTip> all = kHomeTips}) {
    final t = now ?? DateTime.now();
    return HomeTipPicker.pick(t, seen: _seen, all: all);
  }

  /// 테스트에서 비울 때.
  @visibleForTesting
  void resetForTest() {
    _seen.clear();
    _loaded = false;
  }
}

/// 팁 목록. 사장님이 주신 표를 그대로 옮겼다. (#186)
///
/// 🔴 손으로 고쳐도 된다. 위 "팁을 더하거나 고치는 법" 을 보시라.
const List<HomeTip> kHomeTips = [
  HomeTip(
    id: 'S01',
    group: '시즌',
    when: TipWhen.month,
    month: 1,
    title: '졸업 시즌 예약 받기',
    body: '2월 졸업식 꽃다발 예약을 지금부터 받아 보세요. 예약 수량을 알면 사입량을 정확히 맞출 수 있어요.',
  ),
  HomeTip(
    id: 'S02',
    group: '세무',
    when: TipWhen.month,
    month: 1,
    title: '부가세 확정신고 준비',
    body: '과세사업자라면 1월 25일까지 하반기 부가세 확정신고가 있어요. 영수증을 미리 정리해 두세요.',
    deadline: (1, 25),
  ),
  HomeTip(
    id: 'S03',
    group: '관리',
    when: TipWhen.month,
    month: 1,
    title: '난방기 바람 피하기',
    body: '난방기 바람이 바로 닿으면 꽃이 빨리 마르고 시들어요. 진열 위치를 한 번 확인해 보세요.',
  ),
  HomeTip(
    id: 'S04',
    group: '세무',
    when: TipWhen.month,
    month: 2,
    title: '사업장현황신고 확인',
    body: '면세사업자라면 2월 10일까지 사업장현황신고가 있어요. 지난해 매입 영수증을 모아 두세요.',
    deadline: (2, 10),
  ),
  HomeTip(
    id: 'S05',
    group: '시즌',
    when: TipWhen.month,
    month: 2,
    title: '졸업 꽃다발 선주문 마감',
    body: '졸업식이 몰리는 주간에는 선주문 마감일을 정해 공지해 보세요. 포장지·리본도 미리 넉넉히 확보해 두면 좋아요.',
  ),
  HomeTip(
    id: 'S06',
    group: '시즌',
    when: TipWhen.month,
    month: 2,
    title: '발렌타인데이 장미 준비',
    body: '2월 14일 전후로 장미 수요가 늘어요. 사입 일정을 미리 잡고, 지난 영수증 단가와 비교해 보세요.',
  ),
  HomeTip(
    id: 'S07',
    group: '시즌',
    when: TipWhen.month,
    month: 3,
    title: '입학·화이트데이 시즌',
    body: '3월 초 입학식과 3월 14일 화이트데이가 이어져요. 작은 꽃다발 구성을 미리 정해 두면 준비가 빨라요.',
  ),
  HomeTip(
    id: 'S08',
    group: '관리',
    when: TipWhen.month,
    month: 3,
    title: '일교차 큰 날 배송',
    body: '아침저녁 기온 차가 큰 시기예요. 배송할 꽃은 찬 바람에 오래 노출되지 않게 감싸 주세요.',
  ),
  HomeTip(
    id: 'S09',
    group: '시즌',
    when: TipWhen.month,
    month: 4,
    title: '봄 웨딩 상담',
    body: '봄 웨딩 시즌이 시작돼요. 부케 색감을 일찍 확정하면 원하는 꽃을 여유 있게 구할 수 있어요.',
  ),
  HomeTip(
    id: 'S10',
    group: '시즌',
    when: TipWhen.month,
    month: 4,
    title: '어버이날 카네이션 선주문',
    body: '4월 하순부터 어버이날 선주문을 받아 보세요. 주문 수량을 먼저 알면 카네이션 사입량을 맞추기 쉬워요.',
  ),
  HomeTip(
    id: 'S11',
    group: '관리',
    when: TipWhen.month,
    month: 4,
    title: '따뜻해지면 물 자주 갈기',
    body: '기온이 오르면 물이 빨리 상해요. 버킷 물을 더 자주 갈아 주세요.',
  ),
  HomeTip(
    id: 'S12',
    group: '시즌',
    when: TipWhen.month,
    month: 5,
    title: '어버이날 카네이션',
    body: '5월 8일 어버이날이 다가와요. 선주문 수량을 확인하고, 남을 재고를 줄이도록 사입량을 맞춰 보세요.',
  ),
  HomeTip(
    id: 'S13',
    group: '시즌',
    when: TipWhen.month,
    month: 5,
    title: '로즈데이·스승의 날',
    body: '5월 14일 로즈데이와 15일 스승의 날이 이어져요. 장미와 소형 꽃다발 구성을 함께 준비해 보세요.',
  ),
  HomeTip(
    id: 'S14',
    group: '운영',
    when: TipWhen.month,
    month: 5,
    title: '5월 부자재 점검',
    body: '행사가 몰리는 달이에요. 포장지·리본·카드 재고를 행사 전에 먼저 확인해 두세요.',
  ),
  HomeTip(
    id: 'S15',
    group: '관리',
    when: TipWhen.month,
    month: 6,
    title: '장마철 곰팡이 주의',
    body: '습한 날에는 꽃잎과 잎에 물기가 남지 않게 해 주세요. 상한 잎은 바로 떼어 내면 번지는 걸 막을 수 있어요.',
  ),
  HomeTip(
    id: 'S16',
    group: '운영',
    when: TipWhen.month,
    month: 6,
    title: '장마철 포장지 보관',
    body: '종이 포장지는 습기를 먹으면 울어요. 바닥에서 띄우고 밀봉해서 보관해 보세요.',
  ),
  HomeTip(
    id: 'S17',
    group: '운영',
    when: TipWhen.month,
    month: 6,
    title: '비수기 사입량 조절',
    body: '행사가 줄어드는 시기예요. 작년 같은 달 매입을 확인하고 사입량을 조절해 보세요.',
  ),
  HomeTip(
    id: 'S18',
    group: '관리',
    when: TipWhen.month,
    month: 7,
    title: '한여름 냉장 보관',
    body: '더운 날에는 꽃을 냉장 보관하고, 진열 중에도 직사광선을 피해 주세요.',
  ),
  HomeTip(
    id: 'S19',
    group: '세무',
    when: TipWhen.month,
    month: 7,
    title: '부가세 확정신고 준비',
    body: '과세사업자라면 7월 25일까지 상반기 부가세 확정신고가 있어요. 영수증을 미리 정리해 두세요.',
    deadline: (7, 25),
  ),
  HomeTip(
    id: 'S20',
    group: '운영',
    when: TipWhen.month,
    month: 7,
    title: '소량씩 자주 사입',
    body: '더위에 꽃이 빨리 시드는 시기예요. 한 번에 많이 사기보다 소량씩 자주 사입하는 방법도 있어요.',
  ),
  HomeTip(
    id: 'S21',
    group: '관리',
    when: TipWhen.month,
    month: 8,
    title: '차 안에 꽃 두지 않기',
    body: '한여름 차량 안은 금방 뜨거워져요. 사입하거나 배송할 꽃은 차 안에 오래 두지 마세요.',
  ),
  HomeTip(
    id: 'S22',
    group: '운영',
    when: TipWhen.month,
    month: 8,
    title: '가을 시즌 미리 계획',
    body: '추석과 가을 웨딩이 다가와요. 작년 이맘때 매입을 보고 사입 계획을 세워 보세요.',
  ),
  HomeTip(
    id: 'S23',
    group: '시즌',
    when: TipWhen.chuseok,
    title: '추석 선물 예약',
    body: '추석 꽃바구니·화분 선물 예약을 미리 받아 보세요. 배송이 몰리기 전에 마감일을 정해 두면 좋아요.',
  ),
  HomeTip(
    id: 'S24',
    group: '시즌',
    when: TipWhen.month,
    month: 9,
    title: '가을 웨딩 시즌',
    body: '가을 웨딩이 많은 시기예요. 부케·코사지 주문은 색감과 일정을 일찍 확정해 두세요.',
  ),
  HomeTip(
    id: 'S25',
    group: '시즌',
    when: TipWhen.month,
    month: 10,
    title: '가을 행사 꽃 단가 비교',
    body: '가을 행사와 웨딩이 이어져요. 많이 쓰는 꽃은 거래처별 단가를 비교해 보세요.',
  ),
  HomeTip(
    id: 'S26',
    group: '관리',
    when: TipWhen.month,
    month: 10,
    title: '추위에 약한 꽃 위치',
    body: '기온이 내려가요. 안스리움처럼 추위에 약한 꽃은 너무 차가운 곳에 두지 마세요.',
  ),
  HomeTip(
    id: 'S27',
    group: '시즌',
    when: TipWhen.month,
    month: 11,
    title: '수능 응원 꽃',
    body: '수능 전후로 응원 꽃다발을 찾는 손님이 있어요. 작은 구성을 미리 정해 두세요.',
  ),
  HomeTip(
    id: 'S28',
    group: '시즌',
    when: TipWhen.month,
    month: 11,
    title: '연말 예약 준비',
    body: '크리스마스 리스와 연말 꽃 예약을 지금부터 받아 보세요. 소재 사입 계획도 함께 세워 두면 좋아요.',
  ),
  HomeTip(
    id: 'S29',
    group: '관리',
    when: TipWhen.month,
    month: 11,
    title: '건조한 날 물 관리',
    body: '날이 건조해지면 꽃이 물을 빨리 먹어요. 수위를 자주 확인해 주세요.',
  ),
  HomeTip(
    id: 'S30',
    group: '시즌',
    when: TipWhen.month,
    month: 12,
    title: '크리스마스·송년 준비',
    body: '크리스마스와 송년 모임 주문이 몰려요. 리스·소재·부자재 재고를 행사 전에 확인해 두세요.',
  ),
  HomeTip(
    id: 'S31',
    group: '운영',
    when: TipWhen.month,
    month: 12,
    title: '올해 매입 돌아보기',
    body: '한 해 매입 흐름을 시즌 매입 비교에서 확인해 보세요. 내년 사입 계획의 기준이 돼요.',
  ),
  HomeTip(
    id: 'S32',
    group: '관리',
    when: TipWhen.month,
    month: 12,
    title: '한파 배송',
    body: '추운 날 배송할 꽃은 꼭 감싸서 옮겨 주세요. 찬 바람에 꽃잎이 상할 수 있어요.',
  ),
  HomeTip(
    id: 'C01',
    group: '관리',
    when: TipWhen.allYear,
    title: '줄기는 사선으로',
    body: '줄기는 깨끗한 칼로 사선으로 잘라 주세요. 물에 닿는 면이 넓어져 물올림이 좋아져요.',
  ),
  HomeTip(
    id: 'C02',
    group: '관리',
    when: TipWhen.allYear,
    title: '물에 잠기는 잎 떼기',
    body: '물에 잠기는 잎은 떼어 주세요. 잎이 물속에서 상하면 물이 빨리 탁해져요.',
  ),
  HomeTip(
    id: 'C03',
    group: '관리',
    when: TipWhen.allYear,
    title: '버킷은 깨끗하게',
    body: '버킷과 화병을 자주 씻어 주세요. 세균이 줄어 꽃이 더 오래가요.',
  ),
  HomeTip(
    id: 'C04',
    group: '관리',
    when: TipWhen.allYear,
    title: '과일 옆은 피하기',
    body: '익어 가는 과일은 꽃을 빨리 시들게 하는 기체(에틸렌)를 내요. 꽃은 과일과 떨어진 곳에 두세요.',
  ),
  HomeTip(
    id: 'C05',
    group: '관리',
    when: TipWhen.allYear,
    title: '카네이션은 에틸렌 주의',
    body: '카네이션은 에틸렌에 특히 약한 편이에요. 시든 꽃이나 과일 가까이에 두지 마세요.',
  ),
  HomeTip(
    id: 'C06',
    group: '관리',
    when: TipWhen.allYear,
    title: '백합 꽃가루 떼기',
    body: '백합 꽃가루는 꽃잎과 옷에 얼룩을 남겨요. 꽃이 피면 꽃밥을 떼어 주세요.',
  ),
  HomeTip(
    id: 'C07',
    group: '관리',
    when: TipWhen.allYear,
    title: '거베라는 얕은 물',
    body: '거베라 줄기는 물에 오래 잠기면 무르기 쉬워요. 물을 얕게 채워 주세요.',
  ),
  HomeTip(
    id: 'C08',
    group: '관리',
    when: TipWhen.allYear,
    title: '튤립은 계속 자라요',
    body: '튤립은 꽂은 뒤에도 줄기가 자라고 빛 쪽으로 휘어요. 길이를 조금 여유 있게 잡아 주세요.',
  ),
  HomeTip(
    id: 'C09',
    group: '관리',
    when: TipWhen.allYear,
    title: '수국이 처지면',
    body: '수국은 물이 부족하면 금방 처져요. 줄기를 다시 자르고 물을 충분히 먹여 주세요.',
  ),
  HomeTip(
    id: 'C10',
    group: '관리',
    when: TipWhen.allYear,
    title: '장미가 고개를 숙이면',
    body: '장미가 고개를 숙이면 줄기를 물속에서 다시 잘라 물올림을 해 보세요.',
  ),
  HomeTip(
    id: 'C11',
    group: '관리',
    when: TipWhen.allYear,
    title: '먼저 들어온 꽃부터',
    body: '먼저 사입한 꽃부터 쓰면 버리는 꽃을 줄일 수 있어요.',
  ),
  HomeTip(
    id: 'C12',
    group: '관리',
    when: TipWhen.allYear,
    title: '시든 꽃은 바로 골라내기',
    body: '시든 꽃은 주변 꽃도 빨리 시들게 할 수 있어요. 보이면 바로 골라내 주세요.',
  ),
  HomeTip(
    id: 'C13',
    group: '관리',
    when: TipWhen.allYear,
    title: '냉장고 문은 짧게',
    body: '냉장고 문을 자주, 오래 열면 온도가 흔들려요. 꺼낼 꽃을 미리 정하고 열어 보세요.',
  ),
  HomeTip(
    id: 'C14',
    group: '관리',
    when: TipWhen.allYear,
    title: '남은 소재 활용',
    body: '남은 유칼립투스 같은 소재는 말려서 소품에 활용할 수 있어요.',
  ),
  HomeTip(
    id: 'O01',
    group: '운영',
    when: TipWhen.allYear,
    title: '영수증은 받은 날 바로',
    body: '영수증은 받은 날 바로 찍어 두세요. 월말에 몰아서 정리할 필요가 없어요.',
  ),
  HomeTip(
    id: 'O02',
    group: '운영',
    when: TipWhen.allYear,
    title: '손글씨 영수증 찍는 법',
    body: '손글씨 영수증은 밝은 곳에서 그림자 없이 찍으면 더 정확하게 인식돼요.',
  ),
  HomeTip(
    id: 'O03',
    group: '운영',
    when: TipWhen.allYear,
    title: '사입 전날 리스트',
    body: '사입 전날 예산 검토에 살 품목을 적어 보세요. 시장에서 계획에 없던 구매를 줄일 수 있어요.',
  ),
  HomeTip(
    id: 'O04',
    group: '운영',
    when: TipWhen.allYear,
    title: '거래처 단가 비교',
    body: '같은 꽃도 거래처마다 가격이 달라요. 월별 인사이트에서 한 번씩 비교해 보세요.',
  ),
  HomeTip(
    id: 'O05',
    group: '운영',
    when: TipWhen.allYear,
    title: '부자재 대량 구매 전',
    body: '롤·박스 단위 부자재는 남은 재고를 확인하고 사 주세요.',
  ),
  HomeTip(
    id: 'O06',
    group: '운영',
    when: TipWhen.allYear,
    title: '버린 꽃 기록하기',
    body: '버린 꽃을 간단히 기록해 두면 어떤 꽃을 줄여 사야 할지 보여요.',
  ),
  HomeTip(
    id: 'O07',
    group: '운영',
    when: TipWhen.allYear,
    title: '행사 전 주문 마감 공지',
    body: '행사 시즌에는 주문 마감일을 미리 공지해 보세요. 사입량을 맞추기 쉬워져요.',
  ),
  HomeTip(
    id: 'O08',
    group: '운영',
    when: TipWhen.allYear,
    title: '단골 기념일 기록',
    body: '단골손님의 기념일을 적어 두고 미리 연락해 보세요.',
  ),
  HomeTip(
    id: 'O09',
    group: '운영',
    when: TipWhen.allYear,
    title: '단가가 오르면 판매가 점검',
    body: '많이 쓰는 꽃 단가가 올랐다면 원가 계산기로 판매가를 다시 확인해 보세요.',
  ),
  HomeTip(
    id: 'O10',
    group: '운영',
    when: TipWhen.allYear,
    title: '증빙 챙기기',
    body: '계산서·세금계산서·현금영수증을 꼭 받아 두세요. 신고 때 필요한 증빙이에요.',
  ),
  HomeTip(
    id: 'O11',
    group: '운영',
    when: TipWhen.allYear,
    title: '메모장 스케치 활용',
    body: '부케 구성을 사입 메모장에 그려 가면 시장에서 필요한 꽃을 빠뜨리지 않아요.',
  ),
  HomeTip(
    id: 'O12',
    group: '운영',
    when: TipWhen.allYear,
    title: '작년 같은 달 확인',
    body: '시즌 전에 작년 같은 달 매입을 확인하면 사입량을 잡기 쉬워요.',
  ),
];
