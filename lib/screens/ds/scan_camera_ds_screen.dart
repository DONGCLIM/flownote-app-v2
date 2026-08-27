import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_controls_ds.dart';
import '../../design/fn_sheet.dart';
import '../../design/fn_feedback.dart';
import '../../services/gallery_intake.dart';
import '../../widgets/xfile_image.dart';

/// 촬영 화면 — 시안 `AppH7 scan-camera` / `AppH4 biz-camera` 1:1
///
/// ```js
/// Shell { navTitle:'', onBack, bg:'var(--cool-neutral-10)' }
///   div { height:'100%', column, justify:'space-between',
///         color:'var(--static-white)', padding:'20px 20px 32px' }
///     ContentBadge accent { alignSelf:center,
///         background:'rgba(242,104,122,.3)', color:'#FFC9CE' } `${month}월 ${addTarget}일에 추가`
///     div { flex:1, margin:'20px 0', border:'2px dashed rgba(255,255,255,.5)',
///           r16, center, color:'rgba(255,255,255,.6)', fontSize:14 }
///       '영수증을 프레임 안에 맞춰주세요'
///     div { center }
///       button 72x72 r36 bg static-white border '4px solid rgba(255,255,255,.4)'
/// ```
///
/// 시안은 정적 목업이지만 여기에는 **실제 카메라 프리뷰**를 프레임 안에 넣고,
/// 기존 앱이 갖고 있던 기능(플래시 · 전후면 전환 · 연속 촬영 누적 · 미리보기)을
/// 모두 유지한다.
///
/// [mode] : 'single' → 1장 찍고 반환 / 'multi' → 연속 촬영
/// 반환값: `List<XFile>` (취소 시 빈 리스트)
class ScanCameraDsScreen extends StatefulWidget {
  const ScanCameraDsScreen({
    super.key,
    required this.mode,
    this.badgeLabel,
    this.frameHint = '영수증을 프레임 안에 맞춰주세요',
    this.maxShots = 20,
  });

  final String mode;

  /// 상단 배지 문구. 시안은 `'3월 13일에 추가'` 형태.
  /// null 이면 모드에 따라 자동으로 채운다.
  final String? badgeLabel;

  /// 점선 프레임 안 안내 문구.
  final String frameHint;

  /// 연속 촬영 최대 장수 (플랜별 제한).
  final int maxShots;

  @override
  State<ScanCameraDsScreen> createState() => _ScanCameraDsScreenState();
}

