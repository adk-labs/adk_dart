import 'dart:async';

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

  void registerTools({
    required StreamableHTTPConnectionParams connectionParams,
    required List<BaseTool> tools,
  }) {
    _toolsByUrl[connectionParams.url] = tools
        .map((BaseTool tool) => tool)
        .toList(growable: false);
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

  Future<Object?> callTool({
    required StreamableHTTPConnectionParams connectionParams,
    required String toolName,
    required Map<String, dynamic> args,
    Map<String, String>? headers,
  }) async {
    final McpToolExecutor? executor =
        _executorsByUrl[connectionParams.url]?[toolName];
    if (executor == null) {
      throw ArgumentError('MCP tool `$toolName` is not registered.');
    }
    final Object? result = executor(args, headers: headers);
    if (result is Future<Object?>) {
      return result;
    }
    if (result is Future) {
      return await result;
    }
    return result;
  }

  void clear() {
    _toolsByUrl.clear();
    _resourcesByUrl.clear();
    _executorsByUrl.clear();
  }
}
