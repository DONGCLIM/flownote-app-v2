import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🔴 #121/#122 — 로그인 **앞**에 붙는 인트로 화면.
///
/// ## 사장님 지시
/// > "내가 준 이미지랑 텍스트가 그대로 들어가야지 왜 배경만 만들어.
/// >  이거 그대로 만들어줘"
///
/// 그래서 **시안 PNG 를 통째로 화면에 깐다.** 제목·본문·버튼 글자·
/// 인디케이터까지 전부 그림 안에 있는 그대로 쓴다. 코드로 글자를
/// 다시 그리지 않는다.
///
/// ## 딱 하나만 손봤다 — 상태바
/// 시안에는 `19:27` 과 신호/배터리가 그려져 있었다. 그걸 그대로 깔면
/// **기기의 진짜 상태바와 두 겹으로 겹친다.** 그래서 위 44px 만
/// 잘라냈다. 그림·글씨는 한 획도 건드리지 않았다.
///
/// ## 버튼은 어떻게 눌리나
/// 글자가 그림 안에 있으니 그 **위치에 투명한 터치 영역**을 얹는다.
/// 비율로 잡아 두었으므로 화면 크기가 달라도 글자를 따라간다.
///
/// ```
///  0. 로고     Flownote + 태그라인   (버튼 없음 · 매번 뜬다)
///  1. 영수증   건너뛰기 / 다음
///  2. 인사이트 건너뛰기 / 다음
///  3. 가이드   건너뛰기 / 시작하기
/// ```
class IntroSlide {
  const IntroSlide({required this.image, required this.semantics});

  /// 시안 PNG. 상태바만 잘라낸 471 x 980.
  final String image;

  /// 그림 안의 글자는 화면 낭독기가 못 읽는다. 대신 읽어 줄 문장.
  final String semantics;

  /// 원본 픽셀 크기. 상태바(44px)를 잘라낸 뒤의 값이다.
  static const double imageWidth = 471;
  static const double imageHeight = 980;

  /// 원본 비율 (471 / 980)
  static const double ratio = imageWidth / imageHeight;

  static const String splashImage = 'assets/onboarding/intro_0.png';

  static const List<IntroSlide> all = [
    IntroSlide(
      image: 'assets/onboarding/intro_1.png',
      semantics: '쌓이는 영수증, 촬영으로 간편하게. '
          '꽃 사입 내역을 일일이 적지 않아도 품목과 금액을 읽어 정리해 드려요.',
    ),
    IntroSlide(
      image: 'assets/onboarding/intro_2.png',
      semantics: '우리 가게 지출을 한눈에 확인해요. '
          '월별 지출부터 품목별 비중까지 복잡한 사입 내역을 쉽게 파악해요.',
    ),
    IntroSlide(
      image: 'assets/onboarding/intro_3.png',
      semantics: '쌓인 기록으로 다음 사입도 똑똑하게. '
          '우리 가게에 맞는 사입 가이드로 다음 꽃시장 방문을 준비해요.',
    ),
  ];
}

/// 인트로를 이미 봤는지 기억한다.
class IntroPrefs {
  static const String _key = 'intro_seen_v1';

  static Future<bool> seen() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_key) ?? false;
    } catch (_) {
      // 저장소를 못 읽어도 앱이 멈추면 안 된다. 한 번 더 보여준다.
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, true);
    } catch (_) {}
  }

  static Future<void> reset() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }
}

/// 시안 배경과 이어지는 색. 그림이 화면보다 짧을 때 위아래를 메운다.
const Color introTopColor = Color(0xFFFDF2EF);
const Color introBottomColor = Color(0xFFFEFDFB);

/// 시안 PNG 한 장을 **잘리지 않게** 화면에 올린다.
///
/// 🔴 처음엔 cover 로 꽉 채웠다가 크게 틀렸다.
///
/// 시안은 세로로 아주 긴 비율(471:980 = 0.48)이다. 브라우저 창은
/// 보통 가로로 넓다(예: 1024x500 = 2.05). 꽉 채우기는 가로를 맞추려고
/// 이미지를 **2.17배로 확대**하는데, 그러면 세로가 2131px 이 되어
/// **이미지의 아래 23% 만 보인다.** 일러스트는 화면 위로 잘려 사라지고
/// 버튼 글자만 크게 확대돼 보인다. 사장님이 본 그 화면이다.
///
/// 그래서 **이미지 전체가 보이도록** 맞춘다. 남는 자리는 시안 배경색
/// 으로 메운다. 화면이 넓으면 좌우에, 짧으면 위아래에 여백이 생긴다.
///
/// 그려진 사각형은 [onRect] 로 알려 준다. 그림 위에 얹는 투명 버튼이
/// **그림을 따라가야** 하기 때문이다. 화면 기준으로 고정해 두면 넓은
/// 화면에서 버튼이 엉뚱한 곳에 생긴다. (그게 이번 문제였다)
class _IntroImage extends StatelessWidget {
  const _IntroImage({
    required this.asset,
    this.semantics,
    this.onRect,
  });

  final String asset;
  final String? semantics;

  /// 그림이 실제로 그려진 사각형.
  final ValueChanged<Rect>? onRect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final vw = c.maxWidth;
        final vh = c.maxHeight;

        // 이미지 전체가 들어가는 배율 = 가로·세로 배율 중 작은 쪽.
        final sx = vw / IntroSlide.imageWidth;
        final sy = vh / IntroSlide.imageHeight;
        final s = sx < sy ? sx : sy;

