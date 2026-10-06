import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/file_saver.dart';
import '../services/camera_quality.dart';
import '../services/receipt_image_editor.dart';
import '../theme/app_theme.dart';

/// 앱 내 카메라 화면
/// [mode] : 'single' → 1장 찍고 바로 반환 / 'multi' → 연속 촬영
/// 반환값: List of XFile (single이면 1개, multi면 1개 이상)
class InAppCameraScreen extends StatefulWidget {
  final String mode; // 'single' | 'multi'

  const InAppCameraScreen({super.key, required this.mode});

  @override
  State<InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<InAppCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isTakingPicture = false;
  bool _isFrontCamera = false;
  bool _isFlashOn = false;

  /// 시안 촬영 프레임 비율(가로/세로). `ScanCameraDsScreen.frameAspect`
  /// 와 같은 값을 써야 두 화면이 같은 사진을 만든다.
  static const double _frameAspect = 0.62;

  // 연속 촬영 시 찍은 사진 목록
  final List<XFile> _capturedImages = [];

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
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(useFront: _isFrontCamera);
    }
  }

  Future<void> _initCamera({bool useFront = false}) async {
    try {
      // iOS 권한 확인 및 요청
      final status = await Permission.camera.status;

      if (status.isPermanentlyDenied) {
        // 영구 거부 → 설정으로 이동 안내
        if (mounted) _showPermissionDeniedDialog();
        return;
      }

      if (status.isDenied || status.isRestricted || !status.isGranted) {
        // notDetermined(최초) / denied / restricted → 권한 팝업 요청
        final result = await Permission.camera.request();
        if (!result.isGranted) {
          if (mounted) _showPermissionDeniedDialog();
          return;
        }
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          _showError('카메라를 찾을 수 없습니다.');
        }
        return;
      }

      final description = useFront && _cameras.length > 1
          ? _cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => _cameras.first,
            )
          : _cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => _cameras.first,
            );

      await _controller?.dispose();

      // 🔴 ScanCameraDsScreen 과 반드시 같은 방식으로 열어야 한다.
      //    한쪽만 고치면 캘린더/사업자 등록 경로에서만 화질이 나빠진다.
      //    ResolutionPreset.high 를 박아 두면 안 되는 이유는
      //    CameraQuality 문서 주석에 정리해 뒀다.
      final controller = await CameraQuality.open(description);

      _controller = controller;
      if (!mounted) return;

      // 플래시 초기 설정
      await controller.setFlashMode(
          _isFlashOn ? FlashMode.torch : FlashMode.off);

      setState(() {
        _isInitialized = true;
        _isFrontCamera = useFront;
      });
    } catch (e) {
      if (mounted) _showError('카메라 초기화 실패: $e');
    }
  }

  Future<void> _toggleCamera() async {
    setState(() => _isInitialized = false);
    await _initCamera(useFront: !_isFrontCamera);
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() => _isFlashOn = !_isFlashOn);
    await controller.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off);
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isTakingPicture) return;

    setState(() => _isTakingPicture = true);

    try {
      final raw = await controller.takePicture();
      // 화면에서 본 프레임만 남긴다. 실패하면 원본을 그대로 쓴다.
      final xfile = await _cropToFrame(raw);

      if (!mounted) return;

      if (widget.mode == 'single') {
        // 단일 촬영: 미리보기 화면으로 이동
        final action = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => _PreviewScreen(
              imageFile: xfile,
              capturedCount: 0,
              isSingleMode: true,
            ),
          ),
        );
        if (!mounted) return;
        if (action == 'scan') {
          Navigator.pop(context, [xfile]);
        }
        // 'retake' 이면 그냥 다시 카메라로 돌아옴
      } else {
        // 연속 촬영: 미리보기 화면으로 이동
        final action = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => _PreviewScreen(
              imageFile: xfile,
              capturedCount: _capturedImages.length,
              isSingleMode: false,
            ),
          ),
        );
        if (!mounted) return;

        if (action == 'retake') {
          // 버림, 루프 계속
        } else if (action == 'add') {
          _capturedImages.add(xfile);
          // 루프 계속 (카메라로 돌아옴)
        } else if (action == 'scan') {
          _capturedImages.add(xfile);
          Navigator.pop(context, List<XFile>.from(_capturedImages));
        }
        // null (뒤로가기) → 이 장도 추가하고 스캔 확인
        else if (action == null) {
          _capturedImages.add(xfile);
          await _confirmScanOrExit();
        }
      }
    } catch (e) {
      if (mounted) _showError('촬영 실패: $e');
    } finally {
      if (mounted) setState(() => _isTakingPicture = false);
    }
  }

  Future<void> _confirmScanOrExit() async {
    if (_capturedImages.isEmpty) {
      Navigator.pop(context, <XFile>[]);
      return;
    }
    final doScan = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('촬영 종료'),
        content: Text(
            '지금까지 ${_capturedImages.length}장을 촬영했습니다.\n스캔을 진행할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('스캔 시작',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (doScan == true) {
      Navigator.pop(context, List<XFile>.from(_capturedImages));
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.camera_alt, color: Colors.orange),
            SizedBox(width: 8),
            Text('카메라 권한 필요'),
          ],
        ),
        content: const Text(
          '영수증 촬영을 위해 카메라 접근 권한이 필요합니다.\n\n설정 > FlowNote > 카메라를 허용해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // 카메라 화면 닫기
            },
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings(); // iOS 설정 앱으로 이동
            },
            child: const Text('설정으로 이동'),
          ),
        ],
      ),
    );
  }

  // 뒤로가기 처리 (multi + 찍은 게 있을 때 확인 다이얼로그)
  Future<void> _onPopInvoked(bool didPop) async {
    if (didPop) return;
    if (widget.mode == 'multi' && _capturedImages.isNotEmpty) {
      final doScan = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('촬영을 마칠까요?'),
          content: Text(
              '${_capturedImages.length}장을 찍었어요.\n지금까지 찍은 사진으로 스캔을 시작할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('계속 촬영',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'exit'),
              child: const Text('그냥 나가기',
                  style: TextStyle(color: AppColors.error)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'scan'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: const Text('스캔 시작',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (doScan == 'scan') {
        Navigator.pop(context, List<XFile>.from(_capturedImages));
      } else if (doScan == 'exit') {
        Navigator.pop(context, <XFile>[]);
      }
      // 'cancel' → 카메라 화면 유지
    } else {
      Navigator.pop(context, <XFile>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onPopInvoked(didPop),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(child: _buildCameraPreview()),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── 상단 바: 닫기 / 플래시 / 전후면 전환 ──
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 닫기
          IconButton(
            onPressed: () async {
              if (widget.mode == 'multi' && _capturedImages.isNotEmpty) {
                await _confirmScanOrExit();
              } else {
                Navigator.pop(context, <XFile>[]);
              }
            },
            icon: const Icon(Icons.close, color: Colors.white, size: 26),
          ),
          const Spacer(),

          // 연속 촬영 모드: 찍은 장 수 + "지금 스캔" 버튼
          if (widget.mode == 'multi' && _capturedImages.isNotEmpty) ...[
            GestureDetector(
              onTap: () =>
                  Navigator.pop(context, List<XFile>.from(_capturedImages)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${_capturedImages.length}장 스캔',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // 플래시
          IconButton(
            onPressed: _toggleFlash,
            icon: Icon(
              _isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: _isFlashOn ? Colors.yellow : Colors.white,
              size: 24,
            ),
          ),

          // 전후면 전환 (카메라 2개 이상일 때만)
          if (_cameras.length > 1)
            IconButton(
              onPressed: _toggleCamera,
              icon: const Icon(Icons.flip_camera_android,
                  color: Colors.white, size: 24),
            ),
        ],
      ),
    );
  }

  // ── 카메라 프리뷰 ──
  Widget _buildCameraPreview() {
    if (!_isInitialized || _controller == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 12),
            Text('카메라 준비 중...',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      );
    }

    // 🔴 화각 계약 — `scan_camera_ds_screen.dart` 와 **똑같은 규칙**을 쓴다.
    //
    // 직전 버전은 `BoxFit.contain` + 센서 비율로 프리뷰를 그렸다. 화각은
    // 정직해졌지만 프레임이 시안보다 훨씬 작아졌다("왜 갑자기 작아졌어?").
    //
    // 이제는 시안 비율([_frameAspect])로 프레임을 슬롯에 꽉 채우고,
    // 프리뷰를 `BoxFit.cover` 로 채우고, 찍힌 JPEG 를 같은 비율로 잘라낸다
    // (`_cropToFrame`). 화면과 파일이 같아지고 프레임도 커진다.
    return LayoutBuilder(
      builder: (context, constraints) {
        var w = constraints.maxWidth;
        var h = w / _frameAspect;
        if (h > constraints.maxHeight) {
          h = constraints.maxHeight;
          w = h * _frameAspect;
          if (w < constraints.maxWidth * 0.78) {
            w = constraints.maxWidth * 0.78;
            h = constraints.maxHeight;
          }
        }
        final previewW = w;
        final previewH = w / (1 / _controller!.value.aspectRatio);
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    color: const Color(0x0AFFFFFF),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: previewW,
                        height: previewH,
                        child: CameraPreview(_controller!),
                      ),
                    ),
                  ),
                ),
                // 시안: 46% 높이 스캔 라인
                Positioned(
                  left: 26,
                  right: 26,
                  top: h * 0.46,
                  child: Container(
                    height: 2,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Color(0x00EE7686),
                        Color(0xFFEE7686),
                        Color(0x00EE7686),
                      ]),
                    ),
                  ),
                ),
                // 시안: 네 귀퉁이 브래킷
                for (final c in const [
                  (false, false),
                  (false, true),
                  (true, false),
                  (true, true),
                ])
                  Positioned(
                    left: c.$1 ? null : 10,
                    right: c.$1 ? 10 : null,
                    top: c.$2 ? null : 10,
                    bottom: c.$2 ? 10 : null,
                    child: _CornerBracket(right: c.$1, bottom: c.$2),
                  ),
                // 시안: 프레임 아래 안내문
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: Text(
                      '영수증을 프레임 안에 맞춰주세요',
                      style: TextStyle(
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
            ),
          ),
        );
      },
    );
  }

  /// 찍힌 JPEG 를 화면에서 보였던 프레임 비율로 잘라낸다.
  /// 실패하면 원본을 그대로 쓴다.
  Future<XFile> _cropToFrame(XFile shot) async {
    try {
      final bytes = await shot.readAsBytes();
      if (bytes.isEmpty) return shot;
      // 🔴 프리뷰 표면 비율을 반드시 함께 넘긴다.
      //    이걸 빼면 "찍을 때랑 찍고 나서 배율이 다르다" 가 그대로 돌아온다.
      //    프리셋에 따라 프리뷰가 사진과 다른 비율일 수 있다. 예를 들어
      //    사진은 4:3 으로 찍힐 수 있어서, 프리뷰가 이미 촬영본의 중앙
      //    일부만 보여주고 있다. coverCropRect 가 그 몫까지 계산한다.
      final c = _controller;
      final double? cameraAspect =
          (c != null && c.value.isInitialized && c.value.previewSize != null)
              ? 1 / c.value.aspectRatio
              : null;

      final size = await ReceiptImageEditor.measure(bytes);
      if (size == null) return shot;
      final rect = ReceiptImageEditor.coverCropRect(
        imageWidth: size.width,
        imageHeight: size.height,
        previewAspect: _frameAspect,
        cameraAspect: cameraAspect,
      );
      if (rect.isFull) return shot;
      final out = await ReceiptImageEditor.transform(
        bytes,
        rect: rect,
        maxDimension: ReceiptImageEditor.defaultMaxDimension,
      );
      if (out == null || out.isEmpty) return shot;

      final stamp = DateTime.now().microsecondsSinceEpoch;
      final name = 'r_shot_$stamp.jpg';
      // 캐시가 아니라 문서 폴더에 쓴다. 캐시는 OS 가 예고 없이 비운다.
      final dir = await ensureDocsSubdir('receipts');
      if (dir != null) {
        final target = '$dir/$name';
        if (await writeLocalBytes(target, out)) {
          return ReceiptImageEditor.wrap(out, name: name, savedPath: target);
        }
      }
      return ReceiptImageEditor.wrap(out, name: name);
    } catch (e) {
      debugPrint('[InAppCamera] 프레임 자르기 실패(원본 사용): $e');
      return shot;
    }
  }

  // ── 하단 바: 촬영 버튼 + (multi & 1장 이상) 완료 버튼 ──
  Widget _buildBottomBar() {
    final hasCaptured =
        widget.mode == 'multi' && _capturedImages.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 완료 버튼 (1장 이상 찍었을 때만)
          if (hasCaptured) ...
            [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(
                      context, List<XFile>.from(_capturedImages)),
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: Text(
                      '${_capturedImages.length}장 촬영 완료 · 스캔 시작'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          // 촬영 버튼
          GestureDetector(
            onTap: _isTakingPicture ? null : _takePicture,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _isTakingPicture ? 68 : 72,
              height: _isTakingPicture ? 68 : 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isTakingPicture ? Colors.white54 : Colors.white,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5), width: 4),
              ),
              child: _isTakingPicture
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.black54),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 찍은 사진 미리보기 화면 ──
class _PreviewScreen extends StatelessWidget {
  final XFile imageFile;
  final int capturedCount; // 이 장 찍기 전까지의 수
  final bool isSingleMode;

