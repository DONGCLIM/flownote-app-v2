import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/pwa_install.dart';
import '../../theme/fn_ds.dart';
import '../../widgets/fn_inquiry_parts.dart';

/// "바탕화면에 설치하기" 안내창. (#182)
///
/// 사장님 지시: 로그인 화면과 프로필에서 부르고, **지금 상황에 맞는 단계만**
/// 보여 준다. 다른 상황 단계를 같이 늘어놓으면 어느 걸 따라야 할지 몰라서
/// 오히려 못 하신다.
///
/// ## 상황별로 하는 일
///
/// | 지금 열린 곳 | 하는 일 |
/// |---|---|
/// | 카카오톡 안 | **외부 브라우저로 자동 전환.** 안 넘어가면 안내창 |
/// | 인스타그램·그 밖 인앱 | 안내창(사파리·크롬으로 옮기는 법) + 주소 복사 |
/// | 아이폰 사파리 | 안내창(공유 → 홈 화면에 추가) + "설치했어요" |
/// | 안드로이드 크롬 | **설치창을 바로 띄운다.** 안 뜨면 안내창(⋮ → 설치) |
/// | PC | 안내창(주소창 설치 아이콘) |
///
/// 🔴 잘못된 안내(예: 아이폰에 "설치" 버튼)를 보여주면 눌러도 아무 일이
///    없어서 더 답답해진다. 그래서 `pwaState()` 로 정확히 갈라준다.
class AddToHomeSheet extends StatefulWidget {
  const AddToHomeSheet._({required this.state});

  final PwaInstallState state;

  /// 설치를 시작한다.
  ///
  /// 상황에 따라 **안내창을 띄우지 않고 바로 처리**하기도 한다.
  ///  - 안드로이드 크롬: 브라우저 설치창을 바로 띄운다
  ///  - 카카오톡: 외부 브라우저로 자동 전환을 먼저 시도한다
  static Future<void> open(BuildContext context) async {
    final st = pwaState();

    // ── 안드로이드 크롬 — 설치창을 바로 띄운다 ────────────────────
    if (st.canPrompt) {
      final r = await pwaPromptInstall();
      if (!context.mounted) return;
      if (r == PwaPromptResult.installed) return; // 끝. 더 보여줄 게 없다.
      if (r == PwaPromptResult.dismissed) return; // 사장님이 취소하셨다.
      // unavailable — 설치창이 안 떴다. 손으로 하는 법을 안내한다.
      return _show(context, pwaState());
    }

    // ── 카카오톡 — 외부 브라우저로 옮겨 준다 ──────────────────────
    if (st.howTo == PwaHowTo.inAppKakao) {
      if (pwaOpenExternalBrowser()) {
        // 넘어가면 이 화면이 가려진다. 잠깐 기다렸다가 아직 보이면
        // 전환이 안 된 것이므로 손으로 옮기는 법을 안내한다.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!context.mounted) return;
        if (!pwaPageVisible()) return;
      }
      if (!context.mounted) return;
      return _show(context, st);
    }

    return _show(context, st);
  }

  static Future<void> _show(BuildContext context, PwaInstallState st) {
    // 🔴 공용 `showFnSheet` 를 쓰지 않는다. 그 시트는 옛 토큰(`FnColors`)
    //    으로 머리글을 그려서, 이 화면만 색·글씨가 달라진다. 시트 껍데기를
    //    여기서 FnDs 로 그리되 **이 파일 밖으로 내보내지 않는다**(복제 방지).
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => AddToHomeSheet._(state: st),
    );
  }

  @override
  State<AddToHomeSheet> createState() => _AddToHomeSheetState();
}

class _AddToHomeSheetState extends State<AddToHomeSheet> {
  bool _busy = false;

  PwaInstallState get _st => widget.state;

  void _close() => Navigator.of(context).maybePop();

  /// 주소를 복사한다. 인앱 브라우저에서 사파리·크롬으로 옮길 때 쓴다.
  Future<void> _copyUrl() async {
    final url = _st.url;
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    Navigator.of(context).maybePop();
    _toast(_st.onIos
        ? '복사했어요. 사파리 주소창에 붙여 넣어 주세요'
        : '복사했어요. 크롬 주소창에 붙여 넣어 주세요');
  }

  /// 아이폰은 설치됐는지 앱이 알 수 없다. 사장님 말씀을 믿고 안내만 한다.
  void _doneIos() {
    Navigator.of(context).maybePop();
    _toast('바탕화면의 FlowNote 아이콘으로 열어 로그인해 주세요');
  }

