import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../a2a/converters/event_converter.dart';
import '../a2a/converters/part_converter.dart';
import '../a2a/logs/log_utils.dart';
import '../a2a/protocol.dart';
import '../events/event.dart';
import '../flows/llm_flows/functions.dart';
import '../types/content.dart';
import 'base_agent.dart';
import 'invocation_context.dart';

const String agentCardWellKnownPath = '/.well-known/agent.json';
const String a2aMetadataPrefix = 'a2a:';
const double defaultA2aTimeoutSeconds = 600.0;

class AgentCardResolutionError implements Exception {
  AgentCardResolutionError(this.message);

  final String message;

  @override
  String toString() => 'AgentCardResolutionError: $message';
}

class A2aClientError implements Exception {
  A2aClientError(this.message);

  final String message;

  @override
  String toString() => 'A2aClientError: $message';
}

class A2aClientHttpError extends A2aClientError {
  A2aClientHttpError(super.message, {this.statusCode});

  final int? statusCode;

  @override
  String toString() => 'A2aClientHttpError(statusCode: $statusCode): $message';
}

typedef A2aClientEvent = (A2aTask, A2aEvent?);

typedef A2aRequestMetaProvider =
    Map<String, Object?> Function(
      InvocationContext context,
      A2aMessage request,
    );

class A2aClientCallContext {
  A2aClientCallContext({Map<String, Object?>? state})
    : state = state ?? <String, Object?>{};

  Map<String, Object?> state;
}

abstract class A2aClient {
  Stream<Object> sendMessage({
    required A2aMessage request,
    Map<String, Object?>? requestMetadata,
    A2aClientCallContext? context,
  });
}

abstract class A2aClientFactory {
  A2aClient create(AgentCard agentCard);
}

class DefaultA2aClientFactory implements A2aClientFactory {
  const DefaultA2aClientFactory();

  @override
  A2aClient create(AgentCard agentCard) {
    return _DefaultA2aClient(agentCard: agentCard);
  }
}

class _DefaultA2aClient implements A2aClient {
  _DefaultA2aClient({required this.agentCard});

  final AgentCard agentCard;

  @override
  Stream<Object> sendMessage({
    required A2aMessage request,
    Map<String, Object?>? requestMetadata,
    A2aClientCallContext? context,
  }) {
    throw A2aClientError(
      'No A2A client transport is configured for `${agentCard.url}`. '
      'Provide `a2aClientFactory` when creating RemoteA2aAgent.',
    );
  }
}

class RemoteA2aAgent extends BaseAgent {
  RemoteA2aAgent({
    required String name,
    required Object? agentCard,
    String description = '',
    HttpClient? httpClient,
    this.timeout = defaultA2aTimeoutSeconds,
    GenAIPartToA2APartConverter genaiPartConverter = convertGenaiPartToA2aPart,
    A2APartToGenAIPartConverter a2aPartConverter = convertA2aPartToGenaiPart,
    A2aClientFactory? a2aClientFactory,
    this.a2aRequestMetaProvider,
    this.fullHistoryWhenStateless = false,
    List<BaseAgent>? subAgents,
    Object? beforeAgentCallback,
    Object? afterAgentCallback,
  }) : _genaiPartConverter = genaiPartConverter,
       _a2aPartConverter = a2aPartConverter,
       _a2aClientFactory = a2aClientFactory,
       _httpClient = httpClient,
       _httpClientNeedsCleanup = httpClient == null,
       super(
         name: name,
         description: description,
         subAgents: subAgents,
         beforeAgentCallback: beforeAgentCallback,
         afterAgentCallback: afterAgentCallback,
       ) {
    if (agentCard == null) {
      throw ArgumentError('agentCard cannot be null');
    }

    if (agentCard is AgentCard) {
      _agentCard = agentCard;
      return;
    }

    if (agentCard is String) {
      final String normalized = agentCard.trim();
      if (normalized.isEmpty) {
        throw ArgumentError('agentCard string cannot be empty');
      }
      _agentCardSource = normalized;
      return;
    }

    throw ArgumentError(
      'agentCard must be AgentCard, URL string, or file path string, '
      'got ${agentCard.runtimeType}.',
    );
  }

