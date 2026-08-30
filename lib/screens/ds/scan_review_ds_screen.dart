import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_card.dart';
import '../../design/fn_badge_ds.dart';
import '../../design/fn_controls_ds.dart';
import '../../design/fn_sheet.dart';
import '../../design/fn_feedback.dart';
import '../../providers/receipt_provider.dart';
import '../../services/subscription_service.dart';
import '../../services/vendor_tax_service.dart';
import '../scan/scan_draft.dart';
import 'fn_data.dart';
import 'scan_done_ds_screen.dart';
import 'scan_confirm_list_ds_screen.dart';
import '../../widgets/flower_name_field.dart';
import '../../widgets/flower_price_line.dart';
import '../../widgets/xfile_image.dart';
import '../../widgets/pan_zoom_photo.dart';

/// 인식 결과 확인 화면 — 시안 `AppH7 scan-review` 1:1
///
/// ```js
/// Shell { navTitle: '인식 결과 확인', onBack }
///   viewer   // h230, flex-shrink:0, overflow:hidden, bg cool-neutral-25, center
///             //   → receiptPaper (원본 영수증 이미지)
///   div { padding:'8px 16px 0', 12.5, label-alternative } '원본 영수증'
///   div { padding:16, column, gap:14 }
///     Card bordered
///       div { 13, label-alternative, mb8 } '도매업체 정보'
///       row space-between mb6  '거래일자' / 600 `2026.MM.DD`
///       row space-between      '거래처'   / 600 '대한꽃도매'
///     Card bordered
///       div { 13, label-alternative, mb8 } '품목'
///       items.map → editing===i ? editor(i) : row {
///           padding:'12px 10px', r10, background: confBg(conf),
///           boxShadow: conf<70 ? 'inset 0 0 0 1px var(--orange-50)' : 'none' }
///         left  : div 800/17.5 confColor(conf) name
///                 div 13.5 label-alternative `${qty}${unit} · 단가 ${won(price)}`
///         right : div 800/17.5 confColor(conf) won(amount)
///                 conf<70 && div 12/700 red-30 '확인 필요'
///                 span 16 label-assistive '✎'
///       Divider margin:'10px 0'
///       row space-between 700/17  '합계' / won(scanTotal)
///     div { row, gap:10 }
///       Button large outlined flex:1 '다시 촬영'
///       Button large flex:1 disabled:needFix>0
///         → needFix>0 ? `확인 필요 ${needFix}건` : '확인'
/// ```
/// `confBg = c => c < 70 ? 'var(--orange-95)' : 'transparent'`
/// `confColor = c => c >= 90 ? 'var(--label-normal)' : 'var(--orange-30)'`
///
/// 시안은 인라인 editor(수량/단가 + 취소/확인 완료)를 쓴다. 그 구조를 그대로 쓰되,
/// 기존 앱이 갖고 있던 기능을 전부 유지한다:
/// 여러 장 넘기기 · 매입처/날짜 편집 · 품목 추가/삭제 · 합계 직접 입력 ·
/// 과세 구분 토글 · 사업자번호 표시 · 이 건 저장 제외 · 전체보기 시트.
class ScanReviewDsScreen extends StatefulWidget {
  const ScanReviewDsScreen({super.key, required this.drafts});

  final List<ScanDraft> drafts;

  @override
  State<ScanReviewDsScreen> createState() => _ScanReviewDsScreenState();
}

class _ScanReviewDsScreenState extends State<ScanReviewDsScreen> {
  /// 시안 viewer 배경 `--cool-neutral-25`
  static const _viewerBg = Color(0xFF33363D);

  late final PageController _page = PageController();
  int _index = 0;
  bool _saving = false;

