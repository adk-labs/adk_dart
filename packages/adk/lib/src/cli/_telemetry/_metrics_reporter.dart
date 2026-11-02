/// Telemetry metrics reporter with rate-limiting and retry support.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '_constants.dart';

/// Default Clearcut / telemetry endpoint URL.
const String defaultTelemetryEndpoint =
    'https://play.googleapis.com/log?format=json_proto';

/// Result of an HTTP telemetry report attempt.
class HttpReportResult {
  /// Creates an [HttpReportResult].
  const HttpReportResult({
    required this.statusCode,
    this.body = '',
  });

  /// HTTP response status code.
  final int statusCode;

  /// HTTP response body text.
  final String body;
}

/// Extracts `next_request_wait_millis` (or `nextRequestWaitMillis`) from a
/// JSON response body, returning `null` if absent or invalid.
int? extractNextRequestWaitMillis(String responseBody) {
  if (responseBody.trim().isEmpty) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(responseBody);
    if (decoded is Map) {
      final Object? raw =
          decoded['next_request_wait_millis'] ??
          decoded['nextRequestWaitMillis'];
      if (raw is int) {
        return raw;
      }
      if (raw is num) {
        return raw.toInt();
      }
      if (raw is String) {
        return int.tryParse(raw);
      }
    }
  } catch (_) {}
  return null;
}

/// Updates the rate-limit timestamp in the lock/state file at [stateFilePath].
void setRateLimitTimestamp(
  int waitMillis, {
  String? stateFilePath,
  int? nowMillis,
}) {
  if (waitMillis <= 0) {
    return;
  }
  final String path = stateFilePath ?? lockFile;
  final int current = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
  final int nextAllowed = current + waitMillis;
  try {
    final File file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode(<String, Object?>{'next_allowed_timestamp_ms': nextAllowed}),
    );
  } catch (_) {}
}

/// Checks whether telemetry reporting is currently rate-limited.
bool isRateLimited({String? stateFilePath, int? nowMillis}) {
  final String path = stateFilePath ?? lockFile;
  final File file = File(path);
  if (!file.existsSync()) {
    return false;
  }
  try {
    final Object? decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map) {
      final Object? raw = decoded['next_allowed_timestamp_ms'];
      final int? nextAllowed = raw is num
          ? raw.toInt()
          : int.tryParse('$raw');
      if (nextAllowed != null) {
        final int current = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
        return current < nextAllowed;
      }
    }
  } catch (_) {}
  return false;
}

/// Sends a telemetry payload to [endpointUrl] with retry and backoff support.
Future<HttpReportResult?> sendRequestWithRetry(
  String payload, {
  String endpointUrl = defaultTelemetryEndpoint,
  int maxRetries = 3,
  Duration initialDelay = const Duration(milliseconds: 200),
  String? stateFilePath,
  Future<HttpReportResult> Function(String url, String body)? transport,
}) async {
  final Future<HttpReportResult> Function(String url, String body) sender =
      transport ?? _defaultHttpTransport;

  Duration delay = initialDelay;
  for (int attempt = 0; attempt < maxRetries; attempt++) {
    try {
      final HttpReportResult result = await sender(endpointUrl, payload);
      final int? waitMillis = extractNextRequestWaitMillis(result.body);
      if (waitMillis != null && waitMillis > 0) {
        setRateLimitTimestamp(waitMillis, stateFilePath: stateFilePath);
      }
      if (result.statusCode >= 200 && result.statusCode < 300) {
        return result;
      }
      if (result.statusCode >= 400 &&
          result.statusCode < 500 &&
          result.statusCode != 429) {
        return result;
      }
    } catch (_) {
      // Transient transport error; retry if attempts remain.
    }
    if (attempt + 1 < maxRetries) {
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }
  return null;
}

/// Reads queued telemetry events from [queueFilePath], sends them to
/// [endpointUrl], and clears the queue on success.
Future<bool> reportMetrics({
  String? queueFilePath,
  String? stateFilePath,
  String? endpointUrl,
  Future<HttpReportResult> Function(String url, String body)? transport,
}) async {
  final String targetQueue = queueFilePath ?? queueFile;
  final String targetState = stateFilePath ?? lockFile;
  if (isRateLimited(stateFilePath: targetState)) {
    return false;
  }

  final File file = File(targetQueue);
  if (!file.existsSync()) {
    return true;
  }

  List<String> lines;
  try {
    lines = file
        .readAsLinesSync()
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();
  } catch (_) {
    return false;
  }

  if (lines.isEmpty) {
    return true;
  }

  final List<Object?> events = <Object?>[];
  for (final String line in lines) {
    try {
      events.add(jsonDecode(line));
    } catch (_) {}
  }

  if (events.isEmpty) {
    try {
      file.writeAsStringSync('');
    } catch (_) {}
    return true;
  }

  final String body = jsonEncode(<String, Object?>{'events': events});
  final HttpReportResult? response = await sendRequestWithRetry(
    body,
    endpointUrl: endpointUrl ?? defaultTelemetryEndpoint,
    stateFilePath: targetState,
    transport: transport,
  );

  if (response != null &&
      response.statusCode >= 200 &&
      response.statusCode < 300) {
    try {
      file.writeAsStringSync('');
    } catch (_) {}
    return true;
  }
  return false;
}

Future<HttpReportResult> _defaultHttpTransport(String url, String body) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.write(body);
    final HttpClientResponse response = await request.close();
    final String responseBody = await utf8.decoder.bind(response).join();
    return HttpReportResult(
      statusCode: response.statusCode,
      body: responseBody,
    );
  } finally {
    client.close(force: true);
  }
}