  final double timeout;
  final GenAIPartToA2APartConverter _genaiPartConverter;
  final A2APartToGenAIPartConverter _a2aPartConverter;
  final A2aRequestMetaProvider? a2aRequestMetaProvider;
  final bool fullHistoryWhenStateless;

  AgentCard? _agentCard;
  String? _agentCardSource;
  A2aClient? _a2aClient;
  A2aClientFactory? _a2aClientFactory;
  HttpClient? _httpClient;
  bool _httpClientNeedsCleanup;
  bool _isResolved = false;

  AgentCard? get resolvedAgentCard => _agentCard;
  bool get isResolved => _isResolved;

  @override
  RemoteA2aAgent clone({Map<String, Object?>? update}) {
    final Map<String, Object?> cloneUpdate = normalizeCloneUpdate(update);
    validateCloneUpdateFields(
      update: cloneUpdate,
      allowedFields: <String>{
        ...BaseAgent.baseCloneUpdateFields,
        'agentCard',
        'httpClient',
        'timeout',
        'genaiPartConverter',
        'a2aPartConverter',
        'a2aClientFactory',
        'a2aRequestMetaProvider',
        'fullHistoryWhenStateless',
      },
    );

    final List<BaseAgent> clonedSubAgents = cloneSubAgentsField(cloneUpdate);
    final Object? currentAgentCard = _agentCardSource ?? _agentCard;
    final Object? clonedAgentCard = cloneUpdate.containsKey('agentCard')
        ? cloneUpdate['agentCard']
        : currentAgentCard;
    if (clonedAgentCard == null) {
      throw StateError(
        'RemoteA2aAgent clone requires `agentCard` to be set on the source '
        'agent or in the clone update.',
      );
    }

    final RemoteA2aAgent clonedAgent = RemoteA2aAgent(
      name: cloneFieldValue<String>(
        update: cloneUpdate,
        fieldName: 'name',
        currentValue: name,
      ),
      agentCard: clonedAgentCard,
      description: cloneFieldValue<String>(
        update: cloneUpdate,
        fieldName: 'description',
        currentValue: description,
      ),
      httpClient: cloneFieldValue<HttpClient?>(
        update: cloneUpdate,
        fieldName: 'httpClient',
        currentValue: _httpClient,
      ),
      timeout: cloneFieldValue<double>(
        update: cloneUpdate,
        fieldName: 'timeout',
        currentValue: timeout,
      ),
      genaiPartConverter: cloneFieldValue<GenAIPartToA2APartConverter>(
        update: cloneUpdate,
        fieldName: 'genaiPartConverter',
        currentValue: _genaiPartConverter,
      ),
      a2aPartConverter: cloneFieldValue<A2APartToGenAIPartConverter>(
        update: cloneUpdate,
        fieldName: 'a2aPartConverter',
        currentValue: _a2aPartConverter,
      ),
      a2aClientFactory: cloneFieldValue<A2aClientFactory?>(
        update: cloneUpdate,
        fieldName: 'a2aClientFactory',
        currentValue: _a2aClientFactory,
      ),
      a2aRequestMetaProvider: cloneFieldValue<A2aRequestMetaProvider?>(
        update: cloneUpdate,
        fieldName: 'a2aRequestMetaProvider',
        currentValue: a2aRequestMetaProvider,
      ),
      fullHistoryWhenStateless: cloneFieldValue<bool>(
        update: cloneUpdate,
        fieldName: 'fullHistoryWhenStateless',
        currentValue: fullHistoryWhenStateless,
      ),
      subAgents: <BaseAgent>[],
      beforeAgentCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'beforeAgentCallback',
        currentValue: beforeAgentCallback,
      ),
      afterAgentCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'afterAgentCallback',
        currentValue: afterAgentCallback,
      ),
    );
    clonedAgent.subAgents = clonedSubAgents;
    relinkClonedSubAgents(clonedAgent);
    return clonedAgent;
  }

  Future<HttpClient> _ensureHttpClient() async {
    if (_httpClient == null) {
      _httpClient = HttpClient()
        ..connectionTimeout = Duration(milliseconds: (timeout * 1000).round());
      _httpClientNeedsCleanup = true;
    }
    _a2aClientFactory ??= const DefaultA2aClientFactory();
    return _httpClient!;
  }

  Future<AgentCard> _resolveAgentCardFromUrl(String url) async {
    try {
      final Uri? uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.hasScheme ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw ArgumentError('Invalid URL format: $url');
      }

      final Uri cardUri = (uri.path.isEmpty || uri.path == '/')
          ? uri.replace(path: agentCardWellKnownPath)
          : uri;
      final String body = await _fetchText(cardUri);
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Agent card JSON must be an object.');
      }
      return AgentCard.fromJson(_toStringObjectMap(decoded));
    } catch (error) {
      if (error is AgentCardResolutionError) {
        rethrow;
      }
      throw AgentCardResolutionError(
        'Failed to resolve AgentCard from URL $url: $error',
      );
    }
  }

  Future<String> _fetchText(Uri uri) async {
    final HttpClient client = await _ensureHttpClient();
    final HttpClientRequest request = await client.getUrl(uri);
    final HttpClientResponse response = await request.close().timeout(
      Duration(milliseconds: (timeout * 1000).round()),
    );
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw A2aClientHttpError(
        'Failed to fetch `$uri`: status ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  Future<AgentCard> _resolveAgentCardFromFile(String filePath) async {
    try {
      final File file = File(filePath);
      if (!await file.exists()) {
        throw FileSystemException('Agent card file not found', filePath);
      }

      final FileStat stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        throw FileSystemException('Path is not a file', filePath);
      }

      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('Agent card JSON must be an object.');
      }

      return AgentCard.fromJson(_toStringObjectMap(decoded));
    } on FormatException catch (error) {
      throw AgentCardResolutionError(
        'Invalid JSON in agent card file $filePath: $error',
      );
    } catch (error) {
      throw AgentCardResolutionError(
        'Failed to resolve AgentCard from file $filePath: $error',
      );
    }
  }

  Future<AgentCard> _resolveAgentCard() async {
    final String? source = _agentCardSource;
    if (source == null || source.isEmpty) {
      throw AgentCardResolutionError('Agent card source is not set.');
    }

    if (source.startsWith('http://') || source.startsWith('https://')) {
      return _resolveAgentCardFromUrl(source);
    }
    return _resolveAgentCardFromFile(source);
  }

  Future<void> _validateAgentCard(AgentCard agentCard) async {
    if (agentCard.url.trim().isEmpty) {
      throw AgentCardResolutionError(
        'Agent card must have a valid URL for RPC communication.',
      );
    }

    final Uri? uri = Uri.tryParse(agentCard.url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw AgentCardResolutionError(
        'Invalid RPC URL in agent card: ${agentCard.url}.',
      );
    }
  }

  Future<void> _ensureResolved() async {
    if (_isResolved && _a2aClient != null) {
      return;
    }

    try {
      _agentCard ??= await _resolveAgentCard();
      await _validateAgentCard(_agentCard!);

      if (description.isEmpty && _agentCard!.description.isNotEmpty) {
        description = _agentCard!.description;
      }

      await _ensureHttpClient();
      _a2aClient ??= _a2aClientFactory!.create(_agentCard!);

      _isResolved = true;
      developer.log(
        'Successfully resolved remote A2A agent `${name}`.',
        name: 'adk_dart.remote_a2a_agent',
      );
    } catch (error) {
      developer.log(
        'Failed to resolve remote A2A agent `$name`: $error',
        name: 'adk_dart.remote_a2a_agent',
      );
      throw AgentCardResolutionError(
        'Failed to initialize remote A2A agent $name: $error',
      );
    }
  }

  A2aMessage? _createA2aRequestForUserFunctionResponse(InvocationContext ctx) {
    if (ctx.session.events.isEmpty ||
        ctx.session.events.last.author != 'user') {
      return null;
    }

    final Event? functionCallEvent = findMatchingFunctionCall(
      ctx.session.events,
    );
    if (functionCallEvent == null) {
      return null;
    }

    final A2aMessage? message = convertEventToA2aMessage(
      ctx.session.events.last,
      ctx,
      role: A2aRole.user,
      partConverter: _genaiPartConverter,
    );
    if (message == null) {
      return null;
    }

    final Map<String, dynamic>? metadata = functionCallEvent.customMetadata;
    if (metadata != null) {
      final Object? taskId = metadata['${a2aMetadataPrefix}task_id'];
      final Object? contextId = metadata['${a2aMetadataPrefix}context_id'];
      if (taskId is String && taskId.isNotEmpty) {
        message.taskId = taskId;
      }
      if (contextId is String && contextId.isNotEmpty) {
        message.contextId = contextId;
      }
    }
    return message;
  }

  bool _isRemoteResponse(Event event) {
    if (event.author != name) {
      return false;
    }
    final Object? response =
        event.customMetadata?['${a2aMetadataPrefix}response'];
    return _isTruthy(response);
  }

  (List<A2aPart>, String?) _constructMessagePartsFromSession(
    InvocationContext ctx,
  ) {
    final List<A2aPart> messageParts = <A2aPart>[];
    String? contextId;
    final List<Event> eventsToProcess = <Event>[];

    for (int i = ctx.session.events.length - 1; i >= 0; i -= 1) {
      final Event event = ctx.session.events[i];
      if (_isRemoteResponse(event)) {
        final Object? remoteContextId =
            event.customMetadata?['${a2aMetadataPrefix}context_id'];
        if (remoteContextId is String && remoteContextId.isNotEmpty) {
          contextId = remoteContextId;
        }
        if (!fullHistoryWhenStateless || contextId != null) {
          break;
        }
      }
      eventsToProcess.add(event);
    }

    for (final Event rawEvent in eventsToProcess.reversed) {
      Event? event = rawEvent;
      if (_isOtherAgentReply(name, event)) {
        event = _presentOtherAgentMessage(event);
      }
      if (event == null ||
          event.content == null ||
          event.content!.parts.isEmpty) {
        continue;
      }

      for (final Part part in event.content!.parts) {
        final Object? converted = _genaiPartConverter(part);
        final List<A2aPart> convertedParts = <A2aPart>[];

        if (converted is A2aPart) {
          convertedParts.add(converted);
        } else if (converted is List<A2aPart>) {
          convertedParts.addAll(converted);
        } else if (converted is List) {
          convertedParts.addAll(converted.whereType<A2aPart>());
        }

        if (convertedParts.isEmpty) {
          developer.log(
            'Failed to convert part to A2A format: $part',
            name: 'adk_dart.remote_a2a_agent',
          );
          continue;
        }
        messageParts.addAll(convertedParts);
      }
    }

    return (messageParts, contextId);
  }

  Future<Event?> _handleA2aResponse(
    Object a2aResponse,
    InvocationContext ctx,
  ) async {
    try {
      if (a2aResponse is A2aClientEvent) {
        final A2aTask task = a2aResponse.$1;
        final A2aEvent? update = a2aResponse.$2;
        late Event event;

        if (update == null) {
          event = convertA2aTaskToEvent(
            task,
            author: name,
            invocationContext: ctx,
            partConverter: _a2aPartConverter,
          );
          if ((task.status.state == A2aTaskState.submitted ||
                  task.status.state == A2aTaskState.working) &&
              event.content != null &&
              event.content!.parts.isNotEmpty) {
            for (final Part part in event.content!.parts) {
              part.thought = true;
            }
          }
        } else if (update is A2aTaskStatusUpdateEvent &&
            update.status.message != null) {
          event = convertA2aMessageToEvent(
            update.status.message!,
            author: name,
            invocationContext: ctx,
            partConverter: _a2aPartConverter,
          );
          if ((update.status.state == A2aTaskState.submitted ||
                  update.status.state == A2aTaskState.working) &&
              event.content != null) {
            for (final Part part in event.content!.parts) {
              part.thought = true;
            }
          }
        } else if (update is A2aTaskArtifactUpdateEvent &&
            (!update.append || update.lastChunk)) {
          event = convertA2aTaskToEvent(
            task,
            author: name,
            invocationContext: ctx,
            partConverter: _a2aPartConverter,
          );
        } else {
          return null;
        }

        event.customMetadata ??= <String, dynamic>{};
        event.customMetadata!['${a2aMetadataPrefix}task_id'] = task.id;
        if (task.contextId.isNotEmpty) {
          event.customMetadata!['${a2aMetadataPrefix}context_id'] =
              task.contextId;
        }
        return event;
      }

      if (a2aResponse is A2aMessage) {
        final Event event = convertA2aMessageToEvent(
          a2aResponse,
          author: name,
          invocationContext: ctx,
          partConverter: _a2aPartConverter,
        );
        event.customMetadata ??= <String, dynamic>{};
        if (a2aResponse.contextId != null &&
            a2aResponse.contextId!.isNotEmpty) {
          event.customMetadata!['${a2aMetadataPrefix}context_id'] =
              a2aResponse.contextId;
        }
        return event;
      }

      return Event(
        author: name,
        errorMessage: 'Unknown A2A response type',
        invocationId: ctx.invocationId,
        branch: ctx.branch,
      );
    } on A2aClientError catch (error) {
      developer.log(
        'Failed to handle A2A response: $error',
        name: 'adk_dart.remote_a2a_agent',
      );
      return Event(
        author: name,
        errorMessage: 'Failed to process A2A response: $error',
        invocationId: ctx.invocationId,
        branch: ctx.branch,
      );
    }
  }

  @override
  Stream<Event> runAsyncImpl(InvocationContext ctx) async* {
    try {
      await _ensureResolved();
    } catch (error) {
      yield Event(
        author: name,
        errorMessage: 'Failed to initialize remote A2A agent: $error',
        invocationId: ctx.invocationId,
        branch: ctx.branch,
      );
      return;
    }

    A2aMessage? a2aRequest = _createA2aRequestForUserFunctionResponse(ctx);
    if (a2aRequest == null) {
      final (List<A2aPart> messageParts, String? contextId) =
          _constructMessagePartsFromSession(ctx);
      if (messageParts.isEmpty) {
        developer.log(
          'No parts to send to remote A2A agent. Emitting empty event.',
          name: 'adk_dart.remote_a2a_agent',
        );
        yield Event(
          author: name,
          content: Content(),
          invocationId: ctx.invocationId,
          branch: ctx.branch,
        );
        return;
      }

      a2aRequest = A2aMessage(
        messageId: _newMessageId(),
        parts: messageParts,
        role: A2aRole.user,
        contextId: contextId,
      );
    }

    developer.log(
      buildA2aRequestLog(a2aRequest),
      name: 'adk_dart.remote_a2a_agent',
    );

    try {
      final Map<String, Object?>? requestMetadata = a2aRequestMetaProvider
          ?.call(ctx, a2aRequest);

      await for (final Object a2aResponse in _a2aClient!.sendMessage(
        request: a2aRequest,
        requestMetadata: requestMetadata,
        context: A2aClientCallContext(
          state: Map<String, Object?>.from(ctx.session.state),
        ),
      )) {
        developer.log(
          buildA2aResponseLog(_responseForLog(a2aResponse)),
          name: 'adk_dart.remote_a2a_agent',
        );

        final Event? event = await _handleA2aResponse(a2aResponse, ctx);
        if (event == null) {
          continue;
        }

        event.customMetadata ??= <String, dynamic>{};
        event.customMetadata!['${a2aMetadataPrefix}request'] = _pruneNulls(
          _a2aMessageToJson(a2aRequest),
        );

        if (a2aResponse is A2aClientEvent) {
          event.customMetadata!['${a2aMetadataPrefix}response'] = _pruneNulls(
            _a2aTaskToJson(a2aResponse.$1),
          );
        } else if (a2aResponse is A2aMessage) {
          event.customMetadata!['${a2aMetadataPrefix}response'] = _pruneNulls(
            _a2aMessageToJson(a2aResponse),
          );
        }

        yield event;
      }
    } on A2aClientHttpError catch (error) {
      final String message = 'A2A request failed: $error';
      yield Event(
        author: name,
        errorMessage: message,
        invocationId: ctx.invocationId,
        branch: ctx.branch,
        customMetadata: <String, dynamic>{
          '${a2aMetadataPrefix}request': _pruneNulls(
            _a2aMessageToJson(a2aRequest),
          ),
          '${a2aMetadataPrefix}error': message,
          '${a2aMetadataPrefix}status_code': '${error.statusCode ?? ''}',
        },
      );
    } catch (error) {
      final String message = 'A2A request failed: $error';
      yield Event(
        author: name,
        errorMessage: message,
        invocationId: ctx.invocationId,
        branch: ctx.branch,
        customMetadata: <String, dynamic>{
          '${a2aMetadataPrefix}request': _pruneNulls(
            _a2aMessageToJson(a2aRequest),
          ),
          '${a2aMetadataPrefix}error': message,
        },
      );
    }
  }

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    await for (final Event event in runAsyncImpl(context)) {
      yield event;
    }
  }

  Future<void> cleanup() async {
    if (_httpClientNeedsCleanup && _httpClient != null) {
      try {
        _httpClient!.close(force: true);
      } catch (error) {
        developer.log(
          'Failed to close HTTP client for agent `$name`: $error',
          name: 'adk_dart.remote_a2a_agent',
        );
      } finally {
        _httpClient = null;
      }
    }
  }
}

