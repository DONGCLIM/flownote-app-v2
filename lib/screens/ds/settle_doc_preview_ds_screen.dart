import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../design/fn_card.dart';
import '../../design/fn_controls_ds.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_tokens.dart';
import '../../services/settlement_pdf_service.dart';

/// 정산 문서를 **다운로드하기 전에** 보여주는 화면.
///
/// ## 왜 만들었나
///
/// 예전 흐름은 이랬다.
///
/// ```
/// [세금계산서 발행 요청서] 탭  →  PDF 생성  →  즉시 다운로드
/// ```
///
/// 사용자가 문서를 확인할 기회가 아예 없었다. 그래서
/// - 사업자 정보가 잘못 들어갔는지
/// - 금액·건수가 맞는지
/// - 영수증 사진이 실제로 붙었는지
/// 를 알려면 다운로드 폴더에서 파일을 열어봐야 했다. 틀렸으면 처음부터 다시
/// 내보내야 했고, 쓸모없는 파일이 계속 쌓였다. 무료 내보내기 횟수도 같이
/// 깎였다.
///
/// 이제는 이렇게 바뀐다.
///
/// ```
/// [세금계산서 발행 요청서] 탭  →  PDF 생성  →  ★미리보기★  →  [다운로드] / [취소]
/// ```
///
/// **취소하면 파일도 만들지 않고 내보내기 횟수도 깎이지 않는다.**
///
/// ## 미리보기를 어떻게 그리나
///
/// `printing` 패키지의 [PdfPreview] 가 실제 PDF 페이지를 렌더링한다.
/// - 앱: 안드로이드 기본 `PdfRenderer`(OS 내장) / iOS `CGPDF`
/// - 웹: pdf.js — `web/pdfjs/` 에 직접 넣어둔 것을 쓴다
///   (기본값인 unpkg CDN 은 오프라인·차단 환경에서 죽는다)
///
/// 렌더링이 실패해도 화면이 비지 않도록 [PdfPreview.onError] 에서 요약
/// 정보를 대신 보여준다. 사진이 많은 문서는 미리보기가 몇 초 걸릴 수 있어서
/// 상단에 문서 요약을 **먼저** 그린다. 요약만 보고도 판단할 수 있게.
class SettleDocPreviewDsScreen extends StatelessWidget {
  const SettleDocPreviewDsScreen({super.key, required this.draft});

  final SettlementDraft draft;

  /// 미리보기를 띄우고, 사용자가 다운로드를 선택했는지 돌려준다.
  ///
  /// `true`  → 다운로드
  /// `false` / `null` → 취소 (뒤로 가기 포함)
  static Future<bool> open(BuildContext context, SettlementDraft draft) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => SettleDocPreviewDsScreen(draft: draft),
    ));
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: draft.kind.title,
      onBack: () => Navigator.of(context).pop(false),
      bg: FnColors.backgroundAlternative,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _summaryCard(),
          ),
          Expanded(child: _preview()),
          _bottomBar(context),
        ],
      ),
    );
  }

  // ── 요약 ────────────────────────────────────────────────────
  //
  // PDF 렌더링보다 먼저 뜬다. 여기 숫자가 틀렸으면 미리보기를 볼 필요도 없다.
  Widget _summaryCard() {
    // 사진이 영수증 수보다 적으면 알려준다. 조용히 넘기면 사용자는 사진이
    // 전부 붙은 줄 알고 거래처에 보낸다.
    final missing = draft.receiptCount - draft.photoCount;

    return FnCard(
      bordered: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.vendor,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: FnColors.labelNormal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${draft.sizeKb}KB',
                style: const TextStyle(
                  fontSize: 12,
                  color: FnColors.labelAlternative,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _row('기간', draft.period),
          _row('영수증', '${draft.receiptCount}건'),
          _row('사진', '${draft.photoCount}장'),
          _row('합계', SettlementPdfService.wonText(draft.total), bold: true),
          if (missing > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: FnColors.statusCautionaryBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 15, color: FnColors.statusCautionaryStrong),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$missing건은 사진이 없어요. 문서에는 날짜와 금액만 들어갑니다.',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: FnColors.statusCautionaryStrong,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k,
              style: const TextStyle(
                  fontSize: 13, color: FnColors.labelAlternative)),
          Text(
            v,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: FnColors.labelNormal,
            ),
          ),
        ],
      ),
    );
  }

  // ── 실제 PDF 미리보기 ───────────────────────────────────────
  Widget _preview() {
    return PdfPreview(
      // 🔴 이미 만들어진 바이트를 그대로 넘긴다. 다시 만들면 문서번호와
      //    작성일이 달라져서 "본 문서" 와 "받은 문서" 가 달라진다.
      build: (_) async => draft.bytes,

      // 우리 화면에 [다운로드]/[취소] 버튼을 따로 두므로 패키지 액션바는
      // 전부 끈다. 인쇄·공유·용지크기 변경은 여기서 할 일이 아니다.
      useActions: false,
      allowPrinting: false,
      allowSharing: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,

      maxPageWidth: 520,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      scrollViewDecoration: const BoxDecoration(
        color: FnColors.backgroundAlternative,
      ),
      pdfPreviewPageDecoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      loadingWidget: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: FnColors.primaryNormal),
            ),
            SizedBox(height: 12),
            Text('문서를 그리고 있어요',
                style: TextStyle(fontSize: 13, color: FnColors.labelAlternative)),
          ],
        ),
      ),

      // 미리보기 렌더링이 실패해도 다운로드는 막지 않는다.
      // 파일 자체는 이미 완성돼 있다 — 못 그리는 것과 못 쓰는 것은 다르다.
      onError: (_, err) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf_outlined,
                  size: 40, color: FnColors.labelAssistive),
              const SizedBox(height: 12),
              const Text(
                '이 브라우저에서는 미리보기를 그릴 수 없어요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelNormal,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '문서 자체는 정상적으로 만들어졌어요.\n위 요약을 확인하고 다운로드하시면 됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5, height: 1.5, color: FnColors.labelAlternative),
              ),
              const SizedBox(height: 10),
              Text(
                '$err',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, color: FnColors.labelAssistive),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 하단 버튼 ───────────────────────────────────────────────
  Widget _bottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: FnColors.backgroundNormal,
        border: Border(top: BorderSide(color: FnColors.lineAlternative)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Text(
              draft.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5, color: FnColors.labelAssistive),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FnDsButton(
                    label: '취소',
                    variant: FnDsButtonVariant.outlined,
                    color: FnDsButtonColor.neutral,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FnDsButton(
                    label: '다운로드',
                    leadingIcon: const Icon(Icons.download_rounded,
                        size: 18, color: Colors.white),
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
