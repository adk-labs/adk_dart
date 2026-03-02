/// Canonical JSON-like map used by evaluation models.
typedef EvalJson = Map<String, Object?>;

/// Casts [value] to [EvalJson], returning an empty map when invalid.
EvalJson asEvalJson(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) {
      return MapEntry(key.toString(), item);
    });
  }
  return <String, Object?>{};
}

/// Casts [value] to a JSON-like list, returning an empty list when invalid.
List<Object?> asObjectList(Object? value) {
  if (value is List) {
    return List<Object?>.from(value);
  }
  return <Object?>[];
}

/// Casts [value] to a list of [EvalJson] maps.
List<EvalJson> asEvalJsonList(Object? value) {
  return asObjectList(value).map(asEvalJson).toList();
}

/// Returns [value] when it is a [String], otherwise `null`.
String? asNullableString(Object? value) {
  return value is String ? value : null;
}

/// Returns [value] as `double` when numeric, otherwise `null`.
double? asNullableDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

/// Returns [value] as `double` or [fallback] when conversion fails.
double asDoubleOr(Object? value, {double fallback = 0.0}) {
  return asNullableDouble(value) ?? fallback;
}
