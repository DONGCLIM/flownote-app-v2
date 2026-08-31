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
import '../../services/subscription_service.dart';
import 'fn_data.dart';
import 'onboarding_ds_screens.dart';
import 'paywall_ds_screen.dart';
import 'settle_data_live.dart';
import 'settle_doc_preview_ds_screen.dart';
import 'settle_history_ds_screen.dart';

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
        onSubscribe: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PaywallDsScreen()),
        ),
      );
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
      onBack: () => Navigator.of(context).pop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FnCard(
              bordered: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.vendor.name,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: FnColors.labelNormal,
                          ),
                        ),
                      ),
                      if (months.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(
                            () => _sel = allSelected ? [] : List.of(months),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: FnColors.backgroundNormal,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: FnColors.lineNeutral, width: 1),
                            ),
                            child: Text(
                              allSelected ? '전체 해제' : '전체 선택',
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: FnColors.rose50,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (months.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '선택 가능한 내역이 없어요',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          color: FnColors.labelAlternative,
                        ),
                      ),
                    )
                  else
                    for (final m in months)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _toggleMonth(m),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: _sel.contains(m),
                                  onChanged: (_) => _toggleMonth(m),
                                  activeColor: FnColors.rose50,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  FnSettleData.monthLabel[m]!,
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: FnColors.labelNormal,
                                  ),
                                ),
                              ),
                              Text(
                                FnDemo.won(widget.vendor.months[m] ?? 0),
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: FnColors.labelNormal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: FnDsDivider(),
                  ),
                  _kv('공급가액', FnDemo.won(t.supply)),
                  const SizedBox(height: 4),
                  _kv('부가세', FnDemo.won(t.vat)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '합계',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            color: FnColors.labelNormal,
                          ),
                        ),
                      ),
                      Text(
                        FnDemo.won(t.total),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: FnColors.labelNormal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_sel.length > 1) ...[
              const SizedBox(height: 24),
              const Text(
                '내보내기 방식',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelStrong,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _modeChip('combined', '전체 통합 저장', '(1개의 파일)'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _modeChip('separate', '월별 분리 저장', '(월별 개별 파일)'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            _guideBox(),
            const SizedBox(height: 22),
            FnDsButton(
              label: _busy
                  ? '문서를 만들고 있어요...'
                  : '선택한 ${_sel.length}개월 내보내기',
              expand: true,
              disabled: _sel.isEmpty || _busy,
              onPressed: _onExport,
            ),
            const SizedBox(height: 9),
            Text(
              '이번 달 무료 내보내기 $fnExportCount/${FnSettleData.exportCap}회 사용',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: Color(0xFF767676),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
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

  /// 시안: Chip(flex:1, column, height auto, padding '10px 8px', gap 2)
  Widget _modeChip(String id, String title, String sub) {
    final active = _exportMode == id;
    return GestureDetector(
      onTap: () => setState(() => _exportMode = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: active ? FnColors.rose95 : FnColors.fillAlternative,
          borderRadius: BorderRadius.circular(10),
          border: active ? Border.all(color: FnColors.rose50, width: 1) : null,
        ),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: active ? FnColors.rose50 : FnColors.labelNormal,
              ),
            ),
            const SizedBox(height: 2),
            Opacity(
              opacity: 0.75,
              child: Text(
                sub,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11.5,
                  height: 1.4,
                  color: active ? FnColors.rose50 : FnColors.labelNormal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guideBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FnColors.rose99,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline_rounded,
                size: 20, color: FnColors.rose50),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '내보내기 안내',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: FnColors.labelNormal,
                  ),
                ),
                const SizedBox(height: 6),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      height: 1.7,
                      color: FnColors.labelNormal,
                    ),
                    children: [
                      TextSpan(text: '· 카카오톡·이메일로 '),
                      TextSpan(
                          text: '바로 전송',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: '할 수 있어요\n· 내보낸 파일은 '),
                      TextSpan(
                          text: '[파일] 앱과 [저장 이력]',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: '에 보관돼요'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
