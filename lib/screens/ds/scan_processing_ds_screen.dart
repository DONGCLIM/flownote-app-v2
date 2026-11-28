import 'package:flutter/material.dart';

import '../../design/fn_receipt_illust.dart';
import '../../design/fn_scan_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_sheet.dart';
import '../../services/gemini_ocr_service.dart';
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: FnShell(
        navTitle: '영수증 인식 중',
        bg: FnScan.bg,
        onBack: _confirmCancel,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              FnScan.procPad, 0, FnScan.procPad, 24),
          child: Column(
            children: [
              // 🔴 시안 실측 세로 배치 (473x1024, 1.2036 px/dp)
              //
              //   앱바끝  86.4
              //   일러스트 270.9-435.4  (h 164.5)
              //   제목     446.2-478.6
              //   부제     498.5-511.8
              //   카드     527.6-619.0  (h 91.4)
              //   버튼     624.8-690.5
              //
              // ⚠️ `Spacer(flex: 3/4)` 로 배치했더니 카드가 시안보다
              //    151dp 나 아래로 밀렸다. 시안은 비율이 아니라
              //    **고정 간격**이다. 비율 배치로 되돌리지 말 것.
              //
              // 글자 크기는 세로 잉크가 아니라 **가로 글자폭**으로 쟀다.
              // (세로 잉크로 재면 제목이 45dp 라는 엉뚱한 값이 나온다)
              //   제목 205.2dp / 8.6글자 = 23.9  -> 24
              //   부제 229.3dp / 17.5글자 = 13.1 -> 13
              // 시안: 앱바끝(86.4) → 일러스트(270.9) = 184.5dp.
              // 작은 화면에서는 이만큼 못 비우므로 Spacer 로 흡수한다.
              const Spacer(flex: 2),
              const SizedBox(height: 60),
              const Center(child: FnReceiptIllust(width: 208.0)),
              const SizedBox(height: 11),
              Text(
                _done ? '인식이 끝났어요' : '영수증을 읽고 있어요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: FnScan.ink,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                // 기존 기능 유지: 여러 장이면 몇 번째인지 알려준다.
                total > 1
                    ? '$total장 중 ${(_current + 1).clamp(1, total)}번째를 읽고 있어요.'
                    : '품목과 금액을 꼼꼼하게 정리하고 있어요.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                  color: FnScan.sub,
                ),
              ),
              const SizedBox(height: 16),
              _progressCard(pct, total),
              const SizedBox(height: 6),
              _cta(),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  /// 시안 흰 진행 카드 — `인식 진행 중` / `72%` + 진행바
  Widget _progressCard(double pct, int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: FnScan.card,
        borderRadius: BorderRadius.circular(FnScan.procCardRadius),
        boxShadow: FnScan.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _done ? '인식 완료' : '인식 진행 중',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FnScan.ink,
                ),
              ),
              Text(
                '${pct.round()}%',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FnScan.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 진행바 — 시안 트랙 #FFE3DF / 채움 #FB6F7A, 두께 8dp
          ClipRRect(
            borderRadius: BorderRadius.circular(FnScan.procBarH / 2),
            child: SizedBox(
              height: FnScan.procBarH,
              child: Stack(
                children: [
                  const ColoredBox(
                    color: FnScan.track,
                    child: SizedBox.expand(),
                  ),
                  FractionallySizedBox(
                    widthFactor: (pct / 100).clamp(0.0, 1.0),
                    child: const ColoredBox(
                      color: FnScan.coral,
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 기존 기능 유지: 몇 장 끝냈는지
          if (total > 1) ...[
            const SizedBox(height: 10),
            Text(
              '$_doneCount / $total장',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                color: FnScan.sub,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 시안 코랄 버튼 — 인식이 끝나야 눌린다.
  Widget _cta() {
    return GestureDetector(
      onTap: _done ? () => Navigator.pop(context, widget.drafts) : null,
      child: Container(
        height: FnScan.procBtnH,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _done ? FnScan.coralBtn : FnScan.coralBtn.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(FnScan.procBtnRadius),
        ),
        child: const Text(
          '결과 확인하기',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