  const _PreviewScreen({
    required this.imageFile,
    required this.capturedCount,
    required this.isSingleMode,
  });

  @override
  Widget build(BuildContext context) {
    final totalSoFar = capturedCount + 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── 상단 바 ──
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // 장 수 배지 (연속 촬영만)
                  if (!isSingleMode)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$totalSoFar장 촬영됨',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  const Spacer(),
                  // 2장 이상이면 지금 스캔 버튼
                  if (!isSingleMode && totalSoFar >= 2)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, 'scan'),
                      icon: const Icon(Icons.check_circle_outline,
                          color: Colors.white, size: 18),
                      label: const Text('지금 스캔',
                          style:
                              TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                ],
              ),
            ),

            // ── 사진 미리보기 ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(imageFile.path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image,
                          color: Colors.white54, size: 64),
                    ),
                  ),
                ),
              ),
            ),

            // ── 하단 버튼 ──
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: [
                  if (!isSingleMode) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _OutlineBtn(
                            icon: Icons.replay_outlined,
                            label: '다시 찍기',
                            onTap: () => Navigator.pop(context, 'retake'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OutlineBtn(
                            icon: Icons.add_a_photo_outlined,
                            label: '계속 촬영',
                            onTap: () => Navigator.pop(context, 'add'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ] else ...[
                    // 단일 모드: 다시 찍기를 전체 너비로
                    SizedBox(
                      width: double.infinity,
                      child: _OutlineBtn(
                        icon: Icons.replay_outlined,
                        label: '다시 찍기',
                        onTap: () => Navigator.pop(context, 'retake'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // 스캔 시작 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, 'scan'),
                      icon: const Icon(Icons.document_scanner_outlined,
                          size: 20),
                      label: Text(
                        isSingleMode
                            ? '이 사진으로 스캔'
                            : '$totalSoFar장 모두 스캔 시작',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OutlineBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.white54),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// 시안 코너 브래킷 — 34x34 사각형의 두 변만 그린 갈고리.
class _CornerBracket extends StatelessWidget {
  const _CornerBracket({required this.right, required this.bottom});

  final bool right;
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    const none = BorderSide.none;
    const on = BorderSide(color: Color(0xFFEE7686), width: 3);
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
