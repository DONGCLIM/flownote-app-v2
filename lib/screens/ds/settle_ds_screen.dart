import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 🔴 공욨 `FnSegmented`(fn_input.dart)는 스캔 검수 화면
//    (`scan_review_screen.dart`)에서도 사용한다. 프로토타입 `segmented()`
//    치수(패딩 3 / radius 12 / 버튼 h36 r10 font14)로 고치면 스캔
//    화면까지 같이 변한다. 이번 요잭은 "구매내역 날짜별/업처별
//    거기만" 이므로 공욨 위젯을 건드리지 않고
//    `SettleSegmented`(settle_views_ds.dart)를 따로 둔다.
import '../../design/fn_tokens.dart';
import '../../design/fn_controls_ds.dart';
import '../../providers/receipt_provider.dart';
import '../../services/vendor_tax_service.dart';
import 'fn_data.dart';
import 'settle_data_live.dart';
import 'settle_history_ds_screen.dart';
import 'settle_preview_ds_screen.dart';
import 'settle_views_ds.dart';

/// 시안 `AppH2Mvp` → `screen === 'main'` (구매 내역 / settle 탭) 1:1 포팅.
///
/// ```js
/// Shell({ navTitle:'구매 내역', tabs, activeTab:'settle' },
///   div { padding:16, column, gap:14 }
///     ① 안내 박스  gap10 items-start pad14 r12 bg blue-99
///          Icon CircleInfo 20 blue-50 (flexShrink0 mt2)
///          div
///            16/600 label-normal  '매달 반복되는 거래처 정산, 클릭 한 번으로!'
///            13.5 label-alt mt5 lh1.5 '기간별 정산서를 엑셀 또는 PDF 파일로<br>한 번에 내보낼 수 있어요.'
///     ② SearchBar placeholder '거래처명 검색'
///     ③ div flex gap8 wrap  → 연/월 Chip, 정렬 Chip, Pro 3종
///     ④ filtered.length === 0 → '일치하는 거래처가 없어요' center label-assistive pad'24px 0'
///     ⑤ vendorRows
/// ```
///
/// **데이터는 데모가 아니라 실제 `ReceiptProvider.allReceipts` 를 쓴다.**
/// 시안의 하드코딩 `vendors` 배열은 [SettleLiveData] 가 영수증에서 만들어
/// 동일한 `FnVendor` 형태로 공급한다. 레거시 정산 화면의 기능
/// (거래처 과세 구분 · 내보내기 횟수 제한 · 발송 이력)도 함께 유지한다.
///
/// FnShell 안에 들어가므로 Scaffold 를 두지 않는다.
class SettleDsScreen extends StatefulWidget {
  const SettleDsScreen({super.key});

  @override
  State<SettleDsScreen> createState() => _SettleDsScreenState();
}

class _SettleDsScreenState extends State<SettleDsScreen> {
  final _queryCtl = TextEditingController();

  /// null 이면 "데이터에 존재하는 가장 최근 연도"를 자동 사용
  String? _filterYear;
  String _filterMonth = '전체';
  String _sortBy = 'name';
  String? _expanded;

  /// 시안 `taxFilter` — '전체' | '과세' | '면세'
  String _taxFilter = '전체';

  /// 전송 상태 — '전체' | '전송' | '미전송'
  ///
  /// "전송" 의 근거는 `SettleHistoryStore` 에 남은 정산서 내보내기 이력이다.
  /// 🔴 카카오톡으로 실제 보냈는지 앱이 알 방법은 없다. 우리가 아는 건
  ///    "문서를 만들어 내보냈다" 까지다. 그래서 문구도 `전송`(시안 배지와 동일)
  ///    으로만 쓰고, 읽음/수신 같은 표현은 쓰지 않는다.
  String _sendFilter = '전체';

  /// 종합소득세용(5월) 보기 — 프로토타입 원본 `smallOnly`.
  ///
  /// ```js
  /// (!smallOnly || (META[t.vendor].small || []).length > 0)
  /// ```
  ///
  /// 🔴 #98 까지 나는 이 칩을 "직전 연도 전체로 기간을 바꾼다"로 만들었다.
  ///    원본은 기간을 건드리지 않는다. **3만원 이하 결제가 있는 거래처만**
  ///    남기고, 펼치면 그 결제들을 따로 모아 보여준다. 5월 신고에서 실제로
  ///    필요한 건 적격증빙 없이 넘어가는 소액 건 목록이기 때문이다.
  bool _taxSeason = false;

