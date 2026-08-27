import 'package:flutter/material.dart';

import '../../design/fn_button.dart';
import '../../design/fn_sheet.dart';
import '../../design/fn_tokens.dart';
import '../../services/pwa_install.dart';

/// "홈 화면에 추가" 안내 시트.
///
/// 사장님이 웹으로 쓰다가 "이거 홈화면 추가 어떻게 하는거야?" 라고 물었을 때
/// 바로 답이 되도록 만든 화면이다.
///
/// 브라우저마다 방식이 다르기 때문에 **한 가지 안내만 보여주면 안 된다.**
///  - 안드로이드 크롬: 버튼 한 번으로 설치창이 뜬다 → 버튼을 준다.
///  - 아이폰 사파리: API 가 없다 → 공유 버튼 위치를 그림으로 설명한다.
///  - 아이폰의 다른 브라우저: 아예 안 된다 → 사파리로 열라고 말해준다.
///
/// 잘못된 안내(예: 아이폰에 "설치" 버튼)를 보여주면 눌러도 아무 일이
/// 없어서 더 답답해진다. 그래서 `pwaState()` 로 정확히 갈라준다.
class AddToHomeSheet extends StatefulWidget {
  const AddToHomeSheet({super.key});

  /// 시트를 띄운다.
  static Future<void> open(BuildContext context) {
    return showFnSheet<void>(
      context,
      title: '홈 화면에 추가하기',
      subtitle: '앱처럼 한 번에 열 수 있어요',
      child: const AddToHomeSheet(),
    );
  }

  @override
  State<AddToHomeSheet> createState() => _AddToHomeSheetState();
}

class _AddToHomeSheetState extends State<AddToHomeSheet> {
  late PwaInstallState _state = pwaState();
  bool _busy = false;
  String? _msg;

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    final r = await pwaPromptInstall();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _state = pwaState();
      switch (r) {
        case PwaPromptResult.installed:
          _msg = '홈 화면에 추가했어요. 이제 바탕화면에서 바로 열 수 있어요.';
        case PwaPromptResult.dismissed:
          _msg = '취소하셨어요. 언제든 다시 누르시면 됩니다.';
        case PwaPromptResult.unavailable:
          // 프롬프트가 사라진 경우(이미 설치했거나 브라우저가 회수).
          // 수동 안내로 자연스럽게 넘어간다.
          _msg = '브라우저가 설치창을 띄우지 못했어요. 아래 방법으로 해보세요.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 왜 하는지 — 한 줄 이득.
        const _WhyCard(),
        const SizedBox(height: FnSpace.x20),

        ..._body(st),

        if (_msg != null) ...[
          const SizedBox(height: FnSpace.x16),
          _Note(_msg!),
        ],

        const SizedBox(height: FnSpace.x24),
        FnButton(
          label: '알겠어요',
          expand: true,
          variant: FnButtonVariant.outlined,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(height: FnSpace.x8),
      ],
    );
  }

  List<Widget> _body(PwaInstallState st) {
    switch (st.howTo) {
      case PwaHowTo.alreadyInstalled:
        return const [
          _Done(
            title: '이미 홈 화면에서 실행 중이에요',
            body: '따로 하실 게 없습니다. 지금처럼 바탕화면 아이콘으로 열면 돼요.',
          ),
        ];

      case PwaHowTo.notWeb:
        return const [
          _Done(
            title: '앱으로 설치된 상태예요',
            body: '스토어에서 설치한 앱이라 홈 화면 추가가 이미 끝나 있습니다.',
          ),
        ];

      case PwaHowTo.androidPrompt:
        return [
          const _Steps(
            title: '버튼 한 번이면 끝나요',
            steps: [
              '아래 [홈 화면에 추가] 버튼을 누르세요.',
              '브라우저가 물어보면 [설치] 를 누르세요.',
              '바탕화면에 FlowNote 아이콘이 생깁니다.',
            ],
          ),
          const SizedBox(height: FnSpace.x20),
          FnButton(
            label: '홈 화면에 추가',
            expand: true,
            leadingIcon: Icons.add_to_home_screen_rounded,
            loading: _busy,
            onPressed: _busy ? null : _install,
          ),
          const SizedBox(height: FnSpace.x12),
          const _Fold(
            label: '버튼이 안 되면 이렇게 해주세요',
            steps: _androidManualSteps,
          ),
        ];

      case PwaHowTo.androidManual:
        return const [
          _Steps(
            title: '크롬 메뉴에서 추가할 수 있어요',
            steps: _androidManualSteps,
          ),
          SizedBox(height: FnSpace.x16),
          _Note(
            '삼성 인터넷은 메뉴 이름이 "현재 페이지 추가" 입니다. '
            '카카오톡·네이버 앱 안에서 열었다면 먼저 크롬으로 열어주세요.',
          ),
        ];

      case PwaHowTo.iosSafari:
        return const [
          _Steps(
            title: '사파리 공유 버튼에서 추가해요',
            steps: [
              '화면 아래쪽 가운데 공유 버튼(⬆︎ 네모에 위쪽 화살표)을 누르세요.',
              '올라온 목록을 위로 밀어 [홈 화면에 추가] 를 찾으세요.',
              '오른쪽 위 [추가] 를 누르면 끝입니다.',
            ],
          ),
          SizedBox(height: FnSpace.x16),
          _Note(
            '아이폰은 브라우저가 설치창을 띄우는 기능을 지원하지 않아서 '
            '이 방법 하나뿐입니다. 공유 버튼은 주소창을 한 번 누르면 나타나요.',
          ),
        ];

      case PwaHowTo.iosOther:
        return const [
          _Steps(
            title: '먼저 사파리로 열어주세요',
            steps: [
              '지금 브라우저에서 주소를 복사하세요.',
              '사파리를 열고 주소창에 붙여넣어 접속하세요.',
              '아래쪽 공유 버튼 → [홈 화면에 추가] 를 누르세요.',
            ],
          ),
          SizedBox(height: FnSpace.x16),
          _Note(
            '아이폰에서는 사파리에서만 홈 화면 추가가 됩니다. '
            '크롬·네이버·카카오톡 안에서는 이 기능이 막혀 있어요.',
          ),
        ];

      case PwaHowTo.desktop:
        return [
          const _Steps(
            title: 'PC 에서도 앱처럼 쓸 수 있어요',
            steps: [
              '주소창 오른쪽의 설치 아이콘(⊕ 또는 모니터 모양)을 누르세요.',
              '아이콘이 없으면 우측 상단 ⋮ → [앱 설치] 를 누르세요.',
              '설치하면 별도 창으로 열립니다.',
            ],
          ),
          if (st.canPrompt) ...[
            const SizedBox(height: FnSpace.x20),
            FnButton(
              label: '지금 설치',
              expand: true,
              leadingIcon: Icons.install_desktop_rounded,
              loading: _busy,
              onPressed: _busy ? null : _install,
            ),
          ],
          const SizedBox(height: FnSpace.x16),
          const _Note('휴대폰에서 하시려면 폰 브라우저로 같은 주소를 열어주세요.'),
        ];

      case PwaHowTo.unknown:
        return const [
          _Steps(
            title: '브라우저 메뉴에서 추가할 수 있어요',
            steps: [
              '브라우저 메뉴(⋮ 또는 공유 버튼)를 누르세요.',
              '[홈 화면에 추가] 또는 [앱 설치] 를 누르세요.',
              '이름을 확인하고 [추가] 를 누르세요.',
            ],
          ),
        ];
    }
  }
}

