import 'dart:async';

import 'package:adk_mcp/adk_mcp.dart'
    show
        McpRemoteClient,
        McpResourceContent,
        McpServerMessage,
        StreamableHTTPConnectionParams,
        mcpMethodNotFoundCode;

import '../../version.dart';
import '../base_tool.dart';

export 'package:adk_mcp/adk_mcp.dart'
    show
        McpHttpStatusException,
        McpJsonRpcException,
        McpResourceContent,
        StreamableHTTPConnectionParams;

typedef McpToolExecutor =
    FutureOr<Object?> Function(
      Map<String, dynamic> args, {
      Map<String, String>? headers,
    });

class McpSessionManager {
  McpSessionManager._()
    : _remoteClient = McpRemoteClient(
        clientInfoName: 'adk_dart',
        clientInfoVersion: adkVersion,
        onServerMessage: _handleServerMessage,
      );

  static final McpSessionManager instance = McpSessionManager._();

  final McpRemoteClient _remoteClient;

  final Map<String, List<BaseTool>> _toolsByUrl = <String, List<BaseTool>>{};
  final Map<String, Map<String, List<McpResourceContent>>> _resourcesByUrl =
      <String, Map<String, List<McpResourceContent>>>{};
  final Map<String, Map<String, McpToolExecutor>> _executorsByUrl =
      <String, Map<String, McpToolExecutor>>{};
  final Map<String, List<Map<String, Object?>>> _remoteToolDescriptorsByUrl =
      <String, List<Map<String, Object?>>>{};

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
    bool forceRefresh = true,
    Map<String, String>? headers,
  }) async {
    if (!_remoteClient.isRemoteCapable(connectionParams)) {
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

    await _remoteClient.ensureInitialized(connectionParams, headers: headers);
    if (!_remoteClient.hasNegotiatedCapability(connectionParams, 'tools')) {
      return const <Map<String, Object?>>[];
    }

    final List<Map<String, Object?>> descriptors = await _remoteClient
        .collectPaginatedMaps(
          connectionParams: connectionParams,
          method: 'tools/list',
          resultArrayField: 'tools',
          headers: headers,
        );
    final List<Map<String, Object?>> filtered = descriptors
        .where((Map<String, Object?> descriptor) {
          return _asString(descriptor['name']).isNotEmpty;
        })
        .toList(growable: false);

    _remoteToolDescriptorsByUrl[url] = filtered
        .map((Map<String, Object?> item) => Map<String, Object?>.from(item))
        .toList(growable: false);
    return filtered;
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
    StreamableHTTPConnectionParams connectionParams, {
    Map<String, String>? headers,
  }) async {
    final List<String> local = listResources(connectionParams);
    if (local.isNotEmpty) {
      return local;
    }
    if (!_remoteClient.isRemoteCapable(connectionParams)) {
      return const <String>[];
    }

    await _remoteClient.ensureInitialized(connectionParams, headers: headers);
    final Set<String> names = <String>{};

    if (_remoteClient.hasNegotiatedCapability(connectionParams, 'resources')) {
      final List<Map<String, Object?>> resources = await _remoteClient
          .collectPaginatedMaps(
            connectionParams: connectionParams,
            method: 'resources/list',
            resultArrayField: 'resources',
            headers: headers,
          );
      for (final Map<String, Object?> resource in resources) {
        final String name = _asString(resource['uri']).isNotEmpty
            ? _asString(resource['uri'])
            : _asString(resource['name']);
        if (name.isNotEmpty) {
          names.add(name);
        }
      }

      final List<Map<String, Object?>> resourceTemplates = await _remoteClient
          .collectPaginatedMaps(
            connectionParams: connectionParams,
            method: 'resources/templates/list',
            resultArrayField: 'resourceTemplates',
            headers: headers,
            suppressJsonRpcErrorCodes: const <int>{mcpMethodNotFoundCode},
          );
      for (final Map<String, Object?> template in resourceTemplates) {
        final String templateName =
            _asString(template['uriTemplate']).isNotEmpty
            ? _asString(template['uriTemplate'])
            : _asString(template['name']);
        if (templateName.isNotEmpty) {
          names.add(templateName);
        }
      }
    }

    if (_remoteClient.hasNegotiatedCapability(connectionParams, 'prompts')) {
      final List<Map<String, Object?>> prompts = await _remoteClient
          .collectPaginatedMaps(
            connectionParams: connectionParams,
            method: 'prompts/list',
            resultArrayField: 'prompts',
            headers: headers,
            suppressJsonRpcErrorCodes: const <int>{mcpMethodNotFoundCode},
          );
      for (final Map<String, Object?> prompt in prompts) {
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
    Map<String, Object?>? promptArguments,
    Map<String, String>? headers,
  }) async {
    final List<McpResourceContent> local = readResource(
      connectionParams: connectionParams,
      resourceName: resourceName,
    );
    if (local.isNotEmpty) {
      return local;
    }
    if (!_remoteClient.isRemoteCapable(connectionParams)) {
      return const <McpResourceContent>[];
    }

    await _remoteClient.ensureInitialized(connectionParams, headers: headers);

    if (_remoteClient.hasNegotiatedCapability(connectionParams, 'resources')) {
      final Object? readResult = await _remoteClient.tryCall(
        connectionParams: connectionParams,
        method: 'resources/read',
        params: <String, Object?>{'uri': resourceName},
        headers: headers,
        suppressJsonRpcErrorCodes: const <int>{mcpMethodNotFoundCode},
      );
      final List<McpResourceContent> resourceContents = _parseResourceContents(
        readResult,
      );
      if (resourceContents.isNotEmpty) {
        return resourceContents;
      }
    }

    if (_remoteClient.hasNegotiatedCapability(connectionParams, 'prompts')) {
      final Object? promptResult = await _remoteClient.tryCall(
        connectionParams: connectionParams,
        method: 'prompts/get',
        params: <String, Object?>{
          'name': resourceName,
          if (promptArguments != null && promptArguments.isNotEmpty)
            'arguments': promptArguments
          else
            'arguments': <String, Object?>{},
        },
        headers: headers,
        suppressJsonRpcErrorCodes: const <int>{mcpMethodNotFoundCode},
      );
      return _parsePromptContents(promptResult);
    }

    return const <McpResourceContent>[];
  }

  Future<void> subscribeResource({
    required StreamableHTTPConnectionParams connectionParams,
    required String resourceUri,
    Map<String, String>? headers,
  }) async {
    if (!_remoteClient.isRemoteCapable(connectionParams)) {
      return;
    }
    await _remoteClient.ensureInitialized(connectionParams, headers: headers);
    if (!_remoteClient.hasNegotiatedCapability(connectionParams, 'resources')) {
      return;
    }
    await _remoteClient.tryCall(
      connectionParams: connectionParams,
      method: 'resources/subscribe',
      params: <String, Object?>{'uri': resourceUri},
      headers: headers,
      suppressJsonRpcErrorCodes: const <int>{mcpMethodNotFoundCode},
      suppressErrors: true,
    );
  }

  Future<void> unsubscribeResource({
    required StreamableHTTPConnectionParams connectionParams,
    required String resourceUri,
    Map<String, String>? headers,
  }) async {
    if (!_remoteClient.isRemoteCapable(connectionParams)) {
      return;
    }
    await _remoteClient.ensureInitialized(connectionParams, headers: headers);
    if (!_remoteClient.hasNegotiatedCapability(connectionParams, 'resources')) {
      return;
    }
    await _remoteClient.tryCall(
      connectionParams: connectionParams,
      method: 'resources/unsubscribe',
      params: <String, Object?>{'uri': resourceUri},
      headers: headers,
      suppressJsonRpcErrorCodes: const <int>{mcpMethodNotFoundCode},
      suppressErrors: true,
    );
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

    if (!_remoteClient.isRemoteCapable(connectionParams)) {
      throw ArgumentError('MCP tool `$toolName` is not registered.');
    }

    await _remoteClient.ensureInitialized(connectionParams, headers: headers);
    if (!_remoteClient.hasNegotiatedCapability(connectionParams, 'tools')) {
      throw StateError(
        'MCP server `${connectionParams.url}` does not expose `tools` capability.',
      );
    }

    final Object? result = await _remoteClient.call(
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
    _remoteClient.clear();
  }

  static void _handleServerMessage(McpServerMessage message) {
    final String method = message.method.trim();
    if (method == 'notifications/tools/list_changed') {
      instance._remoteToolDescriptorsByUrl.remove(message.url);
      return;
    }
    if (method == 'notifications/resources/list_changed' ||
        method == 'notifications/prompts/list_changed' ||
        method == 'notifications/resources/updated') {
      // No cached remote resources/prompts content exists today.
      return;
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