Object _responseForLog(Object response) {
  if (response is A2aClientEvent) {
    return response.$1;
  }
  return response;
}

bool _isOtherAgentReply(String currentAgentName, Event event) {
  return currentAgentName.isNotEmpty &&
      event.author != currentAgentName &&
      event.author != 'user';
}

Event? _presentOtherAgentMessage(Event event) {
  final Content? original = event.content;
  if (original == null || original.parts.isEmpty) {
    return event;
  }

  final Content content = Content(
    role: 'user',
    parts: <Part>[Part.text('For context:')],
  );
  for (final Part part in original.parts) {
    if (part.thought) {
      continue;
    }
    if (part.text != null && part.text!.trim().isNotEmpty) {
      content.parts.add(Part.text('[${event.author}] said: ${part.text}'));
      continue;
    }
    if (part.functionCall != null) {
      content.parts.add(
        Part.text(
          '[${event.author}] called tool `${part.functionCall!.name}` with '
          'parameters: ${part.functionCall!.args}',
        ),
      );
      continue;
    }
    if (part.functionResponse != null) {
      content.parts.add(
        Part.text(
          '[${event.author}] `${part.functionResponse!.name}` tool returned '
          'result: ${part.functionResponse!.response}',
        ),
      );
      continue;
    }
    if (part.codeExecutionResult != null) {
      content.parts.add(
        Part.text('[${event.author}] code execution result was provided.'),
      );
    }
  }

  if (content.parts.length == 1) {
    return null;
  }

  return Event(
    timestamp: event.timestamp,
    invocationId: event.invocationId,
    author: 'user',
    branch: event.branch,
    content: content,
  );
}

