import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_button.dart';
import '../../design/fn_card.dart';
import '../../design/fn_input.dart';
import '../../design/fn_scaffold.dart';
import '../../design/fn_sheet.dart';
import '../../design/fn_feedback.dart';
import '../../services/business_ocr_service.dart';
import '../../services/gallery_intake.dart';
import '../in_app_camera_screen.dart';

/// 사업자등록증 촬영 → 인식 → 결과 확인 화면.
///
/// 한 화면 안에서 3단계(`_Stage`)를 전환한다.
/// 확인 완료 시 [BusinessInfoResult] 를 pop 으로 반환.
class BusinessScanScreen extends StatefulWidget {
  const BusinessScanScreen({super.key});

  @override
  State<BusinessScanScreen> createState() => _BusinessScanScreenState();
}

enum _Stage { intro, recognizing, confirm }

class _BusinessScanScreenState extends State<BusinessScanScreen> {
  final _ocr = BusinessOcrService();

  _Stage _stage = _Stage.intro;
  XFile? _file;
  BusinessInfoResult? _result;

  // 확인 단계 컨트롤러
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _owner = TextEditingController();
  final _address = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _number, _owner, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    XFile? f;
    if (src == ImageSource.camera) {
      if (!await _ensureCamera()) return;
      if (!mounted) return;
      final r = await Navigator.push<List<XFile>>(
        context,
        MaterialPageRoute(
          builder: (_) => const InAppCameraScreen(mode: 'single'),
        ),
      );
      if (r != null && r.isNotEmpty) f = r.first;
    } else {
      // 🔴 웹에서는 `image_picker` 를 **거치지 않는다.**
      // 플러그인은 `blob:` URL 만 남기고 `File` 객체와 `<input>` 을 버린다.
      // 그 URL 은 브라우저가 임의의 시점에 정리해버릴 수 있어서 같은 사진이
      // 될 때도 있고 안 될 때도 있었다. `pickAndPrepare` 는 웹에서 `File` 을
      // 직접 붙잡고 읽어 blob URL 을 아예 만들지 않는다.
      final intake = await GalleryIntake.pickAndPrepare(multiple: false);
      if (!mounted || intake == null) return; // 취소
      if (intake.usable.isEmpty) {
        showFnToast(
          context,
          '사진 파일을 읽을 수 없어요. 갤러리에서 사진을 한 번 열어 내려받은 뒤 다시 골라주세요',
          type: FnToastType.error,
          duration: const Duration(seconds: 5),
        );
        return;
      }
      f = intake.usable.first;
    }
    if (f == null || !mounted) return;

    setState(() {
      _file = f;
      _stage = _Stage.recognizing;
    });

    final res = await _ocr.recognize(xFile: f);
    if (!mounted) return;

    if (!res.success) {
      setState(() => _stage = _Stage.intro);
      final retry = await showFnAlert(
        context,
        title: '인식하지 못했어요',
        message: res.errorMessage,
        icon: Icons.error_outline_rounded,
        iconColor: FnColors.statusNegative,
        confirmLabel: '다시 찍기',
        cancelLabel: '직접 입력',
      );
      if (!mounted) return;
      if (retry) {
        _pick(ImageSource.camera);
      } else {
        Navigator.pop(context);
      }
      return;
    }

