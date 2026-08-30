import 'package:flutter/material.dart';

/// 영수증 사진을 **핀치줌 없이도 손가락으로 밀어서 볼 수 있는** 뷰어.
///
/// ## 왜 만들었나 (사장님 신고: "핀치줌을 하지 않으면 이동은 안되네")
///
/// 기존 코드는 이랬다.
/// ```dart
/// InteractiveViewer(
///   minScale: 1, maxScale: 5,
///   child: Container(
///     constraints: BoxConstraints(maxHeight: 260),
///     child: ReceiptPhoto(path, fit: BoxFit.fitWidth),  // 세로가 잘린다
///   ),
/// )
/// ```
///
/// `InteractiveViewer` 는 기본값이 `constrained: true` 다. 이러면 자식이
/// **뷰포트와 똑같은 크기**로 강제된다. 사진 자체는 `BoxFit.fitWidth` 로
/// 세로가 잘려 있는데, `InteractiveViewer` 가 보는 "자식 크기"는 잘린
/// 260px 짜리 상자다.
///
/// 그래서 배율 1 에서는 `_boundaryRect`(자식) == `_viewport`(뷰포트) 가 되고,
/// `_matrixTranslate` 가 "움직일 여유가 0" 이라고 판단해 이동을 전부
/// 되돌린다. 핀치줌으로 배율을 올리면 자식이 뷰포트보다 커지니까
/// 그때부터 이동이 되는 것이다. — 사장님이 겪은 그대로다.
///
/// 실제로 재서 확인한 값 (flutter_test, 뷰포트 300x260, 자식 900 높이):
///
/// | 설정 | 배율1에서 위로 10번(120px) 드래그한 이동량 |
/// |---|---|
/// | `constrained: true` (기존) | `Offset(0.0, 0.0)` ← 이동 불가 |
/// | `boundaryMargin: infinity` | `Offset(0.0, -120.0)` |
/// | `constrained: false` + 원본비율 높이 | `Offset(0.0, -120.0)` ✅ |
///
/// `boundaryMargin: infinity` 도 이동은 되지만 **사진 밖 빈 배경까지
/// 무한히 끌려온다.** 사진을 놓쳐 버리기 쉬워서 쓰지 않았다.
///
/// `constrained: false` 를 쓰면 경계가 사진 실제 크기가 되므로,
/// 끝까지 끌어도 사진 밖으로 나가지 않는다. 측정값: 자식 높이 400,
/// 뷰포트 260 → `y = -140.0` 에서 정확히 멈췄다 (= 400-260).
///
/// ## 원본 비율을 어떻게 아나
///
/// `constrained: false` 로 만들려면 자식에게 **진짜 높이**를 줘야 하고,
/// 그러려면 사진의 원본 가로:세로 비를 알아야 한다. 그건 이미지가
/// 디코딩된 뒤에만 알 수 있으므로 [Image.frameBuilder] 가 아니라
/// `ImageStreamListener` 로 `ImageInfo` 를 받아서 알아낸다.
///
/// **비율을 아직 모르는 동안에는 예전과 똑같이 동작한다** (이동량 0).
/// 사진이 안 뜬 상태에서 갑자기 빈 화면이 끌려다니는 것보다 낫다.
class PanZoomPhoto extends StatefulWidget {
  const PanZoomPhoto({
    super.key,
    required this.image,
    this.imageProvider,
    this.height = 260,
    this.background,
    this.quarterTurns = 0,
    this.onTap,
  });

  /// 실제로 그릴 위젯. `ReceiptPhoto` / `XFileImage` 등 무엇이든 된다.
  ///
  /// 🔴 이 위젯은 `BoxFit.fill` 로 그려져야 한다. 바깥에서 이미 원본
  ///    비율대로 크기를 잡아 주기 때문에, 안에서 또 비율을 맞추면
  ///    (`fitWidth` 등) 이중으로 계산돼 여백이 생긴다.
  final Widget image;

