import 'dart:async';

import 'mcp_remote_client.dart'
    show
        McpServerMessageHandler,
        McpServerRequestHandler,
        mcpLatestProtocolVersion,
        mcpSupportedProtocolVersions;

const String _unsupportedMessage =
    'MCP stdio transport is not supported on this platform. '
    'Use StreamableHTTPConnectionParams instead.';

class StdioConnectionParams {
  StdioConnectionParams({
    required this.command,
    List<String>? arguments,
    this.workingDirectory,
    this.environment,
    this.includeParentEnvironment = true,
    this.runInShell = false,
    this.connectionId,
  }) : arguments = arguments ?? const <String>[];

  final String command;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool includeParentEnvironment;
  final bool runInShell;
  final String? connectionId;

  String get resolvedConnectionId {
    if (connectionId != null && connectionId!.trim().isNotEmpty) {
      return connectionId!.trim();
    }
    if (arguments.isEmpty) {
      return 'stdio:$command';
    }
    return 'stdio:$command ${arguments.join(' ')}';
  }
}

class McpStdioClient {
  McpStdioClient({
    required this.clientInfoName,
    required this.clientInfoVersion,
    this.onServerMessage,
    this.onServerRequest,
    this.onStderrLine,
    this.latestProtocolVersion = mcpLatestProtocolVersion,
    Set<String>? supportedProtocolVersions,
    Map<String, Object?>? clientCapabilities,
    this.requestTimeout = const Duration(seconds: 30),
  }) : supportedProtocolVersions =
           supportedProtocolVersions ?? mcpSupportedProtocolVersions,
       clientCapabilities = clientCapabilities ?? const <String, Object?>{};

  final String clientInfoName;
  final String clientInfoVersion;
  final McpServerMessageHandler? onServerMessage;
  final McpServerRequestHandler? onServerRequest;
  final void Function(String connectionId, String line)? onStderrLine;
  final String latestProtocolVersion;
  final Set<String> supportedProtocolVersions;
  final Map<String, Object?> clientCapabilities;
  final Duration requestTimeout;

  bool get isConnected => false;
  bool get isInitialized => false;
  String? get negotiatedProtocolVersion => null;
  Map<String, Object?> get negotiatedCapabilities => const <String, Object?>{};

  Future<void> ensureConnected(StdioConnectionParams connectionParams) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<void> ensureInitialized(StdioConnectionParams connectionParams) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Object?> call({
    required StdioConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Object?> tryCall({
    required StdioConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
    Set<int> suppressJsonRpcErrorCodes = const <int>{},
    bool suppressErrors = false,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<List<Map<String, Object?>>> collectPaginatedMaps({
    required StdioConnectionParams connectionParams,
    required String method,
    required String resultArrayField,
    Map<String, Object?> params = const <String, Object?>{},
    Set<int> suppressJsonRpcErrorCodes = const <int>{},
    bool suppressErrors = false,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<void> notify({
    required StdioConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> ping({
    required StdioConnectionParams connectionParams,
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> complete({
    required StdioConnectionParams connectionParams,
    required Map<String, Object?> ref,
    required Object? argument,
    Map<String, Object?>? context,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> setLoggingLevel({
    required StdioConnectionParams connectionParams,
    required String level,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> listResourcesPage({
    required StdioConnectionParams connectionParams,
    String? cursor,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<List<Map<String, Object?>>> listResources({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> listResourceTemplatesPage({
    required StdioConnectionParams connectionParams,
    String? cursor,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<List<Map<String, Object?>>> listResourceTemplates({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> readResource({
    required StdioConnectionParams connectionParams,
    required String uri,
    String? mimeType,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> subscribeResource({
    required StdioConnectionParams connectionParams,
    required String uri,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> unsubscribeResource({
    required StdioConnectionParams connectionParams,
    required String uri,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> listPromptsPage({
    required StdioConnectionParams connectionParams,
    String? cursor,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<List<Map<String, Object?>>> listPrompts({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> getPrompt({
    required StdioConnectionParams connectionParams,
    required String name,
    Map<String, Object?>? arguments,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> listToolsPage({
    required StdioConnectionParams connectionParams,
    String? cursor,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<List<Map<String, Object?>>> listTools({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> callTool({
    required StdioConnectionParams connectionParams,
    required String name,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> getTask({
    required StdioConnectionParams connectionParams,
    required String id,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> getTaskResult({
    required StdioConnectionParams connectionParams,
    required String id,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> cancelTask({
    required StdioConnectionParams connectionParams,
    required String id,
    String? reason,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<Map<String, Object?>> listTasksPage({
    required StdioConnectionParams connectionParams,
    String? cursor,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<List<Map<String, Object?>>> listTasks({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<void> notifyCancelledRequest({
    required StdioConnectionParams connectionParams,
    required Object requestId,
    String? reason,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<void> notifyProgress({
    required StdioConnectionParams connectionParams,
    required Object requestId,
    required Object progress,
    Object? total,
    String? message,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<void> notifyRootsListChanged({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<void> notifyTaskStatus({
    required StdioConnectionParams connectionParams,
    required String taskId,
    required String status,
    Object? result,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<void> sendInitializedNotification({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  Future<void> close({bool killProcess = true}) async {}
}
