import '../../agents/invocation_context.dart';
import '../../events/event.dart';
import '../../flows/llm_flows/functions.dart';
import '../../types/content.dart';
import '../protocol.dart';
import 'part_converter.dart';
import 'utils.dart';

const String artifactIdSeparator = '-';
const String defaultErrorMessage = 'An error occurred during processing';

typedef AdkEventToA2AEventsConverter =
    List<A2aEvent> Function(
      Event event,
      InvocationContext invocationContext,
      String? taskId,
      String? contextId,
      GenAIPartToA2APartConverter partConverter,
    );

Object _serializeMetadataValue(Object value) {
  if (value is Map || value is List || value is num || value is bool) {
    return value;
  }
  return '$value';
}

Map<String, Object?> _getContextMetadata(
  Event event,
  InvocationContext invocationContext,
) {
  final Map<String, Object?> metadata = <String, Object?>{
    getAdkMetadataKey('app_name'): invocationContext.appName,
    getAdkMetadataKey('user_id'): invocationContext.userId,
    getAdkMetadataKey('session_id'): invocationContext.session.id,
    getAdkMetadataKey('invocation_id'): event.invocationId,
    getAdkMetadataKey('author'): event.author,
    getAdkMetadataKey('event_id'): event.id,
  };

  final Map<String, Object?> optional = <String, Object?>{
    'branch': event.branch,
    'custom_metadata': event.customMetadata,
    'usage_metadata': event.usageMetadata,
    'error_code': event.errorCode,
    'actions': event.actions,
  };

  optional.forEach((String key, Object? value) {
    if (value != null) {
      metadata[getAdkMetadataKey(key)] = _serializeMetadataValue(value);
    }
  });

  return metadata;
}

String createArtifactId(
  String appName,
  String userId,
  String sessionId,
  String filename,
  int version,
) {
  return <String>[
    appName,
    userId,
    sessionId,
    filename,
    '$version',
  ].join(artifactIdSeparator);
}

void _processLongRunningTool(A2aPart a2aPart, Event event) {
  final A2aDataPart? dataPart = a2aPart.dataPart;
  if (dataPart == null || event.longRunningToolIds == null) {
    return;
  }

  if (dataPart.metadata[getAdkMetadataKey(a2aDataPartMetadataTypeKey)] !=
      a2aDataPartMetadataTypeFunctionCall) {
    return;
  }

  final String? id = dataPart.data['id'] as String?;
  if (id == null || !event.longRunningToolIds!.contains(id)) {
    return;
  }

  dataPart.metadata[getAdkMetadataKey(a2aDataPartMetadataIsLongRunningKey)] =
      true;
}

Event convertA2aTaskToEvent(
  A2aTask a2aTask, {
  String? author,
  InvocationContext? invocationContext,
  A2APartToGenAIPartConverter partConverter = convertA2aPartToGenaiPart,
}) {
  A2aMessage? message;
  if (a2aTask.artifacts.isNotEmpty) {
    message = A2aMessage(
      messageId: '',
      role: A2aRole.agent,
      parts: List<A2aPart>.from(a2aTask.artifacts.last.parts),
    );
  } else if (a2aTask.status.message != null &&
      a2aTask.status.message!.parts.isNotEmpty) {
    message = a2aTask.status.message;
  } else if (a2aTask.history.isNotEmpty) {
    message = a2aTask.history.last;
  }

  if (message != null) {
    return convertA2aMessageToEvent(
      message,
      author: author,
      invocationContext: invocationContext,
      partConverter: partConverter,
    );
  }

  final String invocationId =
      invocationContext?.invocationId ??
      'a2a_invocation_${DateTime.now().microsecondsSinceEpoch}';

  return Event(
    invocationId: invocationId,
    author: author ?? 'a2a_agent',
    branch: invocationContext?.branch,
  );
}

Event convertA2aMessageToEvent(
  A2aMessage a2aMessage, {
  String? author,
  InvocationContext? invocationContext,
  A2APartToGenAIPartConverter partConverter = convertA2aPartToGenaiPart,
}) {
  final String invocationId =
      invocationContext?.invocationId ??
      'a2a_invocation_${DateTime.now().microsecondsSinceEpoch}';

  if (a2aMessage.parts.isEmpty) {
    return Event(
      invocationId: invocationId,
      author: author ?? 'a2a_agent',
      branch: invocationContext?.branch,
      content: Content(role: 'model', parts: <Part>[]),
    );
  }

  final List<Part> outputParts = <Part>[];
  final Set<String> longRunningToolIds = <String>{};

  for (final A2aPart a2aPart in a2aMessage.parts) {
    final Object? converted = partConverter(a2aPart);
    final List<Part> parts = <Part>[];

    if (converted is Part) {
      parts.add(converted);
    } else if (converted is List<Part>) {
      parts.addAll(converted);
    }

    for (final Part part in parts) {
      if (a2aPart.root.metadata[getAdkMetadataKey(
                a2aDataPartMetadataIsLongRunningKey,
              )] ==
              true &&
          part.functionCall?.id != null) {
        longRunningToolIds.add(part.functionCall!.id!);
      }
      outputParts.add(part);
    }
  }

  return Event(
    invocationId: invocationId,
    author: author ?? 'a2a_agent',
    branch: invocationContext?.branch,
    longRunningToolIds: longRunningToolIds.isEmpty ? null : longRunningToolIds,
    content: Content(role: 'model', parts: outputParts),
  );
}

