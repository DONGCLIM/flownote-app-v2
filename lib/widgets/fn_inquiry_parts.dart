/// 문의 화면들이 함께 쓰는 조각들.
///
/// 사장님 지시: "글쓰기 화면·사진 첨부·글 상세·답변은 다른 화면에서도
/// 쓸 수 있게 공용 컴포넌트로". 그래서 화면 파일에는 **배치만** 남기고
/// 실제로 그리는 부분은 전부 여기에 모았다.
///
/// | 이름 | 하는 일 | 쓰는 곳 |
/// |---|---|---|
/// | [FnFieldLabel]      | `카테고리 필수` 라벨 | 글쓰기·수정 |
/// | [FnCategoryPicker]  | 카테고리 고르기 칸 | 글쓰기·수정 |
/// | [FnLongTextField]   | 여러 줄 입력 + 글자 수 | 글쓰기·수정·답변 |
/// | [FnPhotoAttachField]| 사진 첨부 + 썸네일 + 삭제 | 글쓰기·수정 |
/// | [FnStatusBadge]     | 접수/답변완료 배지 | 목록·상세 |
/// | [FnInquiryBody]     | 글 본문(분류·날짜·내용·사진) | 상세 |
/// | [FnAnswerBlock]     | 답변 보기 + 관리자 편집 | 상세 |
/// | [FnPrimaryButton]   | 코랄 큰 버튼 | 전부 |
/// | [FnOutlineButton]   | 테두리 버튼 | 상세 |
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/inquiry_service.dart';
import '../theme/fn_ds.dart';
/// `카테고리 필수` — 제목 옆에 작은 글씨.
class FnFieldLabel extends StatelessWidget {
  const FnFieldLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
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
}

/// 카테고리 고르기. 누르면 [onTap] 이 불린다 (시트는 화면이 띄운다).
class FnCategoryPicker extends StatelessWidget {
  const FnCategoryPicker({
    super.key,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  final String value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
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
              child: Text(value,
                  style: const TextStyle(
                    fontFamily: FnDs.font,
                    fontSize: FnDs.inputFont,
                    color: FnDs.title,
                  )),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: FnDs.sub),
          ],
        ),
      ),
    );
  }
}

/// 여러 줄 입력칸. 오른쪽 아래에 글자 수를 직접 그린다.
class FnLongTextField extends StatelessWidget {
  const FnLongTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    this.maxLength = 1000,
    this.minLines = 6,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final int maxLength;
  final int minLines;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final len = controller.text.characters.length;
    return Container(
      decoration: BoxDecoration(
        color: FnDs.card,
        borderRadius: BorderRadius.circular(FnDs.inputRadius),
        border: Border.all(
          color: focusNode.hasFocus ? FnDs.coral : FnDs.line,
          width: focusNode.hasFocus ? 1.4 : FnDs.inputBorderW,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(FnDs.inputPadH, 14, FnDs.inputPadH, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            maxLines: null,
            minLines: minLines,
            maxLength: maxLength,
            // 기본 카운터를 끄고 시안처럼 오른쪽 아래에 직접 그린다.
            buildCounter: (_,
                    {required currentLength,
                    required isFocused,
                    required maxLength}) =>
                null,
            inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(
              fontFamily: FnDs.font,
              fontSize: FnDs.inputFont,
              height: 1.5,
              color: FnDs.title,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: hintText,
              hintStyle: const TextStyle(
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
            child: Text('$len / $maxLength', style: FnDs.tsSub),
          ),
        ],
      ),
    );
  }
}

/// 사진 첨부 칸 — `+ 사진 첨부하기` 버튼 + 썸네일 + ⊗ 지우기.
///
/// 이미 올라간 사진([existingUrls])과 방금 고른 사진([newFiles])을
/// 한 줄에 섞어서 보여준다. 수정 화면에서는 두 가지가 같이 나오기 때문이다.
class FnPhotoAttachField extends StatelessWidget {
  const FnPhotoAttachField({
    super.key,
    this.existingUrls = const <String>[],
    this.newFiles = const <InquiryAttachment>[],
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemoveNew,
    this.max = InquiryService.maxFiles,
    this.enabled = true,
    this.busy = false,
  });

  /// 이미 Storage 에 있는 사진 링크.
  final List<String> existingUrls;

  /// 아직 올리지 않은 사진.
  final List<InquiryAttachment> newFiles;

  final VoidCallback onAdd;
  final ValueChanged<String> onRemoveExisting;
  final ValueChanged<int> onRemoveNew;

  final int max;
  final bool enabled;

  /// 고르는 중/압축 중. 버튼을 두 번 누르지 못하게 막는다.
  final bool busy;

  int get _count => existingUrls.length + newFiles.length;

