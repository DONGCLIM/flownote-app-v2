import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_controls_ds.dart';
import '../../design/fn_sheet.dart';
import '../../services/gemini_ocr_service.dart';
import '../../services/subscription_service.dart';
import '../paywall_screen.dart';
import '../scan/scan_draft.dart';

/// 인식 중 화면 — 시안 `AppH7 scan-processing` 1:1
///
/// ```js
/// Shell { navTitle:'' }
///   div { height:'100%', column, center, gap:28, padding:28 }
///     Circular size 40
///     div 20/600 '영수증을 읽고 있어요'
///     div { padding:'30px 20px', r14, background:'var(--blue-99)',
///           boxShadow:'inset 0 0 0 1px var(--line-normal-neutral)',
///           column, alignItems:'flex-start', gap:18, width:'100%' }
///       div { row, gap:8, 17/600, label-normal } '🔒 Pro 업그레이드 시 혜택'
///       div { column, gap:16, width:'100%' }
///         ['1회 최대 20장 연속 촬영','갤러리 20장 한 번에 불러오기','월간 총 스캔 장수 무제한']
///           → row gap:8
///               span { 17/800, blue-50, lh1.4 } '+'
///               div  { 15/600, #222222, lh1.5, left } t
///     div { width:'100%', marginTop:-8 } ProgressBar value 72
///     Button variant:'text' disabled:!ready '결과 확인하기 →'
/// ```
///
/// 시안은 900ms 타이머 목업이지만 여기서는 **실제 OCR** 을 순차로 돌리고,
/// 진행률/장수/취소 등 기존 기능을 그대로 유지한다.
/// 완료되면 `List<ScanDraft>` 를 pop 으로 반환한다.
class ScanProcessingDsScreen extends StatefulWidget {
  const ScanProcessingDsScreen({super.key, required this.drafts});

  final List<ScanDraft> drafts;

  @override
  State<ScanProcessingDsScreen> createState() => _ScanProcessingDsScreenState();
}

class _ScanProcessingDsScreenState extends State<ScanProcessingDsScreen> {
  /// 시안 카드 배경 `--blue-99` → 로즈 오버라이드
  static const _cardBg = FnColors.rose99;

  /// 시안 본문 글자 `#222222`
  static const _bodyFg = Color(0xFF222222);

  /// 시안 Pro 혜택 3줄 (원문 그대로)
  static const _proBenefits = [
    '1회 최대 20장 연속 촬영',
    '갤러리 20장 한 번에 불러오기',
    '월간 총 스캔 장수 무제한',
  ];

  final _ocr = GeminiOcrService();

  int _current = 0;
  bool _cancelled = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    for (var i = 0; i < widget.drafts.length; i++) {
      if (_cancelled || !mounted) return;
      setState(() => _current = i);

      final d = widget.drafts[i];
      d.status = ScanDraftStatus.processing;
      try {
        final r = await _ocr.recognizeReceipt(xFile: d.file);
        d.applyOcr(r);
      } catch (e) {
        d.status = ScanDraftStatus.failed;
        d.error = '$e'.replaceAll('Exception: ', '');
      }
      if (!mounted) return;
      setState(() {});
    }
    if (!mounted || _cancelled) return;
    setState(() => _done = true);
    // 시안은 사용자가 '결과 확인하기 →' 를 누르게 되어 있다.
    // 자동으로 넘기면 결과를 확인할 틈이 없어서, 짧게 기다린 뒤 넘긴다.
    await Future.delayed(const Duration(milliseconds: 420));
    if (!mounted || _cancelled) return;
    Navigator.pop(context, widget.drafts);
  }

  int get _doneCount =>
      widget.drafts.where((d) => d.isSuccess || d.isFailed).length;

  Future<void> _confirmCancel() async {
    final ok = await showFnAlert(
      context,
      title: '인식을 멈출까요?',
      message: '지금까지 인식한 $_doneCount장은 그대로 넘어가요.',
      icon: Icons.pause_circle_outline_rounded,
      confirmLabel: '멈추기',
      cancelLabel: '계속하기',
    );
    if (ok && mounted) {
      _cancelled = true;
      Navigator.pop(context, widget.drafts);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.drafts.length;
    // 시안은 고정 72. 실제로는 진행률을 그대로 반영한다.
    final pct = total == 0 ? 72.0 : (_doneCount / total) * 100;
    final sub = SubscriptionService.instance;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: FnShell(
        navTitle: '',
        onBack: _confirmCancel,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 200,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const FnCircular(size: 40),
                const SizedBox(height: 28),
                Text(
                  _done ? '인식이 끝났어요' : '영수증을 읽고 있어요',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: FnColors.labelStrong,
                  ),
                ),
                // 기존 기능 유지: 몇 장 중 몇 번째인지
                if (total > 1) ...[
                  const SizedBox(height: 6),
                  Text(
                    '$total장 중 ${(_current + 1).clamp(1, total)}번째',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      color: FnColors.labelAlternative,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                // 시안 Pro 혜택 카드. 이미 PRO 면 안내가 필요 없으므로
                // 인식 결과를 고칠 수 있다는 팁으로 바꿔 보여준다.
                sub.isPro ? _proTipCard() : _proCard(),
                const SizedBox(height: 20),
                FnProgressBar(value: pct),
                const SizedBox(height: 8),
                // 기존 기능 유지: 진행 장수
                Text(
                  '$_doneCount / $total',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    color: FnColors.labelAssistive,
                  ),
                ),
                const SizedBox(height: 20),
                FnDsButton(
                  label: '결과 확인하기 →',
                  variant: FnDsButtonVariant.text,
                  disabled: !_done,
                  onPressed: _done
                      ? () => Navigator.pop(context, widget.drafts)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 시안 Pro 혜택 카드 1:1 (탭하면 PRO 안내로 이동 — 기능 추가)
  Widget _proCard() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: FnColors.lineNeutral),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('🔒', style: TextStyle(fontSize: 17)),
                SizedBox(width: 8),
                Text(
                  'Pro 업그레이드 시 혜택',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: FnColors.labelNormal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < _proBenefits.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '+',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.4,
                      color: FnColors.rose50,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _proBenefits[i],
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                        color: _bodyFg,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// PRO 사용자용 대체 카드 — 같은 레이아웃, 내용만 팁으로
  Widget _proTipCard() {
    const tips = [
      '인식 결과는 다음 화면에서 바로 고칠 수 있어요',
      '품목·단가·수량을 하나씩 확인해 주세요',
      '합계가 맞지 않으면 표시해 드려요',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FnColors.lineNeutral),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('💡', style: TextStyle(fontSize: 17)),
              SizedBox(width: 8),
              Text(
                '인식 결과를 확인할 때',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelNormal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < tips.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '+',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                    color: FnColors.rose50,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tips[i],
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                      color: _bodyFg,
                    ),
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
