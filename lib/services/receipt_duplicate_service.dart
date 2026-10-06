import '../models/receipt_model.dart';
import '../screens/scan/scan_draft.dart';

/// 중복 영수증 판정 강도.
enum DuplicateLevel {
  /// 매입처 · 날짜 · 금액 · 품목이 전부 같다. 거의 확실히 같은 영수증이다.
  exact,

  /// 매입처 · 날짜가 같고 금액 **또는** 품목 중 하나가 같다.
  ///
  /// 같은 날 같은 가게에서 두 번 사면 이 상태가 나올 수 있다.
  /// 그래서 막지 않고 물어보기만 한다.
  likely,
}

/// 영수증 한 건을 비교하기 위한 지문.
///
/// 사진 바이트나 OCR 원문을 쓰지 않는 이유:
///
/// - **사진 해시**는 같은 영수증을 다시 찍으면 절대 안 맞는다.
///   갤러리에서 같은 파일을 두 번 넣은 경우만 잡힌다.
/// - **OCR 원문 해시**는 모델이 매번 미세하게 다르게 읽어서 자주 놓친다.
///
/// 그래서 사람이 눈으로 "같은 영수증이네" 라고 판단할 때 쓰는 값,
/// 즉 **매입처 · 날짜 · 금액 · 품목**으로 지문을 만든다.
class ReceiptKey {
  ReceiptKey({
    required this.store,
    required this.day,
    required this.total,
    required this.items,
  });

  /// 정규화한 매입처 이름
  final String store;

  /// 시:분을 버린 거래일자
  final DateTime day;

  /// 원 단위로 반올림한 총액
  final int total;

  /// 정규화 · 정렬한 품목 서명. 품목이 없으면 ''.
  final String items;

  static ReceiptKey ofReceipt(ReceiptModel r) => ReceiptKey(
        store: normalizeStore(r.storeName),
        day: DateTime(r.date.year, r.date.month, r.date.day),
        total: r.totalAmount.round(),
        items: signature(
          r.items.map((e) => (e.name, e.quantity, e.unitPrice)),
        ),
      );

  static ReceiptKey ofDraft(ScanDraft d) => ReceiptKey(
        store: normalizeStore(d.storeName),
        day: DateTime(d.date.year, d.date.month, d.date.day),
        total: d.total.round(),
        items: signature(
          d.items.map((e) => (e.name, e.quantity, e.unitPrice)),
        ),
      );

  /// 매입처 이름을 비교 가능한 형태로 다듬는다.
  ///
  /// OCR 은 같은 가게를 `대한꽃도매`, `(주)대한꽃도매`, `대한 꽃도매` 처럼
  /// 매번 조금씩 다르게 읽는다. 그대로 비교하면 중복을 통째로 놓친다.
  static String normalizeStore(String raw) {
    var s = raw.toLowerCase();
    // 법인 표기 제거
    for (final t in const ['주식회사', '(주)', '（주）', '㈜', '유한회사', '(유)']) {
      s = s.replaceAll(t, '');
    }
    // 공백 · 마침표 · 하이픈 · 가운뎃점 제거
    s = s.replaceAll(RegExp(r'[\s\.\-·,]'), '');
    return s;
  }

  /// 품목 목록을 순서에 무관한 한 줄 서명으로 만든다.
  ///
  /// 인식 순서가 뒤바뀌어도 같은 값이 나와야 하므로 정렬한다.
  static String signature(Iterable<(String, int, double)> items) {
    final parts = <String>[];
    for (final (name, qty, price) in items) {
      final n = name.toLowerCase().replaceAll(RegExp(r'\s'), '');
      if (n.isEmpty && qty == 0 && price == 0) continue;
      parts.add('$n|$qty|${price.round()}');
    }
    if (parts.isEmpty) return '';
    parts.sort();
    return parts.join(';');
  }

  bool get _hasStore => store.isNotEmpty;

