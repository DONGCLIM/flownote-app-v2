import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 🔴 #132 화면을 **시안 크기로 그린 뒤 통째로 축소**해 넣는 상자.
///
/// ## 왜 필요한가
///
/// 같은 코드인데 환경마다 다르게 보였다. 원인은 화면 크기가 아니라
/// **쓸 수 있는 높이**였다. 로그인 콘텐츠 자연 높이는 817dp 인데,
///
/// ```
///   폰 브라우저(주소창+하단바)  744  ->  73dp 부족 -> 스크롤
///   홈화면 앱(전체화면)        844  ->  27dp 남음 -> 꽉 맞음
///   PC                      900  ->  83dp 남음 -> 들어감
/// ```
///
/// 주소창·하단바가 약 100dp 를 먹어서 브라우저에서만 스크롤이 생겼다.
/// 게다가 PC 에서는 폭 제한이 없어 입력칸이 1392px(화면의 96.7%)까지
/// 늘어나 "전부 확대"처럼 보였다.
///
/// ## 무엇을 하는가
///
/// 1. 내용을 항상 [designWidth] 폭으로 그린다. (= PC 가로 늘어남 차단)
/// 2. 그 결과물을 **가로·세로 같은 배율로** 줄여 화면에 딱 맞춘다.
///    (= 스크롤 없이 전체가 한눈에)
///
/// 가로세로를 같은 배율로 줄이므로 **비율이 절대 변하지 않는다.**
/// 세 환경이 크기만 다르고 생김새는 똑같아진다.
///
/// ## 키보드가 올라올 때
///
/// 키보드가 뜨면 남는 높이가 확 줄어 글씨가 깨알만해진다. 그래서
/// 키보드가 올라온 동안은 축소를 멈추고 **평소 크기 + 스크롤**로
/// 돌아간다. (입력칸이 가려지지 않게)
/// 화면 폭 기준값.
class FnFit {
  const FnFit._();

  /// 이 폭까지는 '휴대폰'으로 본다. 휴대폰에서는 폭을 묶지 않는다.
  ///
  /// 🔴 390(시안 폭)으로 묶으면 412(갤럭시 S·픽셀 7)·430(프로맥스)
  ///    기기에서 좌우에 11px 흰 띠가 생긴다. #129 에서 없앤 문제가
  ///    되살아난다. 그래서 휴대폰 범위는 그대로 꽉 채우고, 태블릿·PC
  ///    만 묶는다.
  static const double phoneMaxWidth = 520;
}

class FnDesignFit extends StatelessWidget {
  const FnDesignFit({
    super.key,
    required this.child,
    this.designWidth = FnFit.phoneMaxWidth,
    this.minScale = 0.68,
  });

  final Widget child;

  /// 내용을 그릴 최대 폭. 휴대폰은 이 값에 못 미치므로 기기 폭을
  /// 그대로 쓰고(= 꽉 채움), 태블릿·PC 에서만 이 폭으로 묶인다.
  final double designWidth;

  /// 이보다 더 줄이지 않는다. 너무 작아지면 글씨를 못 읽는다.
  /// 여기에 걸리면 모자란 만큼만 스크롤된다.
  ///
  /// 0.70 을 쓰는 근거 (로그인 화면 실측 자연 높이 873.6dp):
  /// ```
  ///   폰 브라우저   390x744  필요 0.852  OK
  ///   좁은 기기     360x640  필요 0.718  OK
  ///   홈화면 앱     390x844  필요 0.966  OK
  ///   PC          1440x900  필요 1.000  축소 안 함
  /// ```
  /// 0.62 까지 내리면 아이폰 SE(568)도 담기지만 16dp 글자가 9.9dp 가
  /// 되어 읽기 힘들다. 그래서 0.68 에서 멈춘다. (360x640 에서 0.70 이면
  /// 3.7dp 가 모자라 스크롤이 생겼다 — 실측으로 잡았다)
  /// 0.68 이면 16dp 글자가 10.9dp 로, 작지만 읽을 수 있다.
  final double minScale;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom > 0;

    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        final maxH = c.maxHeight;

