import 'package:flutter/material.dart';

import 'fn_home_tokens.dart';

/// #146 홈 시안 전용 커스텀 아이콘.
///
/// 🔴 왜 Material 아이콘을 안 쓰는가
///
/// 사장님이 주신 홈 시안(334x1024)의 아이콘은 **Material 아이콘 세트에 없는
/// 모양**이다. 확대해서 하나씩 확인했다:
///
/// | 자리   | 시안 모양                              | 지금까지 쓰던 Material        |
/// |--------|----------------------------------------|-------------------------------|
/// | 홈     | 오각형 집 **테두리** + 안에 웃는 입 곡선 | `home_rounded` (꽉 찬 집)      |
/// | 내역   | 체크 3개 + 옆 가로 막대 3개 (체크리스트) | `business_center_outlined` (가방) |
/// | 스캔   | 카메라 + 위 돌출 + 렌즈 원              | `photo_camera_outlined` (비슷하나 다름) |
/// | 캘린더 | 달력 + 위 고리 2개 + 안에 새싹(잎 2장)   | `calendar_today_outlined` (빈 달력) |
/// | 프로필 | **원 테두리** + 안에 머리 원 + 어깨 아치 | `person_outline_rounded` (원 없음) |
/// | 벨     | 돔 + 스커트 + 납작한 가로 바 + 분리된 추 | `notifications_none_rounded`   |
///
/// 그래서 `CustomPainter` 로 직접 그린다. 치수는 전부
/// `FnHome.tabIconSize` / `tabIconStroke` / `bellSize` / `bellStroke` 토큰을
/// 기준으로 한 **비율**이라, 토큰만 바꾸면 전체가 같이 커지고 작아진다.
///
/// 아이콘은 모두 23x23 정사각 캔버스를 0..1 정규 좌표로 보고 그린다.

// ───────────────────────────────────────────────────────────────────────
// 공통
// ───────────────────────────────────────────────────────────────────────

/// 정규 좌표(0..1)를 실제 캔버스 좌표로 바꿔 주는 도우미.
///
/// 아이콘마다 `Size` 가 다를 수 있으므로(탭 23dp, 벨 22dp) 비율로만 쓴다.
class _N {
  const _N(this.size);
  final Size size;
  Offset p(double x, double y) => Offset(x * size.width, y * size.height);
  double w(double v) => v * size.width;
  double h(double v) => v * size.height;
}

/// 선으로 그리는 아이콘의 공통 Paint.
Paint _stroke(Color c, double width) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

/// 채워서 그리는 아이콘의 공통 Paint.
Paint _fill(Color c) => Paint()
  ..color = c
  ..style = PaintingStyle.fill
  ..isAntiAlias = true;

// ───────────────────────────────────────────────────────────────────────
// 탭 아이콘 공개 위젯
// ───────────────────────────────────────────────────────────────────────

/// 시안 탭 아이콘을 키로 골라 그린다.
///
/// `key` 는 `fnTabs` 의 키와 같다: home / settle / scan / calendar / profile.
/// 모르는 키가 오면 **아무것도 그리지 않고 같은 크기 빈칸**을 돌려준다.
/// (없는 아이콘 때문에 화면이 깨지지 않게)
class FnTabIcon extends StatelessWidget {
  const FnTabIcon({
    super.key,
    required this.tabKey,
    required this.color,
    this.size = FnHome.tabIconSize,
  });

  final String tabKey;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final CustomPainter? painter = switch (tabKey) {
      'home' => _HomeIconPainter(color, size),
      'settle' => _HistoryIconPainter(color, size),
      'scan' => _ScanIconPainter(color, size),
      'calendar' => _CalendarIconPainter(color, size),
      'profile' => _ProfileIconPainter(color, size),
      _ => null,
    };
    if (painter == null) return SizedBox(width: size, height: size);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: painter),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────
// 홈 — 오각형 집 테두리 + 안에 웃는 입
// ───────────────────────────────────────────────────────────────────────

