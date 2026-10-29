import 'package:flutter/material.dart';

import '../../design/fn_shell.dart';
import '../../services/inquiry_service.dart';
import '../../theme/fn_ds.dart';
import '../../widgets/fn_inquiry_parts.dart';
import 'inquiry_detail_ds_screen.dart';
import 'inquiry_ds_screen.dart';

/// 문의 목록.
///
/// ## 한 화면이 두 얼굴을 한다
///
/// | | 사장님 | 관리자 |
/// |---|---|---|
/// | 제목 | 내 문의 내역 | 전체 문의 |
/// | 보이는 글 | 본인 것만 | 전부 |
/// | 차례 | 최신 먼저 | **미답변 먼저**, 그 안에서 최신 먼저 |
/// | 머리말 | 🔒 나만 볼 수 있는 문의예요 | 답변을 기다리는 문의가 먼저 보여요 |
/// | 작성자 | 안 보임 | 이메일 표시 |
///
/// 🔴 관리자 전용 화면을 따로 만들지 않았다 (사장님 지시).
///    화면이 둘이면 한쪽만 고쳐 놓고 다른 쪽을 잊게 된다.
///
/// 🔴 목록을 가리는 것은 보기 좋으라고 하는 일이 아니다.
///    실제로 막는 것은 `firestore.rules` 다. 여기서 안 보여줘도
///    규칙이 없으면 서버에 직접 물어서 남의 글을 가져갈 수 있다.
class InquiryListDsScreen extends StatelessWidget {
  const InquiryListDsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = InquiryService.isAdmin;

    return FnShell(
      navTitle: admin ? '전체 문의' : '내 문의 내역',
      bg: FnDs.bg,
      onBack: () => Navigator.of(context).maybePop(),
      child: ColoredBox(
        color: FnDs.bg,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<Inquiry>>(
                  stream: InquiryService.instance.watch(),
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
                      return _message(
                        '목록을 불러오지 못했어요.\n잠시 뒤 다시 들어와 주세요.',
                      );
                    }
                    final items = snap.data ?? const <Inquiry>[];
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(
                          FnDs.pagePad, 18, FnDs.pagePad, 16),
                      children: [
                        _notice(admin),
                        const SizedBox(height: FnDs.gapM),
                        if (items.isEmpty)
                          _empty(admin)
                        else
                          for (final it in items) ...[
                            _InquiryRow(
                              item: it,
                              showWriter: admin,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      InquiryDetailDsScreen(id: it.id),
                                ),
                              ),
                            ),
                            const SizedBox(height: FnDs.gapS),
                          ],
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    FnDs.pagePad, 4, FnDs.pagePad, 16),
                child: FnPrimaryButton(
                  label: '문의하기',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                        builder: (_) => const InquiryDsScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 머리말. 사장님께는 "나만 볼 수 있어요" 안내를 꼭 보여준다.
  Widget _notice(bool admin) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: FnDs.coralFaint,
        borderRadius: BorderRadius.circular(FnDs.inputRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(admin ? Icons.inbox_rounded : Icons.lock_rounded,
              size: 16, color: FnDs.coral),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              admin
                  ? '답변을 기다리는 문의가 먼저 보여요.'
                  : '나만 볼 수 있는 문의예요.',
              style: const TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.fontS,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: FnDs.title,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(bool admin) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          const Icon(Icons.chat_bubble_outline_rounded,
              size: 36, color: FnDs.sub),
          const SizedBox(height: FnDs.gapS),
          Text(
            admin ? '아직 들어온 문의가 없어요.' : '아직 남긴 문의가 없어요.',
            style: FnDs.tsBody,
          ),
        ],
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(FnDs.pagePad),
          child: Text(text, textAlign: TextAlign.center, style: FnDs.tsBody),
        ),
      );
}

/// 목록 한 줄.
class _InquiryRow extends StatelessWidget {
  const _InquiryRow({
    required this.item,
    required this.showWriter,
    required this.onTap,
  });

  final Inquiry item;
  final bool showWriter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(FnDs.cardPad),
        decoration: FnDs.cardDeco(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FnStatusBadge(item.status),
                const SizedBox(width: FnDs.gapXs),
                Expanded(child: Text(item.ymd, style: FnDs.tsSub)),
                if (item.attachmentUrls.isNotEmpty) ...[
                  const Icon(Icons.image_outlined, size: 14, color: FnDs.sub),
                  const SizedBox(width: 2),
                  Text('${item.attachmentUrls.length}', style: FnDs.tsSub),
                  const SizedBox(width: FnDs.gapXs),
                ],
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: FnDs.chevron),
              ],
            ),
            const SizedBox(height: FnDs.gapXs),
            Text(
              item.category,
              style: const TextStyle(
                fontFamily: FnDs.font,
                fontSize: FnDs.fontL,
                fontWeight: FontWeight.w700,
                color: FnDs.title,
              ),
            ),
            if (showWriter && item.writerLabel.isNotEmpty) ...[
              const SizedBox(height: FnDs.gap2xs),
              Text(item.writerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FnDs.tsSub),
            ],
            const SizedBox(height: FnDs.gap2xs),
            Text(
              item.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: FnDs.tsBody,
            ),
          ],
        ),
      ),
    );
  }
}
