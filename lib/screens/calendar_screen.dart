import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/receipt_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../models/receipt_model.dart';
import '../services/gallery_intake.dart';
import '../services/gemini_ocr_service.dart';
import '../services/receipt_parser.dart';
import 'receipt_detail_screen.dart';
import 'receipt_edit_screen.dart';
import 'in_app_camera_screen.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CalendarView();
  }
}

class _CalendarView extends StatefulWidget {
  const _CalendarView();

  @override
  State<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<_CalendarView> {
  // 위아래 스와이프 전환 없이 월간 고정
  final CalendarFormat _calendarFormat = CalendarFormat.month;

  // 연도 목록: 2023~2036, ScrollController로 2026년이 맨 앞에 보이게
  static const List<int> _years = [2023, 2024, 2025, 2026, 2027, 2028, 2029, 2030, 2031, 2032, 2033, 2034, 2035, 2036];
  final ScrollController _yearScrollCtrl = ScrollController();

  @override
  void dispose() {
    _yearScrollCtrl.dispose();
    super.dispose();
  }

  // 년/월 피커 (바텀시트)
  Future<void> _showYearMonthPicker(
      BuildContext context, DateTime focused, ReceiptProvider provider) async {
    final now = DateTime.now();
    int pickerYear = focused.year;

    // 2026년이 기본으로 보이도록 초기 스크롤 위치 계산
    // 각 항목 너비 약 80px + margin 8px = 88px
    // 2026 = index 3 → 3 * 88 = 264px
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_yearScrollCtrl.hasClients) {
        const itemWidth = 88.0;
        final targetIndex = _years.indexOf(2026).clamp(0, _years.length - 1);
        _yearScrollCtrl.jumpTo(targetIndex * itemWidth);
      }
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 핸들
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Row(
                      children: [
                        const Text(
                          '이동할 연도·월 선택',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        // 오늘로 바로 이동
                        GestureDetector(
                          onTap: () {
                            provider.setFocusedDay(now);
                            provider.setSelectedDay(now);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.today_outlined,
                                    size: 13, color: AppColors.primary),
                                SizedBox(width: 4),
                                Text(
                                  '오늘로',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 연도 레이블
                        const Text('연도',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textHint,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        // 연도 가로 스크롤 (2026이 맨 앞)
                        SizedBox(
                          height: 44,
                          child: ListView.builder(
                            controller: _yearScrollCtrl,
                            scrollDirection: Axis.horizontal,
                            itemCount: _years.length,
                            itemBuilder: (_, i) {
                              final y = _years[i];
                              final selected = y == pickerYear;
                              return GestureDetector(
                                onTap: () =>
                                    setModal(() => pickerYear = y),
                                child: Container(
                                  width: 80,
                                  margin: const EdgeInsets.only(right: 8),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(22),
                                    border: selected
                                        ? null
                                        : Border.all(
                                            color: AppColors.border),
                                  ),
                                  child: Text(
                                    '$y년',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 월 레이블 + 안내 문구
                        Row(
                          children: [
                            const Text('월',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textHint,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accent
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '탭하면 바로 이동',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 월 그리드 (탭 즉시 이동)
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 2.2,
                          ),
                          itemCount: 12,
                          itemBuilder: (_, i) {
                            final m = i + 1;
                            final isFocusedMonth = m == focused.month &&
                                pickerYear == focused.year;
                            return GestureDetector(
                              onTap: () {
                                provider.setFocusedDay(
                                    DateTime(pickerYear, m));
                                Navigator.pop(ctx);
                              },
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isFocusedMonth
                                      ? AppColors.primary
                                      : AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(10),
                                  border: isFocusedMonth
                                      ? null
                                      : Border.all(
                                          color: AppColors.border),
                                ),
                                child: Text(
                                  '$m월',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isFocusedMonth
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                      height: MediaQuery.of(ctx).padding.bottom + 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final receiptProvider = context.watch<ReceiptProvider>();
    final receiptsByDay = receiptProvider.receiptsByDay;
    final selectedDay = receiptProvider.selectedDay;
    final focusedDay = receiptProvider.focusedDay;
    final selectedReceipts = receiptProvider.getReceiptsForDay(selectedDay);
    final selectedTotal = receiptProvider.getTotalForDay(selectedDay);
    final fmt = NumberFormat('#,###', 'ko');
    final today = DateTime.now();
    final isCurrentMonth =
        focusedDay.year == today.year && focusedDay.month == today.month;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: _buildCalendarChildren(
            context,
            receiptProvider,
            receiptsByDay,
            selectedDay,
            focusedDay,
            selectedReceipts,
            selectedTotal,
            fmt,
            today,
            isCurrentMonth,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCalendarChildren(
    BuildContext context,
    ReceiptProvider receiptProvider,
    Map<DateTime, List<ReceiptModel>> receiptsByDay,
    DateTime selectedDay,
    DateTime focusedDay,
    List<ReceiptModel> selectedReceipts,
    double selectedTotal,
    NumberFormat fmt,
    DateTime today,
    bool isCurrentMonth,
  ) {
    return [
      // ── 헤더 ──
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
        child: Row(
          children: [
            const Text(
              '구매 캘린더',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            if (!isCurrentMonth)
              GestureDetector(
                onTap: () {
                  receiptProvider.setFocusedDay(today);
                  receiptProvider.setSelectedDay(today);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.today_outlined,
                          size: 14, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text(
                        '오늘',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),

      const SizedBox(height: 10),

      // ── 달력 (자연 크기 – 날짜 수에 따라 유동적) ──
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: TableCalendar<ReceiptModel>(
          firstDay: DateTime.utc(2023, 1, 1),
          lastDay: DateTime.utc(2036, 12, 31),
          focusedDay: focusedDay,
          calendarFormat: _calendarFormat,
          availableCalendarFormats: const {CalendarFormat.month: '월'},
          selectedDayPredicate: (day) => isSameDay(selectedDay, day),
          eventLoader: (day) {
            final key = DateTime(day.year, day.month, day.day);
            return receiptsByDay[key] ?? const [];
          },
          onDaySelected: (selected, focused) {
            receiptProvider.setSelectedDay(selected);
            receiptProvider.setFocusedDay(focused);
          },
          onFormatChanged: (_) {},
          onPageChanged: (focused) {
            final monthReceipts = receiptsByDay.entries
                .where((e) =>
                    e.key.year == focused.year &&
                    e.key.month == focused.month &&
                    e.value.isNotEmpty)
                .toList();
            if (monthReceipts.isNotEmpty) {
              monthReceipts.sort((a, b) => a.key.compareTo(b.key));
              receiptProvider.setFocusedDay(monthReceipts.first.key);
              receiptProvider.setSelectedDay(monthReceipts.first.key);
            } else {
              final firstOfMonth =
                  DateTime(focused.year, focused.month, 1);
              receiptProvider.setFocusedDay(firstOfMonth);
              receiptProvider.setSelectedDay(firstOfMonth);
            }
          },
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (ctx, day, _) => _buildDayCell(
                day, receiptsByDay, fmt,
                isSelected: false, isToday: false),
            todayBuilder: (ctx, day, _) => _buildDayCell(
                day, receiptsByDay, fmt,
                isSelected: isSameDay(selectedDay, day),
                isToday: true),
            selectedBuilder: (ctx, day, _) => _buildDayCell(
                day, receiptsByDay, fmt,
                isSelected: true,
                isToday: isSameDay(day, DateTime.now())),
            markerBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          calendarStyle: const CalendarStyle(
            outsideDaysVisible: false,
            markersMaxCount: 0,
            cellMargin: EdgeInsets.all(3),
            cellPadding: EdgeInsets.zero,
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            leftChevronIcon: const Icon(
              Icons.chevron_left_rounded,
              color: AppColors.textSecondary,
              size: 30,
            ),
            rightChevronIcon: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 30,
            ),
            headerMargin: EdgeInsets.zero,
            headerPadding: const EdgeInsets.symmetric(vertical: 10),
            titleTextFormatter: (date, locale) {
              final label = DateFormat('yyyy년 M월', 'ko').format(date);
              return '$label  ▾';
            },
          ),
          onHeaderTapped: (_) =>
              _showYearMonthPicker(context, focusedDay, receiptProvider),
          daysOfWeekStyle: const DaysOfWeekStyle(
            weekdayStyle: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            weekendStyle: TextStyle(
              fontSize: 13,
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),

      const SizedBox(height: 8),

      // ── 이번 달 총액 바 ──
      _buildMonthStatBar(receiptProvider, fmt, focusedDay),

      const SizedBox(height: 8),

      // ── 선택된 날 상세 (나머지 공간 차지) ──
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildDayDetail(
              context, selectedDay, selectedReceipts, selectedTotal, fmt),
        ),
      ),
    ];
  }
  // ── 날짜 셀 빌더 ──
  Widget _buildDayCell(
    DateTime day,
    Map<DateTime, List<ReceiptModel>> receiptsByDay,
    NumberFormat fmt, {
    required bool isSelected,
    required bool isToday,
  }) {
    final key = DateTime(day.year, day.month, day.day);
    final events = receiptsByDay[key] ?? [];
    final total = events.fold(0.0, (s, r) => s + r.totalAmount);
    final hasReceipts = events.isNotEmpty;

    Color dayColor;
    if (isSelected) {
      dayColor = Colors.white;
    } else if (isToday) {
      dayColor = AppColors.secondary;
    } else if (day.weekday == DateTime.saturday ||
        day.weekday == DateTime.sunday) {
      dayColor = AppColors.error;
    } else {
      dayColor = AppColors.textPrimary;
    }

    return SizedBox.expand(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: isSelected
                ? const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  )
                : isToday
                    ? BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      )
                    : null,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 15,
                fontWeight:
                    isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                color: dayColor,
              ),
            ),
          ),
          if (hasReceipts)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                fmt.format(total),
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? const Color(0xFF5A2D20)
                      : AppColors.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ── 달력 아래 월 총액 바 ──
  Widget _buildMonthStatBar(
      ReceiptProvider provider, NumberFormat fmt, DateTime focused) {
    // "2026년 2월 총지출" 형식
    final label = '${DateFormat("yyyy년 M월", "ko").format(focused)} 총지출';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bar_chart_rounded,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${provider.monthlyReceiptCount}건',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '₩${fmt.format(provider.monthlyTotal)}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayDetail(
    BuildContext context,
    DateTime selectedDay,
    List<ReceiptModel> receipts,
    double total,
    NumberFormat fmt,
  ) {
    final dateFmt = DateFormat("M월 d일 (E)", 'ko');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                // 날짜 + 영수증 수
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateFmt.format(selectedDay),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${receipts.length}개의 영수증',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // 구매 내역 추가 버튼 (항상 표시)
                if (receipts.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showAddReceiptSheet(context, selectedDay),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.25)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: AppColors.primary, size: 14),
                          SizedBox(width: 3),
                          Text(
                            '추가',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (receipts.isNotEmpty) ...
                  [
                    const SizedBox(width: 8),
                    Text(
                      '₩${fmt.format(total)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: receipts.isEmpty
                ? _buildEmptyDayState(context, selectedDay)
                : ListView.separated(
                    padding: EdgeInsets.only(
                      top: 12,
                      left: 12,
                      right: 12,
                      bottom: 12 + MediaQuery.of(context).padding.bottom,
                    ),
                    itemCount: receipts.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _DayReceiptCard(
                        receipt: receipts[index],
                        fmt: fmt,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDayState(BuildContext context, DateTime selectedDay) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            top: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 32,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                const Text('🧾', style: TextStyle(fontSize: 36)),
                const SizedBox(height: 10),
                const Text(
                  '이 날은 구매 내역이 없어요',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _showAddReceiptSheet(context, selectedDay),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline,
                            color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '구매 내역 추가',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 구매 내역 추가 팝업 ──
  Future<void> _showAddReceiptSheet(
      BuildContext context, DateTime selectedDay) async {
    final dateFmt = DateFormat("yyyy년 M월 d일 (E)", 'ko');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 날짜 안내
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${dateFmt.format(selectedDay)}의 구매 내역을 추가합니다',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 카메라 촬영
            _AddSheetTile(
              icon: Icons.photo_camera_outlined,
              iconColor: AppColors.primary,
              title: '카메라로 촬영',
              subtitle: '영수증을 직접 촬영하여 스캔합니다',
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            const SizedBox(height: 10),
            // 갤러리 선택
            _AddSheetTile(
              icon: Icons.photo_library_outlined,
              iconColor: AppColors.secondary,
              title: '갤러리에서 선택',
              subtitle: '저장된 사진을 불러와 스캔합니다',
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    if (result == 'camera') {
      await _addFromCamera(context, selectedDay);
    } else if (result == 'gallery') {
      await _addFromGallery(context, selectedDay);
    }
  }

  // ── 카메라 촬영으로 추가 ──
  Future<void> _addFromCamera(
      BuildContext context, DateTime fixedDate) async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('카메라 권한이 필요합니다.'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    final List<XFile>? images = await Navigator.push<List<XFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => const InAppCameraScreen(mode: 'single'),
      ),
    );
    if (!mounted || images == null || images.isEmpty) return;
    await _runCalendarOcr(context, images.first, fixedDate);
  }

  // ── 갤러리 선택으로 추가 ──
  Future<void> _addFromGallery(
      BuildContext context, DateTime fixedDate) async {
    await Permission.photos.request();
    await Permission.storage.request();

    // 🔴 웹에서는 `image_picker` 를 **거치지 않는다.**
    // 플러그인은 `blob:` URL 만 남기고 `File` 객체와 `<input>` 을 버린다.
    // 그 URL 은 브라우저가 임의의 시점에 정리해버릴 수 있어서 같은 사진이
    // 될 때도 있고 안 될 때도 있었다. `pickAndPrepare` 는 웹에서 `File` 을
    // 직접 붙잡고 읽어 blob URL 을 아예 만들지 않는다.
    final intake = await GalleryIntake.pickAndPrepare(multiple: false);
    if (!mounted || intake == null) return; // 취소
    if (intake.usable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('사진 파일을 읽을 수 없어요. 갤러리에서 사진을 한 번 열어 '
            '기기에 내려받은 뒤 다시 골라주세요.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    await _runCalendarOcr(context, intake.usable.first, fixedDate);
  }

  // ── OCR 처리 + 날짜 고정 후 편집 화면 ──
  Future<void> _runCalendarOcr(
      BuildContext context, XFile xFile, DateTime fixedDate) async {
    // 로딩 표시
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('영수증 분석 중...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final gemini = GeminiOcrService();
      final result = await gemini.recognizeReceipt(xFile: xFile);

      if (!mounted) return;
      Navigator.pop(context); // 로딩 닫기

      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.errorMessage ?? '영수증 인식에 실패했습니다.'),
          backgroundColor: AppColors.error,
        ));
        return;
      }

      // ParsedReceipt 변환
      final items = result.items.map((gi) {
        double unitPrice = gi.unitPrice;
        if (unitPrice <= 0 && gi.quantity > 0) {
          unitPrice = gi.totalPrice / gi.quantity;
        }
        return FlowerItem(
          name: gi.name,
          quantity: gi.quantity,
          unitPrice: unitPrice,
          unit: gi.unit,
        );
      }).toList();

      final parsed = ParsedReceipt(
        storeName: result.storeName,
        date: result.date, // fixedDate로 덮어씌워짐
        items: items,
        totalAmount: result.totalAmount,
        rawText: result.rawText,
        confidence: result.confidence,
      );

      if (!mounted) return;
      final authProvider = context.read<AuthProvider>();
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptEditScreen(
            parsed: parsed,
            imagePath: xFile.path,
            fixedDate: fixedDate, // ← 날짜 고정
          ),
        ),
      );
      if (saved == true && mounted) {
        await authProvider.incrementScanCount();
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // 로딩 닫기
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('처리 중 오류: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }
}

// ── 추가 팝업 타일 ──
class _AddSheetTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddSheetTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}
class _DayReceiptCard extends StatelessWidget {
  final ReceiptModel receipt;
  final NumberFormat fmt;

  const _DayReceiptCard({required this.receipt, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptDetailScreen(receipt: receipt),
          ),
        );
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('🌸', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                receipt.storeName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '₩${fmt.format(receipt.totalAmount)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