  bool _showYearPicker = false;
  bool _showSortPicker = false;
  bool _showTaxPicker = false;
  bool _showSendPicker = false;

  /// 보기 방식 — `'date'`(날짜별) | `'vendor'`(업체별)
  ///
  /// 🔴 기본값을 **날짜별**로 둔다. 스캔 직후 "방금 넣은 게 잘 들어갔나"
  ///    확인하는 게 가장 흔한 행동이고, 그건 날짜순으로 봐야 보인다.
  String _view = 'date';

  /// 거래처별 최근 내보내기 날짜 (`MM.dd`). 발송 이력에서 실제로 채운다.
  Map<String, String> _exported = const {};

  @override
  void initState() {
    super.initState();
    _loadExported();
  }

  /// 레거시와 동일한 이력 저장소에서 거래처별 최근 내보내기 날짜를 읽는다.
  Future<void> _loadExported() async {
    final list = await SettleHistoryStore.load();
    final map = <String, String>{};
    for (final e in list) {
      for (final v in e.vendors) {
        map.putIfAbsent(v, () => e.savedLabel);
      }
    }
    if (!mounted) return;
    setState(() => _exported = map);
  }

  /// `sortLabel = { name:'가나다순', amountDesc:'금액 높은순',
  ///                amountAsc:'금액 낮은순', recent:'최신순' }`
  static const _sortLabel = <String, String>{
    'name': '가나다순',
    'amountDesc': '금액 높은순',
    'amountAsc': '금액 낮은순',
    'recent': '최신순',
  };

  @override
  void dispose() {
    _queryCtl.dispose();
    super.dispose();
  }

  void _closePickers() {
    if (_showYearPicker || _showSortPicker || _showTaxPicker || _showSendPicker) {
      setState(() {
        _showYearPicker = false;
        _showSortPicker = false;
        _showTaxPicker = false;
        _showSendPicker = false;
      });
    }
  }

  /// 드롭다운은 한 번에 하나만 열린다. 두 개가 겹쳐 뜨면 스크롤 뷰 안에서
  /// 어느 칩에 딸린 목록인지 알 수 없게 된다.
  void _openOnly(String which) {
    setState(() {
      _showYearPicker = which == 'year' ? !_showYearPicker : false;
      _showSortPicker = which == 'sort' ? !_showSortPicker : false;
      _showTaxPicker = which == 'tax' ? !_showTaxPicker : false;
      _showSendPicker = which == 'send' ? !_showSendPicker : false;
    });
  }

