import 'package:flutter/material.dart';

import '../../design/fn_brand.dart';
import '../../design/fn_tokens.dart';

/// 🔴 #124 — 로그인 **앞**에 붙는 인트로.
///
/// ## 사장님 지시
/// > "스플래쉬는 잠깐 띄워지는 이미지로 가면 되겠고, 나머지는 PNG를
/// >  통째로 넣는게 아니라 이 이미지로 앱 화면을 너가 만들어야지.
/// >  건너뛰기, 다음 이런 것도 누르면 넘어갈 수 있도록.
/// >  PNG는 이미지 참고용이야. 일회성 말고 계속 띄워지도록."
///
/// 그래서 이렇게 나눴다.
///
/// ```
///   스플래시  splash.png 통째로, 1.4초 뒤 자동으로 넘어간다
///   1~3번     일러스트만 PNG, 제목·본문·버튼·점은 **앱 위젯**
/// ```
///
/// ## 시안에서 잰 값 (471 x 980 원본 -> 화면 비율로 환산)
/// ```
///   일러스트      0 ~ 624px      (화면 높이의 63.7%)
///   제목          634 ~ 706      28dp / w800 / #111111 / 줄높이 1.34
///   본문          734 ~ 771      13dp / w500 / #A1A09E / 줄높이 1.55
///   버튼          864 ~ 877      13dp, 아래에서 85dp
///   좌우 여백     53px           화면의 11.25%
/// ```
class IntroSlide {
  const IntroSlide({
    required this.art,
    required this.title,
    required this.body,
  });

  /// 일러스트만 잘라낸 그림. (471 x 624)
  final String art;
  final String title;
  final String body;

  /// 일러스트 원본 비율.
  static const double artRatio = 471 / 624;

  /// 일러스트가 차지하는 화면 높이 비율. (624 / 980)
  static const double artHeightFactor = 624 / 980;

  /// 좌우 여백 비율. (53 / 471)
  static const double sidePadFactor = 53 / 471;

  /// 시안 문구 그대로. (고해상도 PNG 에서 한 글자씩 옮겼다)
  static const List<IntroSlide> all = [
    IntroSlide(
      art: 'assets/onboarding/art_1.png',
      title: '쌓이는 영수증,\n촬영으로 간편하게',
      body: '꽃 사입 내역을 일일이 적지 않아도\n품목과 금액을 읽어 정리해 드려요.',
    ),
    IntroSlide(
      art: 'assets/onboarding/art_2.png',
      title: '우리 가게 지출을\n한눈에 확인해요',
      body: '월별 지출부터 품목별 비중까지\n복잡한 사입 내역을 쉽게 파악해요.',
    ),
    IntroSlide(
      art: 'assets/onboarding/art_3.png',
      title: '쌓인 기록으로\n다음 사입도 똑똑하게',
      body: '우리 가게에 맞는 사입 가이드로\n다음 꽃시장 방문을 준비해요.',
    ),
  ];
}

/// 시안에서 뽑은 색.
class IntroColors {
  static const Color bgTop = Color(0xFFFDF2EF);
  static const Color bgBottom = Color(0xFFFEFDFB);
  static const Color title = Color(0xFF111111);
  static const Color body = Color(0xFFA1A09E);
  static const Color dotOff = Color(0xFFD5D5D8);
  static const Color accent = FnColors.rose50;

  /// 스플래시 태그라인. 시안 실측 #767676.
  static const Color splashTagline = Color(0xFF767676);
}

const _bgGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [IntroColors.bgTop, IntroColors.bgBottom],
  stops: [0.0, 0.66],
);

/// 스플래시 — **앱 화면으로 그린다.** (#126)
///
/// 사장님 지시:
/// > "스플래쉬도 PNG 파일을 그대로 반영하는게 아니라, 앱 화면으로
/// >  해주되 지금처럼 잠깐 비춰지는 이미지가 될 수 있도록"
///
/// 그래서 그림을 깔지 않고 배경·로고·워드마크·태그라인을 모두 위젯으로
/// 그린다. '잠깐 비춰지는' 동작은 `main.dart` 가 1.4초 뒤 넘기는 것으로
/// 그대로 유지한다. 여기에 **부드럽게 떠오르는 애니메이션**을 넣어
/// 스쳐 지나가는 느낌을 살린다.
///
/// ## 시안에서 픽셀로 잰 값 (471 x 980 -> 390dp)
/// ```
///   배경      위 #FFEDE9 ~ 아래 #FEFDFB (위쪽이 따뜻한 복숭아색)
///   로고      91dp (글로우 포함) · 워드마크 33dp · 태그라인 12dp
///   간격      로고->워드마크 9dp · 워드마크->태그라인 17dp
///   블록 중심 화면 세로의 0.471 (중앙보다 2.9% 위)
/// ```
class IntroSplash extends StatefulWidget {
  const IntroSplash({super.key});

  @override
  State<IntroSplash> createState() => _IntroSplashState();
}

