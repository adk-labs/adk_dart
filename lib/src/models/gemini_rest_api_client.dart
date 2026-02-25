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
  }) {
    final Map<String, String> merged = <String, String>{
      'content-type': 'application/json',
      'x-goog-api-key': apiKey,
    };
    if (headers != null) {
      merged.addAll(headers);
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
          ..headers.addAll(_buildHeaders(apiKey: apiKey, headers: headers))
          ..body = jsonEncode(payload);

        final http.StreamedResponse response = await _httpClient.send(request);
        if (response.statusCode >= 400) {
          final String body = await response.stream.bytesToString();
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
        String? eventName;
        final Stream<String> lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (final String line in lines) {
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

          if (line.startsWith('event:')) {
            eventName = line.substring(6).trimLeft();
            continue;
          }

          if (line.startsWith('data:')) {
            dataBuffer.writeln(line.substring(5).trimLeft());
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
