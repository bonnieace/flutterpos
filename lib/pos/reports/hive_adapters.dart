// hive_adapters.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class TimestampAdapter extends TypeAdapter<Timestamp> {
  @override
  final int typeId = 0; // You can use any unique positive integer here

  @override
  Timestamp read(BinaryReader reader) {
    return Timestamp.fromMillisecondsSinceEpoch(reader.readInt32());
  }

  @override
  void write(BinaryWriter writer, Timestamp obj) {
    writer.writeInt32(obj.millisecondsSinceEpoch);
  }
}
