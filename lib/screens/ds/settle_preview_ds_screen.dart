import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_card.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_badge_ds.dart';
import '../../design/fn_controls_ds.dart';
import '../../design/fn_sheet.dart';
import '../../models/receipt_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/settlement_pdf_service.dart';
import '../../services/vendor_tax_service.dart';
import '../../services/subscription_service.dart';
import 'fn_data.dart';
import 'onboarding_ds_screens.dart';
import 'paywall_ds_screen.dart';
import 'settle_data_live.dart';
import 'settle_doc_preview_ds_screen.dart';
import 'settle_history_ds_screen.dart';
import 'settle_views_ds.dart';

/// 시안 `AppH2Mvp` → `screen === 'preview'` 1:1 포팅.
///
/// ```js
/// Shell({ navTitle:'정산서 미리보기', onBack })
///   div { padding:16, column, gap:14 }
///     Card bordered
///       header: name 18/500  |  '전체 선택'/'전체 해제' 버튼
///                (border 1px line-normal-neutral, bg #fff, color blue-50,
///                 13/700, r8, pad '6px 10px')   marginBottom 8
///       월 목록: row gap8 15  [checkbox 20] [label flex1 15/600] [won 15/600]  pad '5px 0'
///       Divider margin '10px 0'
///       '공급가액' / won(supply)
///       '부가세'  / won(vat)     marginTop 4
///       '합계' (500) / won(grandTotal)  marginTop 8, 17/700
///     combos.length > 1 → '내보내기 방식' heading2 + Chip 2개 (통합 / 분리)
///     안내 박스 (blue-99, marginTop 10)
///     marginTop 22 column gap9
///       Button large disabled=vSel.isEmpty  `선택한 N개월 내보내기`
///       12.5 #767676 center  `이번 달 무료 내보내기 X/3회 사용`
/// ```
class SettlePreviewDsScreen extends StatefulWidget {
  const SettlePreviewDsScreen({
    super.key,
    required this.vendor,
    required this.selectedMonths,
    this.year,
    this.receipts = const [],
  });

  final FnVendor vendor;
  final List<String> selectedMonths;

  /// 실제 데이터 연도 (`'2026'`). 이력 저장 시 사용.
  final String? year;

  /// 이 거래처 · 선택 월에 해당하는 실제 영수증 (이력 건수 계산용)
  final List<ReceiptModel> receipts;

  @override
  State<SettlePreviewDsScreen> createState() => _SettlePreviewDsScreenState();
}

/// 시안 `exportCount` — 이제 실제 `SubscriptionService.exportsUsed` 를 사용한다.
int get fnExportCount => SubscriptionService.instance.exportsUsed;

class _SettlePreviewDsScreenState extends State<SettlePreviewDsScreen> {
  late List<String> _sel = List.of(widget.selectedMonths);
  String _exportMode = 'combined';

  /// 시안 `형식` — PDF / 엑셀(.xlsx).
  ///
  /// 🔴 엑셀 생성기는 **아직 없다.** 예전에 `엑셀/PDF` 선택이 있었는데
  ///    엑셀을 고르면 아무 파일도 안 만들고 '완료' 로 넘어가서, 화면만
  ///    성공처럼 보였다. 그래서 그 선택을 통째로 지웠던 것이다.
  ///
  ///    시안이 이 선택을 다시 요구하므로 화면에는 되살리되, 엑셀을 고르면
  ///    **만들어지지 않는다고 분명히 말하고 PDF 로 되돌린다.**
  ///    거짓 성공은 다시 만들지 않는다.
  String _fileFormat = 'pdf';

  /// PDF 생성 중. 사진이 많으면 몇 초 걸린다.
  /// 그 동안 버튼을 눌러도 반응이 없으면 사용자는 앱이 멈춘 줄 안다.
  /// 그래서 버튼 글자를 바꾸고 다시 누르지 못하게 막는다.
  bool _busy = false;

  List<String> get _availableMonths => FnSettleData.months
      .where((m) => (widget.vendor.months[m] ?? 0) > 0)
      .toList();

