import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/fn_feedback.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_sheet.dart';
import '../../services/inquiry_picker.dart';
import '../../services/inquiry_service.dart';
import '../../theme/fn_ds.dart';

/// 제안 및 피드백(문의하기) — 사장님 시안 1:1.
///
/// ## 배치 (시안 순서)
///
/// ```
///   [←] 제안 및 피드백
///   더 나은 플로우노트를 함께 만들어요        19 / w700
///   문의나 제안을 남겨주시면                  12 / sub
///   관리자가 확인 후 답변드릴게요.
///   카테고리 [필수]                          13.5 / w600 + 코랄 '필수'
///     ▾ 기능 제안                            높이 48 · r12
///   내용 [필수]
///     [여러 줄 입력칸]                 우하단 66 / 1,000
///   파일 첨부 [선택]
///     + 파일 첨부하기                        점선 아닌 실선 테두리
///     [썸네일 ⊗] [썸네일 ⊗] …                최대 3개
///   작성한 내용은 관리자 이메일로 전달돼요.
///   답변은 계정에 등록된 이메일로 안내드려요.
///   [         문의하기         ]              높이 52 · r14 · 코랄
/// ```
///
/// 색·크기·여백은 전부 [FnDs] 에서 가져온다. 이 화면이 통합 기준을
/// 쓰는 첫 화면이다. 다른 화면은 사장님이 개편하실 때 옮긴다.
class InquiryDsScreen extends StatefulWidget {
  const InquiryDsScreen({super.key});

  @override
  State<InquiryDsScreen> createState() => _InquiryDsScreenState();
}

class _InquiryDsScreenState extends State<InquiryDsScreen> {
  static const int _maxLen = 1000;

  final _contentCtrl = TextEditingController();
  final _contentFocus = FocusNode();

