String toCamelCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  final List<String> chunks = value
      .split('_')
      .where((String chunk) => chunk.isNotEmpty)
      .toList(growable: false);
  if (chunks.isEmpty) {
    return '';
  }
  final String head = chunks.first.toLowerCase();
  final Iterable<String> tail = chunks.skip(1).map((String chunk) {
    if (chunk.isEmpty) {
      return chunk;
    }
    return chunk[0].toUpperCase() + chunk.substring(1).toLowerCase();
  });
  return '$head${tail.join()}';
}

abstract class CliBaseModel {
  Map<String, Object?> toJson();
}

Map<String, Object?> normalizeJsonObject(Map<Object?, Object?> input) {
  final Map<String, Object?> normalized = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in input.entries) {
    final String key = '${entry.key}';
    normalized[toCamelCase(key)] = entry.value;
  }
  return normalized;
}