  @override
  Widget build(BuildContext context) {
    final full = _count >= max;
    final on = enabled && !full && !busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: on ? onAdd : null,
          child: Container(
            height: FnDs.inputH,
            decoration: BoxDecoration(
              color: FnDs.card,
              borderRadius: BorderRadius.circular(FnDs.inputRadius),
              border: Border.all(color: FnDs.line, width: FnDs.inputBorderW),
            ),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: FnDs.coral),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded,
                          size: 18, color: on ? FnDs.title : FnDs.sub),
                      const SizedBox(width: 6),
                      Text(
                        full ? '사진은 최대 $max장까지예요' : '사진 첨부하기',
                        style: TextStyle(
                          fontFamily: FnDs.font,
                          fontSize: FnDs.inputFont,
                          fontWeight: FontWeight.w600,
                          color: on ? FnDs.title : FnDs.sub,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (_count > 0) ...[
          const SizedBox(height: FnDs.gapS),
          Wrap(
            spacing: FnDs.gapXs,
            runSpacing: FnDs.gapXs,
            children: [
              for (final u in existingUrls)
                _FnThumb(
                  image: Image.network(u, fit: BoxFit.cover),
                  onRemove: enabled ? () => onRemoveExisting(u) : null,
                ),
              for (var i = 0; i < newFiles.length; i++)
                _FnThumb(
                  image: Image.memory(newFiles[i].bytes, fit: BoxFit.cover),
                  onRemove: enabled ? () => onRemoveNew(i) : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 썸네일 한 장 + 오른쪽 위 ⊗.
class _FnThumb extends StatelessWidget {
  const _FnThumb({required this.image, this.onRemove});

  final Widget image;
  final VoidCallback? onRemove;

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // ⊗ 가 모서리 밖으로 조금 나오므로 자리를 더 준다.
      width: _size + 8,
      height: _size + 8,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: _size,
                height: _size,
                color: FnDs.coralFaint,
                child: image,
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xCC000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `접수` / `답변완료` 배지.
///
/// 🔴 [Align] 로 감싸서 쓴다. 그냥 두면 가로로 끝까지 늘어난다
///    (#164 에서 알림 배지가 화면 끝까지 늘어났던 것과 같은 함정).
///    그래서 이 위젯이 스스로 [Align] 을 품고 있다.
class FnStatusBadge extends StatelessWidget {
  const FnStatusBadge(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final done = status == InquiryService.statusAnswered;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: done ? FnDs.coralFaint : const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          status.isEmpty ? InquiryService.statusNew : status,
          style: TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.fontXs,
            fontWeight: FontWeight.w700,
            color: done ? FnDs.coral : FnDs.sub,
          ),
        ),
      ),
    );
  }
}

/// 글 본문 — 분류 · 날짜 · 내용 · 첨부 사진.
class FnInquiryBody extends StatelessWidget {
  const FnInquiryBody({
    super.key,
    required this.item,
    this.showWriter = false,
    this.onPhotoTap,
  });

  final Inquiry item;

  /// 관리자 화면에서만 작성자를 보여준다.
  final bool showWriter;

  final ValueChanged<String>? onPhotoTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: FnDs.cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FnStatusBadge(item.status),
              const SizedBox(width: FnDs.gapXs),
              Expanded(
                child: Text(
                  item.ymd,
                  style: FnDs.tsSub,
                ),
              ),
            ],
          ),
          const SizedBox(height: FnDs.gapS),
          Text(item.category,
              style: const TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.fontL,
                fontWeight: FontWeight.w700,
                color: FnDs.title,
              )),
          if (showWriter && item.writerLabel.isNotEmpty) ...[
            const SizedBox(height: FnDs.gap2xs),
            Text(item.writerLabel, style: FnDs.tsSub),
          ],
          const SizedBox(height: FnDs.gapS),
          Text(item.content, style: FnDs.tsBody),
          if (item.attachmentUrls.isNotEmpty) ...[
            const SizedBox(height: FnDs.gapM),
            Wrap(
              spacing: FnDs.gapXs,
              runSpacing: FnDs.gapXs,
              children: [
                for (final u in item.attachmentUrls)
                  GestureDetector(
                    onTap: onPhotoTap == null ? null : () => onPhotoTap!(u),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 88,
                        height: 88,
                        color: FnDs.coralFaint,
                        child: Image.network(u, fit: BoxFit.cover),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 답변 칸.
///
/// * 보통 사장님  → 답변이 있으면 보여주고, 없으면 "확인 중" 안내만.
/// * 관리자       → 입력칸 + 저장 / 지우기.
///
/// 입력 상태는 이 위젯이 스스로 들고 있다. 화면마다 컨트롤러를
/// 다시 만들지 않아도 되도록 하기 위해서다.
class FnAnswerBlock extends StatefulWidget {
  const FnAnswerBlock({
    super.key,
    required this.item,
    required this.isAdmin,
    required this.onSave,
    required this.onDelete,
  });

  final Inquiry item;
  final bool isAdmin;

  /// 답변 저장. 실패하면 예외를 던지면 된다 — 여기서 받아 보여준다.
  final Future<void> Function(String answer) onSave;
  final Future<void> Function() onDelete;

  @override
  State<FnAnswerBlock> createState() => _FnAnswerBlockState();
}

class _FnAnswerBlockState extends State<FnAnswerBlock> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  bool _editing = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.item.answer;
    _ctrl.addListener(_redraw);
    _focus.addListener(_redraw);
    // 아직 답변이 없는 글을 관리자가 열면 바로 쓸 수 있게 열어 둔다.
    _editing = widget.isAdmin && !widget.item.isAnswered;
  }

  @override
  void didUpdateWidget(covariant FnAnswerBlock old) {
    super.didUpdateWidget(old);
    // 다른 기기에서 답변이 바뀐 경우. 내가 고치는 중이면 건드리지 않는다.
    if (!_editing && widget.item.answer != _ctrl.text) {
      _ctrl.text = widget.item.answer;
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_redraw);
    _focus.removeListener(_redraw);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    if (!widget.isAdmin) {
      if (!item.isAnswered) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(FnDs.cardPad),
          decoration: FnDs.cardDeco(),
          child: const Text(
            '관리자가 확인하고 있어요. 답변이 등록되면 알려드릴게요.',
            style: FnDs.tsBody,
          ),
        );
      }
      return _answerCard(item);
    }

    // ── 관리자 ──
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: FnDs.cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FnFieldLabel('답변', required: false),
          const SizedBox(height: FnDs.gapXs),
          if (_editing) ...[
            FnLongTextField(
              controller: _ctrl,
              focusNode: _focus,
              hintText: '답변 내용을 입력해 주세요.',
              maxLength: 1000,
              minLines: 4,
              enabled: !_busy,
            ),
            const SizedBox(height: FnDs.gapS),
            Row(
              children: [
                if (item.isAnswered) ...[
                  Expanded(
                    child: FnOutlineButton(
                      label: '취소',
                      onTap: _busy
                          ? null
                          : () => setState(() {
                                _ctrl.text = item.answer;
                                _editing = false;
                              }),
                    ),
                  ),
                  const SizedBox(width: FnDs.gapXs),
                ],
                Expanded(
                  child: FnPrimaryButton(
                    label: item.isAnswered ? '답변 수정' : '답변 등록',
                    busy: _busy,
                    onTap: _ctrl.text.trim().isEmpty
                        ? null
                        : () => _run(() => widget.onSave(_ctrl.text)),
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(item.answer, style: FnDs.tsBody),
            if (item.answeredAt != null) ...[
              const SizedBox(height: FnDs.gapXs),
              Text(_stamp(item.answeredAt!), style: FnDs.tsSub),
            ],
            const SizedBox(height: FnDs.gapS),
            Row(
              children: [
                Expanded(
                  child: FnOutlineButton(
                    label: '답변 수정',
                    onTap: _busy ? null : () => setState(() => _editing = true),
                  ),
                ),
                const SizedBox(width: FnDs.gapXs),
                Expanded(
                  child: FnOutlineButton(
                    label: '답변 삭제',
                    destructive: true,
                    onTap: _busy ? null : () => _run(widget.onDelete),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _answerCard(Inquiry item) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FnDs.cardPad),
      decoration: BoxDecoration(
        color: FnDs.coralFaint,
        borderRadius: BorderRadius.circular(FnDs.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('답변',
              style: TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.fontS,
                fontWeight: FontWeight.w700,
                color: FnDs.coral,
              )),
          const SizedBox(height: FnDs.gapXs),
          Text(item.answer, style: FnDs.tsBody),
          if (item.answeredAt != null) ...[
            const SizedBox(height: FnDs.gapXs),
            Text(_stamp(item.answeredAt!), style: FnDs.tsSub),
          ],
        ],
      ),
    );
  }

  static String _stamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.year % 100)}.${two(d.month)}.${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}

/// 코랄 큰 버튼. 높이 52 · 모서리 14.
///
/// [onTap] 이 null 이면 꺼진 모습이 된다 (회색). 따로 `enabled` 를 두지
/// 않는 이유는, 두 개를 두면 한쪽만 바꿔서 어긋나는 일이 잦기 때문이다.
class FnPrimaryButton extends StatelessWidget {
  const FnPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null && !busy;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: on ? onTap : null,
      child: Container(
        height: FnDs.buttonH,
        alignment: Alignment.center,
        decoration: FnDs.buttonFilled(enabled: on),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: FnDs.onCoral),
              )
            : Text(
                label,
                style: TextStyle(
                  fontFamily: FnDs.font,
                  fontSize: FnDs.buttonFont,
                  fontWeight: FnDs.buttonWeight,
                  color: on ? FnDs.onCoral : FnDs.buttonOffFg,
                ),
              ),
      ),
    );
  }
}

/// 테두리 버튼. 삭제처럼 되돌릴 수 없는 동작은 [destructive] 로 붉게.
class FnOutlineButton extends StatelessWidget {
  const FnOutlineButton({
    super.key,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final fg = !on
        ? FnDs.buttonOffFg
        : (destructive ? FnDs.negative : FnDs.coral);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: FnDs.buttonH,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: FnDs.card,
          borderRadius: BorderRadius.circular(FnDs.buttonRadius),
          border: Border.all(color: on ? fg : FnDs.line, width: 1.4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.buttonFont,
            fontWeight: FnDs.buttonWeight,
            color: fg,
          ),
        ),
      ),
    );
  }
}
