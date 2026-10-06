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

  /// 원본 비율 (471 / 980)
  static const double ratio = 471 / 980;

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

/// 시안 PNG 한 장을 화면에 꽉 채워 깐다.
///
/// 기기 비율이 시안(471:980)과 다르면 [BoxFit.cover] 때문에 좌우나
/// 위아래가 잘린다. 잘리는 쪽을 **아래(글자·버튼)가 아니라 위(그림)**
/// 로 보내기 위해 아래를 기준으로 정렬한다.
class _IntroImage extends StatelessWidget {
  const _IntroImage({required this.asset, this.semantics});

  final String asset;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [introTopColor, introBottomColor],
        ),
      ),
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.high,
        semanticLabel: semantics,
        // 그림을 못 불러와도 화면이 깨지면 안 된다.
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
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
/// 그림을 깔고, **그림 속 버튼 글자 위에 투명 터치 영역을 얹는다.**
/// 좌표는 PNG 에서 픽셀로 재서 비율로 바꿔 두었다. (471 x 980 기준)
///
/// ```
///   건너뛰기  x 0.136~0.448   y 중심 0.888
///   다음/시작하기 x 0.811~0.864  y 중심 0.888
/// ```
class IntroDsScreen extends StatefulWidget {
  const IntroDsScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<IntroDsScreen> createState() => _IntroDsScreenState();
}

class _IntroDsScreenState extends State<IntroDsScreen> {
  final _pager = PageController();
  int _page = 0;

  /// 그림에서 잰 버튼 세로 중심. (864~877 / 980)
  static const double _btnCenterY = 0.888;

  /// 터치 영역 높이. 글자(14px)보다 넉넉하게 준다.
  static const double _btnBandH = 0.055;

  List<IntroSlide> get _slides => IntroSlide.all;
  bool get _isLast => _page == _slides.length - 1;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// __RED__ 저장을 **기다리지 않는다.** 저장소가 느리거나 막혀 있으면
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

  @override
  Widget build(BuildContext context) {
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
            ),
          ),

          // 2) 그림 속 '건너뛰기' 자리에 투명 버튼
          _HitBox(
            left: 0.10,
            right: 0.52,
            centerY: _btnCenterY,
            height: _btnBandH,
            label: '건너뛰기',
            onTap: _finish,
          ),

          // 3) 그림 속 '다음 / 시작하기' 자리에 투명 버튼
          _HitBox(
            left: 0.74,
            right: 0.96,
            centerY: _btnCenterY,
            height: _btnBandH,
            label: _isLast ? '시작하기' : '다음',
            onTap: _next,
          ),
        ],
      ),
    );
  }
}

/// 그림 위에 얹는 투명 터치 영역.
///
/// 🔴 부모 크기를 재려고 LayoutBuilder 를 끼웠다가 터졌다.
/// Stack 안의 절대배치 위젯은 Stack 의 **직접** 자식이어야 해서,
/// 사이에 다른 위젯이 들어가면 `wants to apply ParentData` 가 난다.
/// 그래서 비율 배치를 [Align] + [FractionallySizedBox] 로 한다.
/// 둘 다 부모 크기에 대한 비율로 동작하므로 기기 크기가 달라도
/// 그림 속 글자를 그대로 따라간다.
class _HitBox extends StatelessWidget {
  const _HitBox({
    required this.left,
    required this.right,
    required this.centerY,
    required this.height,
    required this.label,
    required this.onTap,
  });

  /// 0.0 ~ 1.0 (화면 너비 기준)
  final double left;
  final double right;

  /// 0.0 ~ 1.0 (화면 높이 기준) — 띠의 중심
  final double centerY;

  /// 0.0 ~ 1.0 (화면 높이 기준) — 띠의 높이
  final double height;

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cx = (left + right) / 2;
    // Alignment 는 -1 ~ 1 좌표계다. 0~1 비율을 그쪽으로 옮긴다.
    return Align(
      alignment: Alignment(cx * 2 - 1, centerY * 2 - 1),
      child: FractionallySizedBox(
        widthFactor: right - left,
        heightFactor: height,
        child: Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