  /// ```js
  /// function quickExport(v) {
  ///   const vMonths = visibleMonths.filter(m => v.months[m] > 0);
  ///   setSelected({...., [v.id]: vMonths});
  ///   setPreviewVendorId(v.id); setScreen('preview');
  /// }
  /// ```
  void _quickExport(SettleLiveData data, FnVendor v, List<String> vm) {
    final vMonths = vm.where((m) => (v.months[m] ?? 0) > 0).toList();
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => SettlePreviewDsScreen(
              vendor: v,
              selectedMonths: vMonths,
              year: data.years.isEmpty ? null : (_filterYear ?? data.years.first),
              receipts: data.receiptsOf(v.name, vMonths),
            ),
          ),
        )
        // 내보내기를 마치고 돌아오면 '최근 내보내기' 표시를 갱신한다.
        .then((_) => _loadExported());
  }

  @override
  Widget build(BuildContext context) {
    final receipts = context.watch<ReceiptProvider>().allReceipts;
    final data = SettleLiveData.build(receipts, year: _filterYear);
    final years = data.years;
    final year = _filterYear ?? (years.isNotEmpty ? years.first : '-');
    final vm = data.visibleMonths(_filterMonth);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _closePickers,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 총 매입 헤더 ─────────────────────────────────
            //
            // 시안: `2026년 7월 총 매입` / `₩1,184,000` `9건`
            SettleTotalHeader(
              label: _headerLabel(year),
              total: data.periodTotal(_filterMonth),
              count: data.periodCount(_filterMonth),
            ),
            const SizedBox(height: 14),

            // ── 날짜별 / 업체별 토글 ─────────────────────────
            SettleSegmented(
              value: _view,
              items: const ['date', 'vendor'],
              labelOf: (v) => v == 'date' ? '날짜별' : '업체별',
              onChanged: (v) => setState(() {
                _view = v;
                _expanded = null;
                _closePickers();
              }),
            ),
            const SizedBox(height: 14),

            FnSearchBar(
              controller: _queryCtl,
              placeholder: '거래처명 검색',
              onChanged: (_) => setState(() {}),
              onClear: () => setState(() => _queryCtl.clear()),
            ),
            const SizedBox(height: 14),
            _filterChips(year, years),
            const SizedBox(height: 14),

            if (receipts.isEmpty)
              _emptyState(
                '아직 매입 내역이 없어요',
                '영수증을 스캔하면 여기에 쌓이고,\n거래처별 정산서도 만들 수 있어요',
              )
            else if (_view == 'date')
              _dateView(data)
            else
              _vendorView(data, vm),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 헤더 문구 — 시안 `2026년 7월 총 매입`.
  ///
  /// 🔴 문구와 바로 아래 금액은 반드시 **같은 기간**을 가리킨다.
  ///    금액은 `periodTotal(_filterMonth)` 이고, 그 값이 그대로
  ///    업체별 점유율의 분모다. 세 숫자(문구 / 헤더 금액 /
  ///    개별 퍼센트)가 항상 서로 맞는다.
  String _headerLabel(String year) => _filterMonth == '전체'
      ? '$year년 총 매입'
      : '$year년 $_filterMonth 총 매입';

  // ── 날짜별 보기 ─────────────────────────────────────────────
  Widget _dateView(SettleLiveData data) {
    final groups = data.dayGroups(
      query: _queryCtl.text,
      tax: _taxFilterType,
      vendorWhere: _vendorWhere(data),
      monthFilter: _filterMonth,
    );
    if (groups.isEmpty) {
      return const SettleListEmpty(message: '조건에 맞는 내역이 없어요');
    }
    return SettleDayTimeline(groups: groups);
  }

  // ── 업체별 보기 ─────────────────────────────────────────────
  Widget _vendorView(SettleLiveData data, List<String> vm) {
    final shares = data.vendorShares(
      query: _queryCtl.text,
      tax: _taxFilterType,
      sortBy: _sortBy,
      vendorWhere: _vendorWhere(data),
      monthFilter: _filterMonth,
    );

    if (shares.isEmpty) {
      return const SettleListEmpty(message: '조건에 맞는 거래처가 없어요');
    }

    // 🔴 시안에는 목록 아래 집계 줄이 없다. 만들지 않는다.
    //    목록이 조회 기간에서 몇 %인가는 개별 카드의 퍼센트를 더하면
    //    나오므로, 시안에 없는 줄을 둘 이유가 없다.
    return SettleVendorShareList(
      shares: shares,
      smallOnly: _taxSeason,
      expandedName: _expanded,
      exportedAt: _exported,
      onToggle: (name) =>
          setState(() => _expanded = _expanded == name ? null : name),
      onExport: (s) => _exportShare(data, s, vm),
    );
  }

  /// 칩으로 고른 과세 구분을 `TaxType` 으로. `'전체'` 면 `null`.
  TaxType? get _taxFilterType => switch (_taxFilter) {
        '과세' => TaxType.taxable,
        '면세' => TaxType.exempt,
        _ => null,
      };

  /// 업체별 카드의 `이 업체 정산서 만들기`.
  ///
  /// 기존 `_quickExport` 는 시안의 `FnVendor` 를 받으므로, 점유율 카드에서
  /// 온 거래처를 같은 형태로 바꿔 넘긴다. 정산서 생성 경로는 하나만 둔다 —
  /// 두 갈래로 나누면 한쪽만 고쳐지는 일이 생긴다.
  void _exportShare(
      SettleLiveData data, SettleVendorShare s, List<String> vm) {
    final v = data.vendors.firstWhere(
      (e) => e.name == s.name,
      orElse: () => FnVendor(
        id: s.name,
        name: s.name,
        lastDate: s.lastDateLabel,
        months: {for (final m in FnSettleData.months) m: 0},
      ),
    );
    _quickExport(data, v, vm.isEmpty ? FnSettleData.months : vm);
  }

  /// 실제 데이터가 없을 때 — 레거시 `FnEmptyState` 의 문구를 시안 스타일로.
  Widget _emptyState(String message, String? sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: FnColors.labelAssistive,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13.5,
                height: 1.5,
                color: FnColors.labelAssistive,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── ③ 필터 칩 행 ──────────────────────────────
  //
  // 🔴 시안에 있는 칩은 **정확히 5개**다. 그 이상도 이하도 만들지 않는다.
  //      1행: `2026년 전체 ▾`  `가나다순 ▾`  `과세 구분 ▾`
  //      2행: `전송 상태 ▾`    `종합소득세용(5월)`
  //
  //    이전 구현은 여기에 `소액 거래처`·`내보내기 이력`·
  //    `Pro 스마트 분류`·`절세 증빙 모음` 4개를 더 달아뒀다.
  //    Pro 는 전 기능 해제 결정이 난 뒤에도 자물쇠 칩이 남아 있었다 —
  //    제 잘못입니다. 4개 모두 지우고, 기능은 버리지 않고 시안이 가진
  //    칩 안으로 옮겼다:
  //      · `내보내기 이력` → `전송 상태 ▾` 드롭다운 맨 아래 항목.
  //        이 드롭다운의 판단 근거가 곧 내보내기 이력이므로 같은 자리가 맞다.
  //      · `소액 거래처`  → `금액 낮은순` 정렬로 대신한다. 칩을 늘리지 않는다.
  Widget _filterChips(String year, List<String> years) {
    final yearChipLabel =
        _filterMonth == '전체' ? '$year년 전체 ▾' : '$year년 $_filterMonth ▾';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🔴 칩 치수·간격은 **프로토타입 원본 소스**에서 그대로 가져온 값이다.
        //    (b0b603b5 = `AppH10`, `filterBar()`)
        //
        //      React.createElement('div',
        //        { style: { display:'flex', gap:7, flexWrap:'wrap' } }, ...)
        //      dropChip → React.createElement(Chip,
        //        { variant:'outlined', style:{ fontWeight:400 } }, label + ' ▾')
        //
        //    `Chip` 의 기본 size 는 `medium` = 높이 36 / radius 10 /
        //    좌우 패딩 11 / 글자 14 다. `large` 가 아니다.
        //
        // 🔴 여기서 내가 틀렸던 것:
        //    #98 에서 시안 **이미지**의 칩 테두리를 픽셀로 재서
        //    폭 101/74/78 · 간격 24 · 높이 49 를 얻고, 이를 `large` 로
        //    역산해 `size: large` + `spacing: 24` 를 넣었다.
        //    그런데 그 이미지는 402px 기기 목업을 확대 캡처한 것이어서
        //    배율(약 1.36배)이 섞여 있었다. 실제 값은 h36 · gap7 이다.
        //    → 이미지 실측보다 원본 소스가 항상 우선이다.
        //
        //    간격이 7 이면 402px 폭에서 칩이 자연스럽게 두 줄로 접힌다.
        //    줄 수를 코드로 강제하지 않는다. 기기 폭이 넓어지면 한 줄로
        //    펴지는 게 원본 동작이고, 그게 곧 반응형이다.
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            FnDsChip(
              label: yearChipLabel,
              outlined: true,
              active: _filterMonth != '전체',
              fontWeight: FontWeight.w400,
              onTap: () => _openOnly('year'),
            ),
            FnDsChip(
              label: '${_sortLabel[_sortBy]} ▾',
              outlined: true,
              active: _sortBy != 'name',
              fontWeight: FontWeight.w400,
              onTap: () => _openOnly('sort'),
            ),
            FnDsChip(
              label: _taxFilter == '전체' ? '과세 구분 ▾' : '$_taxFilter ▾',
              outlined: true,
              active: _taxFilter != '전체',
              fontWeight: FontWeight.w400,
              onTap: () => _openOnly('tax'),
            ),
            FnDsChip(
              label: _sendFilter == '전체' ? '전송 상태 ▾' : '$_sendFilter ▾',
              outlined: true,
              active: _sendFilter != '전체',
              fontWeight: FontWeight.w400,
              onTap: () => _openOnly('send'),
            ),
            // 종합소득세용(5월) — 켜면 직전 연도 전체로 맞춘다.
            FnDsChip(
              label: '종합소득세용(5월)',
              outlined: true,
              active: _taxSeason,
              fontWeight: FontWeight.w400,
              onTap: _toggleTaxSeason,
            ),
          ],
        ),
        // 시안은 position:absolute top:110% 이지만, 스크롤 뷰 안에서는
        // 칩 바로 아래 인라인으로 펼쳐 같은 동작·같은 모양을 낸다.
        if (_showYearPicker) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FnDropdown(
              minWidth: 150,
              maxHeight: 260,
              items: _yearMenuItems(year, years),
            ),
          ),
        ],
        if (_showSortPicker) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FnDropdown(
              minWidth: 130,
              items: [
                for (final e in _sortLabel.entries)
                  if (e.key != 'amountAsc')
                    FnDropdownItem(
                      label: e.value,
                      active: _sortBy == e.key,
                      onTap: () => setState(() {
                        _sortBy = e.key;
                        _showSortPicker = false;
                      }),
                    ),
              ],
            ),
          ),
        ],
        if (_showTaxPicker) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FnDropdown(
              minWidth: 110,
              items: [
                for (final t in const ['전체', '과세', '면세'])
                  FnDropdownItem(
                    label: t == '전체' ? '과세 구분 전체' : t,
                    active: _taxFilter == t,
                    onTap: () => setState(() {
                      _taxFilter = t;
                      _showTaxPicker = false;
                    }),
                  ),
              ],
            ),
          ),
        ],
        if (_showSendPicker) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FnDropdown(
              minWidth: 130,
              items: [
                for (final s in const ['전체', '전송 완료', '미전송'])
                  FnDropdownItem(
                    label: switch (s) {
                      '전송 완료' => '전송 완료',
                      '미전송' => '아직 안 보낸 거래처',
                      _ => '전송 상태 전체',
                    },
                    active: _sendFilter == s,
                    onTap: () => setState(() {
                      _sendFilter = s;
                      _showSendPicker = false;
                    }),
                  ),
                // 시안에서 `내보내기 이력` 칩이 사라졌으므로 이 기능을
                // 여기로 옮겼다. 이 드롭다운의 `전송`/`미전송` 판단
                // 근거가 곧 내보내기 이력이다.
                FnDropdownItem(
                  label: '내보내기 이력 보기',
                  active: false,
                  divider: true,
                  onTap: () {
                    setState(() => _showSendPicker = false);
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (_) => const SettleHistoryDsScreen()))
                        .then((_) => _loadExported());
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 종합소득세용(5월) 토글 — 기간은 건드리지 않는다(원본 `smallOnly`).
  void _toggleTaxSeason() {
    setState(() {
      _taxSeason = !_taxSeason;
      _closePickersNoSet();
      _expanded = null;
    });
  }

  void _closePickersNoSet() {
    _showYearPicker = false;
    _showSortPicker = false;
    _showTaxPicker = false;
    _showSendPicker = false;
  }

  /// 전송 상태 필터를 거래처명 조건 함수로 바꾼다. `'전체'` 면 `null`.
  bool Function(String)? get _sendFilterWhere => switch (_sendFilter) {
        '전송 완료' => (v) => _exported[v] != null,
        '미전송' => (v) => _exported[v] == null,
        _ => null,
      };

  /// 3만원 이하 결제가 있는 거래처만 남기는 조건 — 원본 `smallOnly`.
  ///
  /// 전송 상태 조건과 **함께** 걸릴 수 있으므로 둘을 합성해서 넘긴다.
  bool Function(String)? _vendorWhere(SettleLiveData data) {
    final send = _sendFilterWhere;
    if (!_taxSeason) return send;
    final small = <String>{
      for (final r in data.receipts)
        if (r.totalAmount > 0 && r.totalAmount <= kSmallPayLimit)
          r.storeName.trim(),
    };
    if (send == null) return (v) => small.contains(v.trim());
    return (v) => send(v) && small.contains(v.trim());
  }

  List<FnDropdownItem> _yearMenuItems(String year, List<String> years) {
    // 실제 데이터에 연도가 없으면 적어도 올해는 골를 수 있게 한다.
    final list = years.isEmpty ? [DateTime.now().year.toString()] : years;
    return [
      for (final y in list)
        FnDropdownItem(
          label: '$y년',
          active: year == y,
          onTap: () => setState(() => _filterYear = y),
        ),
      FnDropdownItem(
        label: '전체',
        active: _filterMonth == '전체',
        divider: true,
        onTap: () => setState(() {
          _filterMonth = '전체';
          _showYearPicker = false;
        }),
      ),
      for (final m in FnSettleData.months)
        FnDropdownItem(
          label: FnSettleData.monthLabel[m]!,
          active: _filterMonth == FnSettleData.monthLabel[m],
          onTap: () => setState(() {
            _filterMonth = FnSettleData.monthLabel[m]!;
            _showYearPicker = false;
          }),
        ),
    ];
  }

}
