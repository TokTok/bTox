import 'package:drift/drift.dart';

final class Id<T> {
  final int value;

  const Id(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Id<T> &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Id<$T>($value)';
}

final class IdConverter<T> extends TypeConverter<Id<T>, int>
    with JsonTypeConverter2<Id<T>, int, int> {
  const IdConverter();

  @override
  Id<T> fromJson(int json) => Id(json);
  @override
  Id<T> fromSql(int fromDb) => Id(fromDb);
  @override
  int toJson(Id<T> value) => value.value;
  @override
  int toSql(Id<T> value) => value.value;
}
