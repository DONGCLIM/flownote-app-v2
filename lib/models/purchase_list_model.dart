import 'package:hive/hive.dart';

import '../services/purchase_list_service.dart';

part 'purchase_list_model.g.dart';

/// 사입 리스트 하나.
///
/// 🔴 사장님 지시(#179): **날짜·목적·품목·한도·메모·스케치·체크 상태를
///    한 덩어리로** 들고 다닌다. 예산 검토(시장 전날)에서 만들고,
///    사입 메모장(시장에서)에서 같은 것을 이어서 쓴다.
///
/// ```
///   예산 검토   → 날짜·목적·품목·한도를 적는다        (준비)
///   사입 메모장 → 체크·메모·스케치를 더한다            (사입 중 → 완료)
/// ```
///
/// 🔴 typeId 는 0·1 을 `receipt_model.dart` 가 이미 쓰고 있다.
///    여기서는 2·3·4 를 쓴다. **이미 쓴 번호를 다시 쓰면 저장된 데이터가
///    엉뚱한 모양으로 읽혀 앱이 죽는다.**
@HiveType(typeId: 2)
class PurchaseList extends HiveObject {
  @HiveField(0)
  String id;

  /// 사입하러 가는 날. 기본값은 **내일**(보통 전날 밤에 적는다).
  @HiveField(1)
  DateTime date;

  /// 왜 사는지. 예) `주말 부케 3건 대비`
  @HiveField(2)
  String purpose;

  @HiveField(3)
  List<PurchaseItem> items;

  /// 이번 사입 한도.
  @HiveField(4)
  double budgetCap;

  /// 사입 메모장에 적은 글.
  @HiveField(5)
  String memo;

  /// 손으로 그린 선들. 좌표만 담는다(그림 파일이 아니다).
  @HiveField(6)
  List<SketchStroke> strokes;

  /// 0 준비 · 1 사입 중 · 2 완료.
  ///
  /// 🔴 숫자로 담는 이유: 나중에 상태를 더 늘려도 저장된 데이터가 안 깨진다.
  ///    바깥에서는 [status] 로만 다룬다.
  @HiveField(7)
  int statusCode;

  @HiveField(8)
  DateTime createdAt;

  @HiveField(9)
  DateTime updatedAt;

  PurchaseList({
    required this.id,
    required this.date,
    this.purpose = '',
    List<PurchaseItem>? items,
    this.budgetCap = 0,
    this.memo = '',
    List<SketchStroke>? strokes,
    this.statusCode = 0,
    required this.createdAt,
    required this.updatedAt,
  })  : items = items ?? <PurchaseItem>[],
        strokes = strokes ?? <SketchStroke>[];

  PurchaseStatus get status => PurchaseStatus.fromCode(statusCode);
  set status(PurchaseStatus v) => statusCode = v.code;

  /// 계획 금액 합계. (실제로 산 값이 아니라 **적어 둔 값**)
  double get plannedTotal =>
      items.fold<double>(0, (acc, e) => acc + e.plannedAmount);

  /// 실제로 쓴 금액. 체크한 것만 센다. 못 산 것은 0 원이다.
  double get spentTotal =>
      items.fold<double>(0, (acc, e) => acc + e.spentAmount);

  /// 한도에서 계획 금액을 뺀 값. 음수면 넘긴 것이다.
  double get remaining => budgetCap - plannedTotal;

  /// 한도를 넘겼는가.
  bool get overBudget => plannedTotal > budgetCap && budgetCap > 0;

  /// 아직 사지도, 포기하지도 않은 품목 수.
  int get pendingCount => items.where((e) => !e.done).length;

  /// 품목이 하나도 없는 리스트인가. (메모만 적어 둔 것)
  ///
  /// 🔴 금액 칸을 비우고 "메모 리스트 · ○줄" 로 보여줄 때 쓴다.
  bool get isMemoOnly => items.isEmpty;

  /// 메모가 몇 줄인가. 빈 줄은 세지 않는다.
  int get memoLineCount =>
      MemoText.total(MemoText.parse(memo));

  /// 장바구니에 남은 예산 — 한도에서 **이미 쓴 돈**을 뺀다.
  double get liveRemaining => budgetCap - spentTotal;

