// GENERATED CODE - DO NOT MODIFY BY HAND
// 使用 Hive TypeAdapter 自动生成的简单实现（手写以避免构建步骤）

part of 'product_model.dart';

class ProductModelAdapter extends TypeAdapter<ProductModel> {
  @override
  final int typeId = 0;

  @override
  ProductModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final key = reader.readByte();
      fields[key] = reader.read();
    }
    return ProductModel(
      id: fields[0] as String,
      platform: (fields[1] as String?) ?? 'taobao',
      title: fields[2] as String,
      price: (fields[3] as double?) ?? 0.0,
      originalPrice: (fields[4] as double?) ?? (fields[3] as double?) ?? 0.0,
      coupon: (fields[5] as double?) ?? 0.0,
      finalPrice: (fields[6] as double?) ?? ((fields[3] as double?) ?? 0.0),
      imageUrl: (fields[7] as String?) ?? '',
      sales: (fields[8] as int?) ?? 0,
      rating: (fields[9] as double?) ?? 0.0,
      link: (fields[10] as String?) ?? '',
      commission: (fields[11] as double?) ?? 0.0,
      description: (fields[12] as String?) ?? '',
      shopTitle: (fields[13] as String?) ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, ProductModel obj) {
    writer
      ..writeByte(14) // 14 个字段
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.platform)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.price)
      ..writeByte(4)
      ..write(obj.originalPrice)
      ..writeByte(5)
      ..write(obj.coupon)
      ..writeByte(6)
      ..write(obj.finalPrice)
      ..writeByte(7)
      ..write(obj.imageUrl)
      ..writeByte(8)
      ..write(obj.sales)
      ..writeByte(9)
      ..write(obj.rating)
      ..writeByte(10)
      ..write(obj.link)
      ..writeByte(11)
      ..write(obj.commission)
      ..writeByte(12)
      ..write(obj.description)
      ..writeByte(13)
      ..write(obj.shopTitle);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
