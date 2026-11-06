import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_button.dart';
import '../../design/fn_card.dart';
import '../../design/fn_input.dart';
import '../../design/fn_scaffold.dart';
import '../../design/fn_feedback.dart';
import '../../providers/auth_provider.dart';
import '../../services/business_ocr_service.dart';
import 'business_scan_screen.dart';
import 'onboarding_complete_screen.dart';

/// 사업자 정보 입력 화면.
///
/// 사업자등록증을 찍으면 자동으로 채워지고, 직접 입력도 가능하다.
class BusinessInfoScreen extends StatefulWidget {
  const BusinessInfoScreen({super.key, this.isOnboarding = true});

  /// 온보딩 중이면 완료 후 완료 화면으로, 아니면 그냥 pop.
  final bool isOnboarding;

  @override
  State<BusinessInfoScreen> createState() => _BusinessInfoScreenState();
}

class _BusinessInfoScreenState extends State<BusinessInfoScreen> {
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _owner = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();

  bool _saving = false;
  bool _autoFilled = false;
  String? _numberError;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthProvider>().currentUser;
    if (u != null) {
      _name.text = u.businessName;
      _number.text = u.businessNumber;
      _owner.text = u.ownerName;
      _address.text = u.businessAddress;
      _phone.text = u.phoneNumber;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _number, _owner, _address, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      _number.text.trim().isNotEmpty &&
      _owner.text.trim().isNotEmpty;

  Future<void> _scan() async {
    final r = await Navigator.push<BusinessInfoResult>(
      context,
      MaterialPageRoute(builder: (_) => const BusinessScanScreen()),
    );
    if (r == null || !mounted) return;

    setState(() {
      if (r.businessName.isNotEmpty) _name.text = r.businessName;
      if (r.businessNumber.isNotEmpty) _number.text = r.businessNumber;
      if (r.ownerName.isNotEmpty) _owner.text = r.ownerName;
      if (r.businessAddress.isNotEmpty) _address.text = r.businessAddress;
      _autoFilled = true;
      _validateNumber();
    });
    showFnToast(context, '사업자 정보를 불러왔어요', type: FnToastType.success);
  }

  void _validateNumber() {
    final v = _number.text.trim();
    if (v.isEmpty) {
      _numberError = null;
    } else if (v.replaceAll(RegExp(r'[^0-9]'), '').length != 10) {
      _numberError = '10자리 숫자를 입력해 주세요';
    } else if (!BusinessOcrService.isValidBizNumber(v)) {
      _numberError = '유효하지 않은 사업자번호예요';
    } else {
      _numberError = null;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await context.read<AuthProvider>().updateBusinessInfo(
          businessName: _name.text.trim(),
          businessNumber:
              BusinessOcrService.normalizeBizNumber(_number.text.trim()),
          ownerName: _owner.text.trim(),
          businessAddress: _address.text.trim(),
          phoneNumber: _phone.text.trim(),
        );
    if (!mounted) return;
    setState(() => _saving = false);

    if (widget.isOnboarding) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OnboardingCompleteScreen(
            businessName: _name.text.trim(),
          ),
        ),
      );
    } else {
      showFnToast(context, '사업자 정보를 저장했어요', type: FnToastType.success);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FnScaffold(
          title: '사업자 정보',
          actions: [
            if (widget.isOnboarding)
              FnTextButton(
                label: '나중에',
                color: FnColors.labelAlternative,
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OnboardingCompleteScreen(),
                  ),
                ),
              ),
          ],
          bottomBar: FnButton(
            label: widget.isOnboarding ? '다음' : '저장',
            size: FnButtonSize.large,
            expand: true,
            onPressed: _canSave ? _save : null,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
                FnSpace.x20, FnSpace.x8, FnSpace.x20, FnSpace.x32),
            children: [
              Text('정산서에 들어갈 정보예요', style: FnType.title3),
              const SizedBox(height: FnSpace.x6),
              Text(
                '사업자등록증을 찍으면 자동으로 채워드려요.',
                style:
                    FnType.body2.copyWith(color: FnColors.labelAlternative),
              ),
              const SizedBox(height: FnSpace.x20),

              // 등록증 스캔 카드
              FnCard(
                color: FnColors.rose99,
                onTap: _scan,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: FnColors.rose95,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.document_scanner_rounded,
                          size: 21, color: FnColors.primaryNormal),
                    ),
                    const SizedBox(width: FnSpace.x12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('사업자등록증 촬영', style: FnType.heading2),
                          const SizedBox(height: 2),
                          Text('상호·번호·주소를 한 번에 입력',
                              style: FnType.caption1.copyWith(
                                  color: FnColors.labelAlternative)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: FnColors.labelAssistive),
                  ],
                ),
              ),
              if (_autoFilled) ...[
                const SizedBox(height: FnSpace.x8),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 14, color: FnColors.statusPositive),
                    const SizedBox(width: FnSpace.x6),
                    Text('자동으로 채웠어요. 틀린 곳이 있으면 고쳐주세요.',
                        style: FnType.caption1
                            .copyWith(color: FnColors.statusPositiveStrong)),
                  ],
                ),
              ],
              const SizedBox(height: FnSpace.x24),

              FnTextField(
                label: '상호 *',
                hint: '예) 플로우노트 플라워',
                controller: _name,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: FnSpace.x16),
              FnTextField(
                label: '사업자등록번호 *',
                hint: '000-00-00000',
                controller: _number,
                keyboardType: TextInputType.number,
                errorText: _numberError,
                inputFormatters: [_BizNumberFormatter()],
                onChanged: (_) => setState(_validateNumber),
              ),
              const SizedBox(height: FnSpace.x16),
              FnTextField(
                label: '대표자명 *',
                hint: '예) 홍길동',
                controller: _owner,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: FnSpace.x16),
              FnTextField(
                label: '사업장 주소',
                hint: '예) 서울시 서초구 반포대로 1',
                controller: _address,
                maxLines: 2,
              ),
              const SizedBox(height: FnSpace.x16),
              FnTextField(
                label: '연락처',
                hint: '예) 02-1234-5678',
                controller: _phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: FnSpace.x20),
              Container(
                padding: const EdgeInsets.all(FnSpace.x12),
                decoration: BoxDecoration(
                  color: FnColors.fillAlternative,
                  borderRadius: FnRadius.br12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 16, color: FnColors.labelAssistive),
                    const SizedBox(width: FnSpace.x8),
                    Expanded(
                      child: Text(
                        '입력한 사업자 정보는 이 기기에만 저장되고, 정산서를 만들 때만 사용해요.',
                        style: FnType.caption1
                            .copyWith(color: FnColors.labelAlternative),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_saving) const FnLoadingOverlay(message: '저장하는 중...'),
      ],
    );
  }
}

/// 000-00-00000 자동 하이픈.
class _BizNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final d = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return const TextEditingValue();
    final capped = d.length > 10 ? d.substring(0, 10) : d;

    final b = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 3 || i == 5) b.write('-');
      b.write(capped[i]);
    }
    final t = b.toString();
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

/// 온보딩 밖(프로필)에서 사업자 정보를 편집할 때 쓰는 헬퍼.
Future<bool> openBusinessInfo(BuildContext context) async {
  final r = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => const BusinessInfoScreen(isOnboarding: false),
    ),
  );
  return r ?? false;
}

/// 갤러리에서 등록증 이미지를 고르는 헬퍼 (스캔 화면에서 사용).
Future<XFile?> pickBusinessImage() => ImagePicker()
    .pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600);