bool _isTruthy(Object? value) {
  if (value == null) {
    return false;
  }
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value.isNotEmpty;
  }
  if (value is Iterable) {
    return value.isNotEmpty;
  }
  if (value is Map) {
    return value.isNotEmpty;
  }
  return true;
}

String _newMessageId() {
  final int micros = DateTime.now().microsecondsSinceEpoch;
  return 'a2a_msg_$micros';
}

Map<String, Object?> _a2aMessageToJson(A2aMessage message) {
  return <String, Object?>{
    'message_id': message.messageId,
    'role': message.role.name,
    'parts': message.parts.map(_a2aPartToJson).toList(growable: false),
    'task_id': message.taskId,
    'context_id': message.contextId,
    'metadata': message.metadata.isEmpty
        ? null
        : _toStringObjectMap(message.metadata),
  };
}

Map<String, Object?> _a2aTaskToJson(A2aTask task) {
  return <String, Object?>{
    'id': task.id,
    'context_id': task.contextId,
    'status': _a2aTaskStatusToJson(task.status),
    'history': task.history.map(_a2aMessageToJson).toList(growable: false),
    'artifacts': task.artifacts.map(_a2aArtifactToJson).toList(growable: false),
    'metadata': task.metadata.isEmpty
        ? null
        : _toStringObjectMap(task.metadata),
  };
}

