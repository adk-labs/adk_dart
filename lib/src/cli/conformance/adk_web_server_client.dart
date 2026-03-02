import 'dart:convert';
import 'dart:io';

class AdkWebServerClient {
  AdkWebServerClient(this.baseUri, {HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _httpClient;

  Future<void> close() async {
    _httpClient.close(force: true);
  }

  Future<Map<String, Object?>> createSession({
    required String userId,
    String? appName,
    Map<String, Object?>? state,
  }) async {
    if (appName == null || appName.trim().isEmpty) {
      return _requestJson('POST', '/api/sessions', <String, Object?>{
        'userId': userId,
      });
    }
    return _requestJson(
      'POST',
      '/apps/${Uri.encodeComponent(appName)}/users/${Uri.encodeComponent(userId)}/sessions',
      <String, Object?>{if (state != null) 'state': state},
    );
  }

  Future<Map<String, Object?>> getSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    return _requestJson(
      'GET',
      '/apps/${Uri.encodeComponent(appName)}/users/${Uri.encodeComponent(userId)}/sessions/${Uri.encodeComponent(sessionId)}',
      null,
    );
  }

  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    await _requestJson(
      'DELETE',
      '/apps/${Uri.encodeComponent(appName)}/users/${Uri.encodeComponent(userId)}/sessions/${Uri.encodeComponent(sessionId)}',
      null,
    );
  }

  Future<Map<String, Object?>> getVersionData() async {
    return _requestJson('GET', '/version', null);
  }

  Future<List<Map<String, Object?>>> runAgentSse({
    required String appName,
    required String userId,
    required String sessionId,
    Object? newMessage,
    Map<String, Object?>? stateDelta,
    bool streaming = false,
  }) async {
    final Uri uri = baseUri.resolve('/run_sse');
    final HttpClientRequest request = await _httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object?>{
        'app_name': appName,
        'user_id': userId,
        'session_id': sessionId,
        if (newMessage != null) 'new_message': newMessage,
        if (stateDelta != null) 'state_delta': stateDelta,
        'streaming': streaming,
      }),
    );
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode >= 400) {
      throw HttpException(
        'Request failed with ${response.statusCode}: $body',
        uri: uri,
      );
    }

    final List<Map<String, Object?>> events = <Map<String, Object?>>[];
    for (final String line in const LineSplitter().convert(body)) {
      final String trimmed = line.trim();
      if (!trimmed.startsWith('data:')) {
        continue;
      }
      final String payload = trimmed.substring('data:'.length).trim();
      if (payload.isEmpty) {
        continue;
      }
      final Object? decoded = jsonDecode(payload);
      if (decoded is! Map) {
        continue;
      }
      final Map<String, Object?> data = decoded.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      if (data.containsKey('error')) {
        throw StateError('${data['error']}');
      }
      events.add(data);
    }
    return events;
  }

  Future<Map<String, Object?>> sendMessage({
    required String sessionId,
    required String userId,
    required String text,
  }) async {
    return _requestJson(
      'POST',
      '/api/sessions/$sessionId/messages',
      <String, Object?>{'userId': userId, 'text': text},
    );
  }

  Future<Map<String, Object?>> getEvents({
    required String sessionId,
    required String userId,
  }) async {
    final Uri uri = baseUri.resolve(
      '/api/sessions/$sessionId/events?userId=${Uri.encodeQueryComponent(userId)}',
    );
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode >= 400) {
      throw HttpException(
        'Request failed with ${response.statusCode}: $body',
        uri: uri,
      );
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Response must be a JSON object.');
    }
    return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
  }

  Future<Map<String, Object?>> _requestJson(
    String method,
    String path,
    Map<String, Object?>? payload,
  ) async {
    final Uri uri = baseUri.resolve(path);
    final HttpClientRequest request = switch (method.toUpperCase()) {
      'POST' => await _httpClient.postUrl(uri),
      'GET' => await _httpClient.getUrl(uri),
      'DELETE' => await _httpClient.deleteUrl(uri),
      'PATCH' => await _httpClient.patchUrl(uri),
      _ => throw ArgumentError('Unsupported HTTP method: $method'),
    };
    if (payload != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
    }
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode >= 400) {
      throw HttpException(
        'Request failed with ${response.statusCode}: $body',
        uri: uri,
      );
    }
    if (body.trim().isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Response must be a JSON object.');
    }
    return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
  }
}
