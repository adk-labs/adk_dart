import 'dart:convert';
import 'dart:io';

class AdkWebServerClient {
  AdkWebServerClient(this.baseUri, {HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _httpClient;

  Future<Map<String, Object?>> createSession({required String userId}) async {
    return _requestJson('POST', '/api/sessions', <String, Object?>{
      'userId': userId,
    });
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
    Map<String, Object?> payload,
  ) async {
    final Uri uri = baseUri.resolve(path);
    final HttpClientRequest request = method == 'POST'
        ? await _httpClient.postUrl(uri)
        : await _httpClient.getUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
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
}
