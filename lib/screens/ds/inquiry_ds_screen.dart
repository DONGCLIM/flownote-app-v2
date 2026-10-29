import 'package:flutter/material.dart';

import '../../design/fn_feedback.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_sheet.dart';
import '../../services/inquiry_picker.dart';
import '../../services/inquiry_service.dart';
import '../../theme/fn_ds.dart';
import '../../widgets/fn_inquiry_parts.dart';

/// 문의 쓰기 / 고치기 — 사장님 시안 1:1.
///
/// ## 배치 (시안 순서)
///
/// ```
///   [←] 제안 및 피드백
///   더 나은 플로우노트를 함께 만들어요        19 / w700
///   문의나 제안을 남겨주시면                  12 / sub
///   관리자가 확인 후 답변드릴게요.
///   카테고리 [필수]                          FnFieldLabel
///     기능 제안                       ▾      FnCategoryPicker
///   내용 [필수]
///     [여러 줄 입력칸]           우하단 0 / 1,000   FnLongTextField
///   사진 첨부 [선택]
///     + 사진 첨부하기                        FnPhotoAttachField
///     [썸네일 ⊗] …                           최대 3장
///   작성한 내용은 관리자에게 전달돼요.
///   답변은 계정에 등록된 이메일로 안내드려요.
///   [         문의하기         ]              FnPrimaryButton
/// ```
///
/// ## 두 가지 모드
///
/// | | [origin] 이 null | [origin] 이 있음 |
/// |---|---|---|
/// | 제목 | 제안 및 피드백 | 문의 수정 |
/// | 버튼 | 문의하기 | 수정 완료 |
/// | 첨부 | 새 사진만 | 기존 사진 + 새 사진 |
///
/// 🔴 화면을 둘로 나누지 않았다. 쓰기와 고치기는 칸이 똑같아서
///    따로 만들면 한쪽만 고쳐 놓고 다른 쪽을 잊게 된다.
class InquiryDsScreen extends StatefulWidget {
  const InquiryDsScreen({super.key, this.origin});

  /// 고칠 글. null 이면 새로 쓰기.
  final Inquiry? origin;

  @override
  State<InquiryDsScreen> createState() => _InquiryDsScreenState();
}

class _InquiryDsScreenState extends State<InquiryDsScreen> {
  static const int _maxLen = 1000;

  final _contentCtrl = TextEditingController();
  final _contentFocus = FocusNode();

  late String _category;

  /// 그대로 둘 기존 첨부 링크. (고치기에서만 쓴다)
  late List<String> _keepUrls;

  /// 새로 고른 사진.
  final List<InquiryAttachment> _files = [];

  bool _sending = false;
  bool _picking = false;

  bool get _isEdit => widget.origin != null;

  @override
  void initState() {
    super.initState();
    final o = widget.origin;
    _category = o != null && InquiryService.categories.contains(o.category)
        ? o.category
        : InquiryService.categories.first;
    _contentCtrl.text = o?.content ?? '';
    _keepUrls = List<String>.from(o?.attachmentUrls ?? const <String>[]);

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
      navTitle: _isEdit ? '문의 수정' : '제안 및 피드백',
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
                      Text(
                        _isEdit
                            ? '내용을 고쳐 주세요'
                            : '더 나은 플로우노트를 함께 만들어요',
                        style: FnDs.tsTitle,
                      ),
                      const SizedBox(height: FnDs.gapXs),
                      Text(
                        _isEdit
                            ? '답변이 달리기 전까지만 고칠 수 있어요.'
                            : '문의나 제안을 남겨주시면\n관리자가 확인 후 답변드릴게요.',
                        style: FnDs.tsSub,
                      ),
                      const SizedBox(height: FnDs.gapL),
                      const FnFieldLabel('카테고리', required: true),
                      const SizedBox(height: 10),
                      FnCategoryPicker(
                        value: _category,
                        enabled: !_sending,
                        onTap: _pickCategory,
                      ),
                      const SizedBox(height: FnDs.gapL),
                      const FnFieldLabel('내용', required: true),
                      const SizedBox(height: 10),
                      FnLongTextField(
                        controller: _contentCtrl,
                        focusNode: _contentFocus,
                        hintText: '문의 내용이나 제안을 자세히 적어주세요.\n'
                            '오류가 발생한 상황을 함께 알려주시면 좋아요.',
                        maxLength: _maxLen,
                        enabled: !_sending,
                      ),
                      const SizedBox(height: FnDs.gapL),
                      const FnFieldLabel('사진 첨부', required: false),
                      const SizedBox(height: 10),
                      FnPhotoAttachField(
                        existingUrls: _keepUrls,
                        newFiles: _files,
                        busy: _picking,
                        enabled: !_sending,
                        onAdd: _pickPhotos,
                        onRemoveExisting: (u) =>
                            setState(() => _keepUrls.remove(u)),
                        onRemoveNew: (i) => setState(() => _files.removeAt(i)),
                      ),
                      const SizedBox(height: FnDs.gapXs),
                      Text(
                        '사진은 최대 ${InquiryService.maxFiles}장, '
                        '올리기 전에 자동으로 줄여서 보내요.',
                        style: FnDs.tsSub,
                      ),
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
                child: FnPrimaryButton(
                  label: _isEdit ? '수정 완료' : '문의하기',
                  busy: _sending,
                  onTap: _canSend ? _submit : null,
                ),
              ),
            ],
          ),
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
          FnSheetOption<String>(value: c, label: c),
      ],
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }

  /// 앨범에서 사진을 고른다. 남은 장수만큼만 받는다.
  Future<void> _pickPhotos() async {
    final remaining =
        InquiryService.maxFiles - _keepUrls.length - _files.length;
    if (remaining <= 0) return;

    setState(() => _picking = true);
    try {
      final got = await InquiryPicker.pickImages(remaining);
      if (!mounted) return;
      if (got.isNotEmpty) setState(() => _files.addAll(got));
    } catch (_) {
      if (!mounted) return;
      showFnToast(context, '사진을 불러오지 못했어요.', type: FnToastType.error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      final origin = widget.origin;
      if (origin == null) {
        await InquiryService.instance.submit(
          category: _category,
          content: _contentCtrl.text,
          files: List.unmodifiable(_files),
        );
        if (!mounted) return;
        await _showDone();
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        await InquiryService.instance.update(
          origin: origin,
          category: _category,
          content: _contentCtrl.text,
          keepUrls: List.unmodifiable(_keepUrls),
          added: List.unmodifiable(_files),
        );
        if (!mounted) return;
        showFnToast(context, '문의를 수정했어요.', type: FnToastType.success);
        Navigator.of(context).pop(true);
      }
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
              FnPrimaryButton(
                label: '확인',
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
