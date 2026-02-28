import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../version.dart';
import '../base_tool.dart';

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

typedef McpToolExecutor =
    FutureOr<Object?> Function(
      Map<String, dynamic> args, {
      Map<String, String>? headers,
    });

class McpSessionManager {
  McpSessionManager._();

  static final McpSessionManager instance = McpSessionManager._();

  final Map<String, List<BaseTool>> _toolsByUrl = <String, List<BaseTool>>{};
  final Map<String, Map<String, List<McpResourceContent>>> _resourcesByUrl =
      <String, Map<String, List<McpResourceContent>>>{};
  final Map<String, Map<String, McpToolExecutor>> _executorsByUrl =
      <String, Map<String, McpToolExecutor>>{};

  final Map<String, List<Map<String, Object?>>> _remoteToolDescriptorsByUrl =
      <String, List<Map<String, Object?>>>{};
  final Set<String> _initializedUrls = <String>{};
  final Map<String, Future<void>> _initializationTasksByUrl =
      <String, Future<void>>{};

  int _requestSequence = 1;

  static const Duration _remoteRequestTimeout = Duration(seconds: 30);
  static const int _methodNotFoundCode = -32601;
  static const int _invalidParamsCode = -32602;

  void registerTools({
    required StreamableHTTPConnectionParams connectionParams,
    required List<BaseTool> tools,
  }) {
    _toolsByUrl[connectionParams.url] = tools
        .map((BaseTool tool) => tool)
        .toList(growable: false);
    _remoteToolDescriptorsByUrl.remove(connectionParams.url);
  }

  void registerResources({
    required StreamableHTTPConnectionParams connectionParams,
    required Map<String, List<McpResourceContent>> resources,
  }) {
    _resourcesByUrl[connectionParams.url] = resources.map(
      (String key, List<McpResourceContent> value) => MapEntry(
        key,
        value
            .map((McpResourceContent item) {
              return McpResourceContent(
                text: item.text,
                blob: item.blob,
                mimeType: item.mimeType,
              );
            })
            .toList(growable: false),
      ),
    );
  }

  void registerToolExecutor({
    required StreamableHTTPConnectionParams connectionParams,
    required String toolName,
    required McpToolExecutor executor,
  }) {
    _executorsByUrl.putIfAbsent(
      connectionParams.url,
      () => <String, McpToolExecutor>{},
    )[toolName] = executor;
  }

  List<BaseTool> getTools(StreamableHTTPConnectionParams connectionParams) {
    final List<BaseTool>? tools = _toolsByUrl[connectionParams.url];
    if (tools == null) {
      return const <BaseTool>[];
    }
    return tools.toList(growable: false);
  }

  Future<List<Map<String, Object?>>> listRemoteToolDescriptors({
    required StreamableHTTPConnectionParams connectionParams,
    bool forceRefresh = false,
  }) async {
    if (!_isRemoteCapable(connectionParams)) {
      return const <Map<String, Object?>>[];
    }

    final String url = connectionParams.url;
    if (!forceRefresh) {
      final List<Map<String, Object?>>? cached =
          _remoteToolDescriptorsByUrl[url];
      if (cached != null) {
        return cached
            .map((Map<String, Object?> item) => Map<String, Object?>.from(item))
            .toList(growable: false);
      }
    }

    await _ensureRemoteInitialized(connectionParams);

    final Object? result = await _jsonRpcCall(
      connectionParams: connectionParams,
      method: 'tools/list',
      params: const <String, Object?>{},
    );
    final Map<String, Object?> resultMap = _asStringObjectMap(result);

    final List<Map<String, Object?>> descriptors =
        _asObjectList(resultMap['tools'])
            .map((Object? item) {
              return _asStringObjectMap(item);
            })
            .where((Map<String, Object?> descriptor) {
              return _asString(descriptor['name']).isNotEmpty;
            })
            .toList(growable: false);

    _remoteToolDescriptorsByUrl[url] = descriptors
        .map((Map<String, Object?> item) => Map<String, Object?>.from(item))
        .toList(growable: false);

    return descriptors;
  }

  List<String> listServerUrls() {
    return _toolsByUrl.keys.toList(growable: false);
  }

  List<String> listResources(StreamableHTTPConnectionParams connectionParams) {
    final Map<String, List<McpResourceContent>>? resources =
        _resourcesByUrl[connectionParams.url];
    if (resources == null) {
      return const <String>[];
    }
    return resources.keys.toList(growable: false);
  }

