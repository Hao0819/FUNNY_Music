// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'folder_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FolderModelAdapter extends TypeAdapter<FolderModel> {
  @override
  final int typeId = 0;

  @override
  FolderModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FolderModel(
      id: fields[0] as String,
      name: fields[1] as String,
      createdAt: fields[2] as DateTime,
      isSystem: fields[3] as bool,
      sortMode: fields[4] as String,
      colorValue: fields[5] as int?,
      coverPath: fields[6] as String?,
      sortDescending: fields[7] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, FolderModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.isSystem)
      ..writeByte(4)
      ..write(obj.sortMode)
      ..writeByte(5)
      ..write(obj.colorValue)
      ..writeByte(6)
      ..write(obj.coverPath)
      ..writeByte(7)
      ..write(obj.sortDescending);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