Map<String, Object?> _a2aTaskStatusToJson(A2aTaskStatus status) {
  return <String, Object?>{
    'state': status.state.name,
    'timestamp': status.timestamp,
    'message': status.message == null
        ? null
        : _a2aMessageToJson(status.message!),
  };
}

Map<String, Object?> _a2aArtifactToJson(A2aArtifact artifact) {
  return <String, Object?>{
    'artifact_id': artifact.artifactId,
    'parts': artifact.parts.map(_a2aPartToJson).toList(growable: false),
  };
}

Map<String, Object?> _a2aPartToJson(A2aPart part) {
  final A2aPartRoot root = part.root;
  if (root is A2aTextPart) {
    return <String, Object?>{
      'kind': 'text',
      'text': root.text,
      'metadata': root.metadata.isEmpty
          ? null
          : _toStringObjectMap(root.metadata),
    };
  }
  if (root is A2aDataPart) {
    return <String, Object?>{
      'kind': 'data',
      'data': _toStringObjectMap(root.data),
      'metadata': root.metadata.isEmpty
          ? null
          : _toStringObjectMap(root.metadata),
    };
  }
  if (root is A2aFilePart) {
    return <String, Object?>{
      'kind': 'file',
      'file': _a2aFileToJson(root.file),
      'metadata': root.metadata.isEmpty
          ? null
          : _toStringObjectMap(root.metadata),
    };
  }
  return <String, Object?>{
    'kind': root.runtimeType.toString(),
    'metadata': root.metadata.isEmpty
        ? null
        : _toStringObjectMap(root.metadata),
  };
}

