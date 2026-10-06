import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_button.dart';
import '../../services/gemini_ocr_service.dart';
import 'scan_draft.dart';

/// 인식 중 화면.
///
/// 촬영한 이미지들을 순차로 OCR 돌리면서 진행률을 보여준다.
/// 완료되면 `List<ScanDraft>` 를 pop 으로 반환.
class ScanProcessingScreen extends StatefulWidget {
  const ScanProcessingScreen({super.key, required this.drafts});

  final List<ScanDraft> drafts;

  @override
  State<ScanProcessingScreen> createState() => _ScanProcessingScreenState();
}

class _ScanProcessingScreenState extends State<ScanProcessingScreen>
    with TickerProviderStateMixin {
  final _ocr = GeminiOcrService();

  int _current = 0;
  bool _cancelled = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  static const _messages = [
    '영수증을 읽고 있어요',
    '품목을 찾고 있어요',
    '단가를 정리하고 있어요',
    '합계를 맞춰보고 있어요',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
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
    // 살짝 여운을 주고 닫기
    await Future.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    Navigator.pop(context, widget.drafts);
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: FnRadius.br20),
        backgroundColor: FnColors.backgroundElevated,
        title: Text('인식을 멈출까요?', style: FnType.heading2),
        content: Text(
          '지금까지 인식한 $_doneCount장은 그대로 넘어가요.',
          style: FnType.body2.copyWith(color: FnColors.labelAlternative),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('계속하기',
                style: FnType.label1.copyWith(color: FnColors.labelNeutral)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('멈추기',
                style: FnType.label1.copyWith(color: FnColors.primaryNormal)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      _cancelled = true;
      Navigator.pop(context, widget.drafts);
    }
  }

  int get _doneCount =>
      widget.drafts.where((d) => d.isSuccess || d.isFailed).length;

  @override
  Widget build(BuildContext context) {
    final total = widget.drafts.length;
    final progress = total == 0 ? 0.0 : _doneCount / total;
    final d = widget.drafts[math.min(_current, total - 1)];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: Scaffold(
        backgroundColor: FnColors.backgroundApp,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(FnSpace.x8),
                  child: FnIconButton(
                    icon: Icons.close_rounded,
                    onPressed: _confirmCancel,
                  ),
                ),
              ),
              const Spacer(),
              _Preview(file: d, pulse: _pulse),
              const SizedBox(height: FnSpace.x32),
              Text(
                total > 1 ? '$total장 중 ${_current + 1}번째' : '영수증을 읽는 중',
                style: FnType.caption1
                    .copyWith(color: FnColors.labelAlternative),
              ),
              const SizedBox(height: FnSpace.x8),
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final idx =
                      (_pulse.value * _messages.length).floor() %
                          _messages.length;
                  return AnimatedSwitcher(
                    duration: FnDuration.normal,
                    child: Text(
                      _messages[idx],
                      key: ValueKey(idx),
                      style: FnType.heading2,
                    ),
                  );
                },
              ),
              const SizedBox(height: FnSpace.x24),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: FnSpace.x48),
                child: ClipRRect(
                  borderRadius: FnRadius.brFull,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: FnDuration.normal,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor: FnColors.fillNormal,
                      valueColor: const AlwaysStoppedAnimation(
                          FnColors.primaryNormal),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: FnSpace.x12),
              Text(
                '$_doneCount / $total',
                style: FnType.caption1
                    .copyWith(color: FnColors.labelAssistive),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    FnSpace.x20, 0, FnSpace.x20, FnSpace.x24),
                child: Container(
                  padding: const EdgeInsets.all(FnSpace.x12),
                  decoration: BoxDecoration(
                    color: FnColors.rose99,
                    borderRadius: FnRadius.br12,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.tips_and_updates_outlined,
                          size: 18, color: FnColors.primaryNormal),
                      const SizedBox(width: FnSpace.x8),
                      Expanded(
                        child: Text(
                          '인식 결과는 다음 화면에서 바로 고칠 수 있어요.',
                          style: FnType.caption1
                              .copyWith(color: FnColors.labelNeutral),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.file, required this.pulse});

  final ScanDraft file;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: FnRadius.br20,
            child: kIsWeb
                ? Container(
                    width: 200,
                    height: 260,
                    color: FnColors.neutral97,
                    child: const Icon(Icons.receipt_long_rounded,
                        size: 56, color: FnColors.neutral80),
                  )
                : Image.file(
                    File(file.file.path),
                    width: 200,
                    height: 260,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 200,
                      height: 260,
                      color: FnColors.neutral97,
                      child: const Icon(Icons.receipt_long_rounded,
                          size: 56, color: FnColors.neutral80),
                    ),
                  ),
          ),
          // 스캔 라인
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(
                  (math.sin(pulse.value * math.pi * 2) + 1) / 2);
              return Positioned(
                top: 8 + t * 236,
                child: Container(
                  width: 184,
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      FnColors.primaryNormal.withValues(alpha: 0),
                      FnColors.primaryNormal,
                      FnColors.primaryNormal.withValues(alpha: 0),
                    ]),
                    boxShadow: [
                      BoxShadow(
                        color: FnColors.primaryNormal.withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          IgnorePointer(
            child: Container(
              width: 200,
              height: 260,
              decoration: BoxDecoration(
                borderRadius: FnRadius.br20,
                border: Border.all(
                    color: FnColors.primaryNormal.withValues(alpha: 0.6),
                    width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
