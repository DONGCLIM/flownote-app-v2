import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_card.dart';
import '../../design/fn_badge_ds.dart';
import '../../design/fn_controls_ds.dart';
import '../../models/receipt_model.dart';
import '../../providers/receipt_provider.dart';
import '../receipt_detail_screen.dart';
import '../scan/scan_flow.dart';
import 'fn_data.dart';

/// 캘린더에서 영수증을 추가할 때의 입력 소스
enum _AddSource { camera, gallery }

/// 시안 `AppH7` → `screen === 'calendar'` 1:1 포팅.
///
/// 프로토타입 원본 (`8fa93f26-…js`) 순서:
/// ```js
/// body = div { padding:'10px 14px 16px', column, gap:14, position:relative }
///   monthTotalCard · header · weekdayRow · grid · heatLegend · Divider · dayDetail
/// ```
///
/// 히트맵:
/// ```js
/// const maxDay = Math.max(1, ...Object.keys(byDay).map(d => dayTotal(d)));
/// const HEAT = ['#FBE4E7', '#F5C2C8', '#EE8E9C', '#DE6A7C'];
/// const lvl = !has ? -1
///   : t/maxDay <= .33 ? 0 : t/maxDay <= .6 ? 1 : t/maxDay <= .85 ? 2 : 3;
/// const bg = has ? HEAT[lvl] : 'transparent';
/// const fg = has ? (lvl >= 2 ? '#fff' : '#8E3A4B') : 'var(--label-normal)';
/// boxShadow: isSel ? 'inset 0 0 0 2px #C9566A'
///          : isToday ? 'inset 0 0 0 1.5px rgba(201,86,106,.45)' : 'none'
/// ```
///
/// FnShell 안에 들어가므로 Scaffold 를 두지 않는다.
class CalendarDsScreen extends StatefulWidget {
  const CalendarDsScreen({super.key});

  @override
  State<CalendarDsScreen> createState() => _CalendarDsScreenState();
}

/// 하루치 매입 한 줄 (`{ vendor, amount, summary }`)
///
/// `receipt` 는 실데이터에서 온 행이면 원본 모델을 담는다.
/// 시안 데모 데이터는 `null` → 상세 화면으로 넘기지 않는다.
typedef _DayRow = ({
  String vendor,
  double amount,
  String summary,
  ReceiptModel? receipt,
});

/// 시안 히트맵 4단계 — 영수증 금액이 클수록 진해진다.
/// ```js
/// const HEAT = ['#FBE4E7', '#F5C2C8', '#EE8E9C', '#DE6A7C'];
/// ```
const List<Color> _kHeat = [
  Color(0xFFFBE4E7),
  Color(0xFFF5C2C8),
  Color(0xFFEE8E9C),
  Color(0xFFDE6A7C),
];

/// 연한 칸에 쓰는 글자색 `#8E3A4B`
const Color _kHeatFgLight = Color(0xFF8E3A4B);

/// 선택 테두리 `#C9566A`
const Color _kSelRing = Color(0xFFC9566A);

/// 오늘 테두리 `rgba(201,86,106,.45)`
const Color _kTodayRing = Color(0x73C9566A);

class _CalendarDsScreenState extends State<CalendarDsScreen> {
  late DateTime _today;
  late int _year;
  late int _month;
  int? _selDay;
  bool _showPicker = false;

  /// 피커에 보여줄 연도 목록.
  /// 구 캘린더는 2023~2036 을 스크롤로 제공했다. 그 범위를 유지한다.
  static const List<int> _pickerYears = [
    2023, 2024, 2025, 2026, 2027, 2028, 2029,
    2030, 2031, 2032, 2033, 2034, 2035, 2036,
  ];

