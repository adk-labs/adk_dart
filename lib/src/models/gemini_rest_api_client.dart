import 'dart:convert';

import 'package:http/http.dart' as http;

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
    String apiVersion,
    Map<String, String>? headers,
  });

  Stream<Map<String, Object?>> streamGenerateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion,
    Map<String, String>? headers,
  });
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
  }) async {
    final Uri uri = _buildUri(
      model: model,
      baseUrl: baseUrl,
      apiVersion: apiVersion,
      stream: false,
    );
    final http.Response response = await _httpClient.post(
      uri,
      headers: _buildHeaders(apiKey: apiKey, headers: headers),
      body: jsonEncode(payload),
    );
    if (response.statusCode >= 400) {
      throw GeminiRestApiException(
        response.statusCode,
        _extractErrorMessage(response.body),
        responseBody: response.body,
      );
    }
    return _decodeJsonObject(response.body);
  }

  @override
  Stream<Map<String, Object?>> streamGenerateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
  }) async* {
    final Uri uri = _buildUri(
      model: model,
      baseUrl: baseUrl,
      apiVersion: apiVersion,
      stream: true,
    );
    final http.Request request = http.Request('POST', uri)
      ..headers.addAll(_buildHeaders(apiKey: apiKey, headers: headers))
      ..body = jsonEncode(payload);

    final http.StreamedResponse response = await _httpClient.send(request);
    if (response.statusCode >= 400) {
      final String body = await response.stream.bytesToString();
      throw GeminiRestApiException(
        response.statusCode,
        _extractErrorMessage(body),
        responseBody: body,
      );
    }

    final StringBuffer dataBuffer = StringBuffer();
    final Stream<String> lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final String line in lines) {
      if (line.isEmpty) {
        final Map<String, Object?>? parsed = _decodeSseData(
          dataBuffer.toString(),
        );
        dataBuffer.clear();
        if (parsed != null) {
          yield parsed;
        }
        continue;
      }

      if (line.startsWith('data:')) {
        dataBuffer.writeln(line.substring(5).trimLeft());
      }
    }

    final Map<String, Object?>? parsed = _decodeSseData(dataBuffer.toString());
    if (parsed != null) {
      yield parsed;
    }
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

Map<String, Object?>? _decodeSseData(String rawData) {
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
  return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
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