/// 시안 실측: 집 폭이 아이콘 폭의 약 78%, 지붕 꼭대기가 위에서 8%,
/// 바닥이 아래에서 12% 지점. 안쪽 웃는 입은 집 높이의 중하단에 걸린다.
class _HomeIconPainter extends CustomPainter {
  _HomeIconPainter(this.color, this.iconSize);
  final Color color;
  final double iconSize;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _N(size);
    final sw = FnHome.tabIconStroke * (iconSize / FnHome.tabIconSize);
    final p = _stroke(color, sw);

    // 집 외곽 — 지붕 꼭대기에서 시작해 시계방향.
    //   좌우 벽 x = 0.13 / 0.87, 어깨(처마) y = 0.40, 바닥 y = 0.86
    const left = 0.13, right = 0.87, apexY = 0.10, eaveY = 0.40, baseY = 0.86;
    const r = 0.09; // 모서리 둥글기 (정규 단위)

    final path = Path()
      // 왼쪽 처마 바로 아래에서 시작
      ..moveTo(n.p(left, baseY - r).dx, n.p(left, baseY - r).dy)
      ..lineTo(n.p(left, eaveY).dx, n.p(left, eaveY).dy)
      // 지붕 왼쪽 사면 -> 꼭대기 (꼭대기를 살짝 둥글게)
      ..quadraticBezierTo(
        n.p(left, eaveY - 0.04).dx,
        n.p(left, eaveY - 0.04).dy,
        n.p(0.5 - r * 0.9, apexY + 0.06).dx,
        n.p(0.5 - r * 0.9, apexY + 0.06).dy,
      )
      ..quadraticBezierTo(
        n.p(0.5, apexY).dx,
        n.p(0.5, apexY).dy,
        n.p(0.5 + r * 0.9, apexY + 0.06).dx,
        n.p(0.5 + r * 0.9, apexY + 0.06).dy,
      )
      // 지붕 오른쪽 사면 -> 오른쪽 처마
      ..quadraticBezierTo(
        n.p(right, eaveY - 0.04).dx,
        n.p(right, eaveY - 0.04).dy,
        n.p(right, eaveY).dx,
        n.p(right, eaveY).dy,
      )
      ..lineTo(n.p(right, baseY - r).dx, n.p(right, baseY - r).dy)
      // 오른쪽 아래 모서리
      ..quadraticBezierTo(
        n.p(right, baseY).dx,
        n.p(right, baseY).dy,
        n.p(right - r, baseY).dx,
        n.p(right - r, baseY).dy,
      )
      ..lineTo(n.p(left + r, baseY).dx, n.p(left + r, baseY).dy)
      // 왼쪽 아래 모서리
      ..quadraticBezierTo(
        n.p(left, baseY).dx,
        n.p(left, baseY).dy,
        n.p(left, baseY - r).dx,
        n.p(left, baseY - r).dy,
      );
    canvas.drawPath(path, p);

    // 안쪽 웃는 입 — 시안에서 집 내부 아래쪽에 걸린 위로 휜 곡선.
    final smile = Path()
      ..moveTo(n.p(0.33, 0.60).dx, n.p(0.33, 0.60).dy)
      ..quadraticBezierTo(
        n.p(0.50, 0.74).dx,
        n.p(0.50, 0.74).dy,
        n.p(0.67, 0.60).dx,
        n.p(0.67, 0.60).dy,
      );
    canvas.drawPath(smile, p);
  }

  @override
  bool shouldRepaint(_HomeIconPainter old) =>
      old.color != color || old.iconSize != iconSize;
}

// ───────────────────────────────────────────────────────────────────────
// 내역 — 체크 3개 + 옆 가로 막대 3개
// ───────────────────────────────────────────────────────────────────────

/// 시안 실측: 3줄이 균등 간격. 체크는 왼쪽 약 30% 폭, 막대는 오른쪽 45% 폭.
/// 막대는 양끝이 완전히 둥근 알약.
class _HistoryIconPainter extends CustomPainter {
  _HistoryIconPainter(this.color, this.iconSize);
  final Color color;
  final double iconSize;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _N(size);
    final sw = FnHome.tabIconStroke * (iconSize / FnHome.tabIconSize);
    final p = _stroke(color, sw);