  /// 시안 데모 데이터 (`byDay`) — 실데이터가 없을 때만 쓴다.
  static const Map<int, List<_DayRow>> _demoByDay = {
    3: [
      (
        vendor: '화람원예',
        amount: 88000,
        summary: '수국 · 유칼립투스',
        receipt: null
      )
    ],
    10: [
      (
        vendor: '대한꽃도매',
        amount: 210000,
        summary: '장미(화이트) · 소국',
        receipt: null
      )
    ],
    15: [
      (
        vendor: '미림화훼',
        amount: 45000,
        summary: '다알리아 · 메리골드',
        receipt: null
      )
    ],
    17: [
      (
        vendor: '그린플러스',
        amount: 98000,
        summary: '포장리본 · 물주머니',
        receipt: null
      )
    ],
    20: [
      (
        vendor: '대한꽃도매',
        amount: 132000,
        summary: '안스리움 · 아미초',
        receipt: null
      )
    ],
    22: [
      (
        vendor: '화람원예',
        amount: 184000,
        summary: '장미(핑크) · 카네이션',
        receipt: null
      )
    ],
    24: [
      (
        vendor: '대한꽃도매',
        amount: 256000,
        summary: '장미(레드) · 거베라 · 수국',
        receipt: null
      ),
      (
        vendor: '그린플러스',
        amount: 62000,
        summary: '포장리본 · 물주머니 · 포장지',
        receipt: null
      ),
    ],
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    // 구 캘린더는 provider 의 selectedDay/focusedDay 를 상태 원본으로 썼다.
    // 다른 화면에서 특정 날짜를 지정해 들어오는 경우를 위해 그 값을 이어받는다.
    final rp = context.read<ReceiptProvider>();
    final f = rp.focusedDay;
    _year = f.year;
    _month = f.month;
    final s = rp.selectedDay;
    _selDay = (s.year == _year && s.month == _month) ? s.day : null;
  }

  /// 현재 선택 상태를 provider 로 되돌려 다른 화면과 공유한다.
  void _syncProvider() {
    final rp = context.read<ReceiptProvider>();
    rp.setFocusedDay(DateTime(_year, _month, 1));
    if (_selDay != null) {
      rp.setSelectedDay(DateTime(_year, _month, _selDay!));
    }
  }

  /// 실데이터가 하나도 없으면 시안 숫자를 그대로 보여준다.
  Map<int, List<_DayRow>> _byDay(ReceiptProvider rp) {
    final all = rp.allReceipts;
    if (all.isEmpty) {
      // 데모 모드: 표시 중인 달에만 시안 데이터를 얹는다.
      return _month == _today.month && _year == _today.year
          ? _demoByDay
          : const {};
    }
    final map = <int, List<_DayRow>>{};
    for (final r in all) {
      if (r.date.year != _year || r.date.month != _month) continue;
      (map[r.date.day] ??= []).add((
        vendor: r.storeName,
        amount: r.totalAmount,
        summary: _summaryOf(r),
        receipt: r,
      ));
    }
    // 하루 안에서는 최신 저장분이 위로
    for (final l in map.values) {
      l.sort((a, b) {
        final ac = a.receipt?.createdAt;
        final bc = b.receipt?.createdAt;
        if (ac == null || bc == null) return 0;
        return bc.compareTo(ac);
      });
    }
    return map;
  }