class _IntroSplashState extends State<IntroSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    duration: const Duration(milliseconds: 620),
    vsync: this,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );

  late final Animation<double> _rise = Tween<double>(begin: 14, end: 0).animate(
    CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // 시안 배경: 위쪽이 따뜻하고 아래로 가며 흰색이 된다.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFEDE9),
            Color(0xFFFFF3EF),
            Color(0xFFFEFDFB),
          ],
          stops: [0.0, 0.34, 0.72],
        ),
      ),
      child: Center(
        // 시안의 블록 중심은 화면 중앙보다 2.9% 위에 있다.
        child: FractionalTranslation(
          translation: const Offset(0, -0.058),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Opacity(
              opacity: _fade.value,
              child: Transform.translate(
                offset: Offset(0, _rise.value),
                child: child_,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget get child_ => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 로고 — 글로우가 그려진 판을 쓴다. (요청 #116)
          const FnAppMark(size: 92, glow: true),
          const SizedBox(height: 6),
          const FnWordmark(height: 33),
          const SizedBox(height: 16),
          Text(
            '꽃은 아름답게, 정산은 정확하게 플로우노트',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.4,
              color: IntroColors.splashTagline,
            ),
          ),
        ],
      );
}

/// 1~3번 인트로 — **앱 화면으로 만들었다.**
///
/// 일러스트만 그림이고, 제목·본문·건너뛰기·점·다음은 모두 위젯이다.
/// 그래서 어떤 화면 크기에서도 글자가 늘어나거나 잘리지 않고,
/// 버튼은 실제 버튼으로 눌린다.
class IntroDsScreen extends StatefulWidget {
  const IntroDsScreen({super.key, required this.onDone});

  /// 인트로가 끝났을 때. 보통 로그인 화면으로 넘어간다.
  final VoidCallback onDone;

  @override
  State<IntroDsScreen> createState() => _IntroDsScreenState();
}

class _IntroDsScreenState extends State<IntroDsScreen> {
  final _pager = PageController();
  int _page = 0;

  List<IntroSlide> get _slides => IntroSlide.all;
  bool get _isLast => _page == _slides.length - 1;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onDone();
      return;
    }
    _pager.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IntroColors.bgBottom,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: _bgGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              // 좌우 여백은 시안 비율(11.25%)을 쓰되 너무 벌어지지 않게 묶는다.
              final pad = (c.maxWidth * IntroSlide.sidePadFactor).clamp(20.0, 40.0);
              return Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pager,
                      itemCount: _slides.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) => _Slide(
                        slide: _slides[i],
                        sidePad: pad,
                      ),
                    ),
                  ),
                  _BottomBar(
                    sidePad: pad,
                    page: _page,
                    total: _slides.length,
                    isLast: _isLast,
                    onSkip: widget.onDone,
                    onNext: _next,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 한 장 — 일러스트 + 제목 + 본문.
class _Slide extends StatelessWidget {
  const _Slide({required this.slide, required this.sidePad});

  final IntroSlide slide;
  final double sidePad;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // 시안에서 일러스트는 화면 높이의 63.7% 를 쓴다. 다만 화면이
        // 짧으면 글이 잘리므로, 글에 필요한 자리를 먼저 떼고 남는 만큼만
        // 그림에 준다.
        const textRoom = 170.0;
        final artH = (c.maxHeight * IntroSlide.artHeightFactor)
            .clamp(0.0, (c.maxHeight - textRoom).clamp(0.0, c.maxHeight));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 일러스트 ─────────────────────────────────────
            //
            // 🔴 #126 꽉 채우기(cover)를 버리고 **전체가 보이게** 한다.
            //
            // 측정해 보니 잘림이 이랬다.
            //   아이폰 14    (390x844)  위아래  3.4%
            //   갤럭시 S     (412x915)  위아래  0.3%
            //   아이폰 ProMax(430x932)  위아래  2.5%
            //   태블릿       (768x1024) 위아래 39.7%
            //
            // 휴대폰은 괜찮았지만 태블릿에서 40% 가까이 잘렸다. 영수증
            // 금액처럼 중요한 부분이 사라질 수 있다. 그래서 contain 으로
            // 바꿔 **한 픽셀도 안 잘리게** 한다. 남는 자리는 배경
            // 그라디언트가 그대로 비쳐서 티가 나지 않는다.
            SizedBox(
              height: artH,
              child: Image.asset(
                slide.art,
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

            // ── 제목 · 본문
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(sidePad, 14, sidePad, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slide.title,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 26,
                        height: 1.34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: IntroColors.title,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      slide.body,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13.5,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                        color: IntroColors.body,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 하단 줄 — 건너뛰기 · 점 · 다음/시작하기.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.sidePad,
    required this.page,
    required this.total,
    required this.isLast,
    required this.onSkip,
    required this.onNext,
  });

  final double sidePad;
  final int page;
  final int total;
  final bool isLast;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(sidePad - 6, 0, sidePad - 6, 26),
      child: Row(
        children: [
          _TapText(
            label: '건너뛰기',
            color: const Color(0xFF8E8D8B),
            weight: FontWeight.w500,
            onTap: onSkip,
          ),
          const Spacer(),
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            _Dot(active: i == page),
          ],
          const Spacer(),
          _TapText(
            label: isLast ? '시작하기' : '다음',
            color: IntroColors.accent,
            weight: FontWeight.w700,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

/// 인디케이터 점. 지금 장만 분홍 알약으로 늘어난다. (시안 그대로)
class _Dot extends StatelessWidget {
  const _Dot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      width: active ? 22 : 7,
      height: 7,
      decoration: BoxDecoration(
        color: active ? IntroColors.accent : IntroColors.dotOff,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// 글자 버튼. 🔴 글자만 있으면 손가락이 빗나가므로 눌리는 면을 넓힌다.
class _TapText extends StatelessWidget {
  const _TapText({
    required this.label,
    required this.color,
    required this.weight,
    required this.onTap,
  });

  final String label;
  final Color color;
  final FontWeight weight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: weight,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