  Future<List<String>> listResourcesAsync(
    StreamableHTTPConnectionParams connectionParams,
  ) async {
    final List<String> local = listResources(connectionParams);
    if (local.isNotEmpty) {
      return local;
    }
    if (!_isRemoteCapable(connectionParams)) {
      return const <String>[];
    }

    await _ensureRemoteInitialized(connectionParams);

    final Set<String> names = <String>{};

    final Object? resourcesResult = await _tryJsonRpcCall(
      connectionParams: connectionParams,
      method: 'resources/list',
      params: const <String, Object?>{},
      suppressErrors: true,
    );
    if (resourcesResult != null) {
      final Map<String, Object?> map = _asStringObjectMap(resourcesResult);
      for (final Object? raw in _asObjectList(map['resources'])) {
        final Map<String, Object?> resource = _asStringObjectMap(raw);
        final String name = _asString(resource['uri']).isNotEmpty
            ? _asString(resource['uri'])
            : _asString(resource['name']);
        if (name.isNotEmpty) {
          names.add(name);
        }
      }
    }

    final Object? promptsResult = await _tryJsonRpcCall(
      connectionParams: connectionParams,
      method: 'prompts/list',
      params: const <String, Object?>{},
      suppressJsonRpcErrorCodes: const <int>{_methodNotFoundCode},
    );
    if (promptsResult != null) {
      final Map<String, Object?> map = _asStringObjectMap(promptsResult);
      for (final Object? raw in _asObjectList(map['prompts'])) {
        final Map<String, Object?> prompt = _asStringObjectMap(raw);
        final String name = _asString(prompt['name']);
        if (name.isNotEmpty) {
          names.add(name);
        }
      }
    }

    final List<String> ordered = names.toList(growable: false)..sort();
    return ordered;
  }

  List<McpResourceContent> readResource({
    required StreamableHTTPConnectionParams connectionParams,
    required String resourceName,
  }) {
    final List<McpResourceContent>? resources =
        _resourcesByUrl[connectionParams.url]?[resourceName];
    if (resources == null) {
      return const <McpResourceContent>[];
    }
    return resources
        .map((McpResourceContent item) {
          return McpResourceContent(
            text: item.text,
            blob: item.blob,
            mimeType: item.mimeType,
          );
        })
        .toList(growable: false);
  }

  Future<List<McpResourceContent>> readResourceAsync({
    required StreamableHTTPConnectionParams connectionParams,
    required String resourceName,
  }) async {
    final List<McpResourceContent> local = readResource(
      connectionParams: connectionParams,
      resourceName: resourceName,
    );
    if (local.isNotEmpty) {
      return local;
    }
    if (!_isRemoteCapable(connectionParams)) {
      return const <McpResourceContent>[];
    }

    await _ensureRemoteInitialized(connectionParams);

    final Object? readResult = await _tryJsonRpcCall(
      connectionParams: connectionParams,
      method: 'resources/read',
      params: <String, Object?>{'uri': resourceName, 'name': resourceName},
      suppressJsonRpcErrorCodes: const <int>{
        _methodNotFoundCode,
        _invalidParamsCode,
      },
    );
    final List<McpResourceContent> resourceContents = _parseResourceContents(
      readResult,
    );
    if (resourceContents.isNotEmpty) {
      return resourceContents;
    }

    final Object? promptResult = await _tryJsonRpcCall(
      connectionParams: connectionParams,
      method: 'prompts/get',
      params: <String, Object?>{
        'name': resourceName,
        'arguments': <String, Object?>{},
      },
      suppressJsonRpcErrorCodes: const <int>{_methodNotFoundCode},
    );
    return _parsePromptContents(promptResult);
  }

  Future<Object?> callTool({
    required StreamableHTTPConnectionParams connectionParams,
    required String toolName,
    required Map<String, dynamic> args,
    Map<String, String>? headers,
  }) async {
    final McpToolExecutor? executor =
        _executorsByUrl[connectionParams.url]?[toolName];
    if (executor != null) {
      final Object? result = executor(args, headers: headers);
      if (result is Future<Object?>) {
        return result;
      }
      if (result is Future) {
        return await result;
      }
      return result;
    }

    if (!_isRemoteCapable(connectionParams)) {
      throw ArgumentError('MCP tool `$toolName` is not registered.');
    }

    await _ensureRemoteInitialized(connectionParams, headers: headers);

    final Object? result = await _jsonRpcCall(
      connectionParams: connectionParams,
      method: 'tools/call',
      params: <String, Object?>{'name': toolName, 'arguments': args},
      headers: headers,
    );

    if (result is Map) {
      return _asStringObjectMap(result);
    }
    return result;
  }

  void clear() {
    _toolsByUrl.clear();
    _resourcesByUrl.clear();
    _executorsByUrl.clear();
    _remoteToolDescriptorsByUrl.clear();
    _initializedUrls.clear();
    _initializationTasksByUrl.clear();
    _requestSequence = 1;
  }