    // 3줄 y 중심: 시안에서 0.22 / 0.50 / 0.78
    const rows = [0.22, 0.50, 0.78];
    for (final y in rows) {
      // 체크 — 내려갔다 올라오는 ✓
      final check = Path()
        ..moveTo(n.p(0.04, y).dx, n.p(0.04, y).dy)
        ..lineTo(n.p(0.13, y + 0.08).dx, n.p(0.13, y + 0.08).dy)
        ..lineTo(n.p(0.30, y - 0.10).dx, n.p(0.30, y - 0.10).dy);
      canvas.drawPath(check, p);

      // 가로 막대 — 알약(strokeCap round 이므로 선 하나로 충분)
      canvas.drawLine(n.p(0.45, y), n.p(0.96, y), p);
    }
  }

  @override
  bool shouldRepaint(_HistoryIconPainter old) =>
      old.color != color || old.iconSize != iconSize;
}

// ───────────────────────────────────────────────────────────────────────
// 스캔 — 카메라 몸통 + 위 돌출 + 렌즈 원
// ───────────────────────────────────────────────────────────────────────

/// 시안 실측: 몸통이 가로로 넓은 둥근 사각(y 0.26..0.82), 위 가운데에
/// 낮은 돌출이 올라앉고, 몸통 정가운데에 렌즈 원이 있다.
class _ScanIconPainter extends CustomPainter {
  _ScanIconPainter(this.color, this.iconSize);
  final Color color;
  final double iconSize;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _N(size);
    final sw = FnHome.tabIconStroke * (iconSize / FnHome.tabIconSize);
    final p = _stroke(color, sw);

    // 위 돌출 — 몸통 위 가운데. 시안은 좌우가 살짝 좁아지는 사다리꼴에 가깝다.
    final bump = Path()
      ..moveTo(n.p(0.33, 0.28).dx, n.p(0.33, 0.28).dy)
      ..lineTo(n.p(0.355, 0.15).dx, n.p(0.355, 0.15).dy)
      ..quadraticBezierTo(
        n.p(0.37, 0.12).dx,
        n.p(0.37, 0.12).dy,
        n.p(0.41, 0.12).dx,
        n.p(0.41, 0.12).dy,
      )
      ..lineTo(n.p(0.59, 0.12).dx, n.p(0.59, 0.12).dy)
      ..quadraticBezierTo(
        n.p(0.63, 0.12).dx,
        n.p(0.63, 0.12).dy,
        n.p(0.645, 0.15).dx,
        n.p(0.645, 0.15).dy,
      )
      ..lineTo(n.p(0.67, 0.28).dx, n.p(0.67, 0.28).dy);
    canvas.drawPath(bump, p);

    // 몸통 — 둥근 사각
    final body = RRect.fromLTRBR(
      n.w(0.06),
      n.h(0.26),
      n.w(0.94),
      n.h(0.84),
      Radius.circular(n.w(0.16)),
    );
    canvas.drawRRect(body, p);

    // 렌즈 — 몸통 가운데 원
    canvas.drawCircle(n.p(0.50, 0.55), n.w(0.155), p);
  }

  @override
  bool shouldRepaint(_ScanIconPainter old) =>
      old.color != color || old.iconSize != iconSize;
}

// ───────────────────────────────────────────────────────────────────────
// 캘린더 — 달력 + 위 고리 2개 + 안에 새싹
// ───────────────────────────────────────────────────────────────────────

/// 시안 실측: 몸통 y 0.18..0.86, 위에서 약 0.38 지점에 가로 구분선,
/// 몸통 위로 고리 2개가 삐져나온다. 아래칸 가운데에 잎 2장짜리 새싹이
/// **채워진 모양**으로 들어 있다.
class _CalendarIconPainter extends CustomPainter {
  _CalendarIconPainter(this.color, this.iconSize);
  final Color color;
  final double iconSize;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _N(size);
    final sw = FnHome.tabIconStroke * (iconSize / FnHome.tabIconSize);
    final p = _stroke(color, sw);

    // 고리 2개 — 몸통 위로 솟은 짧은 세로선
    canvas.drawLine(n.p(0.32, 0.06), n.p(0.32, 0.20), p);
    canvas.drawLine(n.p(0.68, 0.06), n.p(0.68, 0.20), p);

