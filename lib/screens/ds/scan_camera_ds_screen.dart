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
import '../../services/file_saver.dart';
import '../../services/gallery_intake.dart';
import '../../services/receipt_image_editor.dart';
import 'receipt_crop_ds_screen.dart';
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

  /// 시안 촬영 프레임의 **가로/세로 비율**.
  ///
  /// 시안(`AppH7 scan-camera`)의 프레임은 `flex: 1` — 남은 세로를 전부
  /// 차지하는 **세로로 긴 사각형**이다. 영수증(감열지)이 세로로 길기
  /// 때문에 그 모양이 맞다. 화면 폭 372 · 프레임 높이 약 600 이므로
  /// 실측 비율은 0.62 근처다.
  ///
  /// 🔴 이 값이 화면과 저장 사진을 잇는 **유일한 계약**이다.
  ///    프레임을 이 비율로 그리고, 프리뷰를 `BoxFit.cover` 로 꽉 채우고,
  ///    찍힌 JPEG 를 **이 비율로 잘라낸다.** 세 곳이 같은 숫자를 쓰는 한
  ///    "라인에 맞추면 그대로 찍힌다" 가 사실로 유지된다.
  static const double frameAspect = 0.62;

  /// 시안 프레임 배경 `rgba(255,255,255,.04)`
  static const _frameFill = Color(0x0AFFFFFF);

  /// 시안 코너 브래킷 `3px solid #EE7686`
  static const _bracket = Color(0xFFEE7686);

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

  /// 마지막으로 그려진 프레임 크기. 촬영 시 자를 비율을 알기 위해
  /// `_previewSlot()` 이 채운다.
  Size _frameSize = Size.zero;

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
      final raw = await c.takePicture();
      if (!mounted) return;

      // 🔴 화면에서 본 프레임만 남긴다. 이 한 줄이 "라인에 맞춰 찍었는데
      //    더 넓게 나온다" 를 없앤다. 실패하면 원본을 그대로 쓴다.
      var x = await _cropToFrame(raw);
      if (!mounted) return;

      final action = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => _ShotPreviewDsScreen(
            file: x,
            shotIndex: _shots.length + 1,
            isMulti: _isMulti,
            // 미리보기에서 자르면 저장할 파일을 바꿔치기한다.
            onEdited: (edited) => x = edited,
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
              // 시안 프레임 + 실제 프리뷰 (`flex: 1`, margin '20px 0')
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  child: _previewSlot(),
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

  /// 시안 프레임(코너 브래킷 4개 + 스캔 라인 + 하단 안내문) 을 씌운다.
  ///
  /// ## 왜 점선을 버렸나
  ///
  /// 사장님이 준 시안 이미지에는 점선이 없다. 네 귀퉁이에만 분홍색
  /// 갈고리(브래킷)가 있고, 46% 높이에 분홍 그라데이션 스캔 라인이 있고,
  /// 프레임 아래쪽에 안내문이 있다. 프로토타입 소스도 같다.
  ///
  /// ```js
  /// div { flex:1, margin:'20px 0', borderRadius:18, position:'relative',
  ///       background:'rgba(255,255,255,.04)',
  ///       display:'flex', alignItems:'flex-end', justifyContent:'center',
  ///       padding:18 }
  ///   [[0,0],[0,1],[1,0],[1,1]].map(([r,b]) => div {
  ///     position:'absolute', width:34, height:34,
  ///     [r?'right':'left']:10, [b?'bottom':'top']:10, borderRadius:6,
  ///     border:'3px solid #EE7686', ... })
  ///   div { position:'absolute', left:26, right:26, top:'46%', height:2,
  ///         background:'linear-gradient(90deg,
  ///           rgba(238,118,134,0), #EE7686, rgba(238,118,134,0))' }
  ///   div { color:'rgba(255,255,255,.72)', fontSize:13.5 }
  ///     '영수증을 프레임 안에 맞춰주세요'
  /// ```
  Widget _framed(Widget child, {String? topHint}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 프레임 배경 + 라운드 클리핑 안에 프리뷰
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(color: _frameFill, child: child),
        ),
        // 시안: 왼쪽 위 안내문 (`문서 경계 자동 감지 중`)
        //
        // 🔴 left 는 브래킷을 피해야 한다. 브래킷은 inset 10 + 폭 34 이므로
        //    x 10~44 를 차지한다. 예전에 left: 18 로 뒀더니 안내문이
        //    브래킷 세로선에 닿아서 시안과 달라 보였다(E2E 스크린샷으로 확인).
        //    44 + 여백 8 = 52 부터 시작한다.
        if (topHint != null)
          Positioned(
            left: 52,
            top: 22,
            child: Text(
              topHint,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xB8FFFFFF),
                shadows: [
                  Shadow(color: Color(0xCC000000), blurRadius: 4),
                ],
              ),
            ),
          ),
        // 시안: 46% 높이 스캔 라인
        Positioned(
          left: 26,
          right: 26,
          top: 0,
          bottom: 0,
          child: LayoutBuilder(
            builder: (context, box) => Padding(
              padding: EdgeInsets.only(top: box.maxHeight * 0.46),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  height: 2,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0x00EE7686),
                        _bracket,
                        Color(0x00EE7686),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 시안: 네 귀퉁이 브래킷 34x34 / 3px / r6 / 10px 안쪽
        for (final corner in const [
          (false, false),
          (false, true),
          (true, false),
          (true, true),
        ])
          Positioned(
            left: corner.$1 ? null : 10,
            right: corner.$1 ? 10 : null,
            top: corner.$2 ? null : 10,
            bottom: corner.$2 ? 10 : null,
            child: _Bracket(right: corner.$1, bottom: corner.$2),
          ),
        // 시안: 프레임 아래 안내문
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text(
              widget.frameHint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: Color(0xB8FFFFFF),
                shadows: [
                  Shadow(color: Color(0xCC000000), blurRadius: 4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 프레임 슬롯 — 시안의 `flex: 1` 을 그대로 재현한다.
  ///
  /// 🔴 여기가 "왜 갑자기 작아졌어?" 의 정답이다.
  ///
  /// 직전 버전은 프레임 크기를 **센서 비율**로 계산했다.
  ///
  /// ```dart
  /// final ar = 1 / _controller!.value.aspectRatio;   // 4:3 세로 → 0.75
  /// var w = box.maxWidth;
  /// var h = w / ar;
  /// if (h > box.maxHeight) { h = box.maxHeight; w = h * ar; }  // ⚠️ 폭이 줄어든다
  /// ```
  ///
  /// 세로가 넘치면 **가로를 깎아서** 센서 비율을 지켰다. 그래서 프레임이
  /// 슬롯보다 작아지고, 시안의 세로로 긴 영수증 모양이 아니라 사진기
  /// 비율의 작은 사각형이 됐다. 화각을 정직하게 만들려던 수정이 프레임
  /// 크기를 희생한 것이다.
  ///
  /// 이제는 프레임을 **시안 비율([frameAspect])로 슬롯에 꽉** 채우고,
  /// 프리뷰를 `BoxFit.cover` 로 채운다. 그러면 화면과 센서 프레임이
  /// 어긋나는데, 그 차이를 촬영 직후 [_cropToFrame] 이 잘라내서 없앤다.
  /// 화각 정직성과 시안 크기를 둘 다 지키는 유일한 방법이다.
  Widget _previewSlot() {
    return LayoutBuilder(
      builder: (context, box) {
        // 시안 비율로 슬롯을 최대한 채운다.
        var w = box.maxWidth;
        var h = w / frameAspect;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * frameAspect;
          // 세로가 부족해서 가로를 깎게 되면, 시안 느낌을 살리려고
          // 폭을 너무 줄이지는 않는다. 최소 폭을 보장하고 대신 프레임이
          // 조금 더 정사각형에 가까워지도록 허용한다.
          if (w < box.maxWidth * 0.78) {
            w = box.maxWidth * 0.78;
            h = box.maxHeight;
          }
        }
        _frameSize = Size(w, h);
        return Center(child: SizedBox(width: w, height: h, child: _preview()));
      },
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

    // 🔴 화각 계약 (읽지 않고 고치면 반드시 되돌아오는 버그다)
    //
    // 요구가 두 개인데 서로 충돌한다.
    //   (A) 프레임은 시안처럼 세로로 긴 영수증 모양으로 꽉 차야 한다
    //   (B) 라인에 맞춰 찍으면 그대로 저장돼야 한다 (초광각 느낌 금지)
    //
    // 카메라 센서는 4:3(세로로 놓으면 0.75)이고 시안 프레임은 0.62 다.
    // 비율이 다르니 둘 다 만족시키는 배치는 없다.
    //
    // | 방법 | (A) | (B) |
    // |---|---|---|
    // | `contain` + 센서 비율로 프레임 축소 (직전 버전) | ❌ 작아진다 | ✅ |
    // | `cover` + 자르지 않음 (그 전 버전) | ✅ | ❌ 초광각 |
    // | **`cover` + 찍은 JPEG 를 프레임 비율로 자름** | ✅ | ✅ |
    //
    // 마지막 방법을 쓴다. `_cropToFrame()` 이 촬영 직후 `frameAspect` 로
    // 잘라내므로, 화면에서 본 사각형과 파일에 저장된 사각형이 같아진다.
    // (직전 버전에서 이 방법을 안 쓴 이유는 "`image` 패키지를 새 의존성으로
    //  넣어야 한다" 였는데, 크롭/리사이즈 기능이 그 패키지를 이미 필요로
    //  하므로 그 이유는 사라졌다)
    return _framed(
      FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _frameSize.width <= 0 ? 300 : _frameSize.width,
          height: _frameSize.width <= 0
              ? 300 / (1 / _controller!.value.aspectRatio)
              : _frameSize.width / (1 / _controller!.value.aspectRatio),
          child: CameraPreview(_controller!),
        ),
      ),
      topHint: '문서 경계 자동 감지 중',
    );
  }

  /// 찍힌 JPEG 를 **화면에서 보였던 프레임 비율**로 잘라낸다.
  ///
  /// 프리뷰를 `BoxFit.cover` 로 보여주면 센서 프레임의 일부만 화면에
  /// 나타난다. `takePicture()` 는 센서 프레임 전체를 파일에 쓰므로,
  /// 그대로 저장하면 화면보다 넓게 찍히고 영수증이 상대적으로 작아진다.
  /// 그게 "초광각처럼 나온다" 의 정체였다.
  ///
  /// 여기서 같은 비율로 중앙을 잘라내면 그 차이가 없어진다.
  /// 잘라내기가 실패하면 원본을 그대로 쓴다 — 사진 한 장 때문에 촬영을
  /// 실패로 만들지 않는다.
  Future<XFile> _cropToFrame(XFile shot) async {
    try {
      final bytes = await shot.readAsBytes();
      if (bytes.isEmpty) return shot;

      final size = await ReceiptImageEditor.measure(bytes);
      if (size == null) return shot;

      final rect = ReceiptImageEditor.coverCropRect(
        imageWidth: size.width,
        imageHeight: size.height,
        previewAspect: frameAspect,
      );
      // 이미 비율이 같으면(거의 없다) 손대지 않는다.
      if (rect.isFull) return shot;

      final out = await ReceiptImageEditor.transform(
        bytes,
        rect: rect,
        maxDimension: ReceiptImageEditor.defaultMaxDimension,
      );
      if (out == null || out.isEmpty) return shot;

      final stamp = DateTime.now().microsecondsSinceEpoch;
      final name = 'r_shot_$stamp.jpg';

      // 네이티브: 문서 폴더에 실제 파일로 쓴다.
      //
      // 🔴 캐시가 아니라 문서 폴더다. 카메라 원본은
      //    `/data/user/0/com.flownote.app/cache/CAP….jpg` 에 떨어지고
      //    안드로이드가 예고 없이 지운다. 실제로 사장님 계정의 영수증
      //    16건이 그 경로를 들고 있고 파일은 이미 사라진 상태였다.
      //    여기서 문서 폴더에 쓰면 촬영 시점부터 안전한 경로가 된다.
      final dir = await ensureDocsSubdir('receipts');
      if (dir != null) {
        final target = '$dir/$name';
        if (await writeLocalBytes(target, out)) {
          return ReceiptImageEditor.wrap(out, name: name, savedPath: target);
        }
      }
      // 웹: 바이트를 들고 간다. 저장 시점에 클라우드로 올라간다.
      return ReceiptImageEditor.wrap(out, name: name);
    } catch (e) {
      debugPrint('[ScanCamera] 프레임 자르기 실패(원본 사용): $e');
      return shot;
    }
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

/// 시안 코너 브래킷 — 34x34 사각형의 **두 변만** 그린 갈고리.
///
/// ```js
/// div { position:'absolute', width:34, height:34, borderRadius:6,
///       border:'3px solid #EE7686',
///       borderRightWidth: r?3:0, borderLeftWidth: r?0:3,
///       borderBottomWidth: b?3:0, borderTopWidth: b?0:3 }
/// ```
class _Bracket extends StatelessWidget {
  const _Bracket({required this.right, required this.bottom});

  final bool right;
  final bool bottom;

  static const _c = Color(0xFFEE7686);
  static const _w = 3.0;

  @override
  Widget build(BuildContext context) {
    const none = BorderSide.none;
    const on = BorderSide(color: _c, width: _w);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: right ? none : on,
          right: right ? on : none,
          top: bottom ? none : on,
          bottom: bottom ? on : none,
        ),
      ),
    );
  }
}

/// 찍은 한 장 미리보기 — 시안 촬영 화면 톤(cool-neutral-10)을 그대로 유지.
///
/// 여기에 **크롭/리사이즈로 가는 입구**가 붙는다. 촬영 직후가 사장님이
/// 사진을 다시 볼 유일한 지점이라서, 자를 기회도 여기서 줘야 한다.
///
/// 반환: 'retake' | 'add' | 'scan' | null
/// (편집을 하면 [onEdited] 로 새 `XFile` 을 알려주고, 부모가 그 파일을
///  대신 저장한다 — 화면 자체는 계속 살아 있어야 하므로 pop 하지 않는다)
class _ShotPreviewDsScreen extends StatefulWidget {
  const _ShotPreviewDsScreen({
    required this.file,
    required this.shotIndex,
    required this.isMulti,
    required this.onEdited,
  });

  final XFile file;
  final int shotIndex;
  final bool isMulti;

  /// 크롭/리사이즈를 마쳤을 때 부모(`_shoot`)에게 새 파일을 넘긴다.
  final ValueChanged<XFile> onEdited;

  @override
  State<_ShotPreviewDsScreen> createState() => _ShotPreviewDsScreenState();
}

class _ShotPreviewDsScreenState extends State<_ShotPreviewDsScreen> {
  static const _bg = Color(0xFF1B1D22);
  static const _badgeBg = Color(0x4DF2687A);
  static const _badgeFg = Color(0xFFFFC9CE);

  late XFile _file = widget.file;
  bool _edited = false;

  Future<void> _openCrop() async {
    final out = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptCropDsScreen(file: _file),
      ),
    );
    if (!mounted || out == null) return;
    setState(() {
      _file = out;
      _edited = true;
    });
    widget.onEdited(out);
  }

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
                  _edited
                      ? '자르기 적용됨'
                      : (widget.isMulti
                          ? '${widget.shotIndex}장 촬영됨'
                          : '촬영한 사진'),
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
                  //
                  // 🔴 편집한 파일은 `XFile.fromData` 라서 네이티브에서도
                  //    바이트를 들고 있다. `key` 를 바꿔야 새 그림으로 갱신된다.
                  child: XFileImage(_file, key: ValueKey(_file.path),
                      fit: BoxFit.contain),
                ),
              ),
            ),
            // 크롭/리사이즈 입구 — 촬영 직후가 자를 유일한 기회다.
            FnDsButton(
              label: '영수증만 자르기 · 크기 조절',
              size: FnDsButtonSize.large,
              variant: FnDsButtonVariant.outlined,
              foreground: Colors.white,
              expand: true,
              leadingIcon: const Icon(Icons.crop_rounded,
                  size: 19, color: Colors.white),
              onPressed: _openCrop,
            ),
            const SizedBox(height: 10),
            if (widget.isMulti)
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
              label: widget.isMulti
                  ? '${widget.shotIndex}장 인식 시작'
                  : '이 사진으로 인식',
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