  List<ScanDraft> get _drafts => widget.drafts;
  ScanDraft get _d => _drafts[_index];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i < 0 || i >= _drafts.length) return;
    _page.animateToPage(i,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  /// **저장이 실제로 막혀 있는 건수.**
  ///
  /// 예전 `_needFix` 는 `needsAttention` 을 셌는데, 거기에는 고칠 수 없는
  /// `ocrNeedsReview` 가 포함돼 있어서 영구히 0 이 되지 않았다.
  /// 이제 매입처/품목/금액이 비어 있는 건만 센다 → 채우면 0 이 된다.
  int get _blockedCount =>
      _drafts.where((d) => !d.excluded && d.blocksSave).length;

  /// 저장 대상 (제외되지 않고 금액이 있는 건)
  List<ScanDraft> get _liveDrafts =>
      _drafts.where((d) => !d.excluded && d.total > 0).toList();

  Future<void> _confirm() async {
    _d.reviewed = true;
    if (_index < _drafts.length - 1) {
      setState(() {});
      _go(_index + 1);
      return;
    }

    // 🔴 #113(C) 마지막 장까지 확인했다. 2건 이상이면 저장 전에
    //    목록으로 한 번 더 보여준다. 여러 장을 연속으로 넘기다 보면
    //    앞에 뭘 확인했는지 기억이 안 난다는 요청.
    //    1건뿐이면 방금 그 화면이 곧 목록이므로 건너뛴다.
    final live = _liveDrafts;
    if (live.length > 1) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ScanConfirmListDsScreen(
            drafts: live,
            // 목록 자체가 최종 확인이므로 다시 묻지 않는다.
            // pop 하지 않는다 — 저장 끝에서 이 목록까지 한 번에 치운다.
            onSaveAll: () => _save(ask: false),
            onEdit: (i) {
              Navigator.of(context).pop();
              _go(_drafts.indexOf(live[i]));
            },
          ),
        ),
      );
      return;
    }
    await _save();
  }

  /// [ask] 가 false 면 확인 다이얼로그를 건너뛴다.
  /// (인식 결과 확인 목록에서 '모두 저장하기' 를 누른 경우)
  Future<void> _save({bool ask = true}) async {
    final live = _liveDrafts;
    if (live.isEmpty) {
      showFnToast(context, '저장할 영수증이 없어요', type: FnToastType.warning);
      return;
    }
    if (ask) {
      final ok = await showFnAlert(
        context,
        title: '${live.length}건을 저장할까요?',
        message: '합계 ${FnDemo.won(live.fold(0.0, (s, d) => s + d.total))}',
        icon: Icons.save_alt_rounded,
        confirmLabel: '저장',
        cancelLabel: '더 볼게요',
      );
      if (!ok || !mounted) return;
    }

    setState(() => _saving = true);
    final provider = context.read<ReceiptProvider>();
    // 🔴 #113(A) batch 로 감싼다. 예전에는 4장을 저장하면
    //    notifyListeners 가 4번 나서 홈·내역·캘린더가 각각 4번씩
    //    다시 그려졌다. 이제 끝에 한 번만 알린다.
    await provider.batch(() async {
      for (final d in live) {
        await provider.addReceipt(d.toReceipt());
        await SubscriptionService.instance.recordScan();
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);

    // 🔴 pushReplacement 가 아니라 pushAndRemoveUntil 이다.
    //    확인 목록을 거쳐 왔을 수도 있어서(확인 목록 -> 검토 -> 처리 -> 촬영),
    //    루트(5탭 화면)까지 전부 치우고 완료 화면만 올린다.
    //    그래야 완료 화면에서 '캘린더 보기' 를 눌렀을 때 곧바로 루트로 간다.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => ScanDoneDsScreen(summary: ScanSummary.of(live)),
      ),
      (r) => r.isFirst,
    );
  }

  Future<void> _confirmExit() async {
    final ok = await showFnAlert(
      context,
      title: '검토를 그만둘까요?',
      message: '아직 저장하지 않은 인식 결과가 사라져요.',
      icon: Icons.warning_amber_rounded,
      iconColor: FnColors.statusCautionary,
      confirmLabel: '나가기',
      cancelLabel: '계속 검토',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  /// 기존 기능 유지: 여러 장일 때 전체 목록에서 바로 이동 / 제외 토글
  void _showAllSheet() {
    showFnDsBottomSheet<void>(
      context,
      title: '인식한 영수증 ${_drafts.length}건',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '탭하면 해당 영수증으로 이동해요',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: FnColors.labelAlternative,
              ),
            ),
          ),
          for (var i = 0; i < _drafts.length; i++)
            FnDsListCell(
              title: _drafts[i].storeName.trim().isEmpty
                  ? '매입처 미확인'
                  : _drafts[i].storeName.trim(),
              titleWeight: FontWeight.w600,
              description: _drafts[i].excluded
                  ? '저장하지 않음'
                  : '${_drafts[i].items.length}품목 · ${FnDemo.won(_drafts[i].total)}',
              divider: i < _drafts.length - 1,
              onTap: () {
                Navigator.pop(context);
                _go(i);
              },
              trailing: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _drafts[i].excluded = !_drafts[i].excluded);
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    _drafts[i].excluded
                        ? Icons.add_circle_outline_rounded
                        : Icons.remove_circle_outline_rounded,
                    size: 20,
                    color: _drafts[i].excluded
                        ? FnColors.rose50
                        : FnColors.labelAssistive,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _drafts.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Stack(
        children: [
          FnShell(
            navTitle: n > 1 ? '인식 결과 ${_index + 1}/$n' : '인식 결과 확인',
            onBack: _confirmExit,
            trailing: [
              if (n > 1)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showAllSheet,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '전체보기',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: FnColors.rose50,
                      ),
                    ),
                  ),
                ),
            ],
            child: Column(
              children: [
                // 여러 장일 때 진행 표시 (기존 기능 유지)
                if (n > 1) _stepDots(n),
                Expanded(
                  child: PageView.builder(
                    controller: _page,
                    itemCount: n,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _DraftPane(
                      key: ValueKey(_drafts[i].id),
                      draft: _drafts[i],
                      viewerBg: _viewerBg,
                      isLast: i == n - 1,
                      blockedCount: _blockedCount,
                      onChanged: () => setState(() {}),
                      onConfirm: _confirm,
                      onRetake: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_saving) const FnLoadingOverlay(message: '저장하는 중...'),
        ],
      ),
    );
  }

  Widget _stepDots(int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: List.generate(n, (i) {
          final d = _drafts[i];
          final Color c;
          if (d.excluded) {
            c = FnColors.lineNeutral;
          } else if (i == _index) {
            c = FnColors.rose50;
          } else if (d.reviewed) {
            c = FnColors.leaf50;
          } else {
            c = FnColors.lineNormal;
          }
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == n - 1 ? 0 : 4),
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 한 장 검토 패널
// ════════════════════════════════════════════════════════════
class _DraftPane extends StatefulWidget {
  const _DraftPane({
    super.key,
    required this.draft,
    required this.viewerBg,
    required this.isLast,
    required this.blockedCount,
    required this.onChanged,
    required this.onConfirm,
    required this.onRetake,
  });

  final ScanDraft draft;
  final Color viewerBg;
  final bool isLast;
  final int blockedCount;
  final VoidCallback onChanged;
  final VoidCallback onConfirm;
  final VoidCallback onRetake;

  @override
  State<_DraftPane> createState() => _DraftPaneState();
}

class _DraftPaneState extends State<_DraftPane> {
  /// 이미지 수동 회전 (0~3 = 0°/90°/180°/270°).
  /// 저장된 영수증 수정 화면(`ReceiptDetailScreen._imageRotation`)과 동일한 방식.
  int _rotation = 0;

  /// 저장된 영수증 수정 화면(`ReceiptDetailScreen._itemCtrls`)과 동일하게
  /// **항목마다 상시 노출되는 입력 폼**을 쓴다.
  /// (탭해서 편집 모드로 들어가는 시안 방식이 아님 — 사용자 요청)
  final List<_ItemCtrls> _ctrls = [];

  /// 거래일자 YYYY / MM / DD 칩 입력 (`ReceiptDetailScreen._buildDateInputRow`)
  late TextEditingController _yearCtrl;
  late TextEditingController _monthCtrl;
  late TextEditingController _dayCtrl;

  /// 거래처명 상시 입력
  late TextEditingController _vendorCtrl;

  /// 사업자번호 상시 입력
  late TextEditingController _bizCtrl;

  ScanDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    _buildCtrls();
  }

  @override
  void didUpdateWidget(_DraftPane old) {
    super.didUpdateWidget(old);
    // PageView 재활용으로 다른 draft 가 들어오면 컨트롤러를 다시 만든다.
    if (old.draft.id != widget.draft.id) {
      _disposeCtrls();
      _buildCtrls();
      _rotation = 0;
    }
  }

  @override
  void dispose() {
    _disposeCtrls();
    super.dispose();
  }

  void _buildCtrls() {
    _yearCtrl = TextEditingController(text: d.date.year.toString());
    _monthCtrl =
        TextEditingController(text: d.date.month.toString().padLeft(2, '0'));
    _dayCtrl =
        TextEditingController(text: d.date.day.toString().padLeft(2, '0'));
    _vendorCtrl = TextEditingController(text: d.storeName);
    _bizCtrl = TextEditingController(text: d.businessNumber);
    _ctrls
      ..clear()
      ..addAll(d.items.map(_ItemCtrls.fromItem));
  }

  void _disposeCtrls() {
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    _dayCtrl.dispose();
    _vendorCtrl.dispose();
    _bizCtrl.dispose();
    for (final c in _ctrls) {
      c.dispose();
    }
    _ctrls.clear();
  }

  /// 컨트롤러 → `ScanDraft` 즉시 반영.
  /// 저장된 영수증 수정 화면은 '저장' 버튼에서 한 번에 반영하지만,
  /// 스캔 검토는 하단 '확인 / 저장하기' 가 곧 저장이므로 입력 즉시 반영한다.
  void _commit() {
    d.storeName = _vendorCtrl.text.trim();
    d.businessNumber = _bizCtrl.text.trim();

    final y = int.tryParse(_yearCtrl.text) ?? d.date.year;
    final m = (int.tryParse(_monthCtrl.text) ?? d.date.month).clamp(1, 12);
    final maxDay = DateTime(y, m + 1, 0).day;
    final dd = (int.tryParse(_dayCtrl.text) ?? d.date.day).clamp(1, maxDay);
    d.date = DateTime(y, m, dd, d.date.hour, d.date.minute);

    d.items = [
      for (final c in _ctrls)
        DraftItem(
          // 🔴 여기서 standardize() 를 부르지 않는다.
          // Build 19 는 저장 직전에 표준화를 태웠고, 그래서 드롭다운을
          // 건드리지 않아도 입력한 글자가 조용히 바뀌었다.
          // (`그거 강요되는 구조야`) 표준화는 제안일 뿐이고, 저장값을
          // 바꾸는 건 사장님이 후보를 탭했을 때만이다.
          name: c.nameCtrl.text.trim(),
          quantity: c.qty,
          unitPrice: c.price,
          unit: c.unit,
          color: c.color,
        ),
    ];
  }

  void _touch() {
    _commit();
    setState(() {});
    widget.onChanged();
  }

  /// 항목 합산 금액 (`ReceiptDetailScreen._calcTotal` 과 동일한 개념)
  double get _calcTotal => _ctrls.fold(0.0, (s, c) => s + c.calcTotal);

  // ── 시안 confBg / confColor ──────────────────────────────
  /// `confBg = c => c < 70 ? 'var(--orange-95)' : 'transparent'`
  Color _confBg(bool lowConf) =>
      lowConf ? FnColors.statusCautionaryBg : FnColors.backgroundNormal;

  /// 품목 하나가 '확인 필요' 인지. 이름이 비었거나 금액이 0이면 확인이 필요하다.
  /// (OCR 이 draft 전체에 낮은 신뢰도를 표시한 경우도 포함)
  bool _lowConf(_ItemCtrls c) =>
      c.nameCtrl.text.trim().isEmpty ||
      c.calcTotal <= 0 ||
      (d.confidence > 0 && d.confidence < 0.7);

  // ── 날짜 선택 ────────────────────────────────────────────
  /// 거래일자는 `YYYY / MM / DD` 칩에 **직접 입력**할 수 있고,
  /// 옆의 달력 버튼으로 피커를 열 수도 있다. (기존 날짜 선택 기능 유지)
  Future<void> _pickDate() async {
    final y = int.tryParse(_yearCtrl.text) ?? d.date.year;
    final m = (int.tryParse(_monthCtrl.text) ?? d.date.month).clamp(1, 12);
    final maxDay = DateTime(y, m + 1, 0).day;
    final dd = (int.tryParse(_dayCtrl.text) ?? d.date.day).clamp(1, maxDay);
    final r = await showDatePicker(
      context: context,
      initialDate: DateTime(y, m, dd),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ko'),
    );
    if (r == null) return;
    _yearCtrl.text = r.year.toString();
    _monthCtrl.text = r.month.toString().padLeft(2, '0');
    _dayCtrl.text = r.day.toString().padLeft(2, '0');
    _touch();
  }

  /// 품목 추가 — 저장된 영수증 수정 화면(`_buildAddItemButton`)과 동일하게
  /// 시트 없이 **빈 입력 행을 바로 하나 추가**한다.
  void _addItem() {
    _ctrls.add(_ItemCtrls.empty());
    _touch();
  }

  /// 품목 삭제 — 저장된 영수증 수정 화면과 동일하게 행마다 삭제 아이콘.
  void _removeItem(int index) {
    _ctrls.removeAt(index).dispose();
    d.recalcTotal();
    _touch();
  }

  /// 합계 직접 입력 (기존 기능 유지)
  Future<void> _editTotal() async {
    final c = TextEditingController(text: d.total.round().toString());
    final r = await showFnDsBottomSheet<double>(
      context,
      title: '합계 직접 입력',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '이 금액이 그대로 저장돼요. 비우고 \'품목 합계로\' 를 누르면\n'
              '품목 단가를 고칠 때마다 합계가 자동으로 따라옵니다.',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: FnColors.labelAlternative,
              ),
            ),
          ),
          FnDsTextField(
            label: '합계 금액',
            controller: c,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FnDsButton(
                  label: '품목 합계로',
                  size: FnDsButtonSize.large,
                  variant: FnDsButtonVariant.outlined,
                  expand: true,
                  onPressed: () => Navigator.pop(context, -1.0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FnDsButton(
                  label: '적용',
                  size: FnDsButtonSize.large,
                  expand: true,
                  onPressed: () {
                    final v = double.tryParse(
                            c.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
                        0;
                    Navigator.pop(context, v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (r == null) return;
    if (r < 0) {
      d.recalcTotal();
    } else {
      d.total = r;
    }
    _touch();
  }

  @override
  Widget build(BuildContext context) {
    final warn = d.warning;
    final split = d.split;

    // 저장된 영수증 수정 화면(`ReceiptDetailScreen`)과 동일한 방식:
    // 영수증 이미지를 **상단에 고정**하고 아래 내용만 스크롤한다.
    // 원본과 대조하면서 수정하기 편하도록 하기 위한 구조다.
    return Column(
      children: [
        _viewer(),
        Expanded(child: _scrollBody(warn, split)),
      ],
    );
  }

  Widget _scrollBody(String? warn, TaxSplit split) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 경고 배너 (기존 기능 유지)
              if (warn != null) ...[
                _warnBanner(warn, d.isFailed),
                const SizedBox(height: 14),
              ],
              // ── Card: 도매업체 정보 ──
              _vendorCard(),
              const SizedBox(height: 14),
              // ── Card: 품목 ──
              _itemsCard(),
              const SizedBox(height: 14),
              // ── Card: 총 금액 (`ReceiptDetailScreen._buildTotalCard` 방식) ──
              _totalCard(),
              const SizedBox(height: 12),
              // ── 항목 추가 (`ReceiptDetailScreen._buildAddItemButton` 방식) ──
              _addItemButton(),
              // 과세 구분 (기존 기능 유지)
              if (d.storeName.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                _taxCard(split),
              ],
              const SizedBox(height: 14),
              // ── 하단 버튼 2개 ──
              Row(
                children: [
                  Expanded(
                    child: FnDsButton(
                      label: '다시 촬영',
                      size: FnDsButtonSize.large,
                      variant: FnDsButtonVariant.outlined,
                      expand: true,
                      onPressed: widget.onRetake,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FnDsButton(
                      // 🔴 Build 20: 라벨이 `확인 필요 N건` 이면 사장님은
                      // "아직 저장 안 되는구나" 로 읽는다. 실제로 막히는
                      // 건수만 세서 보여준다. 합계 불일치는 경고일 뿐이다.
                      label: widget.blockedCount > 0
                          ? '입력 필요 ${widget.blockedCount}건'
                          : (widget.isLast ? '저장하기' : '확인'),
                      size: FnDsButtonSize.large,
                      expand: true,
                      // 🔴 needsAttention → blocksSave.
                      // 예전에는 OCR 이 세운 `ocrNeedsReview` 가 들어 있어서,
                      // 합계가 안 맞으면 **뭘 고쳐도 버튼이 안 풀렸다.**
                      // (`수정해도 저장이 안된다. 특히 합계랑 안맞으면`)
                      // 이제 매입처/품목/금액만 채우면 즉시 저장된다.
                      disabled: d.blocksSave,
                      onPressed: d.blocksSave ? null : widget.onConfirm,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 이 건 저장 제외 (기존 기능 유지)
              Center(
                child: FnDsButton(
                  label: d.excluded ? '저장 목록에 다시 넣기' : '이 영수증은 저장하지 않기',
                  variant: FnDsButtonVariant.text,
                  size: FnDsButtonSize.small,
                  foreground:
                      d.excluded ? FnColors.rose50 : FnColors.labelAlternative,
                  onPressed: () {
                    d.excluded = !d.excluded;
                    _touch();
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  /// 저장된 영수증 수정 화면(`ReceiptDetailScreen._buildReceiptImage`)과 **동일한 방식**.
  ///
  /// - 상단 툴바: '원본 영수증' 라벨 + 좌/우 회전 + 확대 버튼
  /// - 본체: 핀치줌 가능한 이미지 (maxHeight 260, BoxFit.fitWidth)
  /// - 탭하면 전체화면 뷰어
  ///
  /// 시안(`AppH7 scan-review`)의 h230 뷰어보다 이 방식이 원본 대조에 편하다는
  /// 사용자 피드백을 반영한 것이다.
  Widget _viewer() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: FnColors.lineNeutral)),
      ),
      child: Column(
        children: [
          // ── 회전 / 확대 툴바 ──
          Container(
            color: FnColors.fillNormal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.image_outlined,
                    size: 14, color: FnColors.labelAssistive),
                const SizedBox(width: 6),
                const Text(
                  '원본 영수증',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FnColors.labelAlternative,
                  ),
                ),
                const Spacer(),
                _toolBtn(
                  Icons.rotate_left,
                  () => setState(() => _rotation = (_rotation - 1 + 4) % 4),
                ),
                const SizedBox(width: 8),
                _toolBtn(
                  Icons.rotate_right,
                  () => setState(() => _rotation = (_rotation + 1) % 4),
                ),
                const SizedBox(width: 8),
                _toolBtn(Icons.zoom_in_rounded, _showFull),
              ],
            ),
          ),
          // ── 이미지 본체 (핀치줌 + 배율1에서도 밀어서 이동) ──
          //
          // 🔴 예전에는 `InteractiveViewer(constrained: true)` 기본값이라
          //    배율 1 에서 이동량이 정확히 0 이었다. 핀치줌을 해야 비로소
          //    이동이 됐다 — 사장님이 신고한 그 증상이다.
          //    `PanZoomPhoto` 가 사진 원본 비율대로 자식 크기를 잡아서
          //    배율 1 에서도 넘치는 부분을 밀어 볼 수 있게 한다.
          PanZoomPhoto(
            height: 260,
            background: widget.viewerBg,
            quarterTurns: _rotation,
            imageProvider: XFileImage.providerOf(d.file),
            onTap: _showFull,
            // 바깥에서 원본 비율대로 크기를 잡아 주므로 여기선 fill 이다.
            // fitWidth 로 두면 이중 계산이 돼서 여백이 생긴다.
            image: XFileImage(
              d.file,
              fit: BoxFit.fill,
              errorBuilder: (_, __, ___) => const Center(child: _PaperMock()),
            ),
          ),
        ],
      ),
    );
  }

  /// 저장된 영수증 수정 화면의 툴바 버튼과 동일한 모양
  Widget _toolBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: FnColors.rose95,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: FnColors.rose50),
      ),
    );
  }

  void _showFull() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: RotatedBox(
              quarterTurns: _rotation,
              child: XFileImage(d.file),
            ),
          ),
        ),
      ),
    );
  }

  /// 도매업체 정보 — 저장된 영수증 수정 화면(`ReceiptDetailScreen._buildInfoCard`)
  /// 과 동일하게 **상시 노출 입력 폼**으로 만든다.
  ///
  /// - 거래일자: `YYYY / MM / DD` 3칩 (탭 → 피커, 직접 입력 병행)
  /// - 거래처 / 사업자번호: 항상 열려 있는 텍스트 필드
  Widget _vendorCard() {
    return FnCard(
      bordered: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              '도매업체 정보',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: FnColors.labelAlternative,
              ),
            ),
          ),
          // ── 거래일자 (3칩) ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '거래일자',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  color: FnColors.labelNormal,
                ),
              ),
              _dateInputRow(),
            ],
          ),
          const SizedBox(height: 10),
          // ── 거래처 (상시 입력) ──
          _labeledField(
            '거래처',
            _vendorCtrl,
            hint: '예: 대한꽃도매',
            required: true,
          ),
          const SizedBox(height: 10),
          // ── 사업자번호 (상시 입력, 기존 기능 유지) ──
          _labeledField(
            '사업자번호',
            _bizCtrl,
            hint: '000-00-00000',
          ),
        ],
      ),
    );
  }

  /// `ReceiptDetailScreen._buildDateInputRow` 와 동일한 `YYYY / MM / DD` 칩 3개.
  /// 칩은 직접 입력용이고, 맨 끝 달력 버튼이 피커를 연다.
  Widget _dateInputRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dateChipField(_yearCtrl, 4, 54, 'YYYY'),
        _dateSlash(),
        _dateChipField(_monthCtrl, 2, 34, 'MM'),
        _dateSlash(),
        _dateChipField(_dayCtrl, 2, 34, 'DD'),
        const SizedBox(width: 6),
        _toolBtn(Icons.calendar_today_rounded, _pickDate),
      ],
    );
  }

  Widget _dateSlash() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 3),
        child: Text(
          '/',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            color: FnColors.labelAssistive,
          ),
        ),
      );

  /// `ReceiptDetailScreen._dateChipField` 와 동일 (색만 DS 토큰)
  Widget _dateChipField(
      TextEditingController ctrl, int maxLen, double width, String hint) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: FnColors.rose99,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FnColors.rose50.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        maxLength: maxLen,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => _touch(),
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: FnColors.rose30,
        ),
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          hintStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 9,
            color: FnColors.labelAssistive,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  /// 라벨 + 상시 노출 입력 필드 한 줄
  Widget _labeledField(String label, TextEditingController ctrl,
      {required String hint, bool required = false}) {
    final empty = required && ctrl.text.trim().isEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              color: FnColors.labelNormal,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _plainField(
            ctrl,
            hint: hint,
            align: TextAlign.right,
            error: empty,
          ),
        ),
      ],
    );
  }

  /// 시안 `row space-between` (좌: 라벨, 우: 600 값) — 읽기 전용 행
  Widget _kvRow(String k, String v,
      {VoidCallback? onTap, Color? valueColor}) {
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          k,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 15,
            color: FnColors.labelNormal,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              v,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: valueColor ?? FnColors.labelStrong,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.edit_outlined,
                  size: 14, color: FnColors.labelAssistive),
            ],
          ],
        ),
      ],
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }

  /// 품목 카드 — 저장된 영수증 수정 화면(`ReceiptDetailScreen._buildItemsCard`)
  /// 과 동일하게 **모든 항목이 항상 편집 가능한 폼**으로 나열된다.
  Widget _itemsCard() {
    return FnCard(
      bordered: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '구매 항목',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: FnColors.labelStrong,
                  ),
                ),
                Text(
                  '${_ctrls.length}종',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: FnColors.labelAssistive,
                  ),
                ),
              ],
            ),
          ),
          if (_ctrls.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  const Text(
                    '인식된 품목이 없어요',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      color: FnColors.labelAssistive,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FnDsButton(
                    label: '직접 추가하기',
                    size: FnDsButtonSize.small,
                    variant: FnDsButtonVariant.outlined,
                    onPressed: _addItem,
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < _ctrls.length; i++) _itemForm(i),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: FnDsDivider(),
          ),
          // 합계 — 탭하면 직접 입력 (기존 기능 유지)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _editTotal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '합계',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: FnColors.labelStrong,
                      ),
                    ),
                    if (d.totalOverridden) ...[
                      const SizedBox(width: 6),
                      const FnBadge('직접입력', size: FnBadgeSize.xsmall),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      FnDemo.won(d.total),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: FnColors.labelStrong,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_outlined,
                        size: 14, color: FnColors.labelAssistive),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 항목 하나의 상시 편집 폼.
  /// `ReceiptDetailScreen._buildItemRow` 편집 모드와 **동일한 배치**:
  /// `품목명 + 삭제` / `수량 + 단위 드롭다운` / `단가(₩ prefix)` / `소계`
  Widget _itemForm(int i) {
    final c = _ctrls[i];
    final low = _lowConf(c);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _confBg(low),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: low ? FnColors.statusCautionary : FnColors.lineNeutral,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 품목명 + 삭제 ──
          Row(
            children: [
              Expanded(
                // 맨 텍스트필드 → 자동완성. OCR이 품목명을 일부러 포기하므로
                // (프롬프트 5순위, 판독 불가 시 "") 여기서 고치는 게 정상 경로다.
                // 표준 품목명으로만 저장돼서 통계가 갈라지지 않는다.
                child: FlowerNameField(
                  controller: c.nameCtrl,
                  error: c.nameCtrl.text.trim().isEmpty,
                  onChanged: _touch,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _removeItem(i),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.remove_circle_outline,
                      size: 20, color: FnColors.statusNegative),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── 수량 + 단위 ──
          Row(
            children: [
              const SizedBox(
                width: 40,
                child: Text(
                  '수량',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: FnColors.labelAssistive,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _plainField(
                  c.qtyCtrl,
                  hint: '1',
                  numeric: true,
                  align: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              _unitDropdown(c),
            ],
          ),
          const SizedBox(height: 6),
          // ── 단가 ──
          Row(
            children: [
              const SizedBox(
                width: 40,
                child: Text(
                  '단가',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: FnColors.labelAssistive,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _plainField(
                  c.priceCtrl,
                  hint: '0',
                  numeric: true,
                  prefix: '₩ ',
                ),
              ),
            ],
          ),
          // ── 양재 경매 시세 (이름이 확정된 뒤에만) ──
          //
          // 드롭다운에 있던 시세를 여기로 내렸다. 고치는 중엔 볼 이유가 없고,
          // 확정된 이름 밑에 붙어야 "이 꽃이 요즘 오르고 있다"가 읽힌다.
          // 데이터가 없으면 위젯이 스스로 사라진다.
          FlowerPriceLine(flowerName: c.nameCtrl.text),
          // ── 소계 ──
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              c.calcTotal > 0 ? '소계 ${FnDemo.won(c.calcTotal)}' : '금액 확인 필요',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: c.calcTotal > 0
                    ? FnColors.rose30
                    : FnColors.statusCautionaryStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `ReceiptDetailScreen` 의 단위 드롭다운과 동일한 항목 구성.
  /// OCR 이 준 값('단' 등)이 목록에 없으면 그 값도 함께 넣어 유지한다.
  Widget _unitDropdown(_ItemCtrls c) {
    final units = <String>{..._ItemCtrls.units, c.unit}.toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 40,
      decoration: BoxDecoration(
        color: FnColors.backgroundNormal,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: FnColors.lineNormal),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: c.unit,
          isDense: true,
          icon: const Icon(Icons.expand_more_rounded,
              size: 16, color: FnColors.labelAssistive),
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            color: FnColors.labelNormal,
          ),
          items: units
              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            c.unit = v;
            _touch();
          },
        ),
      ),
    );
  }

  /// 총 금액 카드 — `ReceiptDetailScreen._buildTotalCard` 와 동일한 구성.
  /// 좌: '총 금액 / 항목 합산', 우: 24/w800 금액.
  /// 영수증 합계를 직접 입력해 항목 합산과 다르면 차액을 함께 알려준다.
  Widget _totalCard() {
    final sum = _calcTotal;
    // 🔴 저장되는 총액을 그대로 보여준다.
    // 예전에는 항목 합산(sum)만 크게 띄우면서 정작 저장은 OCR 이 읽은
    // 다른 숫자로 하고 있었다. 보이는 값과 저장값이 달랐던 것이다.
    final saved = d.userTotal ?? (sum > 0 ? sum : d.ocrTotal);
    final ocrDiff = d.ocrTotal - sum;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            FnColors.rose50.withValues(alpha: 0.06),
            FnColors.leaf50.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FnColors.rose50.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '저장될 금액',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      color: FnColors.labelAlternative,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    d.userTotal != null ? '직접 입력한 합계' : '항목 합산',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11,
                      color: FnColors.labelAssistive,
                    ),
                  ),
                ],
              ),
              Text(
                FnDemo.won(saved),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: FnColors.rose30,
                ),
              ),
            ],
          ),
          // ── 영수증에 적힌 합계와 다를 때 ──────────────────────────
          // 예전에는 `totalOverridden` (= OCR 이 세운 플래그) 조건이라
          // 사장님이 고쳐도 안 사라졌다. 이제 실시간 비교다.
          if (d.ocrTotal > 0 && ocrDiff.abs() > 1) ...[
            const SizedBox(height: 10),
            const FnDsDivider(),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '영수증에 적힌 합계',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12.5,
                    color: FnColors.labelAlternative,
                  ),
                ),
                Text(
                  FnDemo.won(d.ocrTotal),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: FnColors.statusCautionaryStrong,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '차이',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12.5,
                    color: FnColors.labelAssistive,
                  ),
                ),
                Text(
                  '${ocrDiff > 0 ? '+' : '-'}${FnDemo.won(ocrDiff.abs())}',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: FnColors.statusCautionaryStrong,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 한 번 눌러서 영수증 합계를 그대로 채택할 수 있게 한다.
            // (품목 단가를 다 못 읽었지만 총액은 맞을 때 쓰는 탈출구)
            FnDsButton(
              label: '영수증 합계(${FnDemo.won(d.ocrTotal)})로 저장',
              size: FnDsButtonSize.small,
              variant: FnDsButtonVariant.outlined,
              expand: true,
              onPressed: () {
                d.total = d.ocrTotal;
                _touch();
              },
            ),
          ],
          // 직접 입력한 합계를 되돌리는 버튼
          if (d.userTotal != null) ...[
            const SizedBox(height: 8),
            FnDsButton(
              label: '항목 합산(${FnDemo.won(sum)})으로 되돌리기',
              size: FnDsButtonSize.small,
              variant: FnDsButtonVariant.text,
              expand: true,
              foreground: FnColors.labelAlternative,
              onPressed: () {
                d.recalcTotal();
                _touch();
              },
            ),
          ],
        ],
      ),
    );
  }

  /// `ReceiptDetailScreen._buildAddItemButton` 과 동일한 점선 없는 외곽선 버튼
  Widget _addItemButton() {
    return FnDsButton(
      label: '항목 추가',
      size: FnDsButtonSize.large,
      variant: FnDsButtonVariant.outlined,
      expand: true,
      leadingIcon: const Icon(Icons.add_rounded, size: 16),
      onPressed: _addItem,
    );
  }

  /// 상시 노출 입력 필드 — `h44 r9 border line-normal, 15`
  Widget _plainField(
    TextEditingController c, {
    required String hint,
    bool numeric = false,
    bool bold = false,
    bool error = false,
    String? prefix,
    TextAlign align = TextAlign.left,
  }) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: c,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        inputFormatters:
            numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        textAlign: align,
        onChanged: (_) => _touch(),
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: bold ? 14 : 13.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: FnColors.labelNormal,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          prefixText: prefix,
          prefixStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: FnColors.rose30,
          ),
          hintStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13.5,
            color: FnColors.labelAssistive,
          ),
          filled: true,
          fillColor: FnColors.backgroundNormal,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(
                color: error ? FnColors.statusCautionary : FnColors.lineNormal),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(
                color: error ? FnColors.statusCautionary : FnColors.lineNormal),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: FnColors.rose50, width: 1.5),
          ),
        ),
      ),
    );
  }

  /// 과세 구분 (기존 기능 유지) — 시안 카드 톤에 맞춰 다시 그린다.
  Widget _taxCard(TaxSplit split) {
    final svc = VendorTaxService.instance;
    final vendor = d.storeName.trim();
    final t = svc.typeOf(vendor);
    return FnCard(
      bordered: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '과세 구분',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  color: FnColors.labelAlternative,
                ),
              ),
              const Spacer(),
              for (final v in TaxType.values)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: FnDsChip(
                    label: v.label,
                    size: FnDsChipSize.small,
                    active: t == v,
                    onTap: () async {
                      await svc.setType(vendor, v);
                      _touch();
                    },
                  ),
                ),
            ],
          ),
          if (t == TaxType.taxable) ...[
            const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: FnDsDivider(),
          ),
            _kvRow('공급가액', FnDemo.won(split.supply)),
            const SizedBox(height: 6),
            _kvRow('부가세', FnDemo.won(split.vat)),
          ],
        ],
      ),
    );
  }

  Widget _warnBanner(String text, bool failed) {
    final c = failed ? FnColors.statusNegative : FnColors.statusCautionary;
    final bg = failed ? FnColors.rose95 : FnColors.statusCautionaryBg;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: c,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: FnColors.labelNormal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 시안 `receiptPaper` — 웹 프리뷰/이미지 오류 시의 대체 목업.
/// ```js
/// div { width:150, background:'#fff', r3, padding:'12px 11px', column, gap:7,
///       boxShadow:'0 2px 12px rgba(0,0,0,.3)' }
///   div center 11/700 ls1.5 #333 '대한꽃도매'
///   div center 8.5 #888 '2026-03-13'
///   div borderTop '1px dashed #ccc'
///   rows...
/// ```
class _PaperMock extends StatelessWidget {
  const _PaperMock();

  static const _rows = [
    ['안스리움 10단', '120,000'],
    ['아미초 15단', '60,000'],
    ['작약 8단', '76,000'],
    ['합계', '256,000'],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '영수증 미리보기',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 7),
          const Divider(height: 1, color: Color(0xFFCCCCCC)),
          for (var i = 0; i < _rows.length; i++) ...[
            const SizedBox(height: 7),
            if (i == _rows.length - 1)
              const Divider(height: 1, color: Color(0xFFCCCCCC)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _rows[i][0],
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 8.5,
                    fontWeight: i == _rows.length - 1
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: i == _rows.length - 1
                        ? const Color(0xFF111111)
                        : const Color(0xFF555555),
                  ),
                ),
                Text(
                  _rows[i][1],
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 8.5,
                    fontWeight: i == _rows.length - 1
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: i == _rows.length - 1
                        ? const Color(0xFF111111)
                        : const Color(0xFF555555),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 항목 하나의 편집용 컨트롤러 묶음.
/// 저장된 영수증 수정 화면(`ReceiptDetailScreen._ItemControllers`)과 **동일한 방식**.
class _ItemCtrls {
  _ItemCtrls({
    required this.nameCtrl,
    required this.qtyCtrl,
    required this.priceCtrl,
    required this.unit,
    this.color,
  });

  /// 드롭다운 기본 단위 (저장된 영수증 수정 화면과 동일)
  static const units = ['송이', '단(묶음)', '개'];

  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  String unit;
  String? color;

  factory _ItemCtrls.fromItem(DraftItem it) => _ItemCtrls(
        nameCtrl: TextEditingController(text: it.name),
        qtyCtrl: TextEditingController(text: it.quantity.toString()),
        priceCtrl: TextEditingController(text: it.unitPrice.round().toString()),
        unit: it.unit.trim().isEmpty ? units[1] : it.unit,
        color: it.color,
      );

  factory _ItemCtrls.empty() => _ItemCtrls(
        nameCtrl: TextEditingController(),
        qtyCtrl: TextEditingController(text: '1'),
        priceCtrl: TextEditingController(),
        unit: units[1],
      );

  int get qty => int.tryParse(qtyCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  double get price =>
      double.tryParse(priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  double get calcTotal => qty * price;

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}
