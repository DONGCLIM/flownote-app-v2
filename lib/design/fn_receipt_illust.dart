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
    PaperSpec(
      left: 0.1440,
      top: 0.2240,
      width: 0.3045,
      height: 0.6094,
      turn: -8.44,
      // 좌우는 가려져서 줄을 정확히 못 쟀다. 가운데 패턴을 줄여 쓴다.
      greyLines: 3,
    ),
    PaperSpec(
      left: 0.6580,
      top: 0.1615,
      width: 0.1934,
      height: 0.6094,
      turn: 7.85,
      greyLines: 2,
    ),
    PaperSpec(
      left: 0.3292,
      top: 0.1458,
      width: 0.3539,
      height: 0.6198,
      turn: -1.32,
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
  static const lineTops = <double>[0.089, 0.214, 0.312, 0.411, 0.500];
  static const lineWidths = <double>[0.58, 0.63, 0.54, 0.60, 0.42];

  /// 코랄 제목줄 색 (실측 `#FEB7BB`).
  static const coralLine = Color(0xFFFEB7BB);

  /// 회색 본문줄 색 (실측 `#FAFAFA` ~ `#F6F6F6`).
  static const greyLine = Color(0xFFF2F1F0);

  @override
  void paint(Canvas canvas, Size size) {
    _paintGlow(canvas, size);
    for (final p in papers) {
      _paintPaper(canvas, size, p);
    }
  }

  void _paintGlow(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, 0.05),
          radius: 0.78,
          colors: [
            Color(0x1AFF6D78),
            Color(0x12FF6D78),
            Color(0x00FF6D78),
          ],
          stops: [0.0, 0.52, 1.0],
        ).createShader(rect),
    );
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
    final padL = rect.left + rect.width * 0.11;
    for (var i = 0; i <= p.greyLines; i++) {
      final lh = (i == 0 ? 4.0 : 2.4) * k;
      final lineRect = Rect.fromLTWH(
        padL,
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
