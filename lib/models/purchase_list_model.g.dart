// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_list_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PurchaseListAdapter extends TypeAdapter<PurchaseList> {
  @override
  final int typeId = 2;

  @override
  PurchaseList read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PurchaseList(
      id: fields[0] as String,
      date: fields[1] as DateTime,
      purpose: fields[2] as String,
      items: (fields[3] as List?)?.cast<PurchaseItem>(),
      budgetCap: fields[4] as double,
      memo: fields[5] as String,
      strokes: (fields[6] as List?)?.cast<SketchStroke>(),
      statusCode: fields[7] as int,
      createdAt: fields[8] as DateTime,
      updatedAt: fields[9] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, PurchaseList obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.purpose)
      ..writeByte(3)
      ..write(obj.items)
      ..writeByte(4)
      ..write(obj.budgetCap)
      ..writeByte(5)
      ..write(obj.memo)
      ..writeByte(6)
      ..write(obj.strokes)
      ..writeByte(7)
      ..write(obj.statusCode)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PurchaseListAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PurchaseItemAdapter extends TypeAdapter<PurchaseItem> {
  @override
  final int typeId = 3;

  @override
  PurchaseItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PurchaseItem(
      name: fields[0] as String,
      qty: fields[1] as double,
      unitPrice: fields[2] as double,
      unit: fields[3] as String,
      checked: fields[4] as bool,
      missed: fields[5] as bool,
      actualPrice: fields[6] as double?,
      basisDate: fields[7] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, PurchaseItem obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.qty)
      ..writeByte(2)
      ..write(obj.unitPrice)
      ..writeByte(3)
      ..write(obj.unit)
      ..writeByte(4)
      ..write(obj.checked)
      ..writeByte(5)
      ..write(obj.missed)
      ..writeByte(6)
      ..write(obj.actualPrice)
      ..writeByte(7)
      ..write(obj.basisDate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PurchaseItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SketchStrokeAdapter extends TypeAdapter<SketchStroke> {
  @override
  final int typeId = 4;

  @override
  SketchStroke read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SketchStroke(
      colorValue: fields[0] as int,
      width: fields[1] as double,
      points: (fields[2] as List?)?.cast<double>(),
    );
  }

  @override
  void write(BinaryWriter writer, SketchStroke obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.colorValue)
      ..writeByte(1)
      ..write(obj.width)
      ..writeByte(2)
      ..write(obj.points);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SketchStrokeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