  /// 원본 픽셀 크기를 알아내기 위한 provider.
  ///
  /// [image] 가 실제로 그리는 것과 **같은 소스**여야 한다. 다르면
  /// 엉뚱한 비율로 늘어난다.
  ///
  /// `null` 이면 (그릴 수 없는 경로 — 예: 앱에서 저장한 사진을 웹에서
  /// 열었을 때) 원본 비율을 알 수 없으므로 **예전과 똑같이** 이동 없이
  /// 보여 준다. 에러 안내는 [image] 가 알아서 그린다.
  final ImageProvider? imageProvider;

  /// 뷰어 높이 (기존 화면들과 동일하게 260 기본)
  final double height;

  final Color? background;

  /// 회전 버튼 상태. 90/270 도면 가로세로가 뒤집히므로 비율도 뒤집는다.
  final int quarterTurns;

  /// 탭했을 때 (전체화면 열기 등). 드래그와 충돌하지 않는다 —
  /// 드래그는 `InteractiveViewer` 가 제스처 아레나에서 이기고,
  /// 짧은 탭만 이쪽으로 온다.
  final VoidCallback? onTap;

  @override
  State<PanZoomPhoto> createState() => _PanZoomPhotoState();
}

class _PanZoomPhotoState extends State<PanZoomPhoto> {
  /// 원본 가로/세로 비. 아직 모르면 null.
  double? _aspect;

  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// 회전/사진 교체 때 이동 상태를 초기화하기 위해 직접 들고 있는다.
  final _tc = TransformationController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PanZoomPhoto old) {
    super.didUpdateWidget(old);
    if (old.imageProvider != widget.imageProvider) {
      _aspect = null;
      _reset();
      _resolve();
    }
    // 회전하면 보고 있던 위치가 의미를 잃는다. 처음으로 돌린다.
    if (old.quarterTurns != widget.quarterTurns) _reset();
  }

  void _reset() => _tc.value = Matrix4.identity();

  void _resolve() {
    final provider = widget.imageProvider;
    if (provider == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    if (_listener != null) _stream?.removeListener(_listener!);
    _listener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (h <= 0 || w <= 0) return;
      if (!mounted) return;
      final a = w / h;
      if (_aspect == a) return;
      setState(() => _aspect = a);
    }, onError: (_, __) {
      // 크기를 못 얻어도 그냥 예전 동작(이동 없음)으로 남는다.
      // 사진 자체의 오류 표시는 widget.image 가 알아서 한다.
    });
    _stream = stream;
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 90/270 도 회전 시 가로세로가 바뀐다.
    final rotated = widget.quarterTurns % 2 == 1;
    final a = _aspect == null
        ? null
        : (rotated ? 1 / _aspect! : _aspect!);

    return Container(
      height: widget.height,
      width: double.infinity,
      color: widget.background,
      child: LayoutBuilder(
        builder: (ctx, cons) {
          final vw = cons.maxWidth;
          final vh = cons.maxHeight;
          // 폭을 꽉 채우고(= 기존 fitWidth 와 같은 느낌) 높이는 원본 비율대로.
          // 비율을 모르면 뷰포트 높이 그대로 → 이동량 0 (예전과 동일).
          final ch = a == null ? vh : (vw / a);
          return InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: 5,
            // 🔴 이 한 줄이 핵심이다. true(기본값)면 자식이 뷰포트 크기로
            //    강제돼서 배율 1 에서 이동 여유가 0 이 된다.
            constrained: false,
            child: SizedBox(
              width: vw,
              // 사진이 뷰포트보다 짧으면 늘리지 않는다(위아래 이동할 게 없다).
              height: ch < vh ? vh : ch,
              child: GestureDetector(
                // 🔴 deferToChild(기본값)로 두면 안 된다. 사진이 아직 로딩
                //    중이거나 에러 대체 위젯(빈 영역)일 때 탭이 아무 것도
                //    맞히지 못해서 전체화면 열기가 죽는다. 뷰어 영역
                //    전체를 탭 대상으로 잡는다.
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: RotatedBox(
                  quarterTurns: widget.quarterTurns,
                  child: widget.image,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