  /// 시안의 `summary` — 품목명을 ` · ` 로 이어 최대 3개까지.
  /// ```js
  /// summary: '장미(레드) · 거베라 · 수국'
  /// ```
  String _summaryOf(ReceiptModel r) {
    final names = r.items
        .map((it) => it.name.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (names.isEmpty) return '영수증 1건';
    if (names.length <= 3) return names.join(' · ');
    return '${names.take(3).join(' · ')} 외 ${names.length - 3}건';
  }

  double _dayTotal(Map<int, List<_DayRow>> m, int d) =>
      (m[d] ?? const []).fold<double>(0, (s, r) => s + r.amount);

  double _monthTotal(Map<int, List<_DayRow>> m) => m.values.fold<double>(
      0, (s, l) => s + l.fold<double>(0, (s2, r) => s2 + r.amount));

  /// 표시 중인 달의 영수증 건수 (구 캘린더의 `monthlyReceiptCount`)
  int _monthCount(Map<int, List<_DayRow>> m) =>
      m.values.fold<int>(0, (s, l) => s + l.length);

  /// 그 달 안에서 가장 많이 쓴 하루의 금액. 히트맵 기준값.
  /// ```js
  /// const maxDay = Math.max.apply(null, [1].concat(... dayTotal(d)));
  /// ```
  double _maxDay(Map<int, List<_DayRow>> m) {
    var mx = 1.0;
    for (final d in m.keys) {
      final t = _dayTotal(m, d);
      if (t > mx) mx = t;
    }
    return mx;
  }

  /// 히트맵 단계. 영수증이 없으면 -1.
  /// ```js
  /// t/maxDay <= .33 ? 0 : <= .6 ? 1 : <= .85 ? 2 : 3
  /// ```
  int _heatLevel(double t, double maxDay) {
    if (t <= 0) return -1;
    final r = t / maxDay;
    if (r <= .33) return 0;
    if (r <= .6) return 1;
    if (r <= .85) return 2;
    return 3;
  }

  /// ```js
  /// function goMonth(delta) { ... setSelDay(null); }
  /// ```
  void _goMonth(int delta) {
    var m = _month + delta;
    var y = _year;
    if (m < 1) {
      m = 12;
      y -= 1;
    } else if (m > 12) {
      m = 1;
      y += 1;
    }
    setState(() {
      _month = m;
      _year = y;
      _selDay = null;
    });
    _syncProvider();
  }

  /// 오늘로 이동 (구 캘린더 '오늘' 버튼)
  void _goToday() {
    setState(() {
      _year = _today.year;
      _month = _today.month;
      _selDay = _today.day;
      _showPicker = false;
    });
    _syncProvider();
  }

  /// 특정 날짜에 영수증 추가 — 카메라 / 갤러리 선택 후 그 날짜로 **고정** 저장.
  ///
  /// 구 캘린더 `_showAddReceiptSheet` 의 동작을 현재 디자인 위에서 유지한다.
  Future<void> _addForDay(int day) async {
    final fixed = DateTime(_year, _month, day);
    final src = await _showAddSourceSheet(fixed);
    if (src == null || !mounted) return;

    if (src == _AddSource.camera) {
      await ScanFlow.start(context, forcedDate: fixed);
    } else {
      await ScanFlow.startFromGallery(context, forcedDate: fixed);
    }
    if (mounted) setState(() {});
  }

  /// 추가 방법 선택 시트 (카메라 / 갤러리) + 대상 날짜 안내
  Future<_AddSource?> _showAddSourceSheet(DateTime day) {
    final label = DateFormat('yyyy년 M월 d일 (E)', 'ko').format(day);
    return showFnDsBottomSheet<_AddSource>(
      context,
      title: '영수증 추가',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 어느 날짜에 들어가는지 분명히 알려준다 (구 캘린더 동작)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: FnColors.rose95,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: FnColors.rose50),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$label 의 매입 내역으로 저장돼요',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FnColors.rose30,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sourceCard(
            title: '카메라로 촬영',
            desc: '영수증을 직접 촬영해서 인식해요',
            icon: Icons.photo_camera_outlined,
            value: _AddSource.camera,
          ),
          const SizedBox(height: 10),
          _sourceCard(
            title: '갤러리에서 선택',
            desc: '저장된 사진을 불러와 인식해요',
            icon: Icons.photo_library_outlined,
            value: _AddSource.gallery,
          ),
        ],
      ),
    );
  }

  Widget _sourceCard({
    required String title,
    required String desc,
    required IconData icon,
    required _AddSource value,
  }) {
    return FnCard(
      bordered: true,
      onTap: () => Navigator.pop(context, value),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: FnColors.rose95,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 19, color: FnColors.rose50),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: FnColors.labelNormal,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    color: FnColors.labelAlternative,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rp = context.watch<ReceiptProvider>();
    final byDay = _byDay(rp);

    final first = DateTime(_year, _month, 1).weekday % 7; // 일=0
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final isThisMonth = _year == _today.year && _month == _today.month;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 시안 순서: 총 매입 카드가 맨 위
              _monthTotalCard(byDay),
              const SizedBox(height: 14),
              _header(isThisMonth),
              const SizedBox(height: 14),
              _weekdayRow(),
              const SizedBox(height: 14),
              _grid(byDay, first, daysInMonth, isThisMonth),
              const SizedBox(height: 4),
              _heatLegend(),
              const SizedBox(height: 14),
              const FnDsDivider(),
              const SizedBox(height: 14),
              _dayDetail(byDay),
            ],
          ),
        ),
        if (_showPicker) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showPicker = false),
              child: const SizedBox.shrink(),
            ),
          ),
          Positioned(
            top: 54,
            left: 14,
            right: 14,
            child: _pickerPopover(),
          ),
        ],
      ],
    );
  }

  /// ```js
  /// monthTotalCard = div { padding:'16px 18px', borderRadius:16,
  ///   background:'linear-gradient(135deg, #FCEEEB 0%, #FFFAF8 100%)' }
  ///   div { fontSize:12.5, label-alternative }  `${year}년 ${month}월 총 매입`
  ///   div { row, alignItems:baseline, gap:8, marginTop:4 }
  ///     span { fontSize:28, fontWeight:700, letterSpacing:'-1px' }  won(monthTotal)
  ///     span { fontSize:12.5, label-alternative }  `${건수}건`
  /// ```
  Widget _monthTotalCard(Map<int, List<_DayRow>> byDay) {
    final count = _monthCount(byDay);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // linear-gradient(135deg, #FCEEEB 0%, #FFFAF8 100%)
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCEEEB), Color(0xFFFFFAF8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$_year년 $_month월 총 매입',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12.5,
              color: FnColors.labelAlternative,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                FnDemo.won(_monthTotal(byDay)),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  color: FnColors.labelNormal,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count건',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12.5,
                  color: FnColors.labelAlternative,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ```js
  /// header = row spaceBetween
  ///   navBtn '‹'  (40x40 r20 fill-normal)
  ///   [ '2026년 7월' 20/700 + '▾' 15 alt ,  !isThisMonth && Chip small outlined '오늘' ]
  ///   navBtn '›'
  /// ```
  Widget _header(bool isThisMonth) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _navBtn(Icons.chevron_left_rounded, () => _goMonth(-1)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => setState(() => _showPicker = !_showPicker),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_year년 $_month월',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: FnColors.labelNormal,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more_rounded,
                      size: 15, color: FnColors.labelAlternative),
                ],
              ),
            ),
            if (!isThisMonth) ...[
              const SizedBox(width: 8),
              FnDsChip(
                label: '오늘',
                size: FnDsChipSize.small,
                outlined: true,
                onTap: _goToday,
              ),
            ],
          ],
        ),
        _navBtn(Icons.chevron_right_rounded, () => _goMonth(1)),
      ],
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: FnColors.fillNormal,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 17, color: FnColors.labelNormal),
      ),
    );
  }

  /// `grid 7열, gap 4, fontSize 12, label-assistive, center`
  Widget _weekdayRow() {
    return Row(
      children: [
        for (final d in const ['일', '월', '화', '수', '목', '금', '토'])
          Expanded(
            child: Text(
              d,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                color: FnColors.labelAssistive,
              ),
            ),
          ),
      ],
    );
  }

  /// ```js
  /// dayCell: aspectRatio 1, borderRadius 10, background HEAT[lvl],
  ///   boxShadow isSel ? 'inset 0 0 0 2px #C9566A'
  ///           : isToday ? 'inset 0 0 0 1.5px rgba(201,86,106,.45)' : 'none',
  ///   column center gap1
  ///     span { fontSize:13.5, fontWeight: has?700:400, color: fg }  d
  ///     has && span { fontSize:9.5, fontWeight:600,
  ///                   color: lvl>=2 ? 'rgba(255,255,255,.92)' : '#8E3A4B' }
  ///                 Math.round(t/10000) + '만원'
  /// ```
  ///
  /// 🔴 시안은 `aspectRatio: 1` 이다. 화면 폭에 따라 칸 높이가 정해진다.
  ///    `LayoutBuilder` 로 실제 폭을 재서 정사각형으로 만든다.
  Widget _grid(Map<int, List<_DayRow>> byDay, int first, int daysInMonth,
      bool isThisMonth) {
    final maxDay = _maxDay(byDay);

    return LayoutBuilder(
      builder: (context, box) {
        // gap 4 가 6군데 → 칸 하나의 변 길이
        final side = (box.maxWidth - 4 * 6) / 7;
        final rows = <Widget>[];
        final total = first + daysInMonth;
        final rowCount = (total / 7).ceil();

        for (var row = 0; row < rowCount; row++) {
          final cols = <Widget>[];
          for (var col = 0; col < 7; col++) {
            if (col > 0) cols.add(const SizedBox(width: 4));
            final idx = row * 7 + col;
            final d = idx - first + 1;
            cols.add(SizedBox(
              width: side,
              height: side,
              child: (d < 1 || d > daysInMonth)
                  ? null
                  : _dayCell(byDay, d, maxDay, isThisMonth),
            ));
          }
          rows.add(Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 4),
            child: Row(children: cols),
          ));
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  Widget _dayCell(Map<int, List<_DayRow>> byDay, int d, double maxDay,
      bool isThisMonth) {
    final t = _dayTotal(byDay, d);
    final has = t > 0;
    final lvl = _heatLevel(t, maxDay);
    final isToday = isThisMonth && d == _today.day;
    final isSel = _selDay == d;

    // 진한 칸(lvl>=2)은 흰 글자, 연한 칸은 #8E3A4B
    final fg = has
        ? (lvl >= 2 ? Colors.white : _kHeatFgLight)
        : FnColors.labelNormal;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _selDay = d);
        _syncProvider();
      },
      child: Container(
        decoration: BoxDecoration(
          color: has ? _kHeat[lvl] : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSel
              ? Border.all(color: _kSelRing, width: 2)
              : isToday
                  ? Border.all(color: _kTodayRing, width: 1.5)
                  : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$d',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13.5,
                height: 1.15,
                fontWeight: has ? FontWeight.w700 : FontWeight.w400,
                color: fg,
              ),
            ),
            if (has) ...[
              const SizedBox(height: 1),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${_manwon(t)}만원',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 9.5,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: lvl >= 2 ? const Color(0xEBFFFFFF) : _kHeatFgLight,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// `Math.round(t / 10000)` — JS 는 .5 를 올린다. Dart `round()` 도 동일.
  int _manwon(double t) => (t / 10000).round();

  /// ```js
  /// heatLegend = row gap6 end marginTop4
  ///   span 11 assistive '적음'
  ///   HEAT.map(c => span { width:12, height:12, borderRadius:3, background:c })
  ///   span 11 assistive '많음'
  /// ```
  Widget _heatLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text(
          '적음',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 11,
            color: FnColors.labelAssistive,
          ),
        ),
        for (final c in _kHeat) ...[
          const SizedBox(width: 6),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
        const SizedBox(width: 6),
        const Text(
          '많음',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 11,
            color: FnColors.labelAssistive,
          ),
        ),
      ],
    );
  }

  /// ```js
  /// dayDetail
  ///   row spaceBetween mb10
  ///     [ '7월 24일' 17/700 , addBtn ]
  ///     selDay && won(dayTotal) 17/500 #EE7686
  ///   !selDay  → '날짜를 탭하면 그날의 매입 내역이 나와요' 14 assistive
  ///   empty    → '이 날짜의 매입 내역이 없어요. 빠진 영수증을 바로 찍어 추가하세요.'
  ///   else     → Card bordered #FFF9F7 : [영수증 아이콘 34x34] vendor / summary / won
  /// ```
  Widget _dayDetail(Map<int, List<_DayRow>> byDay) {
    final selDay = _selDay;
    final list =
        selDay == null ? const <_DayRow>[] : (byDay[selDay] ?? const []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              selDay != null ? '$_month월 $selDay일' : '날짜를 선택하세요',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: FnColors.labelNormal,
              ),
            ),
            if (selDay != null) ...[
              const SizedBox(width: 8),
              _addBtn(selDay),
            ],
            const Spacer(),
            if (selDay != null)
              Text(
                FnDemo.won(_dayTotal(byDay, selDay)),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: FnColors.rose50,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (selDay == null)
          const Text(
            '날짜를 탭하면 그날의 매입 내역이 나와요',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              color: FnColors.labelAssistive,
            ),
          )
        else if (list.isEmpty)
          // 구 캘린더의 빈 상태: 안내문 + '매입 내역 추가' 버튼
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '이 날짜의 매입 내역이 없어요. 빠진 영수증을 바로 찍어 추가하세요.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    color: FnColors.labelAssistive,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              FnDsButton(
                label: '매입 내역 추가',
                size: FnDsButtonSize.medium,
                variant: FnDsButtonVariant.outlined,
                expand: true,
                onPressed: () => _addForDay(selDay),
              ),
            ],
          )
        else
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _receiptRow(list[i]),
          ],
      ],
    );
  }

  /// ```js
  /// addBtn = button { row gap4, height:28, padding:'0 10px', borderRadius:14,
  ///   border:'1px solid rgba(238,118,134,.35)', background:'#FFF9F7',
  ///   color:'#C9566A', fontSize:12, fontWeight:700 }
  ///   Icon camera 14 + '사진 추가'
  /// ```
  Widget _addBtn(int selDay) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _addForDay(selDay),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9F7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x59EE7686)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_camera_rounded,
                size: 14, color: _kSelRing),
            const SizedBox(width: 4),
            const Text(
              '사진 추가',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1,
                color: _kSelRing,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ```js
  /// Card { bordered, padding:13, background:'#FFF9F7',
  ///        boxShadow:'inset 0 0 0 1px rgba(238,118,134,.22)' }
  ///   row gap11
  ///     div 34x34 r10 #FDEEF0 : 영수증 svg 18
  ///     div flex1 : vendor 15.5/600 · summary 12.5 alt (ellipsis)
  ///     span 15.5/700 label-normal : won(amount)
  /// ```
  Widget _receiptRow(_DayRow r) {
    return FnCard(
      bordered: true,
      padding: const EdgeInsets.all(13),
      color: const Color(0xFFFFF9F7),
      borderColor: const Color(0x38EE7686),
      // 실데이터 행이면 상세/수정 화면으로 이동한다.
      onTap: r.receipt == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReceiptDetailScreen(receipt: r.receipt!),
                ),
              ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFDEEF0),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.receipt_long_outlined,
                size: 18, color: FnColors.rose50),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r.vendor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: FnColors.labelNormal,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  r.summary.isEmpty ? '영수증 1건' : r.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12.5,
                    color: FnColors.labelAlternative,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            FnDemo.won(r.amount),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: FnColors.labelNormal,
            ),
          ),
        ],
      ),
    );
  }

  /// ```js
  /// pickerPopover: absolute top54 left14 right14 z150
  ///   bg #fff r16 shadow '0 8px 28px rgba(0,0,0,.18)' pad16 column gap12
  ///     row gap8: [2024,2025,2026] Chip active
  ///     grid 4열 gap8: 1~12월 Chip active
  /// ```
  Widget _pickerPopover() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FnColors.backgroundNormal,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E000000),
              blurRadius: 28,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 구 캘린더의 '이동할 연도·월 선택' 헤더 + 오늘로 바로 이동
            Row(
              children: [
                const Text(
                  '이동할 연도·월',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: FnColors.labelNormal,
                  ),
                ),
                const Spacer(),
                FnDsChip(
                  label: '오늘',
                  size: FnDsChipSize.xsmall,
                  outlined: true,
                  onTap: _goToday,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 연도: 2023~2036 (구 캘린더와 동일 범위) — 가로 스크롤
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pickerYears.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final y = _pickerYears[i];
                  return FnDsChip(
                    label: '$y년',
                    active: _year == y,
                    onTap: () {
                      setState(() => _year = y);
                      _syncProvider();
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            for (var row = 0; row < 3; row++) ...[
              if (row > 0) const SizedBox(height: 8),
              Row(
                children: [
                  for (var col = 0; col < 4; col++) ...[
                    if (col > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Builder(builder: (_) {
                        final m = row * 4 + col + 1;
                        return FnDsChip(
                          label: '$m월',
                          active: _month == m,
                          onTap: () {
                            setState(() {
                              _month = m;
                              _selDay = null;
                              _showPicker = false;
                            });
                            _syncProvider();
                          },
                        );
                      }),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