    // 몸통
    final body = RRect.fromLTRBR(
      n.w(0.10),
      n.h(0.14),
      n.w(0.90),
      n.h(0.88),
      Radius.circular(n.w(0.14)),
    );
    canvas.drawRRect(body, p);

    // 가로 구분선 (헤더 아래)
    canvas.drawLine(n.p(0.10, 0.38), n.p(0.90, 0.38), p);

    // 새싹 — 잎 2장이 아래에서 만난다. 채워진 모양.
    final f = _fill(color);
    final stemBottom = n.p(0.50, 0.76);
    // 왼쪽 잎
    final leafL = Path()
      ..moveTo(stemBottom.dx, stemBottom.dy)
      ..cubicTo(
        n.p(0.33, 0.72).dx, n.p(0.33, 0.72).dy,
        n.p(0.34, 0.52).dx, n.p(0.34, 0.52).dy,
        n.p(0.47, 0.49).dx, n.p(0.47, 0.49).dy,
      )
      ..cubicTo(
        n.p(0.49, 0.56).dx, n.p(0.49, 0.56).dy,
        n.p(0.50, 0.66).dx, n.p(0.50, 0.66).dy,
        stemBottom.dx, stemBottom.dy,
      )
      ..close();
    // 오른쪽 잎 (좌우 대칭)
    final leafR = Path()
      ..moveTo(stemBottom.dx, stemBottom.dy)
      ..cubicTo(
        n.p(0.67, 0.72).dx, n.p(0.67, 0.72).dy,
        n.p(0.66, 0.52).dx, n.p(0.66, 0.52).dy,
        n.p(0.53, 0.49).dx, n.p(0.53, 0.49).dy,
      )
      ..cubicTo(
        n.p(0.51, 0.56).dx, n.p(0.51, 0.56).dy,
        n.p(0.50, 0.66).dx, n.p(0.50, 0.66).dy,
        stemBottom.dx, stemBottom.dy,
      )
      ..close();
    canvas.drawPath(leafL, f);
    canvas.drawPath(leafR, f);
  }

  @override
  bool shouldRepaint(_CalendarIconPainter old) =>
      old.color != color || old.iconSize != iconSize;
}

// ───────────────────────────────────────────────────────────────────────
// 프로필 — 원 테두리 + 안에 머리 원 + 어깨 아치
// ───────────────────────────────────────────────────────────────────────

/// 시안 실측: 바깥 원이 아이콘을 거의 가득 채우고, 그 안에 머리 원과
/// 어깨 아치가 들어 있다. 어깨는 바깥 원에 닿지 않고 떨어져 있다.
class _ProfileIconPainter extends CustomPainter {
  _ProfileIconPainter(this.color, this.iconSize);
  final Color color;
  final double iconSize;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _N(size);
    final sw = FnHome.tabIconStroke * (iconSize / FnHome.tabIconSize);
    final p = _stroke(color, sw);

    // 바깥 원
    canvas.drawCircle(n.p(0.50, 0.50), n.w(0.43), p);

    // 머리
    canvas.drawCircle(n.p(0.50, 0.40), n.w(0.135), p);

    // 어깨 아치 — 위로 열린 반원. 바깥 원에 닿지 않게 좌우를 좁힌다.
    final rect = Rect.fromLTRB(n.w(0.27), n.h(0.57), n.w(0.73), n.h(0.95));
    // 180도(왼쪽)에서 시작해 180도만 그린다 = 위로 솟은 아치
    canvas.drawArc(rect, 3.14159, 3.14159, false, p);
  }

  @override
  bool shouldRepaint(_ProfileIconPainter old) =>
      old.color != color || old.iconSize != iconSize;
}

// ───────────────────────────────────────────────────────────────────────
// 헤더 벨
// ───────────────────────────────────────────────────────────────────────