const _androidManualSteps = [
  '크롬 오른쪽 위 ⋮ 버튼을 누르세요.',
  '[홈 화면에 추가] 를 누르세요.',
  '[설치] 또는 [추가] 를 누르면 끝입니다.',
];

// ─────────────────────────────────────────────────────────────
// 부분 위젯
// ─────────────────────────────────────────────────────────────

class _WhyCard extends StatelessWidget {
  const _WhyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FnSpace.x16),
      decoration: BoxDecoration(
        color: FnColors.rose95,
        borderRadius: FnRadius.br12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: FnRadius.br10,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.phonelink_ring_rounded,
              size: 22,
              color: FnColors.primaryNormal,
            ),
          ),
          const SizedBox(width: FnSpace.x12),
          const Expanded(
            child: Text(
              '홈 화면에 추가하면 주소를 칠 필요 없이 아이콘 하나로 열려요.\n'
              '주소창도 사라져서 앱처럼 화면이 넓어집니다.',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                height: 1.5,
                color: FnColors.labelNeutral,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.title, required this.steps});

  final String title;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: FnSpace.x14),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == steps.length - 1 ? 0 : FnSpace.x12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: const BoxDecoration(
                    color: FnColors.primaryNormal,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: FnSpace.x10),
                Expanded(
                  child: Text(
                    steps[i],
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      height: 1.5,
                      color: FnColors.labelNormal,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 접어둔 보조 안내 (버튼이 안 될 때).
class _Fold extends StatefulWidget {
  const _Fold({required this.label, required this.steps});

  final String label;
  final List<String> steps;

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: FnRadius.br8,
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: FnSpace.x6),
            child: Row(
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: FnColors.labelAlternative,
                  ),
                ),
                const SizedBox(width: FnSpace.x4),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: FnColors.labelAlternative,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: FnSpace.x8),
            child: _Steps(title: '', steps: widget.steps),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FnSpace.x12),
      decoration: BoxDecoration(
        color: FnColors.backgroundAlternative,
        borderRadius: FnRadius.br10,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          height: 1.5,
          color: FnColors.labelAlternative,
        ),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 20,
              color: FnColors.statusPositive,
            ),
            const SizedBox(width: FnSpace.x8),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: FnColors.labelNormal,
              ),
            ),
          ],
        ),
        const SizedBox(height: FnSpace.x10),
        Text(
          body,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 15,
            height: 1.5,
            color: FnColors.labelNeutral,
          ),
        ),
      ],
    );
  }
}
