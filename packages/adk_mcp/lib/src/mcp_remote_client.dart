import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class StreamableHTTPConnectionParams {
  StreamableHTTPConnectionParams({
    required this.url,
    Map<String, String>? headers,
  }) : headers = headers ?? <String, String>{};

  final String url;
  final Map<String, String> headers;
}

class McpResourceContent {
  McpResourceContent({this.text, this.blob, this.mimeType});

  final String? text;
  final String? blob;
  final String? mimeType;
}

class McpServerMessage {
  McpServerMessage({
    required this.url,
    required this.method,
    required this.params,
    this.id,
  });

  final String url;
  final String method;
  final Map<String, Object?> params;
  final Object? id;

  bool get isNotification => id == null;
}

typedef McpServerMessageHandler = void Function(McpServerMessage message);
typedef HttpClientFactory = http.Client Function();

class McpRemoteClient {
  McpRemoteClient({
    required this.clientInfoName,
    required this.clientInfoVersion,
    this.onServerMessage,
    this.latestProtocolVersion = '2025-11-25',
    Set<String>? supportedProtocolVersions,
    this.requestTimeout = const Duration(seconds: 30),
    HttpClientFactory? httpClientFactory,
  }) : supportedProtocolVersions =
           supportedProtocolVersions ??
           const <String>{'2025-03-26', '2025-06-18', '2025-11-25'},
       _httpClientFactory = httpClientFactory ?? http.Client.new;

  final String clientInfoName;
  final String clientInfoVersion;
  final McpServerMessageHandler? onServerMessage;
  final String latestProtocolVersion;
  final Set<String> supportedProtocolVersions;
  final Duration requestTimeout;
  final HttpClientFactory _httpClientFactory;

  final Set<String> _initializedUrls = <String>{};
  final Map<String, Future<void>> _initializationTasksByUrl =
      <String, Future<void>>{};
  final Map<String, String> _negotiatedProtocolVersionByUrl =
      <String, String>{};
  final Map<String, String> _sessionIdByUrl = <String, String>{};
  final Map<String, Map<String, Object?>> _capabilitiesByUrl =
      <String, Map<String, Object?>>{};
  int _requestSequence = 1;

