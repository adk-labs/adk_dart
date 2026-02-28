import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp_remote_client.dart'
    show
        McpJsonRpcException,
        McpServerMessage,
        McpServerMessageHandler,
        McpServerRequestException,
        McpServerRequestHandler,
        mcpLatestProtocolVersion,
        mcpMethodNotFoundCode,
        mcpServerErrorCode,
        mcpSupportedProtocolVersions;

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

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Future<void>? _connectionTask;
  Future<void>? _initializationTask;
  final Map<Object, Completer<Map<String, Object?>>> _pendingById =
      <Object, Completer<Map<String, Object?>>>{};
  Future<void> _writeQueue = Future<void>.value();
  int _requestSequence = 1;
  bool _initialized = false;
  bool _closing = false;
  String? _connectionId;
  String? _negotiatedProtocolVersion;
  Map<String, Object?> _negotiatedCapabilities = <String, Object?>{};

  bool get isConnected => _process != null;
  bool get isInitialized => _initialized;
  String? get negotiatedProtocolVersion => _negotiatedProtocolVersion;
  Map<String, Object?> get negotiatedCapabilities =>
      Map<String, Object?>.from(_negotiatedCapabilities);

  Future<void> ensureConnected(StdioConnectionParams connectionParams) async {
    if (_process != null) {
      return;
    }
    final Future<void>? pending = _connectionTask;
    if (pending != null) {
      await pending;
      return;
    }

    final Future<void> task = () async {
      final Process process = await Process.start(
        connectionParams.command,
        connectionParams.arguments,
        workingDirectory: connectionParams.workingDirectory,
        environment: connectionParams.environment,
        includeParentEnvironment: connectionParams.includeParentEnvironment,
        runInShell: connectionParams.runInShell,
      );
      _process = process;
      _connectionId = connectionParams.resolvedConnectionId;

      _stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (String line) {
              unawaited(_handleStdoutLine(line));
            },
            onError: (Object error, StackTrace stackTrace) {
              _failPending(StateError('MCP stdio stdout stream error: $error'));
            },
            onDone: _handleProcessClosed,
            cancelOnError: false,
          );
      _stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String line) {
            onStderrLine?.call(connectionParams.resolvedConnectionId, line);
          }, cancelOnError: false);
      unawaited(
        process.exitCode.then((int code) {
          if (_closing) {
            return;
          }
          _handleProcessClosed(
            StateError(
              'MCP stdio process exited unexpectedly with code $code.',
            ),
          );
        }),
      );
    }();

    _connectionTask = task;
    try {
      await task;
    } finally {
      _connectionTask = null;
    }
  }

  Future<void> ensureInitialized(StdioConnectionParams connectionParams) async {
    if (_initialized) {
      return;
    }

    final Future<void>? pending = _initializationTask;
    if (pending != null) {
      await pending;
      return;
    }

    final Future<void> task = () async {
      await ensureConnected(connectionParams);
      final Map<String, Object?> initialized = _asStringObjectMap(
        await _jsonRpcCall(
          method: 'initialize',
          params: <String, Object?>{
            'protocolVersion': latestProtocolVersion,
            'capabilities': clientCapabilities,
            'clientInfo': <String, Object?>{
              'name': clientInfoName,
              'version': clientInfoVersion,
            },
          },
          ensureInitialized: false,
        ),
      );
      final String protocolVersion = _asString(
        initialized['protocolVersion'],
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
      _negotiatedProtocolVersion = protocolVersion;
      _negotiatedCapabilities = _asStringObjectMap(initialized['capabilities']);
      _initialized = true;

      await _sendJson(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': const <String, Object?>{},
      });
    }();

    _initializationTask = task;
    try {
      await task;
    } finally {
      _initializationTask = null;
    }
  }

  Future<Object?> call({
    required StdioConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
  }) async {
    if (method != 'initialize') {
      await ensureInitialized(connectionParams);
    } else {
      await ensureConnected(connectionParams);
    }
    return _jsonRpcCall(
      method: method,
      params: params,
      ensureInitialized: method != 'initialize',
    );
  }

  Future<Object?> tryCall({
    required StdioConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
    Set<int> suppressJsonRpcErrorCodes = const <int>{},
    bool suppressErrors = false,
  }) async {
    try {
      return await call(
        connectionParams: connectionParams,
        method: method,
        params: params,
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
    required StdioConnectionParams connectionParams,
    required String method,
    required String resultArrayField,
    Set<int> suppressJsonRpcErrorCodes = const <int>{},
    bool suppressErrors = false,
  }) async {
    final List<Map<String, Object?>> collected = <Map<String, Object?>>[];
    String? cursor;
    final Set<String> seenCursors = <String>{};

    while (true) {
      final Object? result = await tryCall(
        connectionParams: connectionParams,
        method: method,
        params: <String, Object?>{
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        },
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
    required StdioConnectionParams connectionParams,
    required String method,
    required Map<String, Object?> params,
  }) async {
    await ensureInitialized(connectionParams);
    await _sendJson(<String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  Future<void> close({bool killProcess = true}) async {
    _closing = true;
    _initialized = false;
    _negotiatedProtocolVersion = null;
    _negotiatedCapabilities = <String, Object?>{};
    _requestSequence = 1;

    final Process? process = _process;
    _process = null;
    if (killProcess && process != null) {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return 1;
        },
      );
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _failPending(StateError('MCP stdio client is closed.'));
    _closing = false;
  }

  Future<void> _handleStdoutLine(String line) async {
    if (line.trim().isEmpty) {
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      return;
    }
    if (decoded is! Map) {
      return;
    }
    final Map<String, Object?> message = decoded.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );

    if (_isResponseObject(message)) {
      final Object key = _normalizeId(message['id']);
      final Completer<Map<String, Object?>>? completer = _pendingById.remove(
        key,
      );
      if (completer != null && !completer.isCompleted) {
        completer.complete(message);
        return;
      }
    }

    if (_isRequestObject(message)) {
      await _handleIncomingRequest(message);
      return;
    }
    _emitServerMessage(message);
  }

  Future<void> _handleIncomingRequest(Map<String, Object?> payload) async {
    _emitServerMessage(payload);

    final Object? id = payload['id'];
    if (id == null) {
      return;
    }
    final String method = _asString(payload['method']).trim();
    final McpServerMessage request = McpServerMessage(
      url: _connectionId ?? 'stdio',
      method: method,
      params: _asStringObjectMap(payload['params']),
      id: id,
    );

    Object? result = const <String, Object?>{};
    Map<String, Object?>? error;
    try {
      if (onServerRequest != null) {
        final Object? handled = await onServerRequest!(request);
        if (handled != null) {
          result = handled;
        }
      } else if (method != 'ping') {
        throw McpServerRequestException(
          code: mcpMethodNotFoundCode,
          message: 'Unsupported server request method: $method',
          method: method,
        );
      }
    } on McpServerRequestException catch (exception) {
      error = <String, Object?>{
        'code': exception.code,
        'message': exception.message,
        if (exception.data != null) 'data': exception.data,
      };
    } catch (exception) {
      error = <String, Object?>{
        'code': mcpServerErrorCode,
        'message': 'Unhandled error while handling server request `$method`.',
        'data': '$exception',
      };
    }

    await _sendJson(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      if (error != null) 'error': error else 'result': result,
    });
  }

  void _emitServerMessage(Map<String, Object?> payload) {
    final String method = _asString(payload['method']).trim();
    if (method.isEmpty) {
      return;
    }
    onServerMessage?.call(
      McpServerMessage(
        url: _connectionId ?? 'stdio',
        method: method,
        params: _asStringObjectMap(payload['params']),
        id: payload['id'],
      ),
    );
  }

  Future<Object?> _jsonRpcCall({
    required String method,
    required Map<String, Object?> params,
    required bool ensureInitialized,
  }) async {
    if (ensureInitialized && !_initialized) {
      throw StateError(
        'MCP stdio client is not initialized yet. Call ensureInitialized first.',
      );
    }
    final int requestId = _requestSequence++;
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    _pendingById[requestId] = completer;

    try {
      await _sendJson(<String, Object?>{
        'jsonrpc': '2.0',
        'id': requestId,
        'method': method,
        'params': params,
      });
    } catch (error, stackTrace) {
      _pendingById.remove(requestId);
      completer.completeError(error, stackTrace);
    }

    final Map<String, Object?> response;
    try {
      response = await completer.future.timeout(requestTimeout);
    } on TimeoutException catch (_) {
      _pendingById.remove(requestId);
      await _sendJson(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/cancelled',
        'params': <String, Object?>{
          'requestId': requestId,
          'reason': 'request_timeout',
        },
      });
      rethrow;
    }

    final Object? error = response['error'];
    if (error != null) {
      final Map<String, Object?> map = _asStringObjectMap(error);
      throw McpJsonRpcException(
        method: method,
        code: _asInt(map['code']),
        message: _asString(map['message']).trim().isEmpty
            ? '$error'
            : _asString(map['message']).trim(),
      );
    }

    if (!response.containsKey('result')) {
      throw FormatException(
        'MCP response for `$method` is missing both `result` and `error`.',
      );
    }
    return response['result'];
  }

  Future<void> _sendJson(Map<String, Object?> payload) async {
    final Process? process = _process;
    if (process == null) {
      throw StateError('MCP stdio process is not connected.');
    }
    final String encoded = jsonEncode(payload);
    _writeQueue = _writeQueue.then((_) async {
      process.stdin.writeln(encoded);
      await process.stdin.flush();
    });
    await _writeQueue;
  }

  void _handleProcessClosed([Object? reason]) {
    _initialized = false;
    _process = null;
    final Object failure =
        reason ?? StateError('MCP stdio process stdout stream closed.');
    _failPending(failure);
  }

  void _failPending(Object error) {
    if (_pendingById.isEmpty) {
      return;
    }
    final List<Completer<Map<String, Object?>>> completers = _pendingById.values
        .toList(growable: false);
    _pendingById.clear();
    for (final Completer<Map<String, Object?>> completer in completers) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }
}

Object _normalizeId(Object? id) {
  if (id is int) {
    return id;
  }
  if (id is num) {
    return id.toInt();
  }
  if (id is String) {
    final String trimmed = id.trim();
    final int? parsed = int.tryParse(trimmed);
    return parsed ?? trimmed;
  }
  return id ?? '';
}

bool _isResponseObject(Map<String, Object?> message) {
  return message.containsKey('id') &&
      (message.containsKey('result') || message.containsKey('error'));
}

bool _isRequestObject(Map<String, Object?> message) {
  if (!message.containsKey('method')) {
    return false;
  }
  if (!message.containsKey('id')) {
    return false;
  }
  if (message['id'] == null) {
    return false;
  }
  return !message.containsKey('result') && !message.containsKey('error');
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
