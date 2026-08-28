import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../design/fn_controls_ds.dart';
import '../../design/fn_feedback.dart';
import '../../design/fn_shell.dart';
import '../../services/file_saver.dart';
import '../../services/receipt_image_editor.dart';

/// 영수증만 남기는 **크롭 + 리사이즈 편집 화면**.
///
/// ## 왜 필요한가
///
/// 촬영한 사진에는 영수증 말고도 작업대·손·바닥이 함께 담긴다.
/// 그 상태로 저장하면 두 가지가 나빠진다.
///
/// | | 문제 |
/// |---|---|
/// | 인식 | 배경 글자·무늬가 OCR 오인식을 만든다 |
/// | 용량 | 3~8MB 원본이 그대로 올라가 업로드/백업이 느려진다 |
///
/// 이 화면은 네 귀퉁이를 끌어 **영수증만** 남기고, 긴 변 길이를 골라
/// 줄인 뒤, 그 결과를 **새 JPEG** 로 만들어 돌려준다.
///
/// ## 결과는 반드시 저장까지 이어진다
///
/// 예전 파이프라인은 `imagePath: file.path` 로 **경로만** 넘겼다.
/// 그래서 편집 결과 바이트를 만들어도 저장되는 값은 원본 경로였다.
/// 여기서는 네이티브면 편집 결과를 **문서 폴더에 실제 파일로 쓰고**
/// 그 경로를 가진 `XFile` 을 돌려준다. 웹이면 `XFile.fromData` 로
/// 바이트를 붙잡고 있다가 저장 시점에 클라우드로 올라간다.
///
/// 반환값: 편집된 `XFile` / 취소하면 `null`
class ReceiptCropDsScreen extends StatefulWidget {
  const ReceiptCropDsScreen({
    super.key,
    required this.file,
    this.initialMaxDimension = ReceiptImageEditor.defaultMaxDimension,
  });

  final XFile file;

  /// 처음 선택되어 있을 리사이즈 단계(긴 변 px).
  final int? initialMaxDimension;

  @override
  State<ReceiptCropDsScreen> createState() => _ReceiptCropDsScreenState();
}

class _ReceiptCropDsScreenState extends State<ReceiptCropDsScreen> {
  /// `--cool-neutral-10`
  static const _bg = Color(0xFF1B1D22);

  /// 시안 강조색 `#EE7686`
  static const _rose = Color(0xFFEE7686);
  static const _hintFg = Color(0xB3FFFFFF);

  Uint8List? _bytes;
  int _imgW = 0;
  int _imgH = 0;
  String? _error;

  /// 0~1 비율 크롭 영역. 처음에는 전체에서 살짝 안쪽.
  Rel _rect = const Rel(0.06, 0.06, 0.88, 0.88);

  int _turns = 0;
  int? _maxDim;
  bool _working = false;

  /// 드래그 중인 손잡이. null 이면 없음.
  _Grab? _grab;