/// #146 시안 알림 벨.
///
/// Material `notifications_none_rounded` 와 다른 점:
///   - 스커트가 바닥까지 내려오지 않고, **납작한 가로 바**에서 끊긴다
///   - 그 가로 바 아래에 **분리된 작은 추**가 따로 있다
///   - 선이 더 굵다 (벨 폭의 10~12%)
class FnBellIcon extends StatelessWidget {
  const FnBellIcon({
    super.key,
    this.color = FnHome.bellInk,
    this.size = FnHome.bellSize,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _BellPainter(color, size)),
      );
}

class _BellPainter extends CustomPainter {
  _BellPainter(this.color, this.iconSize);
  final Color color;
  final double iconSize;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _N(size);
    final sw = FnHome.bellStroke * (iconSize / FnHome.bellSize);
    final p = _stroke(color, sw);

    // 벨 몸통 — 왼쪽 아래에서 시작해 돔을 돌아 오른쪽 아래로.
    //   스커트 바닥 y = 0.70 (가로 바 위)
    //   돔 꼭대기 y = 0.16
    final body = Path()
      ..moveTo(n.p(0.22, 0.70).dx, n.p(0.22, 0.70).dy)
      // 왼쪽 벽을 타고 올라가며 안쪽으로 좁아진다
      ..lineTo(n.p(0.26, 0.40).dx, n.p(0.26, 0.40).dy)
      // 돔 왼쪽
      ..quadraticBezierTo(
        n.p(0.28, 0.16).dx,
        n.p(0.28, 0.16).dy,
        n.p(0.50, 0.16).dx,
        n.p(0.50, 0.16).dy,
      )
      // 돔 오른쪽
      ..quadraticBezierTo(
        n.p(0.72, 0.16).dx,
        n.p(0.72, 0.16).dy,
        n.p(0.74, 0.40).dx,
        n.p(0.74, 0.40).dy,
      )
      ..lineTo(n.p(0.78, 0.70).dx, n.p(0.78, 0.70).dy);
    canvas.drawPath(body, p);

    // 납작한 가로 바 — 시안에서 가장 진하고 두꺼운 부분.
    canvas.drawLine(n.p(0.17, 0.72), n.p(0.83, 0.72), p);

    // 아래 분리된 추 — 작은 가로 알약.
    final clapper = _stroke(color, sw * 1.15);
    canvas.drawLine(n.p(0.42, 0.87), n.p(0.58, 0.87), clapper);
  }

  @override
  bool shouldRepaint(_BellPainter old) =>
      old.color != color || old.iconSize != iconSize;
}

// ───────────────────────────────────────────────────────────────────────
// 카드1 책 아이콘
// ───────────────────────────────────────────────────────────────────────

/// #146 시안 카드1(영수증 정리 완료)의 펼친 책.
///
/// 🔴 사장님이 따로 주신 아이콘 이미지와 같은 모양이다.
///    왼쪽 페이지가 진한 코랄(#FF787C), 오른쪽이 연한 살구(#FF9385) **투톤**.
///    두 페이지 사이에 아주 얇은 홈이 있고, 바깥쪽 위 모서리는 둥글다.
///    지금 앱의 `Icons.menu_book_rounded` + 분홍 사각 박스를 이걸로 바꾼다.
class FnBookIcon extends StatelessWidget {
  const FnBookIcon({
    super.key,
    this.width = FnHome.bookW,
    this.height = FnHome.bookH,
    this.left = FnHome.bookLeft,
    this.right = FnHome.bookRight,
  });

  final double width;
  final double height;
  final Color left;
  final Color right;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _BookPainter(left, right)),
      );
}

class _BookPainter extends CustomPainter {
  _BookPainter(this.left, this.right);
  final Color left;
  final Color right;

