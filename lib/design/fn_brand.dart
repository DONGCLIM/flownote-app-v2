import 'package:flutter/material.dart';

/// FlowNote 브랜드 자산 위젯.
///
/// 브랜드 그림은 **두 종류**이고 서로 바꿔 쓸 수 없다.
///
/// | 자산 | 파일 | 성격 | 쓰는 곳 |
/// |---|---|---|---|
/// | 심볼(앱로고) | `assets/icon/app_icon.png` | 정사각 스쿼클 + 흰 책 | 앱아이콘 · 파비콘 · 스플래시 · 로그인 상단 |
/// | 워드마크(텍스트로고) | `assets/brand/logo_wordmark.png` | 가로로 긴 `flownote` 글자 | 화면 안 브랜드 표기 (예전의 `Text('FlowNote')` 자리) |
///
/// 🔴 워드마크를 정사각으로 잘리는 자리(런처 아이콘 · 파비콘 · maskable)에
///    넣으면 글자가 잘린다. 그런 자리에는 반드시 심볼만 쓴다.
class FnBrand {
  const FnBrand._();

  static const String symbolAsset = 'assets/icon/app_icon.png';
  static const String wordmarkAsset = 'assets/brand/logo_wordmark.png';

  /// 🔴 #128 로그인/스플래시 시안의 워드마크 — **전부 검정**.
  ///
  /// 시안의 워드마크 칸을 재 보니 코랄 픽셀이 **0개**였다. 기존
  /// `wordmarkAsset` 은 'o' 가 코랄이라(불투명 픽셀의 20.2%) 시안과
  /// 다르다. 그래서 선명한 원본(1787x300)의 코램 픽셀만 검정으로
  /// 덮은 판을 따로 만들었다. 글자 모양은 원본 그대로라 또렷하다.
  static const String wordmarkFlatAsset =
      'assets/brand/logo_wordmark_flat.png';

  /// 로그인 화면용 심볼 — 바깥으로 퍼지는 코랄 글로우가 **그림에**
  /// 포함된 버전이다 (사용자 지정, 요청 #116).
  ///
  /// 🔴 `symbolAsset` 을 이것으로 바꿀 수 없다. 이 그림은 사방에
  ///    반투명한 글로우 여백을 갖고 있어서, 정사각으로 잘리는 자리
  ///    (런처 아이콘 · 파비콘 · maskable)에 넣으면 글로우가 잘리면서
  ///    한 변이 떨어진 네모로 보이거나, 기기가 입힌 한 번 더 잘라낸다.
  ///    그래서 화면 안 표기에만 사용한다.
  static const String symbolGlowAsset = 'assets/brand/logo_symbol_glow.png';

  /// 심볼 그림에 이미 그려져 있는 스쿼클의 곡률 (280/1024, 실측값).
  ///
  /// 예전 코드는 `BorderRadius.circular(22)` 로 잘라냈다(= 84 기준 0.262).
  /// 새 그림은 **이미 둥글게 그려져 있고 모서리가 투명**하므로 다시 자르면
  /// 이중으로 깎여 모서리가 각져 보인다. 그래서 이제 자르지 않고,
  /// 이 값은 **그림자 모양을 그림과 맞추는 데만** 쓴다.
  static const double symbolCorner = 0.273;

  /// 워드마크 가로:세로 비율 (알파 bbox 로 잘라낸 971×163 실측값).
  static const double wordmarkRatio = 5.9571;

  /// 🔴 #128 로그인 시안의 심볼 — **판 없는 코랄 책**.
  ///
  /// 시안(473x1024)의 심볼칸을 재 보니 네 귀퉁이가 배경색 그대로였다
  /// (차이 0~4). 즉 스쿼클 판이 **없다**. `symbolAsset`/`symbolGlowAsset`
  /// 은 둘 다 '코랄 판 + 흰 책'이라 시안과 색이 반대다.
  ///
  /// 그래서 시안의 실루엣을 그대로 떠서 두 톤 코랄로 칠한 그림을 새로
  /// 만들었다. 시안 대비 알파 IoU 0.970.
  ///   왼쪽 면 #FF787C · 오른쪽 면 #FF9386 · 기준선 가로 49%
  static const String symbolFlatAsset = 'assets/brand/logo_symbol_flat.png';