  String _category = InquiryService.categories.first;
  final List<InquiryAttachment> _files = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // 글자 수 표시를 살리려면 입력할 때마다 다시 그려야 한다.
    _contentCtrl.addListener(_onChanged);
    _contentFocus.addListener(_onChanged);
  }

  @override
  void dispose() {
    _contentCtrl.removeListener(_onChanged);
    _contentFocus.removeListener(_onChanged);
    _contentCtrl.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSend => _contentCtrl.text.trim().isNotEmpty && !_sending;

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '제안 및 피드백',
      bg: FnDs.bg,
      onBack: () => Navigator.of(context).maybePop(),
      child: ColoredBox(
        color: FnDs.bg,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                      FnDs.pagePad, 18, FnDs.pagePad, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('더 나은 플로우노트를 함께 만들어요',
                          style: FnDs.tsTitle),
                      const SizedBox(height: FnDs.gapXs),
                      const Text(
                        '문의나 제안을 남겨주시면\n관리자가 확인 후 답변드릴게요.',
                        style: FnDs.tsSub,
                      ),
                      const SizedBox(height: FnDs.gapL),
                      _label('카테고리', required: true),
                      const SizedBox(height: 10),
                      _categoryField(),
                      const SizedBox(height: FnDs.gapL),
                      _label('내용', required: true),
                      const SizedBox(height: 10),
                      _contentField(),
                      const SizedBox(height: FnDs.gapL),
                      _label('파일 첨부', required: false),
                      const SizedBox(height: 10),
                      _attachButton(),
                      if (_files.isNotEmpty) ...[
                        const SizedBox(height: FnDs.gapS),
                        _thumbs(),
                      ],
                      const SizedBox(height: FnDs.gapM),
                      const Text(
                        '작성한 내용은 관리자에게 전달돼요.\n'
                        '답변은 계정에 등록된 이메일로 안내드려요.',
                        style: FnDs.tsSub,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    FnDs.pagePad, 4, FnDs.pagePad, 16),
                child: _sendButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `카테고리 필수` — 제목 옆에 작은 코랄 글씨.
  Widget _label(String text, {required bool required}) {
    return Row(
      children: [
        Text(text,
            style: const TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.fontS,
              fontWeight: FontWeight.w700,
              color: FnDs.title,
            )),
        const SizedBox(width: 6),
        Text(
          required ? '필수' : '선택',
          style: TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.fontXs,
            fontWeight: FontWeight.w600,
            color: required ? FnDs.coral : FnDs.sub,
          ),
        ),
      ],
    );
  }

  // ── 카테고리 ────────────────────────────────────────────────
  Widget _categoryField() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _sending ? null : _pickCategory,
      child: Container(
        height: FnDs.inputH,
        padding: const EdgeInsets.symmetric(horizontal: FnDs.inputPadH),
        decoration: BoxDecoration(
          color: FnDs.card,
          borderRadius: BorderRadius.circular(FnDs.inputRadius),
          border: Border.all(color: FnDs.line, width: FnDs.inputBorderW),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _category,
                style: const TextStyle(
                  fontFamily: FnDs.font,
                  fontSize: FnDs.inputFont,
                  color: FnDs.title,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: FnDs.sub),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCategory() async {
    final picked = await showFnOptionSheet<String>(
      context,
      title: '카테고리',
      selected: _category,
      options: [
        for (final c in InquiryService.categories)
          FnSheetOption(value: c, label: c),
      ],
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }

  // ── 내용 ───────────────────────────────────────────────────
  Widget _contentField() {
    final len = _contentCtrl.text.characters.length;
    return Container(
      decoration: BoxDecoration(
        color: FnDs.card,
        borderRadius: BorderRadius.circular(FnDs.inputRadius),
        border: Border.all(
          color: _contentFocus.hasFocus ? FnDs.coral : FnDs.line,
          width: _contentFocus.hasFocus ? 1.4 : FnDs.inputBorderW,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(FnDs.inputPadH, 14, FnDs.inputPadH, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _contentCtrl,
            focusNode: _contentFocus,
            enabled: !_sending,
            maxLines: null,
            minLines: 6,
            maxLength: _maxLen,
            // 기본 카운터를 끄고 시안처럼 오른쪽 아래에 직접 그린다.
            buildCounter: (_,
                    {required currentLength,
                    required isFocused,
                    required maxLength}) =>
                null,
            inputFormatters: [LengthLimitingTextInputFormatter(_maxLen)],
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.inputFont,
              height: 1.5,
              color: FnDs.title,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: '불편한 점이나 바라는 기능을 자유롭게 적어주세요.',
              hintStyle: TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.inputFont,
                height: 1.5,
                color: FnDs.inputHint,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text('$len / $_maxLen', style: FnDs.tsSub),
          ),
        ],
      ),
    );
  }

  // ── 파일 첨부 ───────────────────────────────────────────────
  Widget _attachButton() {
    final full = _files.length >= InquiryService.maxFiles;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: (_sending || full) ? null : _pickAttachment,
      child: Container(
        height: FnDs.inputH,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: FnDs.inputPadH),
        decoration: BoxDecoration(
          color: FnDs.card,
          borderRadius: BorderRadius.circular(FnDs.inputRadius),
          border: Border.all(color: FnDs.line, width: FnDs.inputBorderW),
        ),
        child: Row(
          children: [
            Icon(Icons.add_rounded,
                size: 18, color: full ? FnDs.sub : FnDs.title),
            const SizedBox(width: 8),
            Text(
              full
                  ? '첨부는 ${InquiryService.maxFiles}개까지예요'
                  : '파일 첨부하기',
              style: TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.inputFont,
                color: full ? FnDs.sub : FnDs.title,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 앨범인지 파일인지 먼저 묻고 고른다.
  Future<void> _pickAttachment() async {
    final remaining = InquiryService.maxFiles - _files.length;
    if (remaining <= 0) return;

    final from = await showFnOptionSheet<String>(
      context,
      title: '첨부 방법',
      subtitle: '$remaining개 더 넣을 수 있어요',
      options: const [
        FnSheetOption(
            value: 'album', label: '앨범에서 사진 고르기', icon: Icons.photo_rounded),
        FnSheetOption(
            value: 'file',
            label: '파일에서 고르기',
            icon: Icons.insert_drive_file_rounded),
      ],
    );
    if (from == null || !mounted) return;

    List<InquiryAttachment> picked;
    try {
      picked = from == 'album'
          ? await InquiryPicker.pickImages(remaining)
          : await InquiryPicker.pickFiles(remaining);
    } catch (e) {
      if (!mounted) return;
      showFnToast(context, '파일을 불러오지 못했어요. 권한을 확인해 주세요.',
          type: FnToastType.error);
      return;
    }
    if (!mounted || picked.isEmpty) return;

    // 너무 큰 파일은 고르는 순간 걸러낸다. 올리다가 거부당하면
    // 사장님은 '보내기가 안 된다' 고만 느끼게 된다.
    final tooBig = picked
        .where((f) => f.bytes.lengthInBytes > InquiryService.maxFileBytes)
        .toList();
    final ok = picked
        .where((f) => f.bytes.lengthInBytes <= InquiryService.maxFileBytes)
        .toList();

    setState(() => _files.addAll(ok));

    if (tooBig.isNotEmpty) {
      showFnToast(context, '${tooBig.first.name} 은(는) 10MB가 넘어 빼놨어요.',
          type: FnToastType.warning);
    }
  }

  /// 고른 첨부 목록. 시안처럼 작은 네모 썸네일 + 오른쪽 위 ⊗.
  Widget _thumbs() {
    return Wrap(
      spacing: FnDs.gapS,
      runSpacing: FnDs.gapS,
      children: [
        for (var i = 0; i < _files.length; i++) _thumb(i, _files[i]),
      ],
    );
  }

  Widget _thumb(int index, InquiryAttachment f) {
    const size = 64.0;
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: size,
                height: size,
                child: f.isImage
                    ? Image.memory(f.bytes, fit: BoxFit.cover)
                    : ColoredBox(
                        color: FnDs.coralFaint,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.description_rounded,
                                size: 22, color: FnDs.coral),
                            const SizedBox(height: 3),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                f.sizeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: FnDs.font,
                                  fontSize: 10,
                                  color: FnDs.sub,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _sending ? null : () => setState(() => _files.removeAt(index)),
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Color(0xFF2A2A2A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 보내기 ─────────────────────────────────────────────────
  Widget _sendButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _canSend ? _submit : null,
      child: Container(
        height: FnDs.buttonH,
        alignment: Alignment.center,
        decoration: FnDs.buttonFilled(enabled: _canSend),
        child: _sending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white),
              )
            : Text(
                '문의하기',
                style: TextStyle(
                  fontFamily: FnDs.font,
                  fontSize: FnDs.buttonFont,
                  fontWeight: FnDs.buttonWeight,
                  color: _canSend ? FnDs.onCoral : FnDs.buttonOffFg,
                ),
              ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      await InquiryService.instance.submit(
        category: _category,
        content: _contentCtrl.text,
        files: List.unmodifiable(_files),
      );
      if (!mounted) return;
      await _showDone();
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } on InquiryFailure catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showFnToast(context, e.message, type: FnToastType.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showFnToast(context, '문의를 보내지 못했어요. 잠시 뒤 다시 시도해 주세요.',
          type: FnToastType.error);
    }
  }

  /// 접수 안내. 누르고 나서야 화면을 닫는다.
  Future<void> _showDone() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: FnDs.cardDeco(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                    color: FnDs.coral, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    size: 28, color: Colors.white),
              ),
              const SizedBox(height: FnDs.gapM),
              const Text('문의가 접수되었습니다',
                  textAlign: TextAlign.center, style: FnDs.tsSection),
              const SizedBox(height: FnDs.gapXs),
              const Text(
                '확인 후 계정에 등록된 이메일로\n답변드릴게요.',
                textAlign: TextAlign.center,
                style: FnDs.tsSub,
              ),
              const SizedBox(height: FnDs.gapL),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  height: FnDs.buttonH,
                  alignment: Alignment.center,
                  decoration: FnDs.buttonFilled(),
                  child: const Text(
                    '확인',
                    style: TextStyle(
                      fontFamily: FnDs.font,
                      fontSize: FnDs.buttonFont,
                      fontWeight: FnDs.buttonWeight,
                      color: FnDs.onCoral,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
