/// Header helpers for Google API client tracking metadata.
library;

import 'client_labels_utils.dart';

/// The standard tracking headers for the current runtime context.
Map<String, String> getTrackingHeaders({Map<String, String>? environment}) {
  final List<String> labels = getClientLabels(environment: environment);
  final String headerValue = labels.join(' ');
  return <String, String>{
    'x-goog-api-client': headerValue,
    'user-agent': headerValue,
  };
}

/// The [headers] map merged with SDK tracking header values.
///
/// Existing header tokens are preserved and deduplicated.
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