        final dw = IntroSlide.imageWidth * s;
        final dh = IntroSlide.imageHeight * s;
        final dx = (vw - dw) / 2;
        final dy = (vh - dh) / 2;

        onRect?.call(Rect.fromLTWH(dx, dy, dw, dh));

        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [introTopColor, introBottomColor],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: dx,
                top: dy,
                width: dw,
                height: dh,
                child: Image.asset(
                  asset,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                  semanticLabel: semantics,
                  // 그림을 못 불러와도 화면이 깨지면 안 된다.
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 0번 — 로고 화면. 버튼이 없고 **매번** 뜬다.
class IntroSplash extends StatelessWidget {
  const IntroSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return const _IntroImage(
      asset: IntroSlide.splashImage,
      semantics: 'Flownote. 꽃은 아름답게, 정산은 정확하게 플로우노트',
    );
  }
}

/// 1~3번 — 넘기는 인트로. 다 보거나 건너뛰면 [onDone] 을 부른다.
///
/// 그림을 깔고, **그림 속 버튼 글자 위에** 투명 터치 영역을 얹는다.
/// 좌표는 PNG 에서 픽셀로 재서 이미지 기준 비율로 바꿔 두었다.
///
/// ```
///   건너뛰기      x 0.136~0.448   y 중심 0.888
///   다음/시작하기 x 0.811~0.864   y 중심 0.888   (471 x 980 기준)
/// ```
///
/// 🔴 이 비율은 **화면이 아니라 그림** 기준이다. 넓은 화면에서는
/// 그림이 좌우 여백을 두고 가운데에만 그려지므로, 화면 기준으로 잡으면
/// 버튼이 그림 밖에 생긴다. 그래서 [_IntroImage] 가 알려 주는 실제
/// 사각형(`_art`)에 맞춰 버튼을 놓는다.
class IntroDsScreen extends StatefulWidget {
  const IntroDsScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<IntroDsScreen> createState() => _IntroDsScreenState();
}

class _IntroDsScreenState extends State<IntroDsScreen> {
  final _pager = PageController();
  int _page = 0;

  /// 그림이 실제로 그려진 사각형. 버튼을 여기에 맞춘다.
  Rect? _art;

  /// 그림에서 잰 버튼 세로 중심. (864~877 / 980)
  static const double _btnCenterY = 0.888;

  /// 터치 띠 높이 (그림 높이 대비). 글자보다 넉넉하게 준다.
  static const double _btnBandH = 0.055;

  List<IntroSlide> get _slides => IntroSlide.all;
  bool get _isLast => _page == _slides.length - 1;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// 🔴 저장을 **기다리지 않는다.** 저장소가 느리거나 막혀 있으면
  /// 버튼을 눌렀는데 아무 일도 안 일어나는 것처럼 보인다.
  void _finish() {
    IntroPrefs.markSeen();
    widget.onDone();
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _pager.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _setArt(Rect r) {
    if (_art == r) return;
    // 레이아웃 중에 setState 를 부를 수 없다. 프레임이 끝난 뒤에 알린다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _art = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final art = _art;
    return Scaffold(
      backgroundColor: introBottomColor,
      body: Stack(
        children: [
          // 1) 시안 그림 (글자·버튼·인디케이터가 모두 그림 안에 있다)
          PageView.builder(
            controller: _pager,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => _IntroImage(
              asset: _slides[i].image,
              semantics: _slides[i].semantics,
              onRect: i == 0 ? _setArt : null,
            ),
          ),

          // 2) 그림 속 버튼 자리에 투명 터치 영역.
          //    그림 크기를 알기 전에는 얹지 않는다. (엉뚱한 곳에
          //    생기는 것보다 아예 없는 게 낫다 — 스와이프는 된다)
          if (art != null) ...[
            _HitBox(
              art: art,
              left: 0.08,
              right: 0.52,
              centerY: _btnCenterY,
              height: _btnBandH,
              label: '건너뛰기',
              onTap: _finish,
            ),
            _HitBox(
              art: art,
              left: 0.70,
              right: 0.97,
              centerY: _btnCenterY,
              height: _btnBandH,
              label: _isLast ? '시작하기' : '다음',
              onTap: _next,
            ),
          ],
        ],
      ),
    );
  }
}

/// 그림 위에 얹는 투명 터치 영역.
///
/// 좌표는 **그림 사각형 [art] 기준 비율**이다. 화면 기준이 아니다.
/// 그래서 그림이 어디에 어떤 크기로 그려져도 글자를 따라간다.
class _HitBox extends StatelessWidget {
  const _HitBox({
    required this.art,
    required this.left,
    required this.right,
    required this.centerY,
    required this.height,
    required this.label,
    required this.onTap,
  });

  /// 그림이 실제로 그려진 사각형 (화면 좌표).
  final Rect art;

  /// 0.0 ~ 1.0 — 그림 너비 기준
  final double left;
  final double right;

  /// 0.0 ~ 1.0 — 그림 높이 기준 (띠의 중심)
  final double centerY;

  /// 0.0 ~ 1.0 — 그림 높이 기준 (띠의 높이)
  final double height;

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = art.height * height;
    return Positioned(
      left: art.left + art.width * left,
      width: art.width * (right - left),
      top: art.top + art.height * centerY - h / 2,
      height: h,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
