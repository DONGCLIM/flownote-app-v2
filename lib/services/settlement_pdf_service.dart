import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/receipt_model.dart';
import '../models/user_model.dart';
import 'file_saver.dart';
import 'receipt_image_store.dart';

/// 정산 문서의 종류.
enum SettlementDocKind {
  /// 세금계산서 발행 요청서 — **도매상에게 보내는 문서.**
  ///
  /// 🔴 품목을 넣지 않는다.
  ///    도매상이 세금계산서를 발행할 때 필요한 건 **날짜와 금액**뿐이다.
  ///    품목명은 보지 않는다. 그런데 우리 품목명은 손글씨 OCR 결과라서
  ///    틀릴 수 있다. 실제 데이터를 확인해 보니 같은 영수증을 두 번 스캔했을 때
  ///    금액은 63,000원으로 똑같았지만 품목 5개 중 4개의 이름이 달랐다.
  ///    (`로얄/조팝`, `시네레/리시안`, `국화/금광`, `도라지/튤립`)
  ///    이런 이름이 거래처로 나가면 "우리가 그런 걸 판 적이 없다" 는
  ///    분쟁만 생긴다. 필요도 없는 정보로 신뢰를 깎을 이유가 없다.
  request,

  /// 매입 내역서 — **내 보관용 / 세무사 제출용.**
  ///
  /// 여기는 품목을 넣는다. 대략적인 이름이라도 나중에 찾을 때 쓸모가 있고,
  /// 영수증 사진이 같이 붙으니 **사진이 정답**이고 글자는 색인일 뿐이다.
  /// 다만 사용자가 확인하지 않은 품목에는 ⚠ 를 붙여서 드러낸다.
  statement,
}

extension SettlementDocKindX on SettlementDocKind {
  String get title => this == SettlementDocKind.request
      ? '세금계산서 발행 요청서'
      : '매입 내역서';

  /// 파일명에 쓰는 짧은 이름
  String get slug =>
      this == SettlementDocKind.request ? '세금계산서요청서' : '매입내역서';

  bool get showItems => this == SettlementDocKind.statement;
}

/// 생성된 문서 하나.
class SettlementDoc {
  const SettlementDoc({
    required this.kind,
    required this.file,
    required this.vendor,
  });

  final SettlementDocKind kind;

  /// 저장된 문서.
  ///
  /// 앱에서는 `file.path` 에 실제 파일 경로가 있어 `share_plus` 로
  /// 카카오톡·메일에 바로 넘길 수 있다. **웹에서는 `path` 가 `null`**
  /// 이다 — 브라우저가 다운로드 폴더로 직접 내려보내기 때문에 앱이
  /// 알 수 있는 경로가 없다. 그래서 공유 대신 "다운로드됐어요" 를
  /// 알려주는 쪽으로 분기해야 한다.
  final SavedFile file;
  final String vendor;
}

/// **아직 저장하지 않은** 문서.
///
/// 🔴 이게 왜 필요한가.
///    예전에는 `build()` 하나가 (바이트 생성 → 파일 저장/브라우저 다운로드)
///    를 한꺼번에 했다. 그래서 사용자가 "세금계산서 발행 요청서" 를 누르는
///    순간 파일이 곧바로 내려가 버렸다. 내용을 확인할 기회가 없어서
///    - 사업자 정보가 틀렸는지
///    - 금액·건수가 맞는지
///    - 사진이 제대로 붙었는지
///    확인하려면 다운로드 폴더를 열어봐야 했고, 틀렸으면 다시 내보내서
///    쓸모없는 파일이 계속 쌓였다(무료 내보내기 횟수도 같이 깎였다).
///
///    그래서 바이트만 먼저 만들고, 미리보기에서 확인한 뒤에 저장한다.
class SettlementDraft {
  const SettlementDraft({
    required this.kind,
    required this.vendor,
    required this.fileName,
    required this.bytes,
    required this.receiptCount,
    required this.photoCount,
    required this.total,
    required this.period,
  });

