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

/// Process launch options for an MCP stdio server.
class StdioConnectionParams {
  /// Creates options used to start an MCP stdio process.
  StdioConnectionParams({
    required this.command,
    List<String>? arguments,
    this.workingDirectory,
    this.environment,
    this.includeParentEnvironment = true,
    this.runInShell = false,
    this.connectionId,
  }) : arguments = arguments ?? const <String>[];

  /// The executable to start.
  final String command;

  /// Arguments passed to [command].
  final List<String> arguments;

  /// The working directory for the process, when provided.
  final String? workingDirectory;

  /// Extra environment variables for the process.
  final Map<String, String>? environment;

  /// Whether to inherit the parent process environment.
  final bool includeParentEnvironment;

  /// Whether to spawn the process through a shell.
  final bool runInShell;

  /// Optional stable identifier used in callbacks and logs.
  final String? connectionId;

  /// A stable connection id derived from [connectionId], [command], and args.
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

/// Placeholder stdio client for platforms without `dart:io` process support.
///
/// All transport methods throw [UnsupportedError] with guidance to use
/// `StreamableHTTPConnectionParams` instead.
class McpStdioClient {
  /// Creates an MCP stdio client placeholder.
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

  /// Name sent in the MCP `initialize.clientInfo.name` field.
  final String clientInfoName;

  /// Version sent in the MCP `initialize.clientInfo.version` field.
  final String clientInfoVersion;

  /// Callback invoked for server notifications and request-shaped messages.
  final McpServerMessageHandler? onServerMessage;

  /// Callback used to handle server-initiated requests.
  final McpServerRequestHandler? onServerRequest;

  /// Callback invoked for each stderr line from the stdio process.
  final void Function(String connectionId, String line)? onStderrLine;

  /// Protocol version advertised during initialization.
  final String latestProtocolVersion;

  /// Protocol versions accepted from the server.
  final Set<String> supportedProtocolVersions;

  /// Capabilities advertised by the client during initialization.
  final Map<String, Object?> clientCapabilities;

  /// Timeout configured for request/response round trips.
  final Duration requestTimeout;

  /// Always `false` on unsupported platforms.
  bool get isConnected => false;

  /// Always `false` on unsupported platforms.
  bool get isInitialized => false;

  /// Always `null` on unsupported platforms.
  String? get negotiatedProtocolVersion => null;

  /// Always an empty map on unsupported platforms.
  Map<String, Object?> get negotiatedCapabilities => const <String, Object?>{};

  /// Throws [UnsupportedError] on this platform.
  Future<void> ensureConnected(StdioConnectionParams connectionParams) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<void> ensureInitialized(StdioConnectionParams connectionParams) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Object?> call({
    required StdioConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Object?> tryCall({
    required StdioConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
    Set<int> suppressJsonRpcErrorCodes = const <int>{},
    bool suppressErrors = false,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
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

  /// Throws [UnsupportedError] on this platform.
  Future<void> notify({
    required StdioConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> ping({
    required StdioConnectionParams connectionParams,
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> complete({
    required StdioConnectionParams connectionParams,
    required Map<String, Object?> ref,
    required Object? argument,
    Map<String, Object?>? context,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> setLoggingLevel({
    required StdioConnectionParams connectionParams,
    required String level,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> listResourcesPage({
    required StdioConnectionParams connectionParams,
    String? cursor,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<List<Map<String, Object?>>> listResources({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> listResourceTemplatesPage({
    required StdioConnectionParams connectionParams,
    String? cursor,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<List<Map<String, Object?>>> listResourceTemplates({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> readResource({
    required StdioConnectionParams connectionParams,
    required String uri,
    String? mimeType,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> subscribeResource({
    required StdioConnectionParams connectionParams,
    required String uri,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> unsubscribeResource({
    required StdioConnectionParams connectionParams,
    required String uri,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> listPromptsPage({
    required StdioConnectionParams connectionParams,
    String? cursor,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<List<Map<String, Object?>>> listPrompts({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> getPrompt({
    required StdioConnectionParams connectionParams,
    required String name,
    Map<String, Object?>? arguments,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> listToolsPage({
    required StdioConnectionParams connectionParams,
    String? cursor,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<List<Map<String, Object?>>> listTools({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> callTool({
    required StdioConnectionParams connectionParams,
    required String name,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> getTask({
    required StdioConnectionParams connectionParams,
    required String id,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> getTaskResult({
    required StdioConnectionParams connectionParams,
    required String id,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> cancelTask({
    required StdioConnectionParams connectionParams,
    required String id,
    String? reason,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<Map<String, Object?>> listTasksPage({
    required StdioConnectionParams connectionParams,
    String? cursor,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<List<Map<String, Object?>>> listTasks({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<void> notifyCancelledRequest({
    required StdioConnectionParams connectionParams,
    required Object requestId,
    String? reason,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<void> notifyProgress({
    required StdioConnectionParams connectionParams,
    required Object requestId,
    required Object progress,
    Object? total,
    String? message,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<void> notifyRootsListChanged({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<void> notifyTaskStatus({
    required StdioConnectionParams connectionParams,
    required String taskId,
    required String status,
    Object? result,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// Throws [UnsupportedError] on this platform.
  Future<void> sendInitializedNotification({
    required StdioConnectionParams connectionParams,
  }) {
    throw UnsupportedError(_unsupportedMessage);
  }

  /// No-op close method for unsupported platforms.
  Future<void> close({bool killProcess = true}) async {}
}
