import 'client_labels_utils.dart';

Map<String, String> getTrackingHeaders({Map<String, String>? environment}) {
  final List<String> labels = getClientLabels(environment: environment);
  final String headerValue = labels.join(' ');
  return <String, String>{
    'x-goog-api-client': headerValue,
    'user-agent': headerValue,
  };
}

Map<String, String> mergeTrackingHeaders(
  Map<String, String>? headers, {
  Map<String, String>? environment,
}) {
  final Map<String, String> merged = <String, String>{...?headers};
  final Map<String, String> tracking = getTrackingHeaders(
    environment: environment,
  );

  tracking.forEach((String key, String trackingValue) {
    final String? customValue = merged[key];
    if (customValue == null || customValue.isEmpty) {
      merged[key] = trackingValue;
      return;
    }

    final List<String> valueParts = trackingValue
        .split(' ')
        .where((String value) => value.isNotEmpty)
        .toList(growable: true);
    for (final String customPart in customValue.split(' ')) {
      if (customPart.isEmpty || valueParts.contains(customPart)) {
        continue;
      }
      valueParts.add(customPart);
    }
    merged[key] = valueParts.join(' ');
  });

  return merged;
}