  /// 위 심볼에 코랄 글로우를 더한 판. 스플래시처럼 번짐이 필요한 자리.
  static const String symbolMarkAsset = 'assets/brand/logo_symbol_mark.png';

  /// 판 없는 심볼의 가로:세로 비율 (실측 1.1512).
  ///
  /// 🔴 정사각이 아니다. `FnAppMark` 처럼 정사각 칸에 넣으면 위아래가
  ///    남는다. 높이를 주고 비율로 폭을 정해야 한다.
  static const double symbolFlatRatio = 1.1512;
}

/// 앱 심볼(앱로고). 정사각 자리에 쓴다.
class FnAppMark extends StatelessWidget {
  const FnAppMark({
    super.key,
    this.size = 84,
    this.shadow = true,
    this.glow = false,
  });

  final double size;

  /// 프로토타입의 `0 6px 18px rgba(238,118,134,.22)` 그림자.
  ///
  /// 🔴 [glow] 를 켜면 이 값은 무시된다. 글로우가 이미 그림에
  ///    들어 있어서 위젯 그림자까지 얹으면 아래쪽만 두 겹으로 짙어진다.
  final bool shadow;

  /// 글로우가 그려진 심볼(`FnBrand.symbolGlowAsset`)을 쓴다.
  ///
  /// 로그인 화면(요청 #116)에서 사용한다. 정사각으로 잘리는 자리에는
  /// 쓰지 않는다 — `FnBrand.symbolGlowAsset` 주석 참고.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      glow ? FnBrand.symbolGlowAsset : FnBrand.symbolAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
    // 글로우 판은 그림 자체가 번짐을 갖고 있으므로 그림자를 얹지 않는다.
    if (!shadow || glow) {
      return SizedBox(width: size, height: size, child: image);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // 🔴 `clipBehavior` 를 주지 않는다. 그림에 스쿼클이 이미 있다.
        //    여기 radius 는 그림자 모양을 그림과 맞추기 위한 값이다.
        borderRadius: BorderRadius.circular(size * FnBrand.symbolCorner),
        boxShadow: const [
          BoxShadow(
            color: Color(0x38EE7686),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: image,
    );
  }
}

/// 🔴 #128 판 없는 코랄 책 심볼. **높이**를 주면 비율대로 넓어진다.
///
/// 로그인·스플래시 시안이 쓰는 그림이다. [FnAppMark] 는 '코랄 판 +
/// 흰 책'(런처 아이콘용)이라 시안과 색이 반대이므로 화면 안에서는
/// 이 위젯을 쓴다.
class FnBookMark extends StatelessWidget {
  const FnBookMark({
    super.key,
    required this.height,
    this.glow = false,
    this.semanticsLabel = 'FlowNote',
  });

  final double height;

  /// 코랄 글로우가 그려진 판을 쓴다. 시안의 로그인 상단이 이 모습이다.
  final bool glow;

  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    // 글로우 판은 사방에 46% 여백이 있어 같은 '책 크기'로 보이려면
    // 전체를 그만큼 크게 잡아야 한다.
    final h = glow ? height * 1.46 : height;
    return Image.asset(
      glow ? FnBrand.symbolMarkAsset : FnBrand.symbolFlatAsset,
      height: h,
      width: h * FnBrand.symbolFlatRatio,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticsLabel,
    );
  }
}

/// 텍스트로고(워드마크). 높이만 주면 비율대로 넓어진다.
class FnWordmark extends StatelessWidget {
  const FnWordmark({
    super.key,
    required this.height,
    this.semanticsLabel = 'FlowNote',
    this.flat = false,
  });

  final double height;
  final String semanticsLabel;

  /// 'o' 까지 전부 검정인 판을 쓴다. 로그인·스플래시 시안이 이것이다.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      flat ? FnBrand.wordmarkFlatAsset : FnBrand.wordmarkAsset,
      height: height,
      width: height * FnBrand.wordmarkRatio,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticsLabel,
    );
  }
}