  bool isRemoteCapable(StreamableHTTPConnectionParams connectionParams) {
    final Uri? uri = Uri.tryParse(connectionParams.url);
    if (uri == null) {
      return false;
    }
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  String? negotiatedProtocolVersion(
    StreamableHTTPConnectionParams connectionParams,
  ) {
    return _negotiatedProtocolVersionByUrl[connectionParams.url];
  }

  String? sessionId(StreamableHTTPConnectionParams connectionParams) {
    return _sessionIdByUrl[connectionParams.url];
  }

  Map<String, Object?> negotiatedCapabilities(
    StreamableHTTPConnectionParams connectionParams,
  ) {
    return Map<String, Object?>.from(
      _capabilitiesByUrl[connectionParams.url] ?? const <String, Object?>{},
    );
  }

  bool hasNegotiatedCapability(
    StreamableHTTPConnectionParams connectionParams,
    String capabilityName,
  ) {
    final Map<String, Object?>? capabilities =
        _capabilitiesByUrl[connectionParams.url];
    if (capabilities == null) {
      return false;
    }
    final Object? raw = capabilities[capabilityName];
    if (raw is bool) {
      return raw;
    }
    return raw is Map;
  }

  Future<void> ensureInitialized(
    StreamableHTTPConnectionParams connectionParams, {
    Map<String, String>? headers,
  }) async {
    if (!isRemoteCapable(connectionParams)) {
      return;
    }

    final String url = connectionParams.url;
    if (_initializedUrls.contains(url)) {
      return;
    }

    final Future<void>? pending = _initializationTasksByUrl[url];
    if (pending != null) {
      await pending;
      return;
    }

    final Future<void> task = () async {
      final _McpJsonRpcCallResponse initialized = await _jsonRpcCallInternal(
        connectionParams: connectionParams,
        method: 'initialize',
        params: <String, Object?>{
          'protocolVersion': latestProtocolVersion,
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{
            'name': clientInfoName,
            'version': clientInfoVersion,
          },
        },
        headers: headers,
        includeSessionHeaders: false,
        includeProtocolHeader: false,
      );

      final Map<String, Object?> result = _asStringObjectMap(
        initialized.result,
      );
      final String protocolVersion = _asString(
        result['protocolVersion'],
      ).trim();
      if (protocolVersion.isEmpty) {
        throw StateError(
          'MCP initialize response is missing `protocolVersion`.',
        );
      }
      if (!supportedProtocolVersions.contains(protocolVersion)) {
        throw StateError(
          'Unsupported MCP protocol version from server: $protocolVersion. '
          'Supported versions: ${supportedProtocolVersions.join(', ')}',
        );
      }
      _negotiatedProtocolVersionByUrl[url] = protocolVersion;

      _capabilitiesByUrl[url] = _asStringObjectMap(result['capabilities']);

      final String sessionId =
          initialized.sessionId ??
          _headerValue(initialized.headers, 'MCP-Session-Id') ??
          _asString(result['sessionId']).trim();
      if (sessionId.isNotEmpty) {
        _sessionIdByUrl[url] = sessionId;
      } else {
        _sessionIdByUrl.remove(url);
      }

      await _jsonRpcNotifyWithRecovery(
        connectionParams: connectionParams,
        method: 'notifications/initialized',
        params: const <String, Object?>{},
        headers: headers,
        allowSessionRecovery: true,
      );

      _initializedUrls.add(url);
    }();

    _initializationTasksByUrl[url] = task;
    try {
      await task;
    } finally {
      _initializationTasksByUrl.remove(url);
    }
  }

  Future<Object?> call({
    required StreamableHTTPConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
    Map<String, String>? headers,
  }) async {
    if (method != 'initialize') {
      await ensureInitialized(connectionParams, headers: headers);
    }
    final _McpJsonRpcCallResponse response = await _jsonRpcCallWithRecovery(
      connectionParams: connectionParams,
      method: method,
      params: params,
      headers: headers,
      allowSessionRecovery: true,
    );
    return response.result;
  }

  Future<Object?> tryCall({
    required StreamableHTTPConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
    Map<String, String>? headers,
    Set<int> suppressJsonRpcErrorCodes = const <int>{},
    bool suppressErrors = false,
  }) async {
    try {
      return await call(
        connectionParams: connectionParams,
        method: method,
        params: params,
        headers: headers,
      );
    } on McpJsonRpcException catch (error) {
      if (suppressErrors) {
        return null;
      }
      if (error.code != null &&
          suppressJsonRpcErrorCodes.contains(error.code)) {
        return null;
      }
      rethrow;
    } catch (_) {
      if (suppressErrors) {
        return null;
      }
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> collectPaginatedMaps({
    required StreamableHTTPConnectionParams connectionParams,
    required String method,
    required String resultArrayField,
    Map<String, String>? headers,
    Set<int> suppressJsonRpcErrorCodes = const <int>{},
    bool suppressErrors = false,
  }) async {
    final List<Map<String, Object?>> collected = <Map<String, Object?>>[];
    String? cursor;
    final Set<String> seenCursors = <String>{};

    while (true) {
      final Map<String, Object?> params = <String, Object?>{
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      };
      final Object? result = await tryCall(
        connectionParams: connectionParams,
        method: method,
        params: params,
        headers: headers,
        suppressJsonRpcErrorCodes: suppressJsonRpcErrorCodes,
        suppressErrors: suppressErrors,
      );
      if (result == null) {
        break;
      }

      final Map<String, Object?> map = _asStringObjectMap(result);
      for (final Object? raw in _asObjectList(map[resultArrayField])) {
        collected.add(_asStringObjectMap(raw));
      }

      final String nextCursor = _asString(map['nextCursor']).trim();
      if (nextCursor.isEmpty || seenCursors.contains(nextCursor)) {
        break;
      }
      seenCursors.add(nextCursor);
      cursor = nextCursor;
    }

    return collected;
  }

  Future<void> notify({
    required StreamableHTTPConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
    Map<String, String>? headers,
  }) async {
    await ensureInitialized(connectionParams, headers: headers);
    await _jsonRpcNotifyWithRecovery(
      connectionParams: connectionParams,
      method: method,
      params: params,
      headers: headers,
      allowSessionRecovery: true,
    );
  }

  void clear() {
    _initializedUrls.clear();
    _initializationTasksByUrl.clear();
    _negotiatedProtocolVersionByUrl.clear();
    _sessionIdByUrl.clear();
    _capabilitiesByUrl.clear();
    _requestSequence = 1;
  }

  void clearConnection(StreamableHTTPConnectionParams connectionParams) {
    _resetRemoteSession(connectionParams.url);
  }

  Future<void> _jsonRpcNotifyWithRecovery({
    required StreamableHTTPConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
    Map<String, String>? headers,
    required bool allowSessionRecovery,
  }) async {
    final Map<String, Object?> requestBody = <String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    };

    try {
      await _postJsonRpc(
        connectionParams: connectionParams,
        requestBody: requestBody,
        headers: headers,
        includeSessionHeaders: true,
        includeProtocolHeader: method != 'initialize',
      );
    } on McpHttpStatusException catch (error) {
      final String url = connectionParams.url;
      final bool hasServerSession = _sessionIdByUrl.containsKey(url);
      if (!allowSessionRecovery ||
          error.statusCode != HttpStatus.notFound ||
          !hasServerSession ||
          method == 'initialize') {
        rethrow;
      }
      _resetRemoteSession(url);
      await ensureInitialized(connectionParams, headers: headers);
      await _jsonRpcNotifyWithRecovery(
        connectionParams: connectionParams,
        method: method,
        params: params,
        headers: headers,
        allowSessionRecovery: false,
      );
    }
  }

  Future<_McpJsonRpcCallResponse> _jsonRpcCallWithRecovery({
    required StreamableHTTPConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
    Map<String, String>? headers,
    required bool allowSessionRecovery,
  }) async {
    try {
      return await _jsonRpcCallInternal(
        connectionParams: connectionParams,
        method: method,
        params: params,
        headers: headers,
        includeSessionHeaders: method != 'initialize',
        includeProtocolHeader: method != 'initialize',
      );
    } on McpHttpStatusException catch (error) {
      final String url = connectionParams.url;
      final bool hasServerSession = _sessionIdByUrl.containsKey(url);
      if (!allowSessionRecovery ||
          error.statusCode != HttpStatus.notFound ||
          !hasServerSession ||
          method == 'initialize') {
        rethrow;
      }
      _resetRemoteSession(url);
      await ensureInitialized(connectionParams, headers: headers);
      return _jsonRpcCallWithRecovery(
        connectionParams: connectionParams,
        method: method,
        params: params,
        headers: headers,
        allowSessionRecovery: false,
      );
    }
  }

  Future<_McpJsonRpcCallResponse> _jsonRpcCallInternal({
    required StreamableHTTPConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
    Map<String, String>? headers,
    required bool includeSessionHeaders,
    required bool includeProtocolHeader,
  }) async {
    final int requestId = _requestSequence++;
    final Map<String, Object?> requestBody = <String, Object?>{
      'jsonrpc': '2.0',
      'id': requestId,
      'method': method,
      'params': params,
    };

    final _McpHttpResponse httpResponse = await _postJsonRpc(
      connectionParams: connectionParams,
      requestBody: requestBody,
      headers: headers,
      includeSessionHeaders: includeSessionHeaders,
      includeProtocolHeader: includeProtocolHeader,
      requestId: requestId,
      requestMethod: method,
    );
    final Map<String, Object?> response = _decodeRpcCallResponse(
      httpResponse: httpResponse,
      requestId: requestId,
      requestMethod: method,
      connectionUrl: connectionParams.url,
    );

    final Object? error = response['error'];
    if (error != null) {
      final Map<String, Object?> map = _asStringObjectMap(error);
      final String message = _asString(map['message']);
      final int? code = _asInt(map['code']);
      throw McpJsonRpcException(
        method: method,
        code: code,
        message: message.isEmpty ? '$error' : message,
      );
    }

    if (!response.containsKey('result')) {
      throw FormatException(
        'MCP response for `$method` is missing both `result` and `error`.',
      );
    }

    return _McpJsonRpcCallResponse(
      result: response['result'],
      headers: httpResponse.headers,
      sessionId: _headerValue(httpResponse.headers, 'MCP-Session-Id'),
    );
  }

  Future<_McpHttpResponse> _postJsonRpc({
    required StreamableHTTPConnectionParams connectionParams,
    required Map<String, Object?> requestBody,
    Map<String, String>? headers,
    required bool includeSessionHeaders,
    required bool includeProtocolHeader,
    int? requestId,
    String? requestMethod,
  }) async {
    final Uri uri = Uri.parse(connectionParams.url);
    final String url = connectionParams.url;
    final String protocolVersion =
        _negotiatedProtocolVersionByUrl[url] ?? latestProtocolVersion;

    final Map<String, String> mergedHeaders = <String, String>{
      ...connectionParams.headers,
      if (headers != null) ...headers,
      if (includeProtocolHeader) 'MCP-Protocol-Version': protocolVersion,
      if (includeSessionHeaders && _sessionIdByUrl[url] != null)
        'MCP-Session-Id': _sessionIdByUrl[url]!,
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.acceptHeader: 'application/json, text/event-stream',
    };

    final http.Client client = _httpClientFactory();
    try {
      final http.Response response;
      try {
        response = await client
            .post(uri, headers: mergedHeaders, body: jsonEncode(requestBody))
            .timeout(requestTimeout);
      } on TimeoutException catch (_) {
        if (requestId != null && requestMethod != null) {
          await _sendCancellation(
            connectionParams: connectionParams,
            requestId: requestId,
            reason: 'request_timeout',
            headers: headers,
            includeSessionHeaders: includeSessionHeaders,
            includeProtocolHeader: includeProtocolHeader,
          );
        }
        rethrow;
      }

      if (response.statusCode >= 400) {
        throw McpHttpStatusException(
          uri: uri,
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      final Map<String, String> responseHeaders = response.headers.map(
        (String key, String value) => MapEntry(key.toLowerCase(), value),
      );
      return _McpHttpResponse(
        statusCode: response.statusCode,
        body: response.body,
        headers: responseHeaders,
      );
    } finally {
      client.close();
    }
  }

  Future<void> _sendCancellation({
    required StreamableHTTPConnectionParams connectionParams,
    required int requestId,
    required String reason,
    Map<String, String>? headers,
    required bool includeSessionHeaders,
    required bool includeProtocolHeader,
  }) async {
    try {
      await _postJsonRpc(
        connectionParams: connectionParams,
        requestBody: <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/cancelled',
          'params': <String, Object?>{'requestId': requestId, 'reason': reason},
        },
        headers: headers,
        includeSessionHeaders: includeSessionHeaders,
        includeProtocolHeader: includeProtocolHeader,
      );
    } catch (_) {
      // Best effort cancellation notification.
    }
  }

  Map<String, Object?> _decodeRpcCallResponse({
    required _McpHttpResponse httpResponse,
    required int requestId,
    required String requestMethod,
    required String connectionUrl,
  }) {
    final String body = httpResponse.body.trim();
    if (body.isEmpty) {
      throw FormatException(
        'MCP response for `$requestMethod` is empty; expected JSON-RPC response.',
      );
    }

    final String contentType =
        httpResponse.headers[HttpHeaders.contentTypeHeader]?.toLowerCase() ??
        '';
    if (contentType.contains('text/event-stream')) {
      final List<Map<String, Object?>> messages = _decodeSseMessages(body);
      if (messages.isEmpty) {
        throw FormatException(
          'MCP SSE response for `$requestMethod` did not contain JSON-RPC data.',
        );
      }

      Map<String, Object?>? response;
      for (final Map<String, Object?> message in messages) {
        if (_isResponseObject(message)) {
          if (_idMatches(message['id'], requestId) && response == null) {
            response = message;
          }
          continue;
        }
        _emitServerMessage(connectionUrl, message);
      }

      if (response == null) {
        throw FormatException(
          'MCP SSE response for `$requestMethod` did not include a JSON-RPC '
          'response with id=$requestId.',
        );
      }
      return response;
    }

    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw FormatException('MCP response is not a JSON object.');
    }
    final Map<String, Object?> map = decoded.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );
    if (!_isResponseObject(map)) {
      _emitServerMessage(connectionUrl, map);
      throw FormatException(
        'MCP response for `$requestMethod` is not a JSON-RPC response object.',
      );
    }
    if (!_idMatches(map['id'], requestId)) {
      throw FormatException(
        'MCP response id mismatch for `$requestMethod`: '
        'expected $requestId, got ${map['id']}.',
      );
    }
    return map;
  }

  List<Map<String, Object?>> _decodeSseMessages(String payload) {
    final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
    final List<String> lines = payload.split(RegExp(r'\r?\n'));
    final List<String> dataLines = <String>[];

    void flushEvent() {
      if (dataLines.isEmpty) {
        return;
      }
      final String combined = dataLines.join('\n').trim();
      dataLines.clear();
      if (combined.isEmpty) {
        return;
      }
      try {
        final Object? decoded = jsonDecode(combined);
        if (decoded is Map) {
          messages.add(
            decoded.map(
              (Object? key, Object? value) =>
                  MapEntry<String, Object?>('$key', value),
            ),
          );
        }
      } catch (_) {
        // Ignore non-JSON SSE events.
      }
    }

    for (final String line in lines) {
      if (line.isEmpty) {
        flushEvent();
        continue;
      }
      if (line.startsWith(':')) {
        continue;
      }
      if (line.startsWith('data:')) {
        String data = line.substring(5);
        if (data.startsWith(' ')) {
          data = data.substring(1);
        }
        dataLines.add(data);
      }
    }
    flushEvent();
    return messages;
  }

  bool _isResponseObject(Map<String, Object?> message) {
    return message.containsKey('id') &&
        (message.containsKey('result') || message.containsKey('error'));
  }

  bool _idMatches(Object? id, int expectedRequestId) {
    if (id is int) {
      return id == expectedRequestId;
    }
    if (id is num) {
      return id.toInt() == expectedRequestId;
    }
    if (id is String) {
      return id.trim() == '$expectedRequestId';
    }
    return false;
  }

  void _emitServerMessage(String url, Map<String, Object?> payload) {
    final String method = _asString(payload['method']).trim();
    if (method.isEmpty) {
      return;
    }
    onServerMessage?.call(
      McpServerMessage(
        url: url,
        method: method,
        params: _asStringObjectMap(payload['params']),
        id: payload['id'],
      ),
    );
  }

  void _resetRemoteSession(String url) {
    _initializedUrls.remove(url);
    _initializationTasksByUrl.remove(url);
    _sessionIdByUrl.remove(url);
    _negotiatedProtocolVersionByUrl.remove(url);
    _capabilitiesByUrl.remove(url);
  }
}

Map<String, Object?> _asStringObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry<String, Object?>('$key', item),
    );
  }
  return <String, Object?>{};
}

