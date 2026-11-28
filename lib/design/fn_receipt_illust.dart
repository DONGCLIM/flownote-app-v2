import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 🔴 #158 — 가입 완료 화면의 영수증 일러스트.
///
/// 사장님 지적: "텍스트 위에 영수증 이미지가 아예 안 뜬다."
/// 맞다. #157 에서 나는 이 자리를 `SizedBox(height: 120)` 으로 비워 두고
/// 그림을 **아예 그리지 않았다.** 그림 자산도 없었다.
/// 그래서 시안을 픽셀로 재서 벡터로 그린다(자산 파일 없이).
///
/// ## 일러스트 전체 (시안 473x1024, 배율 473/375 = 1.26133)
/// 🔴 처음엔 글로우까지 포함한 x112..355 를 박스로 썼다가 종이가
/// 박스의 77% 만 채워 **작아 보였다.** 그래서 박스를 **종이 bbox
/// (x142..328 y275..410)** 에 글로우 여백 28px 을 균등히 더한
/// x114..356 y247..438 (243x192px = 192.7 x 152.2dp) 로 바꿨다.
/// 가로 중심 236.0 vs 화면중심 236.5 → **정확히 가운데 정렬**
///
/// ## 종이 세 장
/// 겹친 부분 때문에 꼭짓점만 보면 기울기가 틀린다. 그래서 **가려지지 않은
/// 바깥 모서리를 직선 피팅**해서 각도를 얻었다.
///
/// | 종이 | 바깥 모서리 식 | 기울기 | 시안 bbox |
/// |---|---|---|---|
/// | 왼쪽   | x = -0.1484y + 200.7 | **-8.44°** | x142..215 y290..410 |
/// | 가운데 | x = -0.0231y + 202.4 | **-1.32°** | x194..276 y275..388 |
/// | 오른쪽 | x = +0.1379y + 275.1 | **+7.85°** | x282..328 y278..393 |
///
/// 가운데가 가장 크고 **맨 앞**이다(좌우를 덮는다).
///
/// ## 🔴 글로우를 진하게 넣지 말 것
/// 처음에 알파 `0x33` 으로 넣었다가 렌더해 보니 **코랄 배경처럼** 보였다.
/// 시안에서 배경색(`#FEF9F5`)을 빼서 재 보니 가장 진한 곳도 이 정도다.
///
/// ```
/// y272 (종이 바로 위)  #FBEDEC   차이 R-3 G-12 B-9   <- 최대
/// y266                #FFF2F1   차이 R+1 G-7  B-4
/// y250 (32dp 바깥)     #FFF5F3   차이 R+1 G-4  B-2
/// ```
///
/// 알파로 치면 `0x1A` 수준이다. 그리고 `BoxShadow` 로 넣으면 아래로
/// 치우쳐서 시안의 **사방으로 고른** 번짐이 안 나온다 → `RadialGradient`.
class FnReceiptIllust extends StatelessWidget {
  const FnReceiptIllust({super.key, this.width = 192.7});

  /// 시안 실측 폭 192.7dp (종이 bbox + 글로우 여백 28px).
  final double width;

  /// 시안 비율 243/192 = 1.2656 (가로/세로).
  static const double ratio = 1.2656;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width / ratio,
      child: CustomPaint(painter: ReceiptIllustPainter()),
    );
  }
}

/// 테스트가 줄 색·장수를 직접 확인하므로 public 으로 둔다.
class ReceiptIllustPainter extends CustomPainter {
  /// 종이 세 장. 좌표는 일러스트 박스(243x192px) 대비 **비율**이다.
  ///
  /// 🔴 좌우 종이의 left 는 실측 bbox 보다 **안쪽으로 당겼다.**
  ///    실측은 가려진 뒤 "보이는 부분"만 잡히므로 그대로 쓰면 세 장이
  ///    서로 떨어져 보인다. 시안은 y330 에서
  ///      왼쪽 151-169 / 가운데 194-275 / 오른쪽 299-321
  ///    처럼 가운데가 좌우를 확실히 덮는다.
  /// 리스트 순서가 곧 쌓이는 순서다 — 가운데가 마지막(맨 앞).
  static const papers = <PaperSpec>[
    // 왼쪽 — 좌변 피팅 dx/dy=-0.1599 (잔차 0.45, n=69)
    PaperSpec(
      left: 0.1437,
      top: 0.2519,
      width: 0.3260,
      height: 0.5734,
      turn: 9.08,
      // 좌우는 가운데 장에 가려져 줄을 다 못 쟀다. 가운데 패턴을 줄여 쓴다.
      greyLines: 3,
    ),
    // 오른쪽 — 우변 피팅 dx/dy=+0.1363 (잔차 0.30, n=71)
    PaperSpec(
      left: 0.5238,
      top: 0.1834,
      width: 0.3299,
      height: 0.5802,
      turn: -7.76,
      greyLines: 3,
    ),
    // 가운데 — 맨 앞. 좌변 -0.0187(잔차 0.32) 우변 -0.0136(잔차 0.35)
    PaperSpec(
      left: 0.3317,
      top: 0.1470,
      width: 0.3329,
      height: 0.5855,
      turn: 0.93,
      greyLines: 4,
    ),
  ];