  /// 체크 상태를 보고 상태를 다시 정한다.
  ///
  /// 🔴 사장님 확정(#179): **"못 샀어요"도 처리된 것으로 친다.**
  ///    안 그러면 한 품목을 못 샀을 때 영영 `완료`가 되지 않는다.
  void refreshStatus() {
    if (items.isEmpty) {
      status = PurchaseStatus.ready;
      return;
    }
    final touched = items.where((e) => e.done).length;
    if (touched == 0) {
      status = PurchaseStatus.ready;
    } else if (touched >= items.length) {
      status = PurchaseStatus.done;
    } else {
      status = PurchaseStatus.shopping;
    }
  }

  PurchaseList copy() => PurchaseList(
        id: id,
        date: date,
        purpose: purpose,
        items: items.map((e) => e.copy()).toList(),
        budgetCap: budgetCap,
        memo: memo,
        strokes: strokes.map((e) => e.copy()).toList(),
        statusCode: statusCode,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// 사입 리스트에 적은 품목 한 줄.
@HiveType(typeId: 3)
class PurchaseItem extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  double qty;

  /// 적어 둔 단가. 보통 직전 영수증에서 가져온다.
  @HiveField(2)
  double unitPrice;

  /// 영수증에 적혀 있던 단위 (`단`, `속`, `개` …).
  @HiveField(3)
  String unit;

  /// 샀다고 체크했는가.
  @HiveField(4)
  bool checked;

  /// 못 샀다고 표시했는가. (품절·너무 비쌈 …)
  @HiveField(5)
  bool missed;

  /// 시장에서 실제로 치른 단가. 비워 두면 [unitPrice] 를 쓴다.
  @HiveField(6)
  double? actualPrice;

  /// 이 단가를 가져온 영수증 날짜. 없으면 직접 적은 것이다.
  @HiveField(7)
  DateTime? basisDate;

  PurchaseItem({
    required this.name,
    this.qty = 0,
    this.unitPrice = 0,
    this.unit = '',
    this.checked = false,
    this.missed = false,
    this.actualPrice,
    this.basisDate,
  });

  /// 계획 금액.
  double get plannedAmount => qty * unitPrice;

  /// 실제 금액. 체크했을 때만 돈이 나간다.
  ///
  /// 🔴 못 산 것은 **0 원**이다. 체크도 안 했으면 아직 안 쓴 돈이다.
  double get spentAmount {
    if (missed || !checked) return 0;
    return qty * (actualPrice ?? unitPrice);
  }

  /// 처리가 끝난 줄인가 (샀거나, 못 샀거나).
  bool get done => checked || missed;

  /// 단가를 영수증에서 가져왔는가.
  bool get fromReceipt => basisDate != null;

  PurchaseItem copy() => PurchaseItem(
        name: name,
        qty: qty,
        unitPrice: unitPrice,
        unit: unit,
        checked: checked,
        missed: missed,
        actualPrice: actualPrice,
        basisDate: basisDate,
      );
}

/// 손으로 그은 선 하나.
///
/// 🔴 사장님 선택(#179): **그림 파일이 아니라 좌표만** 저장한다.
///    용량이 작고(한 장에 몇 KB), 나중에 다시 열어 **이어 그릴 수 있다.**
@HiveType(typeId: 4)
class SketchStroke extends HiveObject {
  /// 색 (`Color.value`).
  @HiveField(0)
  int colorValue;

  /// 선 굵기.
  @HiveField(1)
  double width;

  /// `[x1, y1, x2, y2, …]` 로 납작하게 편 좌표.
  ///
  /// 🔴 `List<Offset>` 을 쓰지 않는 이유: Hive 가 모르는 타입이라 어댑터를
  ///    하나 더 만들어야 한다. 숫자 목록이면 그대로 저장된다.
  @HiveField(2)
  List<double> points;

  SketchStroke({
    required this.colorValue,
    required this.width,
    List<double>? points,
  }) : points = points ?? <double>[];

  SketchStroke copy() => SketchStroke(
        colorValue: colorValue,
        width: width,
        points: List<double>.from(points),
      );
}

/// 사입 리스트의 진행 상태.
enum PurchaseStatus {
  ready(0, '준비'),
  shopping(1, '사입 중'),
  done(2, '완료');

  const PurchaseStatus(this.code, this.label);

  final int code;
  final String label;

  static PurchaseStatus fromCode(int c) => switch (c) {
        1 => PurchaseStatus.shopping,
        2 => PurchaseStatus.done,
        _ => PurchaseStatus.ready,
      };
}