class _ScanCameraDsScreenState extends State<ScanCameraDsScreen>
    with WidgetsBindingObserver {
  /// `--cool-neutral-10`
  static const _bg = Color(0xFF1B1D22);

  /// 시안 배지 배경 `rgba(242,104,122,.3)`
  static const _badgeBg = Color(0x4DF2687A);

  /// 시안 배지 글자 `#FFC9CE`
  static const _badgeFg = Color(0xFFFFC9CE);

  /// 시안 점선 `rgba(255,255,255,.5)`
  static const _dash = Color(0x80FFFFFF);

  /// 시안 안내문 `rgba(255,255,255,.6)`
  static const _hintFg = Color(0x99FFFFFF);

  /// 시안 셔터 테두리 `rgba(255,255,255,.4)`
  static const _shutterRing = Color(0x66FFFFFF);

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _ready = false;
  bool _shooting = false;
  bool _front = false;
  bool _flash = false;

  /// 이 기기/브라우저가 플래시(torch)를 지원하는지. 지원하지 않으면
  /// 상단 플래시 버튼 자체를 숨긴다 — 눌러도 안 되는 버튼을 두지 않는다.
  bool _flashSupported = true;

  /// 카메라를 못 쓰는 환경(웹 프리뷰 / 권한 거부)일 때의 안내
  String? _fallback;

  final List<XFile> _shots = [];

  bool get _isMulti => widget.mode == 'multi';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(useFront: _front);
    }
  }

  // ── 카메라 초기화 ──────────────────────────────────────────
  Future<void> _initCamera({bool useFront = false}) async {
    try {
      final status = await Permission.camera.status;
      if (status.isPermanentlyDenied) {
        if (mounted) _permissionDialog();
        return;
      }
      if (!status.isGranted) {
        final r = await Permission.camera.request();
        if (!r.isGranted) {
          if (mounted) _permissionDialog();
          return;
        }
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _fallback = '카메라를 찾을 수 없어요');
        return;
      }

      final desc = useFront && _cameras.length > 1
          ? _cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => _cameras.first)
          : _cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => _cameras.first);

      await _controller?.dispose();
      final c = CameraController(
        desc,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = c;
      await c.initialize();
      if (!mounted) return;

      // 🔴 플래시 설정은 "실패해도 되는" 작업이다. 절대 초기화를 막으면 안 된다.
      //
      // camera_web 의 setFlashMode 는 브라우저가 torch 를 지원하지 않으면
      // 모드를 보기도 전에 CameraErrorCode.torchModeNotSupported 를 던진다.
      //   if (!torchModeSupported) throw CameraWebException(... torchModeNotSupported ...)
      // 우리는 FlashMode.off(=끄기)를 넣었을 뿐인데도 예외가 나고,
      // 그게 아래 catch 로 떨어져 화면 전체가 '카메라를 열 수 없어요' 가 됐다.
      // 카메라는 이미 정상적으로 열린 상태였다. 그래서 따로 감싼다.
      try {
        await c.setFlashMode(_flash ? FlashMode.torch : FlashMode.off);
        _flashSupported = true;
      } catch (e) {
        _flashSupported = false;
        if (kDebugMode) {
          debugPrint('[ScanCamera] 플래시 미지원 — 무시하고 계속합니다: $e');
        }
      }

      setState(() {
        _ready = true;
        _front = useFront;
        _fallback = null;
      });
    } catch (e, st) {
      // 원인을 삼키지 말자. 이전에는 로그가 하나도 없어서
      // 브라우저 콘솔만 봐도 무엇이 실패했는지 알 수 없었다.
      debugPrint('[ScanCamera] 카메라 초기화 실패: $e');
      if (kDebugMode) debugPrint('$st');
      if (mounted) {
        setState(() => _fallback = kIsWeb
            ? '이 브라우저에서는 카메라를 열 수 없어요'
            : '카메라를 열 수 없어요');
      }
    }
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() => _flash = !_flash);
    try {
      await c.setFlashMode(_flash ? FlashMode.torch : FlashMode.off);
    } catch (e) {
      // 지원하지 않는 환경이면 원래 상태로 되돌리고 버튼을 감춘다.
      debugPrint('[ScanCamera] 플래시 전환 실패: $e');
      if (!mounted) return;
      setState(() {
        _flash = !_flash;
        _flashSupported = false;
      });
      showFnToast(context, '이 기기에서는 플래시를 쓸 수 없어요',
          type: FnToastType.warning);
      return;
    }
  }

  Future<void> _flip() async {
    setState(() => _ready = false);
    await _initCamera(useFront: !_front);
  }

  // ── 촬영 ──────────────────────────────────────────────────
  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _shooting) return;

    if (_isMulti && _shots.length >= widget.maxShots) {
      showFnToast(context, '한 번에 ${widget.maxShots}장까지 찍을 수 있어요',
          type: FnToastType.warning);
      return;
    }

    setState(() => _shooting = true);
    try {
      final x = await c.takePicture();
      if (!mounted) return;

      final action = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => _ShotPreviewDsScreen(
            file: x,
            shotIndex: _shots.length + 1,
            isMulti: _isMulti,
          ),
        ),
      );
      if (!mounted) return;

      switch (action) {
        case 'retake':
          break; // 이 장 버리고 계속
        case 'add':
          _shots.add(x);
          break;
        case 'scan':
          _shots.add(x);
          Navigator.pop(context, List<XFile>.from(_shots));
          return;
        default:
          // 뒤로가기 → 이 장은 살리고 종료 여부 확인
          _shots.add(x);
          await _confirmFinish();
      }
    } catch (_) {
      if (mounted) {
        showFnToast(context, '촬영에 실패했어요', type: FnToastType.error);
      }
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  /// 카메라를 못 쓰는 환경에서의 대체 경로 — 갤러리로 넘긴다.
  Future<void> _fromGallery() async {
    // 🔴 크기 옵션을 주지 않는다. 축소는 `GalleryIntake` 가 직접 한다.
    //
    // 여기도 `scan_flow.startFromGallery` 와 똑같은 함정이 있었다.
    // 웹에서 크기 옵션을 주면 `image_picker_for_web` 이 고른 사진을 전부
    // 동시에 캔버스로 축소하고, 끝나면 원본의 `blob:` URL 을 폐기한다.
    // 축소가 실패하면 그 폐기된 원본을 조용히 그대로 돌려준다.
    // 그 사진은 나중에 읽을 때 실패하기도 하고 성공하기도 한다
    // — 이것이 "됐다가 안 됐다가" 의 원인이었다.
    //
    // 이 경로는 카메라를 못 쓰는 환경의 대체 경로라서 사장님이 실제로
    // 웹에서 자주 밟는다. 스캔 탭만 고치면 여기서 또 같은 증상이 난다.
    // 🔴 웹에서는 `image_picker` 를 **거치지 않는다.**
    // 플러그인은 `blob:` URL 만 남기고 `File` 객체와 `<input>` 을 버린다.
    // 그 URL 은 브라우저가 임의의 시점에 정리해버릴 수 있어서 같은 사진이
    // 될 때도 있고 안 될 때도 있었다. 무효가 된 URL 은 재시도해도 계속
    // 무효라서 재시도로는 해결되지 않았다.
    // `pickAndPrepare` 는 웹에서 `File` 을 직접 붙잡고 읽어 blob URL 을
    // 아예 만들지 않는다. 네이티브는 그대로 `image_picker` 를 쓴다.
    final intake = await GalleryIntake.pickAndPrepare(multiple: _isMulti);
    if (!mounted || intake == null) return; // 취소

    if (intake.allFailed) {
      showFnToast(
        context,
        '사진 파일을 읽을 수 없어요. 갤러리에서 사진을 한 번 열어 내려받은 뒤 다시 골라주세요',
        type: FnToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    if (intake.hasFailures) {
      showFnToast(
        context,
        '${intake.failedCount}장은 파일을 읽을 수 없어 건너뜁니다',
        type: FnToastType.warning,
        duration: const Duration(seconds: 4),
      );
    }
    if (!mounted) return;
    Navigator.pop(context, intake.usable);
  }

  Future<void> _confirmFinish() async {
    if (_shots.isEmpty) {
      Navigator.pop(context, <XFile>[]);
      return;
    }
    final go = await showFnAlert(
      context,
      title: '촬영을 마칠까요?',
      message: '${_shots.length}장을 찍었어요. 지금까지 찍은 사진으로 인식을 시작할게요.',
      icon: Icons.photo_camera_outlined,
      confirmLabel: '인식 시작',
      cancelLabel: '계속 촬영',
    );
    if (!mounted) return;
    if (go) Navigator.pop(context, List<XFile>.from(_shots));
  }

  Future<void> _onBack() async {
    if (_isMulti && _shots.isNotEmpty) {
      await _confirmFinish();
    } else {
      Navigator.pop(context, <XFile>[]);
    }
  }

  void _permissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: FnColors.backgroundElevated,
        title: const Text('카메라 권한이 필요해요',
            style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        content: const Text(
          '영수증을 찍으려면 카메라 접근을 허용해 주세요.\n설정 > FlowNote > 카메라',
          style: TextStyle(fontFamily: 'Pretendard', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(<XFile>[]);
            },
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('설정으로 이동'),
          ),
        ],
      ),
    );
  }

  String get _badge {
    if (widget.badgeLabel != null) return widget.badgeLabel!;
    if (!_isMulti) return '단일 촬영';
    return _shots.isEmpty
        ? '연속 촬영 · 최대 ${widget.maxShots}장'
        : '연속 촬영 ${_shots.length}/${widget.maxShots}장';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: FnShell(
        navTitle: '',
        onBack: _onBack,
        bg: _bg,
        trailing: [
          // 기존 기능 유지: 플래시 · 전후면 전환
          if (_ready && _flashSupported)
            _RoundIcon(
              icon: _flash ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _flash ? const Color(0xFFFFD54F) : Colors.white,
              onTap: _toggleFlash,
            ),
          if (_ready && _cameras.length > 1)
            _RoundIcon(
              icon: Icons.flip_camera_android_rounded,
              onTap: _flip,
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            children: [
              // ContentBadge accent (시안 style override)
              Center(
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _badgeBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _badge,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.385,
                      color: _badgeFg,
                    ),
                  ),
                ),
              ),
              // 점선 프레임 + 실제 프리뷰
              //
              // 🔴 점선 프레임은 여기서 그리지 않는다. 프리뷰가 실제로
              //    차지하는 사각형에 맞춰 `_preview()` 안에서 그린다.
              //    (예전에는 이 슬롯 경계에 그려서, 잘린 프리뷰와 어긋났다)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  child: _preview(),
                ),
              ),
              // 셔터 (시안 72x72)
              _shutterRow(),
            ],
          ),
        ),
      ),
    );
  }

  /// 점선 가이드 프레임 + 라운드 클리핑을 한 번에 씌운다.
  ///
  /// 🔴 예전에는 이 프레임을 `build()` 쪽의 `Expanded` 슬롯 **바깥 경계**에
  ///    그렸다. 프리뷰가 `BoxFit.cover` 로 잘려 있었으니, 그 점선은 실제
  ///    촬영 범위와 아무 관계가 없는 선이었다. 이제는 프리뷰가 실제로
  ///    차지하는 사각형에만 그린다.
  Widget _framed(Widget child) {
    return CustomPaint(
      painter:
          _DashFramePainter(color: _dash, radius: 16, strokeWidth: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }

  Widget _preview() {
    if (_fallback != null) {
      return _framed(Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                size: 44, color: _hintFg),
            const SizedBox(height: 12),
            Text(_fallback!,
                style: const TextStyle(
                    fontFamily: 'Pretendard', fontSize: 14, color: _hintFg)),
            const SizedBox(height: 16),
            FnDsButton(
              label: '갤러리에서 선택',
              size: FnDsButtonSize.medium,
              variant: FnDsButtonVariant.outlined,
              foreground: Colors.white,
              onPressed: _fromGallery,
            ),
          ],
        ),
      ));
    }
    if (!_ready || _controller == null) {
      return _framed(const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FnCircular(size: 32, color: Colors.white),
            SizedBox(height: 12),
            Text('카메라를 준비하고 있어요',
                style: TextStyle(
                    fontFamily: 'Pretendard', fontSize: 14, color: _hintFg)),
          ],
        ),
      ));
    }

    // 🔴 화각 불일치 수정
    //    (사용자 리포트: "라인에 맞추라고 해놓고 찍으면 초광각/광각처럼
    //     물체가 내가 찍는 순간보다 작게 나온다")
    //
    // 이전 코드는 이랬다.
    //
    // ```dart
    // LayoutBuilder(
    //   builder: (context, box) => FittedBox(
    //     fit: BoxFit.cover,                     // ⚠️ 원인
    //     child: SizedBox(
    //       width: box.maxWidth,
    //       height: box.maxWidth * _controller!.value.aspectRatio,
    //       child: CameraPreview(_controller!),
    //     ),
    //   ),
    // )
    // ```
    //
    // `BoxFit.cover` 는 프리뷰를 **확대해서 슬롯을 꽉 채우고, 넘치는 부분을
    // 잘라낸다.** 그런데 저장은 `c.takePicture()` 가 하고, 이 함수는 잘라낸
    // 프리뷰가 아니라 **센서 프레임 전체**를 파일에 쓴다.
    //
    //   - 화면에서 본 것   = 센서 프레임의 일부(확대된 중앙 영역)
    //   - 파일에 저장된 것 = 센서 프레임 전체
    //
    // 그래서 저장된 사진에는 화면에서 본 것보다 **더 넓은 범위**가 담긴다.
    // 같은 영수증이 더 넓은 그림 안에 들어가니 상대적으로 작아 보이고,
    // 그것이 "초광각으로 찍힌 것 같다" 는 느낌의 정확한 정체다. 카메라가
    // 렌즈를 바꾼 것이 아니라, 우리가 화면에서 확대해 보여주고 있었을 뿐이다.
    //
    // 수정: `BoxFit.contain` + 정확한 비율 계산. 프리뷰가 센서 비율 그대로
    // 슬롯 안에 들어가고(남는 쪽에 여백이 생긴다), **화면에 보이는 영역과
    // 저장되는 영역이 정확히 같아진다.** 점선 가이드도 그 사각형에만 그리니
    // 이제 "라인에 맞추면 그대로 찍힌다" 가 사실이 된다.
    //
    // 대안으로 cover 를 유지하고 저장된 JPEG 를 잘라내는 방법도 있었다.
    // 하지만 네이티브에서 JPEG 를 다시 인코딩하려면 `image` 패키지를 새로
    // 의존성에 넣어야 하고(지금은 transitive 뿐이다), 한 장마다 디코딩·
    // 인코딩 비용이 붙는다. 불만의 본질이 "본 것과 찍힌 것이 다르다" 이므로
    // 본 것을 진실로 만드는 쪽을 택했다.
    return LayoutBuilder(
      builder: (context, box) {
        // `CameraPreview` 는 세로 화면에서 `1 / aspectRatio` 로 비율을 잡는다.
        // 이 화면은 `portraitUp` 으로 고정되어 있으므로 그대로 쓴다.
        final ar = 1 / _controller!.value.aspectRatio;
        var w = box.maxWidth;
        var h = w / ar;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * ar;
        }
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: _framed(Stack(
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: CameraPreview(_controller!),
                  ),
                ),
                // 시안 프레임 안 안내 문구 — 프리뷰 위에 얹는다
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x9E000000),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      widget.frameHint,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            )),
          ),
        );
      },
    );
  }

  Widget _shutterRow() {
    final hasShots = _isMulti && _shots.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 기존 기능 유지: 찍은 장수로 바로 인식 시작
        if (hasShots) ...[
          FnDsButton(
            label: '${_shots.length}장 인식 시작',
            size: FnDsButtonSize.large,
            expand: true,
            leadingIcon: const Icon(Icons.check_circle_outline_rounded,
                size: 20, color: Colors.white),
            onPressed: () =>
                Navigator.pop(context, List<XFile>.from(_shots)),
          ),
          const SizedBox(height: 16),
        ],
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _shooting ? null : _shoot,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _shooting ? 68 : 72,
              height: _shooting ? 68 : 72,
              decoration: BoxDecoration(
                color: _shooting ? const Color(0x8AFFFFFF) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: _shutterRing, width: 4),
              ),
              child: _shooting
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.black54),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// 상단 우측 원형 아이콘 버튼 (플래시 / 전후면)
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(child: Icon(icon, size: 22, color: color)),
      ),
    );
  }
}

