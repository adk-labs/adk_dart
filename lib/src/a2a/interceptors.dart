/// Request, card, and execution interceptors for A2A agents and executors.
library;

import 'dart:async';

import '../agents/invocation_context.dart';
import '../artifacts/base_artifact_service.dart';
import '../events/event.dart';
import '../runners/runner.dart';
import '../types/content.dart';
import 'converters/part_converter.dart';
import 'protocol.dart';

/// Standard HTTP header used to advertise A2A extensions.
const String a2aHttpExtensionHeader = 'X-A2A-Extensions';

/// URI identifying the ADK A2A integration extension.
const String newA2aAdkIntegrationExtension =
    'https://google.github.io/adk-docs/a2a/a2a-extension/';

/// Mutable call context passed to A2A client transports.
class A2aClientCallContext {
  /// Creates an [A2aClientCallContext].
  A2aClientCallContext({Map<String, Object?>? state})
    : state = state ?? <String, Object?>{};

  /// Arbitrary transport state (such as `http_kwargs`).
  final Map<String, Object?> state;
}

/// Parameters configuration passed through A2A request interceptors.
class ParametersConfig {
  /// Creates a [ParametersConfig].
  ParametersConfig({
    this.clientCallContext,
    Map<String, Object?>? requestMetadata,
  }) : requestMetadata = requestMetadata ?? <String, Object?>{};

  /// Optional client call context holding HTTP headers and transport options.
  A2aClientCallContext? clientCallContext;

  /// Metadata dictionary attached to the outgoing A2A request.
  final Map<String, Object?> requestMetadata;
}

/// Configuration for fetching an A2A agent card.
class A2aCardRequestConfig {
  /// Creates an [A2aCardRequestConfig].
  A2aCardRequestConfig({
    this.url,
    Map<String, String>? headers,
    this.timeout,
  }) : headers = headers ?? <String, String>{};

  /// Optional override URL for fetching the agent card.
  String? url;

  /// HTTP headers sent when requesting the agent card.
  final Map<String, String> headers;

  /// Optional request timeout.
  Duration? timeout;
}

/// Interceptor invoked before/after fetching an A2A agent card.
class CardRequestInterceptor {
  /// Creates a [CardRequestInterceptor].
  const CardRequestInterceptor({
    this.beforeRequest,
    this.afterRequest,
  });

  /// Callback invoked before requesting the agent card.
  final FutureOr<A2aCardRequestConfig> Function(A2aCardRequestConfig config)?
  beforeRequest;

  /// Callback invoked after receiving the agent card.
  final FutureOr<AgentCard> Function(AgentCard card)? afterRequest;
}

/// Interceptor invoked before/after sending an A2A message request.
///
/// ```dart
/// final interceptor = newIntegrationExtensionInterceptor;
/// ```
class RequestInterceptor {
  /// Creates a [RequestInterceptor].
  const RequestInterceptor({
    this.beforeRequest,
    this.afterRequest,
  });

  /// Callback invoked before sending an [A2aMessage].
  ///
  /// Returns a record of `(messageOrShortCircuitEvent, updatedParams)`.
  final FutureOr<(Object, ParametersConfig)> Function(
    InvocationContext context,
    A2aMessage a2aRequest,
    ParametersConfig params,
  )?
  beforeRequest;

  /// Callback invoked after receiving an A2A response event.
  final FutureOr<Event?> Function(
    InvocationContext context,
    Object a2aResponse,
    Event? adkEvent,
  )?
  afterRequest;
}

/// Execution context exposed to [ExecuteInterceptor] callbacks.
class ExecutorContext {
  /// Creates an [ExecutorContext].
  const ExecutorContext({
    required this.appName,
    required this.userId,
    required this.sessionId,
    required this.runner,
  });

  /// Active application name.
  final String appName;

  /// Active user ID.
  final String userId;

  /// Active session ID.
  final String sessionId;

  /// Runner executing the ADK agent.
  final Runner runner;
}

/// Interceptor invoked around A2A agent executor event emission.
class ExecuteInterceptor {
  /// Creates an [ExecuteInterceptor].
  const ExecuteInterceptor({
    this.beforeAgent,
    this.afterEvent,
    this.afterAgent,
  });

  /// Optional callback invoked before agent execution starts.
  final FutureOr<void> Function(ExecutorContext context)? beforeAgent;