  final SettlementDocKind kind;
  final String vendor;

  /// 저장될 때 쓸 파일명. 미리보기 화면에도 그대로 보여준다.
  final String fileName;

  /// 완성된 PDF 바이트. 미리보기와 저장이 **같은 바이트**를 쓴다.
  /// (다시 만들면 문서번호·작성일이 달라져서 본 것과 받은 것이 달라진다)
  final Uint8List bytes;

  final int receiptCount;

  /// 문서에 실제로 붙은 사진 장수.
  /// 영수증 수보다 적으면 사진이 없는 영수증이 있다는 뜻이다.
  final int photoCount;

  final double total;
  final String period;

  /// 파일 크기(KB). 카카오톡으로 보낼 수 있는지 가늠하는 용도.
  int get sizeKb => (bytes.lengthInBytes / 1024).round();
}

/// 정산 문서(PDF) 생성기.
///
/// ## 참고한 형식과, 일부러 다르게 한 점
///
/// 사용자가 보여준 참고 문서는 경쟁 서비스(플로링크)가 만든 것이다.
/// **구조만 참고하고 디자인은 따라가지 않는다.** ("완전 똑같이하면 욕먹고")
///
/// 우리가 의도적으로 다르게 한 것:
/// - 참고 문서의 `영수증 번호` 칸은 8줄 전부 `-` 였다. 손으로 쓴 영수증에는
///   번호가 없으니 당연하다. 그 칸을 빼고 **월별 소계**를 넣었다.
/// - 문서를 두 종류로 나눴다(요청서 / 내역서). 참고 문서는 한 종류뿐인데,
///   도매상에게 보낼 것과 내가 볼 것의 필요가 다르다.
/// - 부가세 칸은 **넣지 않는다.** 요청서는 "이만큼 샀습니다" 를 알리는
///   문서고, 공급가액·부가세를 계산하는 건 세금계산서를 발행하는 도매상
///   쪽이다. 우리가 계산해서 적으면 틀렸을 때 책임만 생긴다.
///   (참고 문서도 부가세를 넣지 않았고, 그 판단이 옳다)
class SettlementPdfService {
  SettlementPdfService._();
  static final SettlementPdfService instance = SettlementPdfService._();

  static final _num = NumberFormat('#,###', 'ko');
  static String _won(num n) => '${_num.format(n.round())}원';

  /// 미리보기 화면이 **문서와 똑같은 표기**로 금액을 보여주기 위한 공개 창구.
  /// (요약에는 `12,345원`, 문서 안에는 `12,300원` 처럼 달라지면 안 된다)
  static String wonText(num n) => _won(n);

  // ── 폰트 ────────────────────────────────────────────────────
  //
  // 🔴 PDF 는 앱 폰트를 자동으로 쓰지 않는다. 기본 폰트(Helvetica)에는
  //    한글 글리프가 없어서, 폰트를 안 넣으면 모든 한글이 빈칸이나
  //    두부(□)로 나온다. assets 에 있는 Pretendard TTF 를 직접 실어야 한다.
  pw.Font? _regular;
  pw.Font? _bold;

  Future<void> _loadFonts() async {
    if (_regular != null && _bold != null) return;
    final r = await rootBundle.load('assets/fonts/Pretendard-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Pretendard-Bold.ttf');
    _regular = pw.Font.ttf(r);
    _bold = pw.Font.ttf(b);
  }

  // ── 색 (앱 로즈 계열과 맞춤) ─────────────────────────────────
  static const _ink = PdfColor.fromInt(0xFF1A1C1E);
  static const _sub = PdfColor.fromInt(0xFF6B7280);
  static const _line = PdfColor.fromInt(0xFFE5E7EB);
  static const _accent = PdfColor.fromInt(0xFFD9576E); // rose-50
  static const _accentBg = PdfColor.fromInt(0xFFFDF2F4); // rose-99
  static const _headBg = PdfColor.fromInt(0xFFF9FAFB);