  @override
  void initState() {
    super.initState();
    _maxDim = widget.initialMaxDimension;
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await widget.file.readAsBytes();
      if (b.isEmpty) throw StateError('빈 파일');
      // 화면에 그릴 비율을 알아야 크롭 사각형을 계산할 수 있다.
      final ui.Image im = await decodeImageFromList(b);
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _imgW = im.width;
        _imgH = im.height;
      });
      im.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '사진을 읽을 수 없어요');
      debugPrint('[crop] 사진 읽기 실패: $e');
    }
  }

  /// 회전을 반영한 화면상 비율(가로/세로).
  double get _shownAspect {
    if (_imgW == 0 || _imgH == 0) return 0.75;
    final rotated = _turns % 2 == 1;
    return rotated ? _imgH / _imgW : _imgW / _imgH;
  }

  /// 저장될 픽셀 크기 추정값.
  ({int w, int h}) get _outSize {
    if (_imgW == 0) return (w: 0, h: 0);
    final rotated = _turns % 2 == 1;
    final baseW = rotated ? _imgH : _imgW;
    final baseH = rotated ? _imgW : _imgH;
    var w = (baseW * _rect.width).round();
    var h = (baseH * _rect.height).round();
    final cap = _maxDim;
    if (cap != null) {
      final longest = w > h ? w : h;
      if (longest > cap) {
        final k = cap / longest;
        w = (w * k).round();
        h = (h * k).round();
      }
    }
    return (w: w < 1 ? 1 : w, h: h < 1 ? 1 : h);
  }

  // ── 적용 ─────────────────────────────────────────────────
  Future<void> _apply() async {
    final bytes = _bytes;
    if (bytes == null || _working) return;
    setState(() => _working = true);

    // 🔴 회전을 크롭보다 **나중에** 하기로 엔진과 약속했다.
    //    (`_work` 안의 순서: 자르기 → 회전 → 줄이기)
    //    화면에서는 회전된 그림 위에서 사각형을 끌었으니, 그 사각형을
    //    원본 좌표계로 되돌려서 넘겨야 한다.
    final srcRect = _unrotate(_rect, _turns);

    final out = await ReceiptImageEditor.transform(
      bytes,
      rect: srcRect.isFull ? null : srcRect,
      maxDimension: _maxDim,
      quarterTurns: _turns,
    );
    if (!mounted) return;

    if (out == null || out.isEmpty) {
      setState(() => _working = false);
      showFnToast(context, '사진을 편집하지 못했어요. 원본을 그대로 씁니다',
          type: FnToastType.warning);
      Navigator.pop(context, widget.file);
      return;
    }

    final edited = await _materialize(out);
    if (!mounted) return;
    setState(() => _working = false);
    Navigator.pop(context, edited);
  }

  /// 편집 바이트를 **경로가 있는** `XFile` 로 만든다.
  ///
  /// 네이티브에서 경로 없이 `XFile.fromData` 만 쓰면 `path` 가 빈 문자열이
  /// 되고, 그 값이 그대로 `receipt.imagePath` 에 들어가 사진이 사라진다.
  /// 그래서 문서 폴더 `receipts/` 안에 실제 파일로 쓴다.
  /// 이 폴더는 OS 가 지우지 않으므로 캐시 경로 문제도 함께 사라진다.
  Future<XFile> _materialize(Uint8List bytes) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final name = 'r_edit_$stamp.jpg';

    final dir = await ensureDocsSubdir('receipts');
    if (dir != null) {
      final target = '$dir/$name';
      if (await writeLocalBytes(target, bytes)) {
        return ReceiptImageEditor.wrap(bytes, name: name, savedPath: target);
      }
    }
    // 웹이거나 쓰기 실패 → 바이트만 들고 간다(웹은 이게 정상 경로다).
    return ReceiptImageEditor.wrap(bytes, name: name);
  }

  /// 화면(회전된) 좌표계의 사각형을 원본 좌표계로 되돌린다.
  static Rel _unrotate(Rel r, int turns) {
    var out = r;
    // 시계방향 t 번 회전된 그림에서의 좌표 → 원본 좌표
    for (var i = 0; i < turns % 4; i++) {
      out = Rel(out.top, 1 - out.left - out.width, out.height, out.width);
    }
    return out.clampToUnit();
  }

  // ── 드래그 처리 ───────────────────────────────────────────
  void _onPanStart(Offset local, Rect area) {
    _grab = _hitTest(local, area);
  }

  void _onPanUpdate(Offset delta, Rect area) {
    final g = _grab;
    if (g == null || area.width <= 0 || area.height <= 0) return;
    final dx = delta.dx / area.width;
    final dy = delta.dy / area.height;

    // 크롭 사각형이 너무 작아지지 않게 최소 크기를 둔다.
    const minSide = 0.12;
    var l = _rect.left;
    var t = _rect.top;
    var r = _rect.right;
    var b = _rect.bottom;

    if (g == _Grab.move) {
      final w = _rect.width;
      final h = _rect.height;
      l = (l + dx).clamp(0.0, 1.0 - w);
      t = (t + dy).clamp(0.0, 1.0 - h);
      r = l + w;
      b = t + h;
    } else {
      if (g.left) l = (l + dx).clamp(0.0, r - minSide);
      if (g.right) r = (r + dx).clamp(l + minSide, 1.0);
      if (g.top) t = (t + dy).clamp(0.0, b - minSide);
      if (g.bottom) b = (b + dy).clamp(t + minSide, 1.0);
    }
    setState(() => _rect = Rel(l, t, r - l, b - t));
  }

  /// 눌린 지점이 어느 손잡이인지 고른다.
  _Grab _hitTest(Offset p, Rect area) {
    // 손잡이 판정 반경(px). 손가락 크기를 감안해 넉넉히 둔다.
    const grabR = 34.0;
    final cx0 = area.left + _rect.left * area.width;
    final cx1 = area.left + _rect.right * area.width;
    final cy0 = area.top + _rect.top * area.height;
    final cy1 = area.top + _rect.bottom * area.height;

    final nearL = (p.dx - cx0).abs() < grabR;
    final nearR = (p.dx - cx1).abs() < grabR;
    final nearT = (p.dy - cy0).abs() < grabR;
    final nearB = (p.dy - cy1).abs() < grabR;

    if (nearL && nearT) return _Grab.topLeft;
    if (nearR && nearT) return _Grab.topRight;
    if (nearL && nearB) return _Grab.bottomLeft;
    if (nearR && nearB) return _Grab.bottomRight;

    final insideY = p.dy > cy0 - grabR && p.dy < cy1 + grabR;
    final insideX = p.dx > cx0 - grabR && p.dx < cx1 + grabR;
    if (nearL && insideY) return _Grab.leftEdge;
    if (nearR && insideY) return _Grab.rightEdge;
    if (nearT && insideX) return _Grab.topEdge;
    if (nearB && insideX) return _Grab.bottomEdge;
    return _Grab.move;
  }

  // ── 화면 ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '영수증만 자르기',
      onBack: () => Navigator.pop(context),
      bg: _bg,
      trailing: [
        _IconBtn(
          icon: Icons.rotate_90_degrees_ccw_rounded,
          onTap: _bytes == null
              ? null
              : () => setState(() {
                    _turns = (_turns + 3) % 4;
                    _rect = const Rel(0.06, 0.06, 0.88, 0.88);
                  }),
        ),
        _IconBtn(
          icon: Icons.rotate_90_degrees_cw_rounded,
          onTap: _bytes == null
              ? null
              : () => setState(() {
                    _turns = (_turns + 1) % 4;
                    _rect = const Rel(0.06, 0.06, 0.88, 0.88);
                  }),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          children: [
            Expanded(child: _stage()),
            const SizedBox(height: 14),
            _resizeRow(),
            const SizedBox(height: 8),
            _sizeLine(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FnDsButton(
                    label: '전체 선택',
                    size: FnDsButtonSize.large,
                    variant: FnDsButtonVariant.outlined,
                    foreground: Colors.white,
                    expand: true,
                    onPressed: _bytes == null
                        ? null
                        : () => setState(() => _rect = const Rel(0, 0, 1, 1)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FnDsButton(
                    label: _working ? '적용 중…' : '적용',
                    size: FnDsButtonSize.large,
                    expand: true,
                    onPressed: (_bytes == null || _working) ? null : _apply,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stage() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined, size: 44, color: _hintFg),
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    fontFamily: 'Pretendard', fontSize: 14, color: _hintFg)),
          ],
        ),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FnCircular(size: 30, color: Colors.white),
            SizedBox(height: 10),
            Text('사진을 불러오고 있어요',
                style: TextStyle(
                    fontFamily: 'Pretendard', fontSize: 13.5, color: _hintFg)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        // 회전 반영 비율로 사진이 실제로 차지하는 사각형을 구한다.
        final ar = _shownAspect;
        var w = box.maxWidth;
        var h = w / ar;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * ar;
        }
        final area = Rect.fromLTWH(
          (box.maxWidth - w) / 2,
          (box.maxHeight - h) / 2,
          w,
          h,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _onPanStart(d.localPosition, area),
          onPanUpdate: (d) => _onPanUpdate(d.delta, area),
          onPanEnd: (_) => _grab = null,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: area,
                child: RotatedBox(
                  quarterTurns: _turns,
                  child: Image.memory(bytes, fit: BoxFit.fill),
                ),
              ),
              // 어두운 스크림 + 크롭 테두리 + 손잡이
              Positioned.fromRect(
                rect: area,
                child: CustomPaint(
                  painter: _CropPainter(rect: _rect, accent: _rose),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _resizeRow() {
    return Row(
      children: [
        for (final c in ReceiptImageEditor.resizeChoices) ...[
          Expanded(child: _chip(c.label, c.maxDimension)),
          if (c != ReceiptImageEditor.resizeChoices.last)
            const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _chip(String label, int? dim) {
    final on = _maxDim == dim;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _maxDim = dim),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? _rose : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: on ? _rose : const Color(0x33FFFFFF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : _hintFg,
          ),
        ),
      ),
    );
  }

  Widget _sizeLine() {
    final o = _outSize;
    final text = o.w == 0
        ? '크기를 확인하고 있어요'
        : '저장 크기 ${o.w} × ${o.h} px'
            '${_maxDim == null ? ' · 원본 유지' : ''}';
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 12,
        color: Color(0x8AFFFFFF),
      ),
    );
  }
}

/// 드래그로 잡을 수 있는 지점.
enum _Grab {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  leftEdge,
  rightEdge,
  topEdge,
  bottomEdge,
  move;

  bool get left =>
      this == topLeft || this == bottomLeft || this == leftEdge;
  bool get right =>
      this == topRight || this == bottomRight || this == rightEdge;
  bool get top => this == topLeft || this == topRight || this == topEdge;
  bool get bottom =>
      this == bottomLeft || this == bottomRight || this == bottomEdge;
}

/// 크롭 영역 밖을 어둡게 덮고, 테두리 · 3분할선 · 손잡이를 그린다.
class _CropPainter extends CustomPainter {
  _CropPainter({required this.rect, required this.accent});

  final Rel rect;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      rect.left * size.width,
      rect.top * size.height,
      rect.width * size.width,
      rect.height * size.height,
    );

    // 바깥 어둡게
    final scrim = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = const Color(0x99000000));

    // 3분할 안내선
    final grid = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = r.left + r.width * i / 3;
      final y = r.top + r.height * i / 3;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), grid);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
    }

    // 테두리
    canvas.drawRect(
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // 네 귀퉁이 손잡이 — 시안 촬영 프레임과 같은 분홍 브래킷 모양
    const len = 24.0;
    const th = 4.0;
    final hp = Paint()
      ..color = accent
      ..strokeWidth = th
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    void bracket(Offset c, double sx, double sy) {
      canvas.drawLine(c, c.translate(len * sx, 0), hp);
      canvas.drawLine(c, c.translate(0, len * sy), hp);
    }

    bracket(r.topLeft, 1, 1);
    bracket(r.topRight, -1, 1);
    bracket(r.bottomLeft, 1, -1);
    bracket(r.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.rect != rect || old.accent != accent;
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Icon(icon,
              size: 21,
              color: onTap == null ? Colors.white24 : Colors.white),
        ),
      ),
    );
  }
}