List<Object?> _asObjectList(Object? value) {
  if (value is List<Object?>) {
    return List<Object?>.from(value);
  }
  if (value is List) {
    return value.toList(growable: false);
  }
  return const <Object?>[];
}

String _asString(Object? value) {
  if (value == null) {
    return '';
  }
  return '$value';
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

String? _headerValue(Map<String, String> headers, String name) {
  final String lowerName = name.toLowerCase();
  return headers[lowerName]?.trim();
}

class McpJsonRpcException extends StateError {
  McpJsonRpcException({
    required this.method,
    required this.code,
    required String message,
  }) : super(
         'MCP RPC `$method` failed${code == null ? '' : ' ($code)'}: $message',
       );

  final String method;
  final int? code;
}

class McpHttpStatusException extends HttpException {
  McpHttpStatusException({
    required Uri uri,
    required this.statusCode,
    required this.body,
  }) : super('MCP HTTP request failed ($statusCode): $body', uri: uri);

  final int statusCode;
  final String body;
}

class _McpJsonRpcCallResponse {
  _McpJsonRpcCallResponse({
    required this.result,
    required this.headers,
    this.sessionId,
  });

  final Object? result;
  final Map<String, String> headers;
  final String? sessionId;
}

class _McpHttpResponse {
  _McpHttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

const int mcpMethodNotFoundCode = -32601;
