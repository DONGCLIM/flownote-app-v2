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

  /// 심볼 그림에 이미 그려져 있는 스쿼클의 곡률 (280/1024, 실측값).
  ///
  /// 예전 코드는 `BorderRadius.circular(22)` 로 잘라냈다(= 84 기준 0.262).
  /// 새 그림은 **이미 둥글게 그려져 있고 모서리가 투명**하므로 다시 자르면
  /// 이중으로 깎여 모서리가 각져 보인다. 그래서 이제 자르지 않고,
  /// 이 값은 **그림자 모양을 그림과 맞추는 데만** 쓴다.
  static const double symbolCorner = 0.273;

  /// 워드마크 가로:세로 비율 (알파 bbox 로 잘라낸 971×163 실측값).
  static const double wordmarkRatio = 5.9571;
}

/// 앱 심볼(앱로고). 정사각 자리에 쓴다.
class FnAppMark extends StatelessWidget {
  const FnAppMark({super.key, this.size = 84, this.shadow = true});

  final double size;

  /// 프로토타입의 `0 6px 18px rgba(238,118,134,.22)` 그림자.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      FnBrand.symbolAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
    if (!shadow) return SizedBox(width: size, height: size, child: image);
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

/// 텍스트로고(워드마크). 높이만 주면 비율대로 넓어진다.
class FnWordmark extends StatelessWidget {
  const FnWordmark({super.key, required this.height, this.semanticsLabel = 'FlowNote'});

  final double height;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      FnBrand.wordmarkAsset,
      height: height,
      width: height * FnBrand.wordmarkRatio,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticsLabel,
    );
  }
}