A2aMessage? convertEventToA2aMessage(
  Event event,
  InvocationContext invocationContext, {
  A2aRole role = A2aRole.agent,
  GenAIPartToA2APartConverter partConverter = convertGenaiPartToA2aPart,
}) {
  final Content? content = event.content;
  if (content == null || content.parts.isEmpty) {
    return null;
  }

  final List<A2aPart> outputParts = <A2aPart>[];
  for (final Part part in content.parts) {
    final Object? converted = partConverter(part);
    if (converted is A2aPart) {
      outputParts.add(converted);
      _processLongRunningTool(converted, event);
      continue;
    }

    if (converted is List<A2aPart>) {
      for (final A2aPart p in converted) {
        outputParts.add(p);
        _processLongRunningTool(p, event);
      }
    }
  }

  if (outputParts.isEmpty) {
    return null;
  }

  return A2aMessage(
    messageId: 'a2a_msg_${DateTime.now().microsecondsSinceEpoch}',
    role: role,
    parts: outputParts,
  );
}

A2aTaskStatusUpdateEvent _createErrorStatusEvent(
  Event event,
  InvocationContext invocationContext,
  String? taskId,
  String? contextId,
) {
  final String message = event.errorMessage ?? defaultErrorMessage;
  final Map<String, Object?> metadata = _getContextMetadata(
    event,
    invocationContext,
  );

  if (event.errorCode != null) {
    metadata[getAdkMetadataKey('error_code')] = event.errorCode;
  }

  return A2aTaskStatusUpdateEvent(
    taskId: taskId,
    contextId: contextId,
    metadata: metadata,
    status: A2aTaskStatus(
      state: A2aTaskState.failed,
      message: A2aMessage(
        messageId: 'a2a_err_${DateTime.now().microsecondsSinceEpoch}',
        role: A2aRole.agent,
        parts: <A2aPart>[A2aPart.text(message)],
        metadata: event.errorCode == null
            ? <String, Object?>{}
            : <String, Object?>{
                getAdkMetadataKey('error_code'): event.errorCode,
              },
      ),
    ),
    finalEvent: false,
  );
}

A2aTaskStatusUpdateEvent _createStatusUpdateEvent(
  A2aMessage message,
  InvocationContext invocationContext,
  Event event,
  String? taskId,
  String? contextId,
) {
  A2aTaskState state = A2aTaskState.working;

  for (final A2aPart part in message.parts) {
    final A2aDataPart? dataPart = part.dataPart;
    if (dataPart == null) {
      continue;
    }
    final Object? type =
        dataPart.metadata[getAdkMetadataKey(a2aDataPartMetadataTypeKey)];
    final bool isLongRunning =
        dataPart.metadata[getAdkMetadataKey(
          a2aDataPartMetadataIsLongRunningKey,
        )] ==
        true;

    if (type == a2aDataPartMetadataTypeFunctionCall && isLongRunning) {
      if (dataPart.data['name'] == requestEucFunctionCallName) {
        state = A2aTaskState.authRequired;
        break;
      }
      state = A2aTaskState.inputRequired;
    }
  }

  return A2aTaskStatusUpdateEvent(
    taskId: taskId,
    contextId: contextId,
    status: A2aTaskStatus(state: state, message: message),
    metadata: _getContextMetadata(event, invocationContext),
    finalEvent: false,
  );
}

List<A2aEvent> convertEventToA2aEvents(
  Event event,
  InvocationContext invocationContext, {
  String? taskId,
  String? contextId,
  GenAIPartToA2APartConverter partConverter = convertGenaiPartToA2aPart,
}) {
  final List<A2aEvent> events = <A2aEvent>[];

  if (event.errorCode != null) {
    events.add(
      _createErrorStatusEvent(event, invocationContext, taskId, contextId),
    );
  }

  final A2aMessage? message = convertEventToA2aMessage(
    event,
    invocationContext,
    partConverter: partConverter,
  );
  if (message != null) {
    events.add(
      _createStatusUpdateEvent(
        message,
        invocationContext,
        event,
        taskId,
        contextId,
      ),
    );
  }

  return events;
}