Map<String, Object?> _a2aFileToJson(A2aFile file) {
  if (file is A2aFileWithUri) {
    return <String, Object?>{'uri': file.uri, 'mime_type': file.mimeType};
  }
  if (file is A2aFileWithBytes) {
    return <String, Object?>{'bytes': file.bytes, 'mime_type': file.mimeType};
  }
  return <String, Object?>{'mime_type': file.mimeType};
}

Map<String, Object?> _toStringObjectMap(Map value) {
  final Map<String, Object?> result = <String, Object?>{};
  value.forEach((Object? key, Object? value) {
    result['$key'] = _normalizeJsonValue(value);
  });
  return result;
}

Object? _normalizeJsonValue(Object? value) {
  if (value is Map) {
    return _toStringObjectMap(value);
  }
  if (value is List) {
    return value.map(_normalizeJsonValue).toList(growable: false);
  }
  if (value is num || value is bool || value is String || value == null) {
    return value;
  }
  return '$value';
}

Object? _pruneNulls(Object? value) {
  if (value is Map) {
    final Map<String, Object?> result = <String, Object?>{};
    value.forEach((Object? key, Object? innerValue) {
      final Object? normalized = _pruneNulls(innerValue);
      if (normalized != null) {
        result['$key'] = normalized;
      }
    });
    return result;
  }

  if (value is List) {
    final List<Object?> out = <Object?>[];
    for (final Object? item in value) {
      final Object? normalized = _pruneNulls(item);
      if (normalized != null) {
        out.add(normalized);
      }
    }
    return out;
  }

  return value;
}