  /// [other] 와 견줘 중복 강도를 낸다. 아니면 null.
  DuplicateLevel? compare(ReceiptKey other) {
    // 매입처를 모르면 판단하지 않는다. '미지정 매입처' 끼리 전부
    // 중복으로 잡히면 경고가 쓸모없어진다.
    if (!_hasStore || !other._hasStore) return null;
    if (store != other.store) return null;
    if (day != other.day) return null;

    final sameTotal = total == other.total && total > 0;
    final sameItems =
        items.isNotEmpty && other.items.isNotEmpty && items == other.items;

    if (sameTotal && sameItems) return DuplicateLevel.exact;
    if (sameTotal || sameItems) return DuplicateLevel.likely;
    return null;
  }
}

/// 중복 한 건.
class DuplicateHit {
  const DuplicateHit({
    required this.draft,
    required this.level,
    this.saved,
    this.sibling,
  });

  /// 지금 저장하려는 건
  final ScanDraft draft;

  final DuplicateLevel level;

  /// 이미 저장돼 있던 영수증과 겹친 경우
  final ReceiptModel? saved;

  /// 이번에 함께 찍은 다른 장과 겹친 경우
  final ScanDraft? sibling;

  bool get isExact => level == DuplicateLevel.exact;

  /// 겹친 상대의 설명 한 줄
  String get againstLabel =>
      sibling != null ? '이번에 함께 찍은 영수증' : '이미 저장된 영수증';
}

/// 저장 직전 중복 검사.
///
/// ## 왜 저장을 막지 않는가
///
/// 같은 날 같은 가게에서 두 번 사는 일은 실제로 있다. 우리가 그걸
/// 판단해서 저장을 거부할 권리는 없다. 그래서 **알려주고 고르게** 한다.
/// (`blocksSave` 를 최소한으로 둔 것과 같은 이유다.)
class ReceiptDuplicateService {
  const ReceiptDuplicateService._();

  /// [drafts] 를 [saved] 및 서로와 견줘 중복을 찾는다.
  ///
  /// 한 건당 가장 강한 판정 하나만 돌려준다. 목록 순서는 [drafts] 순서다.
  static List<DuplicateHit> check(
    List<ScanDraft> drafts,
    List<ReceiptModel> saved,
  ) {
    final savedKeys = [
      for (final r in saved) (r, ReceiptKey.ofReceipt(r)),
    ];
    final draftKeys = [
      for (final d in drafts) (d, ReceiptKey.ofDraft(d)),
    ];

    final hits = <DuplicateHit>[];
    for (var i = 0; i < draftKeys.length; i++) {
      final (draft, key) = draftKeys[i];

      DuplicateHit? best;

      // 1) 이미 저장된 영수증과 비교
      for (final (r, rk) in savedKeys) {
        final lv = key.compare(rk);
        if (lv == null) continue;
        if (best == null || (lv == DuplicateLevel.exact && !best.isExact)) {
          best = DuplicateHit(draft: draft, level: lv, saved: r);
        }
        if (best.isExact) break;
      }

      // 2) 이번 묶음 안의 **앞선** 장과 비교.
      //    앞선 장만 보는 이유: 2장이 서로 같으면 뒤엣것 하나만
      //    경고하면 된다. 둘 다 경고하면 사장님이 둘 다 빼 버린다.
      if (best == null || !best.isExact) {
        for (var j = 0; j < i; j++) {
          final (other, ok) = draftKeys[j];
          final lv = key.compare(ok);
          if (lv == null) continue;
          if (best == null || (lv == DuplicateLevel.exact && !best.isExact)) {
            best = DuplicateHit(draft: draft, level: lv, sibling: other);
          }
          if (best.isExact) break;
        }
      }

      if (best != null) hits.add(best);
    }
    return hits;
  }

  /// 처음 화면을 열 때 기본으로 제외해 둘 건들.
  ///
  /// 확실한 중복만 기본 제외한다. '의심' 은 사장님이 직접 고르셔야 한다.
  static Set<String> defaultSkipIds(List<DuplicateHit> hits) =>
      {for (final h in hits.where((e) => e.isExact)) h.draft.id};
}