  Future<void> _retryPrompt() async {
    setState(() => _busy = true);
    final r = await pwaPromptInstall();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == PwaPromptResult.installed) {
      Navigator.of(context).maybePop();
      _toast('설치했어요. 바탕화면 아이콘으로 열어 주세요');
    }
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: FnDs.font)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: FnDs.card,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(FnDs.cardRadius)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 손잡이 ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: FnDs.gapXs, bottom: 2),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FnDs.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              // ── 제목 + 닫기 ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    FnDs.pagePad, FnDs.gapS, FnDs.gapXs, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(plan.title, style: FnDs.tsTitle),
                          if (plan.subtitle != null) ...[
                            const SizedBox(height: FnDs.gap2xs),
                            Text(plan.subtitle!,
                                style: const TextStyle(
                                  fontFamily: FnDs.font,
                                  fontSize: FnDs.fontS,
                                  height: 1.5,
                                  color: FnDs.body,
                                )),
                          ],
                        ],
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _close,
                      child: const Padding(
                        padding: EdgeInsets.all(FnDs.gapS),
                        child: Icon(Icons.close_rounded,
                            size: 20, color: FnDs.sub),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                      FnDs.pagePad, FnDs.gapM, FnDs.pagePad, FnDs.gapM),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < plan.steps.length; i++) ...[
                        if (i > 0) const SizedBox(height: FnDs.gapM),
                        _StepRow(no: i + 1, step: plan.steps[i]),
                      ],
                      if (plan.note != null) ...[
                        const SizedBox(height: FnDs.gapM),
                        Text(
                          plan.note!,
                          style: const TextStyle(
                            fontFamily: FnDs.font,
                            fontSize: FnDs.fontXs,
                            height: 1.5,
                            color: FnDs.sub,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // ── 메인 버튼 ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    FnDs.pagePad, 0, FnDs.pagePad, FnDs.gapS),
                child: FnPrimaryButton(
                  label: plan.action,
                  busy: _busy,
                  onTap: _busy ? null : plan.onAction,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 지금 상황에 맞는 **한 가지** 안내만 만든다.
  _Plan _plan() {
    final ios = _st.onIos;

    switch (_st.howTo) {
      // ── 인앱 브라우저 ──────────────────────────────────────────
      case PwaHowTo.inAppKakao:
      case PwaHowTo.inAppInstagram:
      case PwaHowTo.inAppOther:
        return _Plan(
          title: ios
              ? '사파리에서 열면 바로 설치할 수 있어요'
              : '크롬에서 열면 바로 설치할 수 있어요',
          subtitle: '바탕화면 설치는 사파리·크롬에서만 할 수 있어서, 한 번만 옮겨 주세요.',
          steps: ios
              ? const [
                  _Step('오른쪽 위 ', icon: _StepIcon.more, tail: ' 누르기'),
                  _Step('"외부 브라우저에서 열기" 누르기'),
                ]
              : const [
                  _Step('오른쪽 위 ', icon: _StepIcon.vmore, tail: ' 누르기'),
                  _Step('"Chrome에서 열기" 누르기'),
                ],
          action: '주소 복사하기',
          onAction: _copyUrl,
        );

      // ── 아이폰 사파리 ──────────────────────────────────────────
      case PwaHowTo.iosSafari:
        return _Plan(
          title: '바탕화면에 설치하기',
          subtitle: '한 번 설치하면 앱처럼 바로 열려요.',
          steps: const [
            _Step('화면 아래 맨 왼쪽 ', icon: _StepIcon.more, tail: ' 누르기'),
            _Step('"공유" ', icon: _StepIcon.share, tail: ' 누르기'),
            _Step('맨 아래 "더보기" 누르기'),
            _Step('"홈 화면에 추가" ', icon: _StepIcon.add, tail: ' 누르기'),
          ],
          note: '메뉴가 다르게 보이면 아래 공유 버튼 → 홈 화면에 추가',
          action: '설치했어요',
          onAction: _doneIos,
        );

      // ── 아이폰인데 사파리가 아니다 ──────────────────────────────
      case PwaHowTo.iosOther:
        return _Plan(
          title: '사파리에서 열면 바로 설치할 수 있어요',
          subtitle: '바탕화면 설치는 사파리에서만 할 수 있어서, 한 번만 옮겨 주세요.',
          steps: const [
            _Step('아래 "주소 복사하기" 누르기'),
            _Step('사파리를 열고 주소창에 붙여 넣기'),
          ],
          action: '주소 복사하기',
          onAction: _copyUrl,
        );

      // ── 안드로이드 — 설치창이 안 떴다 ───────────────────────────
      case PwaHowTo.androidManual:
      case PwaHowTo.androidPrompt:
        return _Plan(
          title: '바탕화면에 설치하기',
          subtitle: '한 번 설치하면 앱처럼 바로 열려요.',
          steps: const [
            _Step('오른쪽 위 ', icon: _StepIcon.vmore, tail: ' 누르기'),
            _Step('"홈 화면에 추가" 또는 "앱 설치" ',
                icon: _StepIcon.add, tail: ' 누르기'),
            _Step('"설치" 누르기'),
          ],
          action: '다시 시도하기',
          onAction: _retryPrompt,
        );

      // ── PC ────────────────────────────────────────────────────
      case PwaHowTo.desktop:
        return _Plan(
          title: '바탕화면에 설치하기',
          subtitle: '한 번 설치하면 앱처럼 바로 열려요.',
          steps: const [
            _Step('주소창 오른쪽 ', icon: _StepIcon.add, tail: ' 누르기'),
            _Step('"설치" 누르기'),
          ],
          action: _st.canPrompt ? '지금 설치하기' : '알겠어요',
          onAction: _st.canPrompt ? _retryPrompt : _close,
        );

      // ── 그 밖 ─────────────────────────────────────────────────
      case PwaHowTo.unknown:
      case PwaHowTo.notWeb:
      case PwaHowTo.alreadyInstalled:
        return _Plan(
          title: '바탕화면에 설치하기',
          subtitle: '한 번 설치하면 앱처럼 바로 열려요.',
          steps: const [
            _Step('브라우저 메뉴 ', icon: _StepIcon.vmore, tail: ' 누르기'),
            _Step('"홈 화면에 추가" ', icon: _StepIcon.add, tail: ' 누르기'),
          ],
          action: '알겠어요',
          onAction: _close,
        );
    }
  }
}

/// 한 상황에 보여 줄 안내 묶음.
class _Plan {
  const _Plan({
    required this.title,
    required this.steps,
    required this.action,
    required this.onAction,
    this.subtitle,
    this.note,
  });

  final String title;
  final String? subtitle;
  final List<_Step> steps;
  final String? note;
  final String action;
  final VoidCallback onAction;
}

/// 문장 안에 넣을 버튼 모양.
///
/// 🔴 스크린샷을 쓰지 않는다(사장님 지시). 글자 사이에 **실제 버튼 모양**을
///    작게 그려 넣어, 폰 화면에서 무엇을 찾아야 하는지 바로 알게 한다.
enum _StepIcon {
  /// 가로 점 셋 — 사파리 아래쪽 메뉴, 인앱 브라우저 오른쪽 위.
  more,

  /// 세로 점 셋 — 크롬 오른쪽 위.
  vmore,

  /// 공유 — 네모에서 위로 나가는 화살표.
  share,

  /// 추가 — 동그라미 안 더하기.
  add,
}

class _Step {
  const _Step(this.text, {this.icon, this.tail});

  final String text;
  final _StepIcon? icon;

  /// 아이콘 뒤에 붙는 글자.
  final String? tail;
}

/// 코랄 번호 원 + 문장 한 줄.
class _StepRow extends StatelessWidget {
  const _StepRow({required this.no, required this.step});

  final int no;
  final _Step step;

  static const _text = TextStyle(
    fontFamily: FnDs.font,
    fontSize: FnDs.fontM,
    height: 1.5,
    color: FnDs.title,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(top: 1),
          decoration: const BoxDecoration(
            color: FnDs.coral,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$no',
            style: const TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.fontXs,
              fontWeight: FontWeight.w800,
              color: FnDs.onCoral,
            ),
          ),
        ),
        const SizedBox(width: FnDs.gapS),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: step.text),
                if (step.icon != null)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _IconChip(kind: step.icon!),
                  ),
                if (step.tail != null) TextSpan(text: step.tail),
              ],
            ),
            style: _text,
          ),
        ),
      ],
    );
  }
}

/// 문장 안에 들어가는 작은 버튼 그림.
class _IconChip extends StatelessWidget {
  const _IconChip({required this.kind});

  final _StepIcon kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: FnDs.coralFaint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: switch (kind) {
        // 사파리 아래쪽 '···' 은 아이콘이 없어서 글자로 그린다.
        _StepIcon.more => const Text(
            '···',
            style: TextStyle(
              fontFamily: FnDs.font,
              fontSize: 15,
              height: 1,
              fontWeight: FontWeight.w900,
              color: FnDs.coral,
            ),
          ),
        _StepIcon.vmore =>
          const Icon(Icons.more_vert_rounded, size: 15, color: FnDs.coral),
        _StepIcon.share =>
          const Icon(Icons.ios_share_rounded, size: 15, color: FnDs.coral),
        _StepIcon.add => const Icon(Icons.add_circle_outline_rounded,
            size: 15, color: FnDs.coral),
      },
    );
  }
}