    _name.text = res.businessName;
    _number.text = res.businessNumber;
    _owner.text = res.ownerName;
    _address.text = res.businessAddress;
    setState(() {
      _result = res;
      _stage = _Stage.confirm;
    });
  }

  Future<bool> _ensureCamera() async {
    var s = await Permission.camera.status;
    if (s.isGranted) return true;
    if (s.isPermanentlyDenied) {
      if (!mounted) return false;
      final go = await showFnAlert(
        context,
        title: '카메라 권한이 필요해요',
        message: '설정에서 카메라 접근을 허용해 주세요.',
        icon: Icons.camera_alt_rounded,
        confirmLabel: '설정 열기',
        cancelLabel: '닫기',
      );
      if (go) await openAppSettings();
      return false;
    }
    s = await Permission.camera.request();
    return s.isGranted;
  }

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _Stage.intro => _buildIntro(),
      _Stage.recognizing => _buildRecognizing(),
      _Stage.confirm => _buildConfirm(),
    };
  }

  // ─────────────── 1. 안내 + 촬영

  Widget _buildIntro() {
    return FnScaffold(
      title: '사업자등록증 촬영',
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FnButton(
            label: '촬영하기',
            size: FnButtonSize.large,
            expand: true,
            leadingIcon: Icons.photo_camera_rounded,
            onPressed: () => _pick(ImageSource.camera),
          ),
          const SizedBox(height: FnSpace.x8),
          FnButton(
            label: '앨범에서 고르기',
            variant: FnButtonVariant.text,
            size: FnButtonSize.large,
            expand: true,
            onPressed: () => _pick(ImageSource.gallery),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            FnSpace.x20, FnSpace.x8, FnSpace.x20, FnSpace.x24),
        children: [
          Text('등록증 전체가 보이게 찍어주세요', style: FnType.title3),
          const SizedBox(height: FnSpace.x6),
          Text(
            '상호·등록번호·대표자명을 자동으로 읽어와요.',
            style: FnType.body2.copyWith(color: FnColors.labelAlternative),
          ),
          const SizedBox(height: FnSpace.x24),
          const _GuideFrame(),
          const SizedBox(height: FnSpace.x24),
          const _Rule(
            icon: Icons.crop_free_rounded,
            text: '네 모서리가 모두 화면 안에 들어오게',
          ),
          const _Rule(
            icon: Icons.wb_sunny_rounded,
            text: '그림자와 빛 반사가 없는 곳에서',
          ),
          const _Rule(
            icon: Icons.straighten_rounded,
            text: '기울지 않게 정면에서',
          ),
        ],
      ),
    );
  }

  // ─────────────── 2. 인식 중

  Widget _buildRecognizing() {
    return Scaffold(
      backgroundColor: FnColors.backgroundApp,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_file != null && !kIsWeb)
              ClipRRect(
                borderRadius: FnRadius.br16,
                child: Image.file(
                  File(_file!.path),
                  width: 220,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              )
            else
              Container(
                width: 220,
                height: 150,
                decoration: BoxDecoration(
                  color: FnColors.neutral97,
                  borderRadius: FnRadius.br16,
                ),
                child: const Icon(Icons.description_rounded,
                    size: 42, color: FnColors.neutral80),
              ),
            const SizedBox(height: FnSpace.x32),
            const FnSpinner(size: 30),
            const SizedBox(height: FnSpace.x20),
            Text('사업자등록증을 읽고 있어요', style: FnType.heading1),
            const SizedBox(height: FnSpace.x8),
            Text('보통 5초 안에 끝나요',
                style: FnType.body2
                    .copyWith(color: FnColors.labelAlternative)),
          ],
        ),
      ),
    );
  }

  // ─────────────── 3. 결과 확인

  Widget _buildConfirm() {
    final r = _result!;
    final lowConf = r.confidence > 0 && r.confidence < 0.7;

    return FnScaffold(
      title: '인식 결과 확인',
      onBack: () => setState(() => _stage = _Stage.intro),
      bottomBar: FnButton(
        label: '이 정보로 사용하기',
        size: FnButtonSize.large,
        expand: true,
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                  context,
                  r.copyWith(
                    businessName: _name.text.trim(),
                    businessNumber: BusinessOcrService.normalizeBizNumber(
                        _number.text.trim()),
                    ownerName: _owner.text.trim(),
                    businessAddress: _address.text.trim(),
                  ),
                ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            FnSpace.x20, FnSpace.x8, FnSpace.x20, FnSpace.x24),
        children: [
          if (lowConf)
            Container(
              margin: const EdgeInsets.only(bottom: FnSpace.x12),
              padding: const EdgeInsets.all(FnSpace.x12),
              decoration: BoxDecoration(
                color: FnColors.statusCautionaryBg,
                borderRadius: FnRadius.br12,
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 18, color: FnColors.statusCautionary),
                  const SizedBox(width: FnSpace.x8),
                  Expanded(
                    child: Text('글자가 흐릿해요. 아래 내용을 한번 확인해 주세요.',
                        style: FnType.caption1
                            .copyWith(color: FnColors.labelNeutral)),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 18, color: FnColors.statusPositive),
              const SizedBox(width: FnSpace.x6),
              Text('읽어온 정보', style: FnType.heading2),
            ],
          ),
          const SizedBox(height: FnSpace.x12),
          FnTextField(
              label: '상호',
              controller: _name,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: FnSpace.x14),
          FnTextField(label: '사업자등록번호', controller: _number),
          const SizedBox(height: FnSpace.x14),
          FnTextField(label: '대표자명', controller: _owner),
          const SizedBox(height: FnSpace.x14),
          FnTextField(label: '사업장 주소', controller: _address, maxLines: 2),
          if (r.businessType.isNotEmpty || r.businessItem.isNotEmpty) ...[
            const SizedBox(height: FnSpace.x16),
            FnCard(
              bordered: true,
              radius: FnRadius.r12,
              padding: const EdgeInsets.all(FnSpace.x14),
              child: Column(
                children: [
                  if (r.businessType.isNotEmpty)
                    _MiniRow(label: '업태', value: r.businessType),
                  if (r.businessItem.isNotEmpty) ...[
                    const SizedBox(height: FnSpace.x8),
                    _MiniRow(label: '종목', value: r.businessItem),
                  ],
                  if (r.openDate.isNotEmpty) ...[
                    const SizedBox(height: FnSpace.x8),
                    _MiniRow(label: '개업일', value: r.openDate),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: FnSpace.x16),
          Center(
            child: FnTextButton(
              label: '다시 찍기',
              color: FnColors.labelAlternative,
              onPressed: () => setState(() => _stage = _Stage.intro),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideFrame extends StatelessWidget {
  const _GuideFrame();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.5,
      child: Container(
        decoration: BoxDecoration(
          color: FnColors.rose99,
          borderRadius: FnRadius.br16,
          border: Border.all(
              color: FnColors.primaryNormal.withValues(alpha: 0.35),
              width: 2),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined,
                  size: 44, color: FnColors.rose70),
              const SizedBox(height: FnSpace.x10),
              Text('사 업 자 등 록 증',
                  style: FnType.label1
                      .copyWith(color: FnColors.labelAssistive)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FnSpace.x10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: FnColors.primaryNormal),
          const SizedBox(width: FnSpace.x10),
          Expanded(
            child: Text(text,
                style: FnType.body2.copyWith(color: FnColors.labelNeutral)),
          ),
        ],
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(label,
              style: FnType.caption1
                  .copyWith(color: FnColors.labelAlternative)),
        ),
        Expanded(
          child: Text(value,
              style: FnType.body2.copyWith(color: FnColors.labelNormal)),
        ),
      ],
    );
  }
}