  /// ```js
  /// const taxType = getVendorTax(v.name) || 'taxable';
  /// const supply = taxType === 'exempt' ? amount : Math.round(amount / 1.1);
  /// const vat = amount - supply;
  /// ```
  ({double total, double supply, double vat}) get _totals {
    double total = 0, supply = 0, vat = 0;
    for (final m in _sel) {
      final amount = widget.vendor.months[m] ?? 0;
      // 실제 VendorTaxService 로 공급가액/부가세를 분리 (레거시 동일)
      final s = SettleLiveData.split(widget.vendor.name, amount);
      total += amount;
      supply += s.supply;
      vat += s.vat;
    }
    return (total: total, supply: supply, vat: vat);
  }

  void _toggleMonth(String m) {
    setState(() {
      if (_sel.contains(m)) {
        _sel.remove(m);
      } else {
        _sel.add(m);
      }
    });
  }

  void _onExport() {
    // 레거시와 동일하게 실제 국도 제한을 사용한다 (PRO 는 무제한).
    if (!SubscriptionService.instance.canExport) {
      showFnProModal(
        context,
        title: '🔒 이번 달 무료 내보내기 횟수(3/3회) 초과',
        desc: 'Pro 요금제 구독시 정산서 내보내기를 무제한으로 이용할 수 있어요',
        // 🔴 웹에서는 구독 안내로 보내지 않는다. (#120)
        //    입구를 감췄으므로 버튼도 주지 않는다. 앱에서는 그대로 동작한다.
        onSubscribe: SubscriptionService.showPaywallEntry
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PaywallDsScreen()),
                )
            : null,
      );
      return;
    }

    // 🔴 엑셀을 고른 채로 누르면 **지금은 만들 수 없다.**
    //    생성기가 없는데 조용히 PDF 를 뱉으면, 사장님은 엑셀을 받은 줄
    //    알고 세무사에게 보낸다. 그래서 말하고 멈춘다.
    //    (화면의 선택은 시안대로 남겨 두고, 붙는 날 이 블록만 지운다)
    if (_fileFormat != 'pdf') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('엑셀 내보내기는 아직 준비 중이에요. PDF 로 먼저 받아보세요.'),
          duration: Duration(seconds: 3),
        ),
      );
      setState(() => _fileFormat = 'pdf');
      return;
    }

    _openMethodSheet();
  }

  /// 내보낼 **문서 종류**를 고른다.
  ///
  /// 🔴 원래는 `엑셀 / PDF` 두 개였다. 두 가지 문제가 있었다.
  ///    ① 엑셀 생성기가 아예 없었다(패키지조차 없었다)
  ///    ② PDF 도 파일을 만들지 않았다. 이력만 쓰고 '완료' 화면으로 넘겨서
  ///       화면상으로는 성공처럼 보였다.
  ///
  ///    그리고 사용자에게 필요한 선택은 '파일 형식' 이 아니라 **문서 종류**다.
  ///    도매상에게 보낼 요청서와, 내가 보관할 내역서는 내용이 달라야 한다.
  ///    (요청서에는 품목을 넣지 않는다 — OCR 품목명이 틀릴 수 있어서)
  void _openMethodSheet() {
    showFnDsBottomSheet(
      context,
      title: '어떤 문서로 내보낼까요?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in const [
            (
              kind: SettlementDocKind.request,
              label: '세금계산서 발행 요청서',
              desc: '거래처에 보내는 문서 · 날짜와 금액, 영수증 사진',
            ),
            (
              kind: SettlementDocKind.statement,
              label: '매입 내역서',
              desc: '내 보관 · 세무사 제출용 · 품목까지 포함',
            ),
          ])
            FnDsListCell(
              leading: const _FileTypeIcon(kind: 'PDF'),
              title: e.label,
              description: e.desc,
              divider: true,
              onTap: () {
                Navigator.of(context).pop();
                _export(e.kind);
              },
            ),
          const SizedBox(height: 10),
          // 바로 다운로드되지 않는다는 걸 미리 알려준다.
          // 누르기 전에 알면 "잘못 눌렀나?" 하고 멈추지 않는다.
          const Text(
            '문서를 만든 뒤 미리보기로 확인하고,\n그때 다운로드할지 결정할 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: FnColors.labelAlternative,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 실제로 PDF 를 만들고 공유 시트를 띄운다.
  Future<void> _export(SettlementDocKind kind) async {
    final me = context.read<AuthProvider>().currentUser;

    // ── 사업자 정보 확인 ─────────────────────────────────────
    //
    // 🔴 사업자등록번호가 없으면 도매상이 세금계산서를 **발행할 수 없다.**
    //    문서가 나가도 아무 쓸모가 없고, 거래처에 한 번 더 물어보게 만든다.
    //    그래서 내보내기 전에 막는다.
    //    (요청서만 막는다. 내역서는 내 보관용이라 없어도 의미가 있다)
    if (kind == SettlementDocKind.request) {
      final missing = <String>[
        if (me == null || me.businessName.isEmpty) '상호명',
        if (me == null || me.businessNumber.isEmpty) '사업자등록번호',
        if (me == null || me.ownerName.isEmpty) '대표자',
        if (me == null || me.phoneNumber.isEmpty) '전화번호',
        if (me == null || me.businessAddress.isEmpty) '주소',
      ];
      if (missing.isNotEmpty) {
        final go = await showFnAlert(
          context,
          title: '사업자 정보가 필요해요',
          message: '${missing.join(' · ')} 이(가) 비어 있어요.\n\n'
              '이 정보가 없으면 거래처에서 세금계산서를 발행할 수 없어요. '
              '지금 입력하시겠어요?',
          confirmLabel: '입력하기',
          cancelLabel: '나중에',
        );
        if (!mounted) return;
        if (go == true) {
          await BizReviewDsScreen.openEdit(context);
        }
        return;
      }
    }

    // 선택한 월의 영수증만 골라낸다.
    final rs = _receiptsForSelection();
    if (rs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택한 기간에 영수증이 없어요')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      // ── 1단계: 바이트만 만든다 (저장하지 않는다) ─────────────
      //
      // 🔴 예전에는 `build()` 하나로 (생성 → 저장/다운로드) 를 한꺼번에 했다.
      //    그래서 사용자가 문서를 보기도 전에 파일이 내려가 버렸다. 내용이
      //    틀렸으면 다시 내보내야 했고, 쓸모없는 파일이 쌓이고 무료 내보내기
      //    횟수도 같이 깎였다. 그래서 생성과 저장을 분리했다.
      final draft = await SettlementPdfService.instance.draft(
        kind: kind,
        vendorName: widget.vendor.name,
        receipts: rs,
        me: me,
        periodLabel: _periodLabel(),
      );

      if (!mounted) return;
      setState(() => _busy = false);

      // ── 2단계: 미리보기 → 사용자가 결정한다 ─────────────────
      final wantsDownload =
          await SettleDocPreviewDsScreen.open(context, draft);
      if (!mounted) return;

      // 취소했다. 파일도 만들지 않고, 이력도 남기지 않고,
      // 무료 내보내기 횟수도 깎지 않는다.
      if (!wantsDownload) return;

      setState(() => _busy = true);

      // ── 3단계: 실제 저장 ───────────────────────────────────
      final doc = await SettlementPdfService.instance.save(draft);

      final t = _totals;

      // 이력은 **파일이 실제로 만들어진 뒤에** 남긴다.
      // 예전에는 파일도 없이 이력부터 썼다.
      await SettleHistoryStore.add(SettleHistoryEntry(
        month: '${widget.year ?? DateTime.now().year}-'
            '${_sel.isEmpty ? '1' : int.parse(_sel.first).toString()}',
        vendors: [widget.vendor.name],
        receiptCount: rs.length,
        total: t.total,
        sentAt: DateTime.now(),
        months: _sel.map((m) => FnSettleData.monthLabel[m] ?? m).toList(),
        method: kind.slug,
        fileCount: 1,
      ));
      await SubscriptionService.instance.recordExport();

      if (!mounted) return;
      setState(() => _busy = false);

      // 공유 시트. 카카오톡·메일·드라이브 어디로든 보낼 수 있다.
      //
      // 🔴 웹은 공유할 파일 경로가 없다.
      //    브라우저가 이미 다운로드 폴더로 내려보냈으므로 `path` 가 null 이다.
      //    그 상태에서 `XFile(null!)` 을 하면 앱이 죽는다. 그래서 분기한다.
      final path = doc.file.path;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${doc.file.name} 을 다운로드했어요')),
        );
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path)],
            text: '${widget.vendor.name} ${kind.title}',
          ),
        );
      }

      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SettleSharedDsScreen(
          method: kind.title,
          exportMode: _exportMode,
          comboCount: _sel.length,
          grandTotal: t.total,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // 무엇이 실패했는지 알려준다. 조용히 넘기면 또 추측으로 쫓게 된다.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('문서를 만들지 못했어요: $e')),
      );
    }
  }

  /// 선택한 월에 해당하는 영수증.
  ///
  /// `widget.receipts` 는 이 거래처의 (연도 범위) 영수증이다.
  /// 사용자가 체크한 월만 남긴다.
  List<ReceiptModel> _receiptsForSelection() {
    if (_sel.isEmpty) return const [];
    final keys = _sel.toSet();
    return widget.receipts
        .where((r) => keys.contains(r.date.month.toString().padLeft(2, '0')))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  String _periodLabel() {
    if (_sel.isEmpty) return '-';
    final ms = [..._sel]..sort();
    final y = widget.year ?? '${DateTime.now().year}';
    final labels = ms.map((m) => '$y.$m');
    return ms.length == 1 ? labels.first : '${labels.first} ~ ${labels.last}';
  }

  @override
  Widget build(BuildContext context) {
    final months = _availableMonths;
    final t = _totals;
    final allSelected = months.isNotEmpty && _sel.length == months.length;

    return FnShell(
      navTitle: '정산서 미리보기',
      bg: _kBg,
      onBack: () => Navigator.of(context).pop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(_kPad, 12, _kPad, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summaryCard(t),
            const SizedBox(height: 16),
            _monthCard(months, t, allSelected),
            const SizedBox(height: 20),
            // 🔴 '저장 방식' 은 **두 달 이상 골랐을 때만** 뜻이 있다.
            //    한 달이면 통합이든 분리든 결과가 같은 파일 하나다.
            //    (예전 구현도 `_sel.length > 1` 조건이었다)
            if (_sel.length > 1) ...[
              _groupLabel('저장 방식'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _optionCard(
                      selected: _exportMode == 'combined',
                      title: '전체 통합',
                      sub: '1개의 파일로 저장',
                      onTap: () => setState(() => _exportMode = 'combined'),
                    ),
                  ),
                  const SizedBox(width: _kGap),
                  Expanded(
                    child: _optionCard(
                      selected: _exportMode == 'separate',
                      title: '월별 분리',
                      sub: '월마다 각각 저장',
                      onTap: () => setState(() => _exportMode = 'separate'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            _groupLabel('형식'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _optionCard(
                    selected: _fileFormat == 'pdf',
                    title: 'PDF',
                    sub: '범용 문서 형식',
                    onTap: () => setState(() => _fileFormat = 'pdf'),
                  ),
                ),
                const SizedBox(width: _kGap),
                Expanded(
                  child: _optionCard(
                    selected: _fileFormat == 'xlsx',
                    title: '엑셀 (.xlsx)',
                    sub: '데이터 편집 가능',
                    onTap: () => setState(() => _fileFormat = 'xlsx'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _exportButton(),
            const SizedBox(height: 10),
            Text(
              '이번 달 무료 내보내기 $fnExportCount/${FnSettleData.exportCap}회 사용',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                color: _kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 시안 조각들 ─────────────────────────────────────────────

  /// 카드1 — 거래처 이름 + 선택 기간 합계.
  ///
  /// 시안 실측: y 126.6..320.5 (h 193.9), 좌우 24.7..364.2.
  ///   이름    y 150.7..182.0 (왼쪽 44.8)
  ///   '선택 기간 합계'  y 222.4..231.3 (가운데)
  ///   큰 금액  y 247.0..278.4 (가운데)
  ///   '1개월 · 영수증 18건'  y 288.5..297.5 (가운데)
  Widget _summaryCard(({double total, double supply, double vat}) t) {
    final tax = SettleLiveData.taxOf(widget.vendor.name);
    final sub = <String>[
      if (widget.vendor.lastDate.isNotEmpty) '최근 거래 ${widget.vendor.lastDate}',
      tax == TaxType.exempt ? '면세' : '과세',
    ].join(' · ');

    return _card(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.vendor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: _kInk,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12.5,
                        color: _kMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 🔴 시안의 '정보 보기'. 예전 '전체 선택/해제' 버튼은 아래
              //    월 카드 머리로 옮겼다(시안이 거기에 뒀다).
              _TextLink(
                label: '정보 보기',
                onTap: () => _showVendorInfo(tax),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            '선택 기간 합계',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12.5,
              color: _kMuted,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              settleWon(t.total),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: _kInk,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_sel.length}개월 · 영수증 ${widget.receipts.length}건',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12.5,
              color: _kMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// 카드2 — 정산 월 선택 + 공급가액/부가세/합계.
  ///
  /// 시안 실측: y 337.3..832.7, 구분선 y 678.5 (#E6E6E6) 하나.
  Widget _monthCard(
    List<String> months,
    ({double total, double supply, double vat}) t,
    bool allSelected,
  ) {
    return _card(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '정산 월 선택',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                  ),
                ),
              ),
              if (months.isNotEmpty)
                _TextLink(
                  // 기능 유지 — 예전 '전체 선택/해제' 와 같은 동작이다.
                  label: allSelected ? '전체 해제' : '전체 선택',
                  onTap: () => setState(
                    () => _sel = allSelected ? [] : List.of(months),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (months.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '선택 가능한 내역이 없어요',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  color: _kMuted,
                ),
              ),
            )
          else
            for (final m in months) _monthRow(m),
          const SizedBox(height: 10),
          // 시안 구분선 — y 678.5, #E6E6E6.
          Container(height: 1, color: _kLine2),
          const SizedBox(height: 14),
          _kv('공급가액', settleWon(t.supply)),
          const SizedBox(height: 12),
          _kv('부가세',
              t.vat <= 0 ? '${settleWon(0)} (면세)' : settleWon(t.vat)),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '합계',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    settleWon(t.total),
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: _kCoral,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 월 한 줄 — 라디오 + 라벨 + 금액.
  ///
  /// 🔴 시안은 네모 체크박스가 아니라 **동그란 라디오**다.
  ///    고른 달은 코랄 동그라미에 흰 체크, 글자와 금액도 코랄로 바뀐다.
  ///    (예전: Material Checkbox + 항상 검정 글자)
  Widget _monthRow(String m) {
    final on = _sel.contains(m);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleMonth(m),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              _Radio(on: on),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  FnSettleData.monthLabel[m]!,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14.5,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? _kCoral : _kInk,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    settleWon(widget.vendor.months[m] ?? 0),
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: on ? _kCoral : _kInk,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `저장 방식` / `형식` 같은 묶음 제목.
  Widget _groupLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _kInk,
          ),
        ),
      );

  /// 저장 방식 / 형식 칸.
  ///
  /// 시안 실측: 고른 칸 #FFF1EE + 코랄 테두리, 안 고른 칸 흰색 + 얕은 그림자.
  Widget _optionCard({
    required bool selected,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_kOptRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? _kOptOn : Colors.white,
            borderRadius: BorderRadius.circular(_kOptRadius),
            border: Border.all(
              color: selected ? _kCoral : _kLine,
              width: selected ? 1.2 : 1,
            ),
            // 고른 칸은 코랄 테두리가 윤곽을 잡아주므로 그림자를 빼고,
            // 안 고른 칸만 시안처럼 얕게 띄운다.
            boxShadow: selected ? null : _kShadowSm,
          ),
          child: Row(
            children: [
              _Radio(on: selected, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? _kCoral : _kInk,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 11,
                        color: selected
                            ? _kCoral.withValues(alpha: 0.75)
                            : _kMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 시안 하단 코랄 알약 버튼 — `내보내기`.
  Widget _exportButton() {
    final disabled = _sel.isEmpty || _busy;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : _onExport,
          borderRadius: BorderRadius.circular(_kBtnH / 2),
          child: Container(
            height: _kBtnH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kCoral,
              borderRadius: BorderRadius.circular(_kBtnH / 2),
              boxShadow: disabled ? null : _kShadowBtn,
            ),
            child: Text(
              _busy ? '문서를 만들고 있어요...' : '내보내기',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 흰 카드 껍데기 — 시안 그림자 9dp 번짐.
  Widget _card({required Widget child, required EdgeInsets padding}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _kLine),
        boxShadow: _kShadowLg,
      ),
      child: child,
    );
  }

  /// 카드1 의 `정보 보기` — 거래처 과세 구분과 최근 거래를 알려준다.
  ///
  /// 🔴 시안에 글자는 있는데 무엇을 보여줄지는 없다. 없는 화면으로
  ///    보내 깨뜨리는 대신, 이 화면이 이미 아는 사실만 정리해 보여준다.
  void _showVendorInfo(TaxType tax) {
    showFnDsBottomSheet(
      context,
      title: widget.vendor.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kv('과세 구분', tax == TaxType.exempt ? '면세' : '과세'),
          const SizedBox(height: 12),
          _kv('최근 거래',
              widget.vendor.lastDate.isEmpty ? '-' : widget.vendor.lastDate),
          const SizedBox(height: 12),
          _kv('영수증', '${widget.receipts.length}건'),
          const SizedBox(height: 12),
          _kv('선택한 달', '${_sel.length}개월'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k,
              style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  color: FnColors.labelNormal)),
          Text(v,
              style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  color: FnColors.labelNormal)),
        ],
      );
}

/// ```js
/// function FileTypeIcon({ kind }) {
///   const excel = kind === 'Excel';
///   const c = excel ? '#3F8F4E' : '#EE7686', bg = excel ? '#EAF5EC' : '#FDECEC';
///   div 36x36 r10 bg  →  문서 아이콘 + 'X' | 'PDF' 텍스트
/// }
/// ```
class _FileTypeIcon extends StatelessWidget {
  const _FileTypeIcon({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    final excel = kind == 'Excel';
    final c = excel ? const Color(0xFF3F8F4E) : const Color(0xFFEE7686);
    final bg = excel ? const Color(0xFFEAF5EC) : const Color(0xFFFDECEC);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.description_outlined, size: 22, color: c),
          Positioned(
            bottom: 5,
            child: Text(
              excel ? 'X' : 'PDF',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: excel ? 8 : 6.5,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 시안 `screen === 'shared'` 1:1
///
/// ```js
/// Shell({ navTitle:'', onBack })
///   div height100% center column gap14 pad24 textAlign center
///     64x64 r32 bg green-95 fontSize30 color green-50  '✓'
///     heading2  `${method}로 전송했어요`
///     body2 label-alt 600  분리&&n>1 ? `월별로 나눠 N개 파일로 전송했어요`
///                                   : '선택한 내역을 하나의 파일로 전송했어요'
///     Card bordered width100% textAlign left
///        600 mb4  `${combos.length}건 정산서`
///        14 alt   `${won(grandTotal)} · ${fileCount}개 파일`
///     Button large width100% '확인'
///     Button large text '내보내기 이력 보기'
/// ```
class SettleSharedDsScreen extends StatelessWidget {
  const SettleSharedDsScreen({
    super.key,
    required this.method,
    required this.exportMode,
    required this.comboCount,
    required this.grandTotal,
  });

  final String method;
  final String exportMode;
  final int comboCount;
  final double grandTotal;

  @override
  Widget build(BuildContext context) {
    final fileCount = exportMode == 'separate' ? comboCount : 1;
    return FnShell(
      navTitle: '',
      onBack: () => Navigator.of(context).pop(),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: FnColors.leaf95,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '✓',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 30,
                      color: FnColors.leaf50,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '$method로 전송했어요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelStrong,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                exportMode == 'separate' && fileCount > 1
                    ? '월별로 나눠 $fileCount개 파일로 전송했어요'
                    : '선택한 내역을 하나의 파일로 전송했어요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelAlternative,
                ),
              ),
              const SizedBox(height: 14),
              FnCard(
                bordered: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$comboCount건 정산서',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: FnColors.labelNormal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${FnDemo.won(grandTotal)} · $fileCount개 파일',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        color: FnColors.labelAlternative,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FnDsButton(
                label: '확인',
                expand: true,
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
              ),
              const SizedBox(height: 14),
              FnDsButton(
                label: '내보내기 이력 보기',
                expand: true,
                variant: FnDsButtonVariant.text,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SettleHistoryDsScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ════════════════════════════════════════════════════════════════
//  #144 정산서 미리보기 시안 실측 (348x1024, 환산비 1.1207)
// ════════════════════════════════════════════════════════════════
//
//   배경        #FEF9F5
//   카드1       y 126.6..320.5 (h 193.9)   좌우 24.7..364.2
//   카드2       y 337.3..832.7 (h 495.4)   같은 좌우
//   카드 그림자   Δ[3,17,13,11,7,5,3,2,1,0]   = 9dp 번짐
//   구분선      y 678.5  #E6E6E6  (카드2 안에 하나뿐)
//   고른 옵션칸  #FFF1EE + 코랄 테두리
//   안 고른 칸   #FFFFFF + 얕은 그림자 Δ[4,4,21,1,0]
//   내보내기 버튼 #FF6D78, y 1068..1126 (h 58), 그림자 Δ[10,10,7,4,3,2,1,0]
//   월 라디오    지름 ~18dp. 고르면 코랄 채움 + 흰 체크

/// 시안 배경.
const Color _kBg = Color(0xFFFEF9F5);

/// 시안 본문 글자색.
const Color _kInk = Color(0xFF171717);

/// 시안 보조 글자색.
const Color _kMuted = Color(0xFF8A8580);

/// 시안 코랄.
const Color _kCoral = Color(0xFFFF6D78);

/// 카드 테두리 — 홈/내역과 같은 연한 선.
const Color _kLine = Color(0x14C9A79B);

/// 카드2 안 구분선 — 시안 실측 #E6E6E6.
const Color _kLine2 = Color(0xFFE6E6E6);

/// 고른 옵션 칸 채움 — 시안 실측 #FFF1EE.
const Color _kOptOn = Color(0xFFFFF1EE);

/// 시안 좌우 여백 24.7dp.
const double _kPad = 24.0;

/// 옵션 칸 사이 간격.
const double _kGap = 12.0;

/// 카드 모서리.
const double _kCardRadius = 18.0;

/// 옵션 칸 모서리.
const double _kOptRadius = 14.0;

/// 내보내기 버튼 높이 — 시안 y 1068..1126.
const double _kBtnH = 58.0;

/// 카드 그림자 — 9dp 번짐. 내역 화면과 같은 따뜻한 회갈색을 쓴다.
const List<BoxShadow> _kShadowLg = [
  BoxShadow(color: Color(0x268A7268), blurRadius: 10, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x118A7268), blurRadius: 20, offset: Offset(0, 5)),
];

/// 안 고른 옵션 칸 그림자 — 아주 얕다.
const List<BoxShadow> _kShadowSm = [
  BoxShadow(color: Color(0x148A7268), blurRadius: 3, offset: Offset(0, 1)),
];

/// 내보내기 버튼 그림자 — 코랄 자체를 번지게 한다.
const List<BoxShadow> _kShadowBtn = [
  BoxShadow(color: Color(0x33FF6D78), blurRadius: 12, offset: Offset(0, 4)),
];

/// 시안 동그란 라디오.
///
/// 🔴 Material `Radio` 를 쓰지 않은 이유: 기본 지름·터치영역·색 규칙이
///    시안과 다르고, 크기를 줄이려면 `VisualDensity` 를 건드려야 해서
///    오히려 손이 더 간다. 모양이 단순하므로 직접 그린다.
class _Radio extends StatelessWidget {
  const _Radio({required this.on, this.size = 18});

  final bool on;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? _kCoral : Colors.white,
        border: Border.all(
          color: on ? _kCoral : const Color(0xFFE3E3E3),
          width: 1.4,
        ),
      ),
      child: on
          ? Icon(Icons.check_rounded, size: size * 0.66, color: Colors.white)
          : null,
    );
  }
}

/// 카드 머리의 글자 링크 (`정보 보기`, `전체 선택`).
class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kMuted,
            ),
          ),
        ),
      ),
    );
  }
}