        // 폭은 시안 폭을 넘지 않는다. 좁은 기기에서는 기기 폭을 쓴다.
        final w = maxW < designWidth ? maxW : designWidth;

        // 키보드가 올라오면 축소하지 않고 스크롤에 맡긴다.
        if (keyboard || !maxH.isFinite) {
          return Center(
            child: SizedBox(
              width: w,
              child: SingleChildScrollView(child: child),
            ),
          );
        }

        // minScale 에 걸려서도 넘치는 경우에만 스크롤이 필요하다.
        // 그 판단은 _ScaleToFitBox 가 레이아웃에서 하므로, 여기서는
        // 넘칠 수 있는 여지를 스크롤로 열어 둔다.
        return Center(
          child: SizedBox(
            width: w,
            height: maxH,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: _ScaleToFit(
                maxHeight: maxH,
                minScale: minScale,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 자식을 **한 벌만** 그리고, 넘치면 그만큼 줄인다.
///
/// 🔴 처음에는 투명한 사본을 하나 더 그려서 높이를 쟀는데, 그러면
///    같은 위젯이 트리에 두 벌 생긴다. 테스트에서 `Found 2 widgets with
///    text "이메일"` 로 바로 걸렸고, 실제로도 입력칸·버튼이 두 개가 되어
///    키보드 포커스와 탭이 엉킨다. 그래서 사본 없이
///    `UnconstrainedBox`+`OverflowBox` 로 자연 높이를 받아 쓴다.
class _ScaleToFit extends SingleChildRenderObjectWidget {
  const _ScaleToFit({
    required Widget super.child,
    required this.maxHeight,
    required this.minScale,
  });

  final double maxHeight;
  final double minScale;

  @override
  _ScaleToFitBox createRenderObject(BuildContext context) =>
      _ScaleToFitBox(maxHeight: maxHeight, minScale: minScale);

  @override
  void updateRenderObject(BuildContext context, _ScaleToFitBox renderObject) {
    renderObject
      ..maxHeight = maxHeight
      ..minScale = minScale;
  }
}

/// 자식을 폭에 맞춰 **높이 제약 없이** 재고, 넘치는 만큼 축소해 그린다.
class _ScaleToFitBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _ScaleToFitBox({required double maxHeight, required double minScale})
      : _maxHeight = maxHeight,
        _minScale = minScale;

  double _maxHeight;
  double get maxHeight => _maxHeight;
  set maxHeight(double v) {
    if (_maxHeight == v) return;
    _maxHeight = v;
    markNeedsLayout();
  }

  double _minScale;
  double get minScale => _minScale;
  set minScale(double v) {
    if (_minScale == v) return;
    _minScale = v;
    markNeedsLayout();
  }

  double _scale = 1.0;

  /// 실제 적용된 배율. 테스트에서 확인한다.
  double get appliedScale => _scale;

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    final w = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : constraints.minWidth;

    // 폭은 고정, 높이는 무제한으로 재어 '자연 높이'를 얻는다.
    c.layout(BoxConstraints(minWidth: w, maxWidth: w), parentUsesSize: true);
    final natural = c.size.height;

    var s = 1.0;
    if (natural > 0 && natural > _maxHeight) {
      s = _maxHeight / natural;
      if (s < _minScale) s = _minScale;
    }
    _scale = s;

    final used = natural * s;
    size = Size(w, used < _maxHeight ? _maxHeight : used);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    if (_scale == 1.0) {
      context.paintChild(c, offset);
      return;
    }
    // 가로세로 같은 배율 -> 비율이 변하지 않는다.
    context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.diagonal3Values(_scale, _scale, 1.0),
      (ctx, off) => ctx.paintChild(c, off),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    // 눌리는 자리도 같이 줄여야 버튼이 엉뚱한 곳에서 눌린다.
    return result.addWithPaintTransform(
      transform: Matrix4.diagonal3Values(_scale, _scale, 1.0),
      position: position,
      hitTest: (BoxHitTestResult r, Offset p) =>
          c.hitTest(r, position: p),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.scaleByDouble(_scale, _scale, 1.0, 1.0);
  }
}
