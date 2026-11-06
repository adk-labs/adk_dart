/// Header helpers for Google API client tracking metadata.
library;

import '../models/llm_request.dart';
import 'client_labels_utils.dart';

/// The standard tracking headers for the current runtime context.
Map<String, String> getTrackingHeaders({
  String? frameworkLabel,
  Map<String, String>? environment,
}) {
  final List<String> labels = getClientLabels(
    frameworkLabel: frameworkLabel,
    environment: environment,
  );
  final String headerValue = labels.join(' ');
  return <String, String>{
    'x-goog-api-client': headerValue,
    'user-agent': headerValue,
  };
}

const Set<String> _trackingHeaderNames = <String>{
  'user-agent',
  'x-goog-api-client',
};

/// The [headers] map merged with SDK tracking header values.
///
/// Existing header tokens are preserved and deduplicated.
Map<String, String> mergeTrackingHeaders(
  Map<String, String>? headers, {
  String? frameworkLabel,
  Map<String, String>? environment,
}) {
  final Map<String, String> merged = <String, String>{};
  if (headers != null) {
    for (final MapEntry<String, String> entry in headers.entries) {
      final String lower = entry.key.toLowerCase();
      if (_trackingHeaderNames.contains(lower)) {
        merged[lower] = entry.value;
      } else {
        merged[entry.key] = entry.value;
      }
    }
  }
  final Map<String, String> tracking = getTrackingHeaders(
    frameworkLabel: frameworkLabel,
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

/// Merges tracking headers into [httpOptions] ([HttpOptions] or `Map`).
///
/// If [httpOptions] is `null` or an empty map, returns a new [HttpOptions]
/// instance with tracking headers populated.
Object mergeTrackingHttpOptions({
  Object? httpOptions,
  String? frameworkLabel,
  Map<String, String>? environment,
}) {
  if (httpOptions == null || (httpOptions is Map && httpOptions.isEmpty)) {
    return HttpOptions(
      headers: mergeTrackingHeaders(
        null,
        frameworkLabel: frameworkLabel,
        environment: environment,
      ),
    );
  }
  if (httpOptions is Map) {
    final Object? rawHeaders = httpOptions['headers'];
    Map<String, String>? headers;
    if (rawHeaders is Map) {
      headers = rawHeaders.map(
        (Object? k, Object? v) =>
            MapEntry<String, String>(k.toString(), v?.toString() ?? ''),
      );
    }
    httpOptions['headers'] = mergeTrackingHeaders(
      headers,
      frameworkLabel: frameworkLabel,
      environment: environment,
    );
    return httpOptions;
  }
  if (httpOptions is HttpOptions) {
    httpOptions.headers = mergeTrackingHeaders(
      httpOptions.headers,
      frameworkLabel: frameworkLabel,
      environment: environment,
    );
    return httpOptions;
  }
  throw ArgumentError.value(
    httpOptions,
    'httpOptions',
    'Expected HttpOptions, Map, or null.',
  );
}