  /// 문서를 만들어 **파일로 저장까지** 한다.
  ///
  /// [receipts] 는 한 거래처의 영수증만 담겨 있어야 한다.
  ///
  /// 🔴 미리보기 화면에서는 이 함수를 쓰면 안 된다. 저장(웹이면 브라우저
  ///    다운로드)이 함수 안에서 일어나기 때문에, 사용자가 문서를 보기도
  ///    전에 파일이 내려가 버린다. 미리보기는 [draft] → [save] 로 나눠 쓴다.
  Future<SettlementDoc> build({
    required SettlementDocKind kind,
    required String vendorName,
    required List<ReceiptModel> receipts,
    required UserModel? me,
    String? periodLabel,
  }) async {
    final d = await draft(
      kind: kind,
      vendorName: vendorName,
      receipts: receipts,
      me: me,
      periodLabel: periodLabel,
    );
    return save(d);
  }

  /// 문서 **바이트만** 만든다. 저장하지 않는다.
  ///
  /// 미리보기 → [SettlementDraft.bytes] 를 화면에 그린다.
  /// 사용자가 "다운로드" 를 누르면 [save] 를 호출한다.
  Future<SettlementDraft> draft({
    required SettlementDocKind kind,
    required String vendorName,
    required List<ReceiptModel> receipts,
    required UserModel? me,
    String? periodLabel,
  }) async {
    await _loadFonts();

    final sorted = [...receipts]..sort((a, b) => a.date.compareTo(b.date));
    final photos = await _loadPhotos(sorted);

    final theme = pw.ThemeData.withFont(base: _regular!, bold: _bold!);
    final doc = pw.Document(theme: theme);

    final total = sorted.fold<double>(0, (s, r) => s + r.totalAmount);
    final docNo = _docNumber(sorted);

    // ── 1페이지: 표지 + 내역 표 ────────────────────────────────
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
        footer: (c) => _footer(c),
        build: (c) => [
          _header(kind, docNo),
          pw.SizedBox(height: 18),
          _addressee(kind, vendorName),
          pw.SizedBox(height: 14),
          _myBusiness(kind, me),
          pw.SizedBox(height: 14),
          _summary(
            kind: kind,
            count: sorted.length,
            total: total,
            period: periodLabel ?? _periodOf(sorted),
          ),
          pw.SizedBox(height: 16),
          ..._table(kind, sorted, total),
          pw.SizedBox(height: 14),
          _notice(kind, sorted, photos.length),
        ],
      ),
    );

    // ── 2페이지 이후: 영수증 사진 (2×2 = 한 장에 4개) ─────────
    if (photos.isNotEmpty) {
      const perPage = 4;
      final pages = (photos.length / perPage).ceil();
      for (var p = 0; p < pages; p++) {
        final from = p * perPage;
        final to = (from + perPage).clamp(0, photos.length);
        final slice = photos.sublist(from, to);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
            build: (c) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _photoHeader(from + 1, to, photos.length),
                pw.SizedBox(height: 12),
                pw.Expanded(child: _photoGrid(slice)),
                pw.SizedBox(height: 8),
                _footerText(),
              ],
            ),
          ),
        );
      }
    }

    // ── 바이트 생성 (저장은 하지 않는다) ───────────────────────
    final bytes = await doc.save();

    final safeVendor = _safeName(vendorName);
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final name = '${kind.slug}_${safeVendor}_$stamp.pdf';

    return SettlementDraft(
      kind: kind,
      vendor: vendorName,
      fileName: name,
      bytes: bytes,
      receiptCount: sorted.length,
      photoCount: photos.length,
      total: total,
      period: periodLabel ?? _periodOf(sorted),
    );
  }

  /// 만들어둔 문서를 실제 파일로 내린다.
  ///
  /// 앱: 문서 폴더에 파일로 저장 → 공유 가능
  /// 웹: 브라우저 다운로드
  /// (플랫폼 분기는 `file_saver.dart` 조건부 export 가 처리한다)
  Future<SettlementDoc> save(SettlementDraft d) async {
    final saved = await saveDocumentBytes(bytes: d.bytes, fileName: d.fileName);
    return SettlementDoc(kind: d.kind, file: saved, vendor: d.vendor);
  }

  // ────────────────────────────────────────────────────────────
  // 조각들
  // ────────────────────────────────────────────────────────────

  pw.Widget _header(SettlementDocKind kind, String docNo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(kind.title,
                style: pw.TextStyle(
                    fontSize: 22, fontWeight: pw.FontWeight.bold, color: _ink)),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('문서번호  $docNo',
                    style: const pw.TextStyle(fontSize: 9, color: _sub)),
                pw.SizedBox(height: 2),
                pw.Text(
                    '작성일  ${DateFormat('yyyy. MM. dd.').format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 9, color: _sub)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: 2, color: _accent),
      ],
    );
  }

  /// 문서 상단의 상대방 표기.
  ///
  /// 🔴 `귀중` 은 **요청서에만** 쓴다.
  ///    `귀중` 은 받는 사람을 높이는 말이다. 요청서는 도매상에게 보내는
  ///    문서니까 맞지만, 내역서는 내가 보관하거나 세무사에게 내는 문서다.
  ///    거기에 `강남화훼 귀중` 을 찍으면 "이 문서를 강남화훼에 보낸다" 는
  ///    뜻이 되어 문서의 성격이 뒤바뀐다.
  ///
  ///    거래처명은 영수증에서 OCR 로 읽은 값이라 정확하지 않을 수 있다.
  ///    (품목명과 같은 문제다) 그래서 요청서에서는 이름 아래에 짧게
  ///    확인을 요청한다.
  pw.Widget _addressee(SettlementDocKind kind, String vendor) {
    final isRequest = kind == SettlementDocKind.request;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (!isRequest)
              pw.Padding(
                padding: const pw.EdgeInsets.only(right: 6),
                child: pw.Text('거래처',
                    style: const pw.TextStyle(fontSize: 10, color: _sub)),
              ),
            pw.Text(vendor,
                style: pw.TextStyle(
                    fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink)),
            if (isRequest) ...[
              pw.SizedBox(width: 6),
              pw.Text('귀중',
                  style: const pw.TextStyle(fontSize: 11, color: _sub)),
            ],
          ],
        ),
      ],
    );
  }

  /// 우리 사업자 정보 5행. (사용자 결정 D — 5개 항목 전부)
  pw.Widget _myBusiness(SettlementDocKind kind, UserModel? me) {
    // 값이 없으면 예시값을 채우지 않는다. 빈 문서가 나가는 게
    // 틀린 정보가 나가는 것보다 낫다. (내보내기 단계에서 미리 막는다)
    String v(String? s) => (s != null && s.trim().isNotEmpty) ? s.trim() : '-';

    final rows = <List<String>>[
      ['상호', v(me?.businessName)],
      ['사업자등록번호', v(me?.businessNumber)],
      ['대표자', v(me?.ownerName)],
      ['전화번호', v(me?.phoneNumber)],
      ['주소', v(me?.businessAddress)],
    ];

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            width: double.infinity,
            color: _headBg,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: pw.Text(
                kind == SettlementDocKind.request
                    ? '요청하는 사업자 (공급받는 자)'
                    : '사업자 정보',
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(10, 4, 10, 6),
            child: pw.Column(
              children: [
                for (final r in rows)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.SizedBox(
                          width: 88,
                          child: pw.Text(r[0],
                              style:
                                  const pw.TextStyle(fontSize: 9.5, color: _sub)),
                        ),
                        pw.Expanded(
                          child: pw.Text(r[1],
                              style: pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _ink)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _summary({
    required SettlementDocKind kind,
    required int count,
    required double total,
    required String period,
  }) {
    pw.Widget cell(String k, String v, {bool strong = false}) {
      return pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(k, style: const pw.TextStyle(fontSize: 8.5, color: _sub)),
            pw.SizedBox(height: 3),
            pw.Text(v,
                style: pw.TextStyle(
                    fontSize: strong ? 15 : 11,
                    fontWeight: pw.FontWeight.bold,
                    color: strong ? _accent : _ink)),
          ],
        ),
      );
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: pw.BoxDecoration(
        color: _accentBg,
        border: pw.Border.all(color: PdfColor.fromInt(0xFFF7DDE2)),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          cell('대상 기간', period),
          cell('영수증', '$count건'),
          cell(
              kind == SettlementDocKind.request ? '요청 금액 합계' : '매입 합계',
              _won(total),
              strong: true),
        ],
      ),
    );
  }

  /// 내역 표. 월이 바뀌는 지점에 **월별 소계**를 끼워 넣는다.
  ///
  /// 사용자 요청: "월별로 금액이 쭉 나와야 한다"
  /// 참고 문서에는 소계가 없었다. 여러 달을 한 파일로 묶을 때
  /// 소계가 없으면 도매상도 우리도 달별 확인이 안 된다.
  List<pw.Widget> _table(
      SettlementDocKind kind, List<ReceiptModel> rs, double total) {
    final showItems = kind.showItems;

    // 열 구성.
    //
    // 🔴 요청서는 **3열**(순번 · 거래일 · 금액)이다.
    //    참고 문서에는 `영수증 번호` 열이 있었지만 8줄 전부 `-` 였다.
    //    손으로 쓴 영수증에 번호가 없으니 당연하다. 그 자리에 '비고' 를
    //    넣어봤더니 역시 전부 `-` 로 나왔다 — 같은 실수를 반복한 것이다.
    //    채울 게 없는 열은 만들지 않는다.
    final widths = showItems
        ? <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(1.0), // 순번
            1: const pw.FlexColumnWidth(2.4), // 거래일
            2: const pw.FlexColumnWidth(5.6), // 품목
            3: const pw.FlexColumnWidth(2.6), // 금액
          }
        : <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(1.2), // 순번
            1: const pw.FlexColumnWidth(5.0), // 거래일
            2: const pw.FlexColumnWidth(3.4), // 금액
          };

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _headBg),
        children: [
          _th('순번', center: true),
          _th('거래일'),
          if (showItems) _th('품목'),
          _th('금액', right: true),
        ],
      ),
    ];

    var i = 0;
    var monthSum = 0.0;
    var monthCount = 0;
    String? curMonth;

    void flushMonth() {
      if (curMonth == null || monthCount == 0) return;
      rows.add(pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFAFAFB)),
        children: [
          _td('', center: true),
          _td('$curMonth 소계  ($monthCount건)', bold: true),
          if (showItems) _td('', color: _sub),
          _td(_won(monthSum), right: true, bold: true),
        ],
      ));
    }

    for (final r in rs) {
      final m = DateFormat('yyyy년 M월').format(r.date);
      if (curMonth != m) {
        flushMonth();
        curMonth = m;
        monthSum = 0;
        monthCount = 0;
      }
      i++;
      monthSum += r.totalAmount;
      monthCount++;

      rows.add(pw.TableRow(children: [
        _td('$i', center: true),
        _td('${DateFormat('yyyy.MM.dd').format(r.date)} (${_weekday(r.date)})'),
        if (showItems) _itemsCell(r),
        _td(_won(r.totalAmount), right: true, bold: true),
      ]));
    }
    flushMonth();

    // 총 합계
    rows.add(pw.TableRow(
      decoration: const pw.BoxDecoration(color: _accentBg),
      children: [
        _td('', center: true),
        _td('합계  (${rs.length}건)', bold: true),
        if (showItems) _td('', color: _sub),
        _td(_won(total), right: true, bold: true, color: _accent, size: 11.5),
      ],
    ));

    return [
      pw.Table(
        border: pw.TableBorder.symmetric(
          inside: const pw.BorderSide(color: _line, width: .5),
          outside: const pw.BorderSide(color: _line, width: .5),
        ),
        columnWidths: widths,
        children: rows,
      ),
    ];
  }

  /// 품목 칸.
  ///
  /// 🔴 사용자가 확인하지 않은 영수증(`isManuallyEdited == false`)의 품목은
  ///    OCR 원본이라서 틀릴 수 있다. 숨기지 않고 ⚠ 로 드러낸다.
  ///    숨기면 나중에 틀린 걸 발견했을 때 앱 전체를 못 믿게 된다.
  pw.Widget _itemsCell(ReceiptModel r) {
    if (r.items.isEmpty) {
      return _td('-', color: _sub);
    }
    final unchecked = !r.isManuallyEdited;
    final names = r.items.map((e) {
      final q = e.quantity > 1 ? ' ${e.quantity}${e.unit}' : '';
      return '${e.name}$q';
    }).join(', ');

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: names,
              style: const pw.TextStyle(fontSize: 9, color: _ink),
            ),
            if (unchecked)
              pw.TextSpan(
                text: '  (미확인)',
                style: pw.TextStyle(
                    fontSize: 8, color: _accent, font: _bold, fontBold: _bold),
              ),
          ],
        ),
      ),
    );
  }

  pw.Widget _th(String s, {bool right = false, bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(s,
          textAlign: right
              ? pw.TextAlign.right
              : center
                  ? pw.TextAlign.center
                  : pw.TextAlign.left,
          style: pw.TextStyle(
              fontSize: 9, fontWeight: pw.FontWeight.bold, color: _sub)),
    );
  }

  pw.Widget _td(
    String s, {
    bool right = false,
    bool center = false,
    bool bold = false,
    PdfColor color = _ink,
    double size = 9,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(s,
          textAlign: right
              ? pw.TextAlign.right
              : center
                  ? pw.TextAlign.center
                  : pw.TextAlign.left,
          style: pw.TextStyle(
              fontSize: size,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color)),
    );
  }

  /// 문서 아래 안내문.
  ///
  /// 요청서와 내역서에서 문구가 다르다. 요청서는 도매상이 읽고,
  /// 내역서는 내가(또는 세무사가) 읽는다.
  pw.Widget _notice(
      SettlementDocKind kind, List<ReceiptModel> rs, int photoCount) {
    final lines = <String>[];

    if (kind == SettlementDocKind.request) {
      lines.add('위 내역에 대한 세금계산서 발행을 요청드립니다.');
      lines.add('금액은 실제 거래 영수증을 기준으로 정리한 것이며, 원본 사진을 함께 첨부했습니다.');
      lines.add('공급가액과 부가세 구분은 발행하시는 기준에 따라 처리해 주시기 바랍니다.');
    } else {
      lines.add('이 문서는 보관·제출용 매입 내역입니다.');
      final unchecked = rs.where((r) => !r.isManuallyEdited).length;
      if (unchecked > 0) {
        lines.add(
            '품목명 중 $unchecked건은 자동 인식(OCR) 결과이며 "(미확인)" 으로 표시했습니다. '
            '금액은 저장 시 확인된 값이지만, 품목명은 첨부한 영수증 사진을 기준으로 확인해 주세요.');
      }
    }

    if (photoCount > 0) {
      lines.add('첨부: 영수증 사진 $photoCount장');
    } else {
      lines.add('첨부: 영수증 사진 없음 (저장된 사진이 확인되지 않았습니다)');
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Text('· $l',
                  style: const pw.TextStyle(
                      fontSize: 8.5, color: _sub, lineSpacing: 1.6)),
            ),
        ],
      ),
    );
  }

  // ── 사진 페이지 ─────────────────────────────────────────────

  pw.Widget _photoHeader(int from, int to, int total) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('첨부 영수증',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold, color: _ink)),
            pw.Text('$from-$to / $total',
                style: const pw.TextStyle(fontSize: 9, color: _sub)),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 1, color: _line),
      ],
    );
  }

  /// 2×2 = 한 페이지에 4장.
  ///
  /// 사용자 결정: 한 장에 4장. (참고 문서는 2×3 = 6장)
  /// 4장이면 사진 하나가 커져서 손글씨 금액을 눈으로 읽을 수 있다.
  pw.Widget _photoGrid(List<_Photo> ph) {
    pw.Widget cellOf(_Photo? p) {
      if (p == null) return pw.SizedBox();
      return pw.Container(
        margin: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Image(pw.MemoryImage(p.bytes),
                    fit: pw.BoxFit.contain),
              ),
            ),
            pw.Container(
              width: double.infinity,
              color: _headBg,
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: pw.Text(
                '#${p.index}  ·  ${DateFormat('yyyy.MM.dd').format(p.date)}  ·  ${_won(p.amount)}',
                style: const pw.TextStyle(fontSize: 8, color: _sub),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget row(_Photo? a, _Photo? b) => pw.Expanded(
          child: pw.Row(children: [
            pw.Expanded(child: cellOf(a)),
            pw.Expanded(child: cellOf(b)),
          ]),
        );

    _Photo? at(int i) => i < ph.length ? ph[i] : null;

    return pw.Column(children: [row(at(0), at(1)), row(at(2), at(3))]);
  }

  pw.Widget _footer(pw.Context c) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text('FlowNote  ·  ${c.pageNumber} / ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _sub)),
    );
  }

  pw.Widget _footerText() {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('FlowNote',
          style: const pw.TextStyle(fontSize: 8, color: _sub)),
    );
  }

  // ── 도우미 ──────────────────────────────────────────────────

  /// 사진을 읽어 메모리에 올린다.
  ///
  /// 파일이 없으면 **조용히 건너뛴다.** 캐시 폴더에 있던 옛 영수증은
  /// 이미 사라졌을 수 있다(그래서 영구 저장을 도입했다). 그 때문에
  /// 내보내기 자체가 실패하면 안 된다.
  Future<List<_Photo>> _loadPhotos(List<ReceiptModel> rs) async {
    final out = <_Photo>[];

    var idx = 0;
    for (final r in rs) {
      idx++;
      final p = r.imagePath ?? '';
      if (p.isEmpty) continue;

      Uint8List? bytes;

      if (p.startsWith('http')) {
        // ── 클라우드에 올려둔 사진 ─────────────────────────────
        //
        // 🔴 웹에서 저장한 영수증은 사진이 Firebase Storage 에 있다.
        //    예전에는 `p.startsWith('http')` 를 그냥 `continue` 로 넘겨서
        //    웹에서 뽑은 정산서에는 사진이 한 장도 붙지 않았다.
        //    이제는 내려받아 붙인다.
        //
        //    앱에서도 유효하다. 기기를 바꿔 로컬 파일이 없는 영수증도
        //    클라우드 URL 이 남아 있으면 사진이 살아난다.
        bytes = await _fetchRemote(p);
      } else if (kCanReadLocalFiles) {
        // ── 기기에 보관한 사진 (앱) ────────────────────────────
        if (!await ReceiptImageStore.instance.exists(p)) continue;
        bytes = await readLocalFile(p);
      } else {
        // 웹인데 로컬 경로 → 이미 죽은 blob URL 이다. 읽을 방법이 없다.
        continue;
      }

      if (bytes == null || bytes.isEmpty) continue;
      out.add(_Photo(
        index: idx,
        bytes: bytes,
        date: r.date,
        amount: r.totalAmount,
      ));
    }
    return out;
  }

  /// 원격 사진(Firebase Storage 등)을 내려받는다.
  ///
  /// 실패하면 `null` — 사진 한 장 때문에 정산서 생성 전체가 실패하면 안 된다.
  /// 사진이 많으면 시간이 걸리므로 한 장당 제한을 둔다.
  ///
  /// 🔴 웹에서는 여기도 CORS 에 걸린다.
  ///    `package:http` 는 웹에서 결국 브라우저 XHR 로 나가기 때문에,
  ///    버킷에 CORS 규칙이 없으면 200 응답이어도 바이트를 못 읽는다.
  ///    (화면의 `ReceiptPhoto` 가 안 뜨던 것과 똑같은 원인이다)
  ///    버킷에 CORS 를 넣어 해결했지만, 화면과 달리 PDF 는 HTML <img>
  ///    로 대체할 수 없다 — 진짜 바이트가 필요하다. 그래서 실패했을 때
  ///    원인을 로그에 분명히 남긴다. 조용히 사진 없는 정산서가 나오면
  ///    무엇이 잘못됐는지 알 수 없다.
  Future<Uint8List?> _fetchRemote(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        debugPrint('[settle] 사진 내려받기 실패 status=${res.statusCode}');
        return null;
      }
      if (res.bodyBytes.isEmpty) {
        debugPrint('[settle] 사진 내려받기 결과가 0바이트다 — CORS 차단 의심');
        return null;
      }
      return res.bodyBytes;
    } catch (e) {
      // 웹에서 CORS 로 막히면 여기로 온다 (ClientException / XMLHttpRequest error).
      debugPrint(kIsWeb
          ? '[settle] 사진 내려받기 실패(건너뜀). 웹이면 Storage 버킷의 CORS '
              '설정을 확인해야 한다: $e'
          : '[settle] 사진 내려받기 예외(건너뜀): $e');
      return null;
    }
  }

  /// 요일. (월·화·수…)
  ///
  /// 🔴 `DateFormat('E', 'ko')` 를 쓰지 않는다.
  ///    그건 `initializeDateFormatting('ko')` 가 **먼저** 불려 있어야 하고,
  ///    안 불려 있으면 `LocaleDataException` 으로 PDF 생성이 통째로 죽는다.
  ///    (실제로 테스트에서 그렇게 터졌다)
  ///    앱은 `main()` 에서 초기화하지만, 정산서 생성이 그 호출 순서에
  ///    의존할 이유가 없다. 7글자짜리 표라서 직접 만드는 게 안전하다.
  static const _wd = ['월', '화', '수', '목', '금', '토', '일'];
  String _weekday(DateTime d) => _wd[(d.weekday - 1) % 7];

  String _periodOf(List<ReceiptModel> rs) {
    if (rs.isEmpty) return '-';
    final f = DateFormat('yyyy.MM');
    final a = f.format(rs.first.date);
    final b = f.format(rs.last.date);
    return a == b ? a : '$a ~ $b';
  }

  /// 문서번호. 날짜 + 건수로 만든다.
  /// (참고 문서는 `20260614-01` 형태였다)
  String _docNumber(List<ReceiptModel> rs) {
    final d = DateFormat('yyyyMMdd').format(DateTime.now());
    final n = rs.length.toString().padLeft(2, '0');
    return '$d-$n';
  }

  /// 파일명에 쓸 수 없는 문자를 없앤다.
  String _safeName(String s) {
    final t = s.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_').trim();
    return t.isEmpty ? '거래처' : t;
  }
}

class _Photo {
  const _Photo({
    required this.index,
    required this.bytes,
    required this.date,
    required this.amount,
  });

  final int index;
  final Uint8List bytes;
  final DateTime date;
  final double amount;
}