  bool _isRemoteCapable(StreamableHTTPConnectionParams connectionParams) {
    final Uri? uri = Uri.tryParse(connectionParams.url);
    if (uri == null) {
      return false;
    }
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  Future<void> _ensureRemoteInitialized(
    StreamableHTTPConnectionParams connectionParams, {
    Map<String, String>? headers,
  }) async {
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
      bool shouldCacheInitialized = false;
      try {
        await _jsonRpcCall(
          connectionParams: connectionParams,
          method: 'initialize',
          params: <String, Object?>{
            'protocolVersion': '2025-03-26',
            'capabilities': <String, Object?>{},
            'clientInfo': <String, Object?>{
              'name': 'adk_dart',
              'version': adkVersion,
            },
          },
          headers: headers,
        );
        shouldCacheInitialized = true;
      } on _McpJsonRpcException catch (error) {
        if (error.code == _methodNotFoundCode) {
          // Some MCP HTTP deployments proxy method subsets and may not require
          // or expose initialize. Cache this and continue with best-effort calls.
          shouldCacheInitialized = true;
        }
      } catch (_) {
        // Some MCP HTTP deployments proxy method subsets and may not require
        // or expose initialize. Keep calls best-effort, but retry initialize
        // on subsequent requests since this failure may be transient.
      } finally {
        if (shouldCacheInitialized) {
          _initializedUrls.add(url);
        }
      }
    }();

    _initializationTasksByUrl[url] = task;
    try {
      await task;
    } finally {
      _initializationTasksByUrl.remove(url);
    }
  }

  Future<Object?> _tryJsonRpcCall({
    required StreamableHTTPConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
    Map<String, String>? headers,
    Set<int> suppressJsonRpcErrorCodes = const <int>{},
    bool suppressErrors = false,
  }) async {
    try {
      return await _jsonRpcCall(
        connectionParams: connectionParams,
        method: method,
        params: params,
        headers: headers,
      );
    } on _McpJsonRpcException catch (error) {
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

  Future<Object?> _jsonRpcCall({
    required StreamableHTTPConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
    Map<String, String>? headers,
  }) async {
    final int requestId = _requestSequence++;
    final Map<String, Object?> requestBody = <String, Object?>{
      'jsonrpc': '2.0',
      'id': requestId,
      'method': method,
      'params': params,
    };

    final Map<String, Object?> response = await _postJsonRpc(
      connectionParams: connectionParams,
      requestBody: requestBody,
      headers: headers,
    );

    final Object? error = response['error'];
    if (error != null) {
      final Map<String, Object?> map = _asStringObjectMap(error);
      final String message = _asString(map['message']);
      final int? code = _asInt(map['code']);
      throw _McpJsonRpcException(
        method: method,
        code: code,
        message: message.isEmpty ? '$error' : message,
      );
    }

    return response['result'];
  }

  Future<Map<String, Object?>> _postJsonRpc({
    required StreamableHTTPConnectionParams connectionParams,
    required Map<String, Object?> requestBody,
    Map<String, String>? headers,
  }) async {
    final Uri uri = Uri.parse(connectionParams.url);
    final Map<String, String> mergedHeaders = <String, String>{
      ...connectionParams.headers,
      if (headers != null) ...headers,
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.acceptHeader: 'application/json',
    };

    final http.Client client = http.Client();
    try {
      final http.Response response = await client
          .post(uri, headers: mergedHeaders, body: jsonEncode(requestBody))
          .timeout(_remoteRequestTimeout);
      if (response.statusCode >= 400) {
        throw HttpException(
          'MCP HTTP request failed (${response.statusCode}): ${response.body}',
          uri: uri,
        );
      }

      final String body = response.body.trim();
      if (body.isEmpty) {
        return const <String, Object?>{};
      }

      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw FormatException('MCP response is not a JSON object.');
      }

      return decoded.map(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
    } finally {
      client.close();
    }
  }

  List<McpResourceContent> _parseResourceContents(Object? result) {
    final Map<String, Object?> map = _asStringObjectMap(result);
    final List<McpResourceContent> parsed = <McpResourceContent>[];
    for (final Object? raw in _asObjectList(map['contents'])) {
      final Map<String, Object?> content = _asStringObjectMap(raw);
      final String? text = content['text'] is String
          ? content['text'] as String
          : null;
      final String? blob = content['blob'] is String
          ? content['blob'] as String
          : null;
      final String? mimeType =
          (content['mimeType'] ?? content['mime_type']) is String
          ? '${content['mimeType'] ?? content['mime_type']}'
          : null;
      if (text == null && blob == null) {
        continue;
      }
      parsed.add(
        McpResourceContent(text: text, blob: blob, mimeType: mimeType),
      );
    }
    return parsed;
  }

  List<McpResourceContent> _parsePromptContents(Object? result) {
    final Map<String, Object?> map = _asStringObjectMap(result);
    final List<McpResourceContent> parsed = <McpResourceContent>[];
    for (final Object? raw in _asObjectList(map['messages'])) {
      final Map<String, Object?> message = _asStringObjectMap(raw);
      final Object? content = message['content'];
      if (content is String) {
        final String text = content.trim();
        if (text.isNotEmpty) {
          parsed.add(McpResourceContent(text: text));
        }
        continue;
      }

      final Map<String, Object?> contentMap = _asStringObjectMap(content);
      final String text = _asString(contentMap['text']);
      if (text.isNotEmpty) {
        parsed.add(McpResourceContent(text: text));
      }
    }
    return parsed;
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

class _McpJsonRpcException extends StateError {
  _McpJsonRpcException({
    required this.method,
    required this.code,
    required String message,
  }) : super(
         'MCP RPC `$method` failed${code == null ? '' : ' ($code)'}: $message',
       );

  final String method;
  final int? code;
}
