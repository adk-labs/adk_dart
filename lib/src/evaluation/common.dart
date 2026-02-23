typedef EvalJson = Map<String, Object?>;

EvalJson asEvalJson(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) {
      return MapEntry(key.toString(), item);
    });
  }
  return <String, Object?>{};
}

List<Object?> asObjectList(Object? value) {
  if (value is List) {
    return List<Object?>.from(value);
  }
  return <Object?>[];
}

List<EvalJson> asEvalJsonList(Object? value) {
  return asObjectList(value).map(asEvalJson).toList();
}

String? asNullableString(Object? value) {
  return value is String ? value : null;
}

double? asNullableDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

double asDoubleOr(Object? value, {double fallback = 0.0}) {
  return asNullableDouble(value) ?? fallback;
}