  /// Optional callback invoked after each ADK event is converted to an A2A event.
  ///
  /// May return a single A2A event (`A2aTaskStatusUpdateEvent` or
  /// `A2aTaskArtifactUpdateEvent`) or a `List<Object>` of A2A events.
  final FutureOr<Object> Function(
    ExecutorContext context,
    Object a2aEvent,
    Event adkEvent,
  )?
  afterEvent;

  /// Optional callback invoked after agent execution finishes.
  final FutureOr<void> Function(ExecutorContext context)? afterAgent;
}

Future<(Object, ParametersConfig)> _injectIntegrationExtensionBeforeRequest(
  InvocationContext _,
  A2aMessage a2aRequest,
  ParametersConfig params,
) async {
  params.clientCallContext ??= A2aClientCallContext();
  final Map<String, Object?> httpKwargs =
      (params.clientCallContext!.state['http_kwargs'] is Map)
      ? Map<String, Object?>.from(
          params.clientCallContext!.state['http_kwargs'] as Map,
        )
      : <String, Object?>{};
  final Map<String, String> headers = (httpKwargs['headers'] is Map)
      ? (httpKwargs['headers'] as Map).map(
          (Object? k, Object? v) => MapEntry('$k', '$v'),
        )
      : <String, String>{};
  final List<String> extensions = (headers[a2aHttpExtensionHeader] ?? '')
      .split(',')
      .map((String e) => e.trim())
      .where((String e) => e.isNotEmpty)
      .toList();
  if (!extensions.contains(newA2aAdkIntegrationExtension)) {
    extensions.add(newA2aAdkIntegrationExtension);
  }
  headers[a2aHttpExtensionHeader] = extensions.join(',');
  httpKwargs['headers'] = headers;
  params.clientCallContext!.state['http_kwargs'] = httpKwargs;
  return (a2aRequest, params);
}

/// Built-in [RequestInterceptor] that injects the ADK A2A integration extension header.
const RequestInterceptor newIntegrationExtensionInterceptor =
    RequestInterceptor(beforeRequest: _injectIntegrationExtensionBeforeRequest);

Future<Object> _includeArtifactsAfterEvent(
  ExecutorContext ctx,
  Object a2aEvent,
  Event adkEvent,
) async {
  String? taskId;
  String? contextId;
  Map<String, Object?>? metadata;

  if (a2aEvent is A2aTaskStatusUpdateEvent) {
    taskId = a2aEvent.taskId;
    contextId = a2aEvent.contextId;
    metadata = a2aEvent.metadata;
  } else if (a2aEvent is A2aTaskArtifactUpdateEvent) {
    taskId = a2aEvent.taskId;
    contextId = a2aEvent.contextId;
    metadata = a2aEvent.artifact.metadata;
  } else {
    return a2aEvent;
  }

  final BaseArtifactService? artifactService = ctx.runner.artifactService;
  if (artifactService == null || adkEvent.actions.artifactDelta.isEmpty) {
    return a2aEvent;
  }

  final List<Object> newEvents = <Object>[];
  for (final MapEntry<String, int> entry
      in adkEvent.actions.artifactDelta.entries) {
    final String filename = entry.key;
    final int version = entry.value;
    final Part? genaiPart = await artifactService.loadArtifact(
      appName: ctx.appName,
      userId: ctx.userId,
      sessionId: ctx.sessionId,
      filename: filename,
      version: version,
    );
    if (genaiPart != null) {
      final Object? converted = convertGenaiPartToA2aPart(genaiPart);
      final A2aPart? a2aPart = converted is A2aPart ? converted : null;
      if (a2aPart != null) {
        final A2aArtifact artifact = A2aArtifact(
          artifactId: '${filename}_$version',
          parts: <A2aPart>[a2aPart],
          metadata: <String, Object?>{
            'name': filename,
            ...metadata,
          },
        );
        newEvents.add(
          A2aTaskArtifactUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            artifact: artifact,
            append: false,
            lastChunk: true,
          ),
        );
      }
    }
  }

  adkEvent.actions.artifactDelta.clear();
  if (newEvents.isNotEmpty) {
    return <Object>[a2aEvent, ...newEvents];
  }
  return a2aEvent;
}

/// Built-in [ExecuteInterceptor] that emits `A2aTaskArtifactUpdateEvent`s for
/// artifacts recorded in `adkEvent.actions.artifactDelta`.
const ExecuteInterceptor includeArtifactsInA2aEventInterceptor =
    ExecuteInterceptor(afterEvent: _includeArtifactsAfterEvent);