  /// 🔴 가운데 종이의 줄 패턴 (시안 실측, 종이 높이 대비 상대 위치).
  ///
  /// | 상대y | 폭(dp) | 색 |
  /// |---|---|---|
  /// | 0.089 | 38.1 | `#FEB7BB` ← **코랄 제목줄** |
  /// | 0.214 | 41.2 | 회색 |
  /// | 0.312 | 35.7 | 회색 |
  /// | 0.411 | 39.6 | 회색 |
  /// | 0.500 | 27.7 | 회색 (짧다) |
  ///
  /// 종이 폭 65.8dp 기준 상대 폭 = .58 .63 .54 .60 .42
  static const lineTops = <double>[0.1403, 0.2471, 0.3360, 0.4339, 0.5317];
  static const lineWidths = <double>[0.593, 0.630, 0.532, 0.581, 0.420];

  /// 줄 왼쪽 여백(종이 폭 대비). 코랄줄만 살짝 더 안쪽이다.
  static const lineLefts = <double>[0.1286, 0.1533, 0.1409, 0.1409, 0.1409];

  /// 코랄 제목줄 색. 시안 코어 평균 (250,187,193) 실측.
  static const coralLine = Color(0xFFFABBC1);

  /// 회색 본문줄 색.
  /// 🔴 #159 보정: `#F2F1F0`(G=241) 은 **너무 진했다.**
  ///    시안 세로 프로파일을 보면 본문줄은 (250,250,250) 으로
  ///    거의 안 보일 만큼 연하다. 진하면 영수증이 아니라
  ///    줄공책처럼 보인다.
  static const greyLine = Color(0xFFFAFAFA);

  /// 글로우 색. 알파는 실측 감쇠(배경 대비 최대 G-12)에 맞춘 값이다.
  /// 🔴 진하게 넣으면 코랄 배경처럼 보인다 — #158 에서 이미 겪었다.
  static const glowColor = Color(0x1AFF6D78);

  /// 글로우 번짐 반경(박스 폭 192.7 기준 dp).
  /// 실측상 종이 둘레에서 r 90px(=71dp) 바깥이면 사실상 0 이 된다.
  static const double glowBlur = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGlow(canvas, size);
    for (final p in papers) {
      _paintPaper(canvas, size, p);
    }
  }

  /// 종이 세 장을 **각각 코랄로 칠한 뒤 크게 블러**해서 글로우를 만든다.
  ///
  /// 🔴 사각형 + 방사 그라디언트 조합을 쓰면 안 된다. 그라디언트가
  ///    완전히 투명해지기 전에 사각형 경계에서 잘려 **네모난 테두리**가
  ///    보인다 (#159 에서 사장님이 지적하신 바로 그 문제).
  ///    실루엣 블러는 번지는 모양이 종이를 따라가므로 사각 경계가
  ///    생길 수 없고, 시안처럼 종이 둘레가 가장 진하게 나온다.
  ///
  /// 겹치는 부분은 전부 흰 종이에 덮이므로 장마다 따로 그려도 된다.
  void _paintGlow(Canvas canvas, Size size) {
    final k = size.width / 192.7;
    // 넓고 연한 번짐 -> 종이 가까이의 조금 진한 번짐 순서.
    // 두 겹이라야 "둘레가 진하고 바깥으로 길게 사라지는" 시안 느낌이 난다.
    for (final blur in <double>[glowBlur, glowBlur * 0.45]) {
      for (final p in papers) {
        final rect = Rect.fromLTWH(
          p.left * size.width,
          p.top * size.height,
          p.width * size.width,
          p.height * size.height,
        );
        canvas.save();
        canvas.translate(rect.center.dx, rect.center.dy);
        canvas.rotate(p.turn * math.pi / 180);
        canvas.translate(-rect.center.dx, -rect.center.dy);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(6.3 * k)),
          Paint()
            ..color = glowColor
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * k),
        );
        canvas.restore();
      }
    }
  }

  void _paintPaper(Canvas canvas, Size size, PaperSpec p) {
    final w = size.width, h = size.height;
    final k = w / 192.7; // 시안 폭 대비 배율
    final rect = Rect.fromLTWH(
      p.left * w,
      p.top * h,
      p.width * w,
      p.height * h,
    );
    // 실측 모서리 8px ÷ 1.26133 = 6.34dp
    final radius = Radius.circular(6.3 * k);

    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(p.turn * math.pi / 180);
    canvas.translate(-rect.center.dx, -rect.center.dy);

    // 겹친 장이 서로 떨어져 보이게 하는 아주 연한 그림자.
    // ⚠️ 진하게 넣으면 시안의 보송한 느낌이 사라진다.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.translate(0, 2 * k), radius),
      Paint()
        ..color = const Color(0x12B08A86)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * k),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = Colors.white,
    );

    // 줄 — 0번만 코랄(제목), 나머지는 회색(본문).
    for (var i = 0; i <= p.greyLines; i++) {
      // 코랄 제목줄은 시안에서 5px 두께(=3.96dp), 본문줄은 2px 수준.
      final lh = (i == 0 ? 3.96 : 2.0) * k;
      final lineRect = Rect.fromLTWH(
        rect.left + rect.width * lineLefts[i],
        rect.top + rect.height * lineTops[i],
        rect.width * lineWidths[i],
        lh,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(lineRect, Radius.circular(lh / 2)),
        Paint()..color = i == 0 ? coralLine : greyLine,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ReceiptIllustPainter oldDelegate) => false;
}

/// 종이 한 장의 사양.
class PaperSpec {
  const PaperSpec({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.turn,
    required this.greyLines,
  });

  /// 일러스트 박스 대비 비율.
  final double left;
  final double top;
  final double width;
  final double height;

  /// 회전 각도(도). 음수는 반시계.
  final double turn;

  /// 코랄 제목줄 **아래로** 더 그릴 회색 줄 수.
  final int greyLines;
}