/// `border: 2px dashed` 재현
class _DashFramePainter extends CustomPainter {
  _DashFramePainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  static const double dash = 7;
  static const double gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2,
          size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );
    for (final m in (Path()..addRRect(rrect)).computeMetrics()) {
      var p = 0.0;
      while (p < m.length) {
        final n = (p + dash).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(p, n), paint);
        p = n + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashFramePainter old) =>
      old.color != color || old.radius != radius;
}

/// 찍은 한 장 미리보기 — 시안 촬영 화면 톤(cool-neutral-10)을 그대로 유지.
///
/// 반환: 'retake' | 'add' | 'scan' | null
class _ShotPreviewDsScreen extends StatelessWidget {
  const _ShotPreviewDsScreen({
    required this.file,
    required this.shotIndex,
    required this.isMulti,
  });

  final XFile file;
  final int shotIndex;
  final bool isMulti;

  static const _bg = Color(0xFF1B1D22);
  static const _badgeBg = Color(0x4DF2687A);
  static const _badgeFg = Color(0xFFFFC9CE);

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '',
      onBack: () => Navigator.pop(context, 'retake'),
      bg: _bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          children: [
            Center(
              child: Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isMulti ? '$shotIndex장 촬영됨' : '촬영한 사진',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.385,
                    color: _badgeFg,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  // 웹에서는 File() 이 UnsupportedError 를 던진다. XFileImage 가
                  // 플랫폼에 따라 blob URL / 로컬 파일을 알아서 골라준다.
                  child: XFileImage(file, fit: BoxFit.contain),
                ),
              ),
            ),
            if (isMulti)
              Row(
                children: [
                  Expanded(
                    child: FnDsButton(
                      label: '다시 찍기',
                      size: FnDsButtonSize.large,
                      variant: FnDsButtonVariant.outlined,
                      foreground: Colors.white,
                      expand: true,
                      onPressed: () => Navigator.pop(context, 'retake'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FnDsButton(
                      label: '계속 촬영',
                      size: FnDsButtonSize.large,
                      variant: FnDsButtonVariant.outlined,
                      foreground: Colors.white,
                      expand: true,
                      onPressed: () => Navigator.pop(context, 'add'),
                    ),
                  ),
                ],
              )
            else
              FnDsButton(
                label: '다시 찍기',
                size: FnDsButtonSize.large,
                variant: FnDsButtonVariant.outlined,
                foreground: Colors.white,
                expand: true,
                onPressed: () => Navigator.pop(context, 'retake'),
              ),
            const SizedBox(height: 10),
            FnDsButton(
              label: isMulti ? '$shotIndex장 인식 시작' : '이 사진으로 인식',
              size: FnDsButtonSize.large,
              expand: true,
              onPressed: () => Navigator.pop(context, 'scan'),
            ),
          ],
        ),
      ),
    );
  }
}
