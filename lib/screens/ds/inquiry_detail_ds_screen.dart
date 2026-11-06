import 'package:flutter/material.dart';

import '../../design/fn_feedback.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_sheet.dart';
import '../../services/inquiry_service.dart';
import '../../theme/fn_ds.dart';
import '../../widgets/fn_inquiry_parts.dart';
import 'inquiry_ds_screen.dart';

/// 문의 한 건 보기.
///
/// ```
///   [←] 문의 상세
///   [접수] 26.09.18                      FnInquiryBody
///   기능 제안
///   (내용)
///   [사진][사진]
///   (답변 칸)                             FnAnswerBlock
///   [ 수정 ] [ 삭제 ]                     작성자이고 접수 상태일 때만
/// ```
///
/// ## 누가 무엇을 보나
///
/// | | 작성자 | 관리자 |
/// |---|---|---|
/// | 답변 칸 | 읽기만 | 쓰기·고치기·지우기 |
/// | 수정 | 접수 상태일 때만 | 없음 (남의 글 내용은 안 건드린다) |
/// | 삭제 | 언제든 | 언제든 |
///
/// 🔴 글이 사라지면(다른 기기에서 지웠거나 관리자가 지웠거나) 화면을
///    바로 닫는다. 빈 화면을 들여다보게 두면 왜 안 되는지 알 수 없다.
class InquiryDetailDsScreen extends StatefulWidget {
  const InquiryDetailDsScreen({super.key, required this.id});

  final String id;

  @override
  State<InquiryDetailDsScreen> createState() => _InquiryDetailDsScreenState();
}

class _InquiryDetailDsScreenState extends State<InquiryDetailDsScreen> {
  bool _busy = false;

  /// 내가 지워서 닫는 중. 스트림이 null 을 뱉어도 두 번 닫지 않게.
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final admin = InquiryService.isAdmin;

    return FnShell(
      navTitle: '문의 상세',
      bg: FnDs.bg,
      onBack: () => Navigator.of(context).maybePop(),
      child: ColoredBox(
        color: FnDs.bg,
        child: SafeArea(
          top: false,
          child: StreamBuilder<Inquiry?>(
            stream: InquiryService.instance.watchOne(widget.id),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: FnDs.coral),
                  ),
                );
              }
              if (snap.hasError) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(FnDs.pagePad),
                    child: Text('이 문의를 볼 수 없어요.',
                        textAlign: TextAlign.center, style: FnDs.tsBody),
                  ),
                );
              }

              final item = snap.data;
              if (item == null) {
                // 사라진 글. 프레임이 끝난 뒤에 닫는다 (빌드 중 pop 금지).
                if (!_closing) {
                  _closing = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) Navigator.of(context).maybePop();
                  });
                }
                return const SizedBox.shrink();
              }

              final mine = InquiryService.isMine(item);

              return ListView(
                padding: const EdgeInsets.fromLTRB(
                    FnDs.pagePad, 18, FnDs.pagePad, 24),
                children: [
                  FnInquiryBody(item: item, showWriter: admin),
                  const SizedBox(height: FnDs.gapM),
                  FnAnswerBlock(
                    item: item,
                    isAdmin: admin,
                    onSave: (text) => _guard(
                        () => InquiryService.instance.saveAnswer(item.id, text),
                        '답변을 등록했어요.'),
                    onDelete: () => _guard(
                        () => InquiryService.instance.deleteAnswer(item.id),
                        '답변을 지웠어요.'),
                  ),
                  if (mine || admin) ...[
                    const SizedBox(height: FnDs.gapM),
                    Row(
                      children: [
                        if (mine) ...[
                          Expanded(
                            child: FnOutlineButton(
                              label: '수정',
                              // 답변이 달리면 고칠 수 없다. 버튼을 숨기지 않고
                              // 꺼 두는 편이 "왜 없지?" 보다 낫다.
                              onTap: (!item.editable || _busy)
                                  ? null
                                  : () => _edit(item),
                            ),
                          ),
                          const SizedBox(width: FnDs.gapXs),
                        ],
                        Expanded(
                          child: FnOutlineButton(
                            label: '삭제',
                            destructive: true,
                            onTap: _busy ? null : () => _delete(item),
                          ),
                        ),
                      ],
                    ),
                    if (mine && !item.editable) ...[
                      const SizedBox(height: FnDs.gapXs),
                      const Text('답변이 달린 문의는 수정할 수 없어요.',
                          style: FnDs.tsSub),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _edit(Inquiry item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (_) => InquiryDsScreen(origin: item)),
    );
    // 스트림이 알아서 새 내용을 가져오므로 따로 다시 읽지 않는다.
  }

  Future<void> _delete(Inquiry item) async {
    final ok = await showFnAlert(
      context,
      title: '문의를 삭제할까요?',
      message: item.attachmentUrls.isEmpty
          ? '지운 문의는 되돌릴 수 없어요.'
          : '첨부한 사진도 함께 지워져요. 되돌릴 수 없어요.',
      confirmLabel: '삭제',
      cancelLabel: '취소',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await InquiryService.instance.delete(item);
      if (!mounted) return;
      _closing = true;
      showFnToast(context, '문의를 삭제했어요.', type: FnToastType.success);
      Navigator.of(context).maybePop();
    } on InquiryFailure catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showFnToast(context, e.message, type: FnToastType.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showFnToast(context, '삭제하지 못했어요. 잠시 뒤 다시 시도해 주세요.',
          type: FnToastType.error);
    }
  }

  /// 답변 저장/삭제 공통 — 실패하면 그대로 알려 준다.
  Future<void> _guard(Future<void> Function() job, String done) async {
    try {
      await job();
      if (mounted) showFnToast(context, done, type: FnToastType.success);
    } on InquiryFailure catch (e) {
      if (mounted) showFnToast(context, e.message, type: FnToastType.error);
      rethrow;
    } catch (_) {
      if (mounted) {
        showFnToast(context, '처리하지 못했어요. 잠시 뒤 다시 시도해 주세요.',
            type: FnToastType.error);
      }
      rethrow;
    }
  }
}