  // 🔴 사장님이 주신 1024x1024 아이콘 원본을 픽셀 단위로 훑어 얻은 윤곽.
  //    (코랄 영역 bbox 608x537, 가로/세로 비 1.132)
  //
  //   정규 y    왼쪽 가장자리 x    설명
  //   0.000     0.788            위 오른쪽 모서리만 먼저 등장 (둥근 모서리)
  //   0.069     0.000            좌우가 완전히 펴진다
  //   0.696     0.002            여기까지 **수직**으로 내려온다
  //   0.728     0.012            ↓ 여기서부터 V 자로 모인다
  //   0.823     0.127
  //   0.886     0.322
  //   0.950     0.411
  //   1.000     ~0.48           바닥 한 점으로 모인다
  //
  //   가운데 홈: x 0.484..0.515 (폭 약 3.1%) — y 0.3 부터 아래까지 일정
  //   위 모서리 둥글기: y 0.069 안에서 끝나므로 반경 ≈ 폭의 7%
  //
  // 🔴 처음엔 수직 구간을 0.66 까지로 잡아서 하트처럼 보였다. 0.70 이 맞다.
  static const double _gutter = 0.0155; // 가운데 홈 반폭 (0.0310 / 2)
  static const double _straightTo = 0.700; // 여기까지 수직
  static const double _corner = 0.070; // 위 모서리 둥글기 (폭 기준)

  @override
  void paint(Canvas canvas, Size size) {
    final n = _N(size);

    /// 한 쪽 페이지를 그린다. [sign] = -1 이면 왼쪽, +1 이면 오른쪽.
    Path page(double sign) {
      final spineX = 0.5 + sign * _gutter; // 홈 쪽 가장자리
      final outerX = sign < 0 ? 0.0 : 1.0; // 바깥 가장자리
      final r = _corner;
      // 바깥쪽으로 r 만큼 들어온 지점 (둥근 모서리 시작)
      final cornerInX = outerX - sign * r;

      return Path()
        // 홈 위쪽에서 시작
        ..moveTo(n.p(spineX, 0.0).dx, n.p(spineX, 0.0).dy)
        // 위 가장자리를 따라 바깥쪽으로
        ..lineTo(n.p(cornerInX, 0.0).dx, n.p(cornerInX, 0.0).dy)
        // 둥근 모서리
        ..quadraticBezierTo(
          n.p(outerX, 0.0).dx,
          n.p(outerX, 0.0).dy,
          n.p(outerX, r * (size.width / size.height)).dx,
          n.p(outerX, r * (size.width / size.height)).dy,
        )
        // 바깥 벽을 수직으로 내려간다
        ..lineTo(n.p(outerX, _straightTo).dx, n.p(outerX, _straightTo).dy)
        // V 자 — 바닥 가운데로 모인다.
        //
        // 🔴 처음엔 제어점 한 개짜리 2차 곡선으로 그렸더니 y 0.85~0.95 구간이
        //    원본보다 **덜 좁아져서 방패처럼** 보였다. 렌더를 원본과 수치로
        //    맞춰 보니 차이가 그 구간에서 -0.13 까지 벌어졌다.
        //    그래서 원본 실측 좌표를 그대로 통과하도록 3차 곡선으로 바꿨다.
        //
        //   맞춰야 할 원본 좌표 (왼쪽 페이지 기준, 정규 x)
        //     y 0.80 -> 0.067   y 0.85 -> 0.250
        //     y 0.90 -> 0.342   y 0.95 -> 0.411   y 1.00 -> 0.457
        //   = 0.80 직후 급격히 꺾였다가 바닥 쪽에서 완만해진다
        // 제어점은 눈대중이 아니라, 위 목표 좌표 6개에 대한 **최소제곱
        // 맞춤으로 풀었다** (격자 탐색 + 좌표 하강). 평균 오차 1.4% 폭.
        //   P1 = (-0.010, 0.850)   P2 = (0.280, 0.790)   (왼쪽 페이지 기준)
        // 오른쪽 페이지는 x 를 좌우 반전해서 같은 곡선을 쓴다.
        ..cubicTo(
          n.p(outerX - sign * -0.010, 0.850).dx,
          n.p(outerX - sign * -0.010, 0.850).dy,
          n.p(outerX - sign * 0.280, 0.790).dx,
          n.p(outerX - sign * 0.280, 0.790).dy,
          n.p(spineX, 1.0).dx,
          n.p(spineX, 1.0).dy,
        )
        ..close();
    }

    canvas.drawPath(page(-1), _fill(left));
    canvas.drawPath(page(1), _fill(right));
  }

  @override
  bool shouldRepaint(_BookPainter old) =>
      old.left != left || old.right != right;
}
