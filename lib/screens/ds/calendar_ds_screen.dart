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
/// ```js
/// body = div { padding:'10px 14px 16px', column, gap:14, position:relative }
///   header · weekdayRow · grid · monthTotalCard · Divider · dayDetail
/// ```
///
/// FnShell 안에 들어가므로 Scaffold 를 두지 않는다.
class CalendarDsScreen extends StatefulWidget {
  const CalendarDsScreen({super.key});

  @override
  State<CalendarDsScreen> createState() => _CalendarDsScreenState();
}

/// 하루치 매입 한 줄 (`{ vendor, amount }`)
///
/// `receipt` 는 실데이터에서 온 행이면 원본 모델을 담는다.
/// 시안 데모 데이터는 `null` → 상세 화면으로 넘기지 않는다.
typedef _DayRow = ({String vendor, double amount, ReceiptModel? receipt});

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
  /// ```js
  /// TODAY = { year:2026, month:7, day:24 }
  /// byDay = { 3:[{화람원예,88000}], 10:[{대한꽃도매,210000}], 15:[{미림화훼,45000}],
  ///           17:[{그린플러스,98000}], 20:[{대한꽃도매,132000}], 22:[{화람원예,184000}],
  ///           24:[{대한꽃도매,256000},{그린플러스,62000}] }
  /// ```
  static const Map<int, List<_DayRow>> _demoByDay = {
    3: [(vendor: '화람원예', amount: 88000, receipt: null)],
    10: [(vendor: '대한꽃도매', amount: 210000, receipt: null)],
    15: [(vendor: '미림화훼', amount: 45000, receipt: null)],
    17: [(vendor: '그린플러스', amount: 98000, receipt: null)],
    20: [(vendor: '대한꽃도매', amount: 132000, receipt: null)],
    22: [(vendor: '화람원예', amount: 184000, receipt: null)],
    24: [
      (vendor: '대한꽃도매', amount: 256000, receipt: null),
      (vendor: '그린플러스', amount: 62000, receipt: null),
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
      (map[r.date.day] ??= []).add(
        (vendor: r.storeName, amount: r.totalAmount, receipt: r),
      );
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

  double _dayTotal(Map<int, List<_DayRow>> m, int d) =>
      (m[d] ?? const []).fold<double>(0, (s, r) => s + r.amount);

  double _monthTotal(Map<int, List<_DayRow>> m) => m.values.fold<double>(
      0, (s, l) => s + l.fold<double>(0, (s2, r) => s2 + r.amount));

  /// 표시 중인 달의 영수증 건수 (구 캘린더의 `monthlyReceiptCount`)
  int _monthCount(Map<int, List<_DayRow>> m) =>
      m.values.fold<int>(0, (s, l) => s + l.length);

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
              _header(isThisMonth),
              const SizedBox(height: 14),
              _weekdayRow(),
              const SizedBox(height: 14),
              _grid(byDay, first, daysInMonth, isThisMonth),
              const SizedBox(height: 14),
              _monthTotalCard(byDay),
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
  /// header = row spaceBetween
  ///   navBtn '‹'  (40x40 r20 fill-normal, fontSize 20)
  ///   [ '2026년 7월' 20/700 + '▾' 13 alt ,  !isThisMonth && Chip small outlined '오늘' ]
  ///   navBtn '›'
  /// ```
  Widget _header(bool isThisMonth) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _navBtn('‹', () => _goMonth(-1)),
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
                  const Text(
                    '▾',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      color: FnColors.labelAlternative,
                    ),
                  ),
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
        _navBtn('›', () => _goMonth(1)),
      ],
    );
  }

  Widget _navBtn(String label, VoidCallback onTap) {
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
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 20,
            height: 1,
            color: FnColors.labelNormal,
          ),
        ),
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
  /// dayCell: minHeight 58, r10,
  ///   bg  isSel ? blue-50 : has ? blue-95 : transparent
  ///   shadow isToday && !isSel ? 'inset 0 0 0 1.5px blue-50' : none
  ///   column center gap2 padding '5px 0'
  ///     span 15  weight (has||isSel)?700:400
  ///          color isSel?#fff : has?blue-50 : label-normal
  ///     has && span 12/600 letterSpacing -0.2
  ///          color isSel? rgba(255,255,255,.95) : label-normal
  /// ```
  Widget _grid(Map<int, List<_DayRow>> byDay, int first, int daysInMonth,
      bool isThisMonth) {
    final cells = <Widget>[];
    for (var i = 0; i < first; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final t = _dayTotal(byDay, d);
      final has = t > 0;
      final isToday = isThisMonth && d == _today.day;
      final isSel = _selDay == d;

      cells.add(GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _selDay = d);
          _syncProvider();
        },
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: isSel
                ? FnColors.rose50
                : has
                    ? FnColors.rose95
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isToday && !isSel
                ? Border.all(color: FnColors.rose50, width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$d',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight:
                      (has || isSel) ? FontWeight.w700 : FontWeight.w400,
                  color: isSel
                      ? Colors.white
                      : has
                          ? FnColors.rose50
                          : FnColors.labelNormal,
                ),
              ),
              if (has) ...[
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    FnDemo.won(t),
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: isSel
                          ? const Color(0xF2FFFFFF)
                          : FnColors.labelNormal,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ));
    }

    // gridTemplateColumns: repeat(7,1fr), gap 4
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      final chunk = cells.sublist(i, (i + 7).clamp(0, cells.length));
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
        child: SizedBox(
          height: 58,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < 7; j++) ...[
                if (j > 0) const SizedBox(width: 4),
                Expanded(
                  child: j < chunk.length ? chunk[j] : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  /// `Card { background: blue-99, borderRadius: 22, row spaceBetween }`
  ///
  /// 구 캘린더의 월 총액 바에는 **건수(N건)** 도 함께 있었다. 그 정보를 유지한다.
  Widget _monthTotalCard(Map<int, List<_DayRow>> byDay) {
    final count = _monthCount(byDay);
    return FnCard(
      color: FnColors.rose99,
      radius: 22,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$_month월 총 매입',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelNormal,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$count건',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    color: FnColors.labelAssistive,
                  ),
                ),
              ],
            ],
          ),
          Text(
            FnDemo.won(_monthTotal(byDay)),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 19,
              fontWeight: FontWeight.w500,
              color: FnColors.rose50,
            ),
          ),
        ],
      ),
    );
  }

  /// ```js
  /// dayDetail
  ///   row spaceBetween mb10
  ///     [ '7월 24일' 17/700 , addBtn 28x28 r14 fill-normal + Camera 15 ]
  ///     selDay && won(dayTotal) 17/500 blue-50
  ///   !selDay  → '날짜를 탭하면 그날의 매입 내역이 나와요' 14 assistive
  ///   empty    → '이 날짜의 매입 내역이 없어요. 빠진 영수증을 바로 찍어 추가하세요.' 14 assistive pad'8px 0'
  ///   else     → ListCell divider title=vendor 16/600  desc='영수증 1건' 13  trailing=won 600
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
              selDay != null
                  ? DateFormat('M월 d일 (E)', 'ko')
                      .format(DateTime(_year, _month, selDay))
                  : '날짜를 선택하세요',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: FnColors.labelNormal,
              ),
            ),
            if (selDay != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _addForDay(selDay),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: FnColors.fillNormal,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.photo_camera_outlined,
                      size: 15, color: FnColors.labelAlternative),
                ),
              ),
              // 구 캘린더의 '개의 영수증' 표기를 유지한다.
              if (list.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '영수증 ${list.length}건',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    color: FnColors.labelAssistive,
                  ),
                ),
              ],
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
          for (final r in list)
            FnDsListCell(
              title: r.vendor,
              titleWeight: FontWeight.w600,
              // 구 캘린더는 품목 요약을 보여줬다. 그 정보를 유지한다.
              description: _itemSummary(r),
              // 실데이터 행이면 상세/수정 화면으로 이동한다.
              onTap: r.receipt == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ReceiptDetailScreen(receipt: r.receipt!),
                        ),
                      ),
              divider: true,
              trailing: Text(
                FnDemo.won(r.amount),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelNormal,
                ),
              ),
            ),
      ],
    );
  }

  /// `장미(레드) 외 3건` 형태의 품목 요약. 품목이 없으면 '영수증 1건'.
  String _itemSummary(_DayRow r) {
    final items = r.receipt?.items ?? const [];
    if (items.isEmpty) return '영수증 1건';
    final first = items.first.name.trim();
    final head = first.isEmpty ? '품목 미확인' : first;
    return items.length == 1 ? head : '$head 외 ${items.length - 1}건';
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
