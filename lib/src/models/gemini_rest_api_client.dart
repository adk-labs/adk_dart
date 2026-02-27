import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'llm_request.dart';

class GeminiRestApiException implements Exception {
  GeminiRestApiException(this.statusCode, this.message, {this.responseBody});

  final int statusCode;
  final String message;
  final String? responseBody;

  @override
  String toString() {
    return 'GeminiRestApiException(statusCode: $statusCode, message: $message)';
  }
}

abstract class GeminiRestTransport {
  Future<Map<String, Object?>> generateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    required String apiVersion,
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  });

  Stream<Map<String, Object?>> streamGenerateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    required String apiVersion,
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  });

  Future<Map<String, Object?>> createInteraction({
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) {
    throw UnsupportedError(
      'Interactions API is not supported by this transport.',
    );
  }

  Stream<Map<String, Object?>> streamCreateInteraction({
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async* {
    throw UnsupportedError(
      'Interactions API is not supported by this transport.',
    );
  }
}

class GeminiRestHttpTransport implements GeminiRestTransport {
  GeminiRestHttpTransport({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const String defaultBaseUrl =
      'https://generativelanguage.googleapis.com';
  final http.Client _httpClient;

  @override
  Future<Map<String, Object?>> generateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async {
    final Uri uri = _buildUri(
      model: model,
      baseUrl: baseUrl,
      apiVersion: apiVersion,
      stream: false,
    );
    return _postJsonWithRetry(
      uri: uri,
      apiKey: apiKey,
      payload: payload,
      headers: headers,
      retryOptions: retryOptions,
    );
  }

  @override
  Stream<Map<String, Object?>> streamGenerateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async* {
    final Uri uri = _buildUri(
      model: model,
      baseUrl: baseUrl,
      apiVersion: apiVersion,
      stream: true,
    );
    yield* _streamJsonWithRetry(
      uri: uri,
      apiKey: apiKey,
      payload: payload,
      headers: headers,
      retryOptions: retryOptions,
      includeEventName: false,
    );
  }

  @override
  Future<Map<String, Object?>> createInteraction({
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async {
    final Uri uri = _buildInteractionsUri(
      baseUrl: baseUrl,
      apiVersion: apiVersion,
    );
    return _postJsonWithRetry(
      uri: uri,
      apiKey: apiKey,
      payload: payload,
      headers: headers,
      retryOptions: retryOptions,
    );
  }

  @override
  Stream<Map<String, Object?>> streamCreateInteraction({
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async* {
    final Uri uri = _buildInteractionsUri(
      baseUrl: baseUrl,
      apiVersion: apiVersion,
    );
    yield* _streamJsonWithRetry(
      uri: uri,
      apiKey: apiKey,
      payload: payload,
      headers: headers,
      retryOptions: retryOptions,
      includeEventName: true,
    );
  }

  Uri _buildUri({
    required String model,
    required String? baseUrl,
    required String apiVersion,
    required bool stream,
  }) {
    final String normalizedBase = _normalizeBaseUrl(baseUrl ?? defaultBaseUrl);
    final String modelPath = _normalizeModelPath(model);
    final String methodName = stream
        ? 'streamGenerateContent'
        : 'generateContent';
    final Uri base = Uri.parse(normalizedBase);
    final Uri uri = base.resolve('$apiVersion/$modelPath:$methodName');
    if (!stream) {
      return uri;
    }
    final Map<String, String> query = <String, String>{
      ...uri.queryParameters,
      'alt': 'sse',
    };
    return uri.replace(queryParameters: query);
  }

  Uri _buildInteractionsUri({
    required String? baseUrl,
    required String apiVersion,
  }) {
    final String normalizedBase = _normalizeBaseUrl(baseUrl ?? defaultBaseUrl);
    final Uri base = Uri.parse(normalizedBase);
    return base.resolve('$apiVersion/interactions');
  }

  String _normalizeBaseUrl(String baseUrl) {
    if (baseUrl.endsWith('/')) {
      return baseUrl;
    }
    return '$baseUrl/';
  }

  String _normalizeModelPath(String model) {
    final String trimmed = model.trim();
    if (trimmed.startsWith('models/') || trimmed.startsWith('projects/')) {
      return trimmed;
    }
    if (trimmed.contains('/')) {
      return trimmed;
    }
    return 'models/$trimmed';
  }

  Map<String, String> _buildHeaders({
    required String apiKey,
    required Map<String, String>? headers,
    bool acceptEventStream = false,
  }) {
    final Map<String, String> merged = <String, String>{};
    bool hasAcceptHeader = false;
    if (headers != null) {
      headers.forEach((String key, String value) {
        final String lowered = key.toLowerCase();
        if (lowered == 'content-type' || lowered == 'x-goog-api-key') {
          return;
        }
        if (lowered == 'accept') {
          hasAcceptHeader = true;
        }
        merged[key] = value;
      });
    }
    merged['content-type'] = 'application/json';
    merged['x-goog-api-key'] = apiKey;
    if (acceptEventStream && !hasAcceptHeader) {
      merged['accept'] = 'text/event-stream';
    }
    return merged;
  }

  Future<Map<String, Object?>> _postJsonWithRetry({
    required Uri uri,
    required String apiKey,
    required Map<String, Object?> payload,
    required Map<String, String>? headers,
    required HttpRetryOptions? retryOptions,
  }) async {
    final _ResolvedRetryConfig resolved = _resolveRetryConfig(retryOptions);
    for (int attempt = 1; attempt <= resolved.attempts; attempt += 1) {
      try {
        final http.Response response = await _httpClient.post(
          uri,
          headers: _buildHeaders(apiKey: apiKey, headers: headers),
          body: jsonEncode(payload),
        );
        if (response.statusCode >= 400) {
          final GeminiRestApiException exception = GeminiRestApiException(
            response.statusCode,
            _extractErrorMessage(response.body),
            responseBody: response.body,
          );
          final bool shouldRetry =
              attempt < resolved.attempts &&
              resolved.retryStatusCodes.contains(response.statusCode);
          if (shouldRetry) {
            await Future<void>.delayed(
              _retryDelay(resolved: resolved, attempt: attempt),
            );
            continue;
          }
          throw exception;
        }
        return _decodeJsonObject(response.body);
      } on GeminiRestApiException {
        rethrow;
      } on Exception catch (error) {
        final bool shouldRetry =
            attempt < resolved.attempts && _isRetriableException(error);
        if (!shouldRetry) {
          rethrow;
        }
        await Future<void>.delayed(
          _retryDelay(resolved: resolved, attempt: attempt),
        );
      }
    }
    throw StateError('Retry loop exited unexpectedly.');
  }

  Stream<Map<String, Object?>> _streamJsonWithRetry({
    required Uri uri,
    required String apiKey,
    required Map<String, Object?> payload,
    required Map<String, String>? headers,
    required HttpRetryOptions? retryOptions,
    required bool includeEventName,
  }) async* {
    final _ResolvedRetryConfig resolved = _resolveRetryConfig(retryOptions);
    for (int attempt = 1; attempt <= resolved.attempts; attempt += 1) {
      bool emittedChunks = false;
      try {
        final http.Request request = http.Request('POST', uri)
          ..headers.addAll(
            _buildHeaders(
              apiKey: apiKey,
              headers: headers,
              acceptEventStream: true,
            ),
          )
          ..body = jsonEncode(payload);

        final http.StreamedResponse response = await _httpClient.send(request);
        if (response.statusCode >= 400) {
          final String body = await _readStreamedBody(response);
          final GeminiRestApiException exception = GeminiRestApiException(
            response.statusCode,
            _extractErrorMessage(body),
            responseBody: body,
          );
          final bool shouldRetry =
              attempt < resolved.attempts &&
              resolved.retryStatusCodes.contains(response.statusCode);
          if (shouldRetry) {
            await Future<void>.delayed(
              _retryDelay(resolved: resolved, attempt: attempt),
            );
            continue;
          }
          throw exception;
        }

        final StringBuffer dataBuffer = StringBuffer();
        final StringBuffer unexpectedLinePreview = StringBuffer();
        String? eventName;
        bool sawRecognizedSseField = false;
        bool sawUnexpectedContent = false;
        bool isFirstLine = true;
        final Stream<String> lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (final String rawLine in lines) {
          String line = rawLine;
          if (isFirstLine) {
            line = _stripUtf8Bom(line);
            isFirstLine = false;
          }
          if (line.isEmpty) {
            final Map<String, Object?>? parsed = _decodeSseData(
              dataBuffer.toString(),
              eventName: eventName,
              includeEventName: includeEventName,
            );
            dataBuffer.clear();
            eventName = null;
            if (parsed != null) {
              emittedChunks = true;
              yield parsed;
            }
            continue;
          }

          if (line.startsWith(':')) {
            continue;
          }

          final _SseField? field = _parseSseField(line);
          if (field == null) {
            sawUnexpectedContent = true;
            _appendSseUnexpectedLine(unexpectedLinePreview, line);
            continue;
          }

          switch (field.name) {
            case 'event':
              sawRecognizedSseField = true;
              eventName = field.value;
              break;
            case 'data':
              sawRecognizedSseField = true;
              dataBuffer.writeln(field.value);
              break;
            case 'id':
            case 'retry':
              sawRecognizedSseField = true;
              break;
            default:
              sawUnexpectedContent = true;
              _appendSseUnexpectedLine(unexpectedLinePreview, line);
              break;
          }
        }

        final Map<String, Object?>? parsed = _decodeSseData(
          dataBuffer.toString(),
          eventName: eventName,
          includeEventName: includeEventName,
        );
        if (parsed != null) {
          emittedChunks = true;
          yield parsed;
        }

        if (!emittedChunks && sawUnexpectedContent && !sawRecognizedSseField) {
          throw GeminiRestApiException(
            500,
            'Gemini SSE response is not a valid event stream.',
            responseBody: unexpectedLinePreview.toString().trimRight(),
          );
        }
        return;
      } on GeminiRestApiException {
        rethrow;
      } on Exception catch (error) {
        final bool shouldRetry =
            !emittedChunks &&
            attempt < resolved.attempts &&
            _isRetriableException(error);
        if (!shouldRetry) {
          rethrow;
        }
        await Future<void>.delayed(
          _retryDelay(resolved: resolved, attempt: attempt),
        );
      }
    }
    throw StateError('Retry loop exited unexpectedly.');
  }

  Future<String> _readStreamedBody(http.StreamedResponse response) async {
    final List<int> bytes = await response.stream.toBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  bool _isRetriableException(Object error) {
    return error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error is http.ClientException;
  }

  Duration _retryDelay({
    required _ResolvedRetryConfig resolved,
    required int attempt,
  }) {
    final double exponent = math.max(0, attempt - 1).toDouble();
    final double nextDelay =
        resolved.initialDelaySeconds * math.pow(resolved.expBase, exponent);
    final double clamped = math.min(nextDelay, resolved.maxDelaySeconds);
    return Duration(milliseconds: (clamped * 1000).round());
  }

  _ResolvedRetryConfig _resolveRetryConfig(HttpRetryOptions? options) {
    final int attempts = math.max(1, options?.attempts ?? 1);
    final double initialDelay = _normalizeDelay(options?.initialDelay, 1.0);
    final double maxDelay = _normalizeDelay(options?.maxDelay, 60.0);
    final double expBase = options?.expBase == null || options!.expBase! <= 0
        ? 2.0
        : options.expBase!;
    final Set<int> retryStatusCodes =
        options == null || options.httpStatusCodes.isEmpty
        ? _defaultRetryStatusCodes
        : options.httpStatusCodes.toSet();
    return _ResolvedRetryConfig(
      attempts: attempts,
      initialDelaySeconds: initialDelay,
      maxDelaySeconds: math.max(initialDelay, maxDelay),
      expBase: expBase,
      retryStatusCodes: retryStatusCodes,
    );
  }

  double _normalizeDelay(double? seconds, double fallback) {
    if (seconds == null || seconds.isNaN || seconds.isInfinite || seconds < 0) {
      return fallback;
    }
    return seconds;
  }
}

Map<String, Object?> _decodeJsonObject(String body) {
  final Object? decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw GeminiRestApiException(
      500,
      'Gemini API response is not a JSON object.',
      responseBody: body,
    );
  }
  return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
}

Map<String, Object?>? _decodeSseData(
  String rawData, {
  String? eventName,
  bool includeEventName = false,
}) {
  final String data = rawData.trim();
  if (data.isEmpty || data == '[DONE]') {
    return null;
  }
  final Object? decoded = jsonDecode(data);
  if (decoded is! Map) {
    throw GeminiRestApiException(
      500,
      'Gemini SSE event is not a JSON object.',
      responseBody: data,
    );
  }
  final Map<String, Object?> mapped = decoded.map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );
  if (includeEventName &&
      eventName != null &&
      eventName.isNotEmpty &&
      !mapped.containsKey('eventType') &&
      !mapped.containsKey('event_type')) {
    mapped['eventType'] = eventName;
  }
  return mapped;
}

_SseField? _parseSseField(String line) {
  final int separatorIndex = line.indexOf(':');
  if (separatorIndex < 0) {
    return _SseField(name: line, value: '');
  }
  final String name = line.substring(0, separatorIndex);
  if (name.isEmpty) {
    return null;
  }
  String value = line.substring(separatorIndex + 1);
  if (value.startsWith(' ')) {
    value = value.substring(1);
  }
  return _SseField(name: name, value: value);
}

String _stripUtf8Bom(String value) {
  if (value.startsWith('\ufeff')) {
    return value.substring(1);
  }
  return value;
}

void _appendSseUnexpectedLine(StringBuffer preview, String line) {
  const int maxPreviewLength = 2048;
  if (preview.length >= maxPreviewLength) {
    return;
  }
  final String trimmedLine = line.trimRight();
  if (trimmedLine.isEmpty) {
    return;
  }
  if (preview.isNotEmpty) {
    preview.writeln();
  }
  final int remaining = maxPreviewLength - preview.length;
  if (trimmedLine.length <= remaining) {
    preview.write(trimmedLine);
    return;
  }
  preview.write(trimmedLine.substring(0, remaining));
}

String _extractErrorMessage(String body) {
  if (body.isEmpty) {
    return 'Gemini API request failed.';
  }

  try {
    final Object? decoded = jsonDecode(body);
    if (decoded is Map) {
      final Map<String, Object?> map = decoded.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final Map<String, Object?> error = _asMap(map['error']);
      final String? message = _stringValue(error['message']);
      if (message != null && message.isNotEmpty) {
        return message;
      }
      final String? status = _stringValue(error['status']);
      if (status != null && status.isNotEmpty) {
        return status;
      }
    }
  } catch (_) {
    // Ignore parse failures and fall back to raw body.
  }

  return body;
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value';
  if (text.isEmpty) {
    return null;
  }
  return text;
}

const Set<int> _defaultRetryStatusCodes = <int>{408, 429, 500, 502, 503, 504};

class _ResolvedRetryConfig {
  const _ResolvedRetryConfig({
    required this.attempts,
    required this.initialDelaySeconds,
    required this.maxDelaySeconds,
    required this.expBase,
    required this.retryStatusCodes,
  });

  final int attempts;
  final double initialDelaySeconds;
  final double maxDelaySeconds;
  final double expBase;
  final Set<int> retryStatusCodes;
}

class _SseField {
  const _SseField({required this.name, required this.value});

  final String name;
  final String value;
}
