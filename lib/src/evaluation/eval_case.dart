/// Evaluation case and invocation data models.
library;

import 'app_details.dart';
import 'common.dart';
import 'conversation_scenarios.dart';

/// Canonical JSON map type for evaluation payloads.
typedef EvalJsonMap = Map<String, Object?>;

/// Intermediate tool-use and response payloads for an invocation.
class IntermediateData {
  /// Creates intermediate invocation data.
  IntermediateData({
    List<EvalJsonMap>? toolUses,
    List<EvalJsonMap>? toolResponses,
    List<InvocationResponse>? intermediateResponses,
  }) : toolUses = toolUses ?? <EvalJsonMap>[],
       toolResponses = toolResponses ?? <EvalJsonMap>[],
       intermediateResponses = intermediateResponses ?? <InvocationResponse>[];

  /// Tool-call payloads.
  final List<EvalJsonMap> toolUses;

  /// Tool-response payloads.
  final List<EvalJsonMap> toolResponses;

  /// Intermediate model responses.
  final List<InvocationResponse> intermediateResponses;

  /// Creates intermediate data from JSON.
  factory IntermediateData.fromJson(EvalJsonMap json) {
    return IntermediateData(
      toolUses: asEvalJsonList(json['toolUses'] ?? json['tool_uses']),
      toolResponses: asEvalJsonList(
        json['toolResponses'] ?? json['tool_responses'],
      ),
      intermediateResponses:
          asObjectList(
            json['intermediateResponses'] ?? json['intermediate_responses'],
          ).map((Object? value) {
            return InvocationResponse.fromJson(asEvalJson(value));
          }).toList(),
    );
  }

  /// Serializes intermediate data to JSON.
  EvalJsonMap toJson() {
    return <String, Object?>{
      'tool_uses': toolUses,
      'tool_responses': toolResponses,
      'intermediate_responses': intermediateResponses
          .map((InvocationResponse value) => value.toJson())
          .toList(),
    };
  }
}

/// One intermediate model response.
class InvocationResponse {
  /// Creates an invocation response.
  InvocationResponse({required this.author, List<EvalJsonMap>? parts})
    : parts = parts ?? <EvalJsonMap>[];

  /// Response author.
  final String author;

  /// Response parts.
  final List<EvalJsonMap> parts;

  /// Creates invocation response from JSON.
  factory InvocationResponse.fromJson(EvalJsonMap json) {
    return InvocationResponse(
      author: asNullableString(json['author']) ?? '',
      parts: asEvalJsonList(json['parts']),
    );
  }

  /// Serializes invocation response to JSON.
  EvalJsonMap toJson() => <String, Object?>{'author': author, 'parts': parts};
}

/// One invocation event entry.
class InvocationEvent {
  /// Creates an invocation event.
  InvocationEvent({required this.author, this.content});

  /// Event author.
  final String author;

  /// Optional content payload.
  final EvalJsonMap? content;

  /// Creates invocation event from JSON.
  factory InvocationEvent.fromJson(EvalJsonMap json) {
    return InvocationEvent(
      author: asNullableString(json['author']) ?? '',
      content: json['content'] == null ? null : asEvalJson(json['content']),
    );
  }

  /// Serializes invocation event to JSON.
  EvalJsonMap toJson() {
    return <String, Object?>{
      'author': author,
      if (content != null) 'content': content,
    };
  }
}

/// Collection of invocation events.
class InvocationEvents {
  /// Creates invocation events container.
  InvocationEvents({List<InvocationEvent>? invocationEvents})
    : invocationEvents = invocationEvents ?? <InvocationEvent>[];

  /// Invocation events.
  final List<InvocationEvent> invocationEvents;

  /// Creates invocation events from JSON.
  factory InvocationEvents.fromJson(EvalJsonMap json) {
    return InvocationEvents(
      invocationEvents:
          asObjectList(
            json['invocationEvents'] ?? json['invocation_events'],
          ).map((Object? value) {
            return InvocationEvent.fromJson(asEvalJson(value));
          }).toList(),
    );
  }

  /// Serializes invocation events to JSON.
  EvalJsonMap toJson() {
    return <String, Object?>{
      'invocation_events': invocationEvents
          .map((InvocationEvent value) => value.toJson())
          .toList(),
    };
  }
}

/// One invocation inside an eval conversation.
class Invocation {
  /// Creates an invocation model.
  Invocation({
    this.invocationId = '',
    required this.userContent,
    this.finalResponse,
    this.intermediateData,
    this.creationTimestamp = 0,
    List<EvalJsonMap>? rubrics,
    this.appDetails,
  }) : rubrics = rubrics ?? <EvalJsonMap>[];

  /// Invocation identifier.
  final String invocationId;

  /// User content payload.
  final EvalJsonMap userContent;

  /// Optional final response payload.
  final EvalJsonMap? finalResponse;

  /// Optional intermediate data payload.
  final Object? intermediateData;

  /// Creation timestamp in seconds since epoch.
  final double creationTimestamp;

  /// Invocation rubrics.
  final List<EvalJsonMap> rubrics;

  /// Optional app details metadata.
  final AppDetails? appDetails;

  /// Creates invocation from JSON.
  factory Invocation.fromJson(EvalJsonMap json) {
    if (json.containsKey('query')) {
      final String query = asNullableString(json['query']) ?? '';
      final String reference = asNullableString(json['reference']) ?? '';
      return Invocation(
        invocationId: '',
        userContent: _contentFromText(role: 'user', text: query),
        finalResponse: _contentFromText(role: 'model', text: reference),
      );
    }

    final Object? rawIntermediate =
        json['intermediateData'] ?? json['intermediate_data'];

    return Invocation(
      invocationId:
          asNullableString(json['invocationId']) ??
          asNullableString(json['invocation_id']) ??
          '',
      userContent: asEvalJson(json['userContent'] ?? json['user_content']),
      finalResponse:
          json['finalResponse'] == null && json['final_response'] == null
          ? null
          : asEvalJson(json['finalResponse'] ?? json['final_response']),
      intermediateData: _parseIntermediateData(rawIntermediate),
      creationTimestamp: asDoubleOr(
        json['creationTimestamp'] ?? json['creation_timestamp'],
      ),
      rubrics: asEvalJsonList(json['rubrics']),
      appDetails: json['appDetails'] == null && json['app_details'] == null
          ? null
          : AppDetails.fromJson(
              asEvalJson(json['appDetails'] ?? json['app_details']),
            ),
    );
  }

  /// Serializes invocation to JSON.
  EvalJsonMap toJson() {
    return <String, Object?>{
      'invocation_id': invocationId,
      'user_content': userContent,
      if (finalResponse != null) 'final_response': finalResponse,
      if (intermediateData is IntermediateData)
        'intermediate_data': (intermediateData as IntermediateData).toJson(),
      if (intermediateData is InvocationEvents)
        'intermediate_data': (intermediateData as InvocationEvents).toJson(),
      if (intermediateData is! IntermediateData &&
          intermediateData is! InvocationEvents &&
          intermediateData != null)
        'intermediate_data': intermediateData,
      'creation_timestamp': creationTimestamp,
      if (rubrics.isNotEmpty) 'rubrics': rubrics,
      if (appDetails != null) 'app_details': appDetails!.toJson(),
    };
  }
}

/// Session initialization payload used by eval runs.
class SessionInput {
  /// Creates session input.
  SessionInput({
    required this.appName,
    required this.userId,
    EvalJsonMap? state,
  }) : state = state ?? <String, Object?>{};

  /// App name for session creation.
  final String appName;

  /// User ID for session creation.
  final String userId;

  /// Initial session state.
  final EvalJsonMap state;

  /// Creates session input from JSON.
  factory SessionInput.fromJson(EvalJsonMap json) {
    return SessionInput(
      appName:
          asNullableString(json['appName']) ??
          asNullableString(json['app_name']) ??
          '',
      userId:
          asNullableString(json['userId']) ??
          asNullableString(json['user_id']) ??
          '',
      state: asEvalJson(json['state']),
    );
  }

  /// Serializes session input to JSON.
  EvalJsonMap toJson() {
    return <String, Object?>{
      'app_name': appName,
      'user_id': userId,
      'state': state,
    };
  }
}

/// One evaluation case definition.
class EvalCase {
  /// Creates an eval case.
  EvalCase({
    required this.evalId,
    this.input = '',
    this.expectedOutput,
    this.conversation,
    this.conversationScenario,
    this.sessionInput,
    this.creationTimestamp = 0,
    List<EvalJsonMap>? rubrics,
    EvalJsonMap? finalSessionState,
    EvalJsonMap? metadata,
  }) : rubrics = rubrics ?? <EvalJsonMap>[],
       finalSessionState = finalSessionState ?? <String, Object?>{},
       metadata = metadata ?? <String, Object?>{} {
    if (conversation != null && conversationScenario != null) {
      throw ArgumentError(
        'Only one of conversation and conversationScenario can be set.',
      );
    }
  }

  /// Eval case identifier.
  final String evalId;

  /// Primary input text.
  final String input;

  /// Optional expected output.
  final String? expectedOutput;

  /// Optional explicit conversation transcript.
  final List<Invocation>? conversation;

  /// Optional generated conversation scenario.
  final ConversationScenario? conversationScenario;

  /// Optional session initialization payload.
  final SessionInput? sessionInput;

  /// Creation timestamp in seconds since epoch.
  final double creationTimestamp;

  /// Eval rubrics.
  final List<EvalJsonMap> rubrics;

  /// Expected final session state.
  final EvalJsonMap finalSessionState;

  /// Additional case metadata.
  final EvalJsonMap metadata;

  /// Creates an eval case from JSON.
  factory EvalCase.fromJson(EvalJsonMap json) {
    final List<Invocation>? conversation = _readConversation(json);
    final String inferredInput = _inferInput(json, conversation);
    final String? inferredExpectedOutput = _inferExpectedOutput(
      json,
      conversation,
    );
    return EvalCase(
      evalId:
          asNullableString(json['evalId']) ??
          asNullableString(json['eval_id']) ??
          asNullableString(json['name']) ??
          '',
      input: inferredInput,
      expectedOutput: inferredExpectedOutput,
      conversation: conversation,
      conversationScenario:
          json['conversationScenario'] == null &&
              json['conversation_scenario'] == null
          ? null
          : ConversationScenario.fromJson(
              asEvalJson(
                json['conversationScenario'] ?? json['conversation_scenario'],
              ),
            ),
      sessionInput:
          json['sessionInput'] == null && json['session_input'] == null
          ? null
          : SessionInput.fromJson(
              asEvalJson(json['sessionInput'] ?? json['session_input']),
            ),
      creationTimestamp: asDoubleOr(
        json['creationTimestamp'] ?? json['creation_timestamp'],
      ),
      rubrics: asEvalJsonList(json['rubrics']),
      finalSessionState: asEvalJson(
        json['finalSessionState'] ?? json['final_session_state'],
      ),
      metadata: asEvalJson(json['metadata']),
    );
  }

  /// Serializes eval case to JSON.
  EvalJsonMap toJson() {
    return <String, Object?>{
      'eval_id': evalId,
      if (input.isNotEmpty) 'input': input,
      if (expectedOutput != null) 'expected_output': expectedOutput,
      if (conversation != null)
        'conversation': conversation!
            .map((Invocation value) => value.toJson())
            .toList(),
      if (conversationScenario != null)
        'conversation_scenario': conversationScenario!.toJson(),
      if (sessionInput != null) 'session_input': sessionInput!.toJson(),
      if (creationTimestamp != 0) 'creation_timestamp': creationTimestamp,
      if (rubrics.isNotEmpty) 'rubrics': rubrics,
      if (finalSessionState.isNotEmpty)
        'final_session_state': finalSessionState,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

/// Returns all tool-call payloads from [intermediateData].
List<EvalJsonMap> getAllToolCalls(Object? intermediateData) {
  if (intermediateData == null) {
    return <EvalJsonMap>[];
  }
  if (intermediateData is IntermediateData) {
    return intermediateData.toolUses;
  }
  if (intermediateData is InvocationEvents) {
    final List<EvalJsonMap> calls = <EvalJsonMap>[];
    for (final InvocationEvent event in intermediateData.invocationEvents) {
      final EvalJsonMap? content = event.content;
      if (content == null) {
        continue;
      }
      calls.addAll(_extractFunctionCallsFromContent(content));
    }
    return calls;
  }
  if (intermediateData is Map) {
    final EvalJsonMap data = asEvalJson(intermediateData);
    if (data.containsKey('invocation_events') ||
        data.containsKey('invocationEvents')) {
      return getAllToolCalls(InvocationEvents.fromJson(data));
    }
    return asEvalJsonList(data['tool_uses'] ?? data['toolUses']);
  }
  throw ArgumentError(
    'Unsupported type for intermediateData `${intermediateData.runtimeType}`',
  );
}

/// Returns all tool-response payloads from [intermediateData].
List<EvalJsonMap> getAllToolResponses(Object? intermediateData) {
  if (intermediateData == null) {
    return <EvalJsonMap>[];
  }
  if (intermediateData is IntermediateData) {
    return intermediateData.toolResponses;
  }
  if (intermediateData is InvocationEvents) {
    final List<EvalJsonMap> responses = <EvalJsonMap>[];
    for (final InvocationEvent event in intermediateData.invocationEvents) {
      final EvalJsonMap? content = event.content;
      if (content == null) {
        continue;
      }
      responses.addAll(_extractFunctionResponsesFromContent(content));
    }
    return responses;
  }
  if (intermediateData is Map) {
    final EvalJsonMap data = asEvalJson(intermediateData);
    if (data.containsKey('invocation_events') ||
        data.containsKey('invocationEvents')) {
      return getAllToolResponses(InvocationEvents.fromJson(data));
    }
    return asEvalJsonList(data['tool_responses'] ?? data['toolResponses']);
  }
  throw ArgumentError(
    'Unsupported type for intermediateData `${intermediateData.runtimeType}`',
  );
}

/// Returns tool calls paired with optional matching responses.
List<(EvalJsonMap, EvalJsonMap?)> getAllToolCallsWithResponses(
  Object? intermediateData,
) {
  final List<EvalJsonMap> toolCalls = getAllToolCalls(intermediateData);
  final List<EvalJsonMap> toolResponses = getAllToolResponses(intermediateData);
  final Map<String, EvalJsonMap> byId = <String, EvalJsonMap>{};
  for (final EvalJsonMap response in toolResponses) {
    final String? idValue = asNullableString(response['id']);
    if (idValue != null && idValue.isNotEmpty) {
      byId[idValue] = response;
    }
  }

  final List<(EvalJsonMap, EvalJsonMap?)> result =
      <(EvalJsonMap, EvalJsonMap?)>[];
  for (final EvalJsonMap call in toolCalls) {
    final String? idValue = asNullableString(call['id']);
    if (idValue != null && idValue.isNotEmpty) {
      result.add((call, byId[idValue]));
    } else {
      result.add((call, null));
    }
  }
  return result;
}

List<Invocation>? _readConversation(EvalJsonMap json) {
  final Object? rawConversation = json['conversation'];
  if (rawConversation is List) {
    return rawConversation.map((Object? item) {
      return Invocation.fromJson(asEvalJson(item));
    }).toList();
  }

  // Legacy eval case format uses top-level query/reference.
  if (json.containsKey('query') || json.containsKey('reference')) {
    return <Invocation>[
      Invocation.fromJson(<String, Object?>{
        'query': asNullableString(json['query']) ?? '',
        'reference': asNullableString(json['reference']) ?? '',
      }),
    ];
  }

  return null;
}

String _inferInput(EvalJsonMap json, List<Invocation>? conversation) {
  final String? rawInput = asNullableString(json['input']);
  if (rawInput != null) {
    return rawInput;
  }
  final String? legacyQuery = asNullableString(json['query']);
  if (legacyQuery != null) {
    return legacyQuery;
  }
  if (conversation != null && conversation.isNotEmpty) {
    final EvalJsonMap userContent = conversation.first.userContent;
    final List<Object?> parts = asObjectList(userContent['parts']);
    for (final Object? part in parts) {
      final String? text = asNullableString(asEvalJson(part)['text']);
      if (text != null) {
        return text;
      }
    }
  }
  return '';
}

String? _inferExpectedOutput(EvalJsonMap json, List<Invocation>? conversation) {
  final String? raw =
      asNullableString(json['expectedOutput']) ??
      asNullableString(json['expected_output']);
  if (raw != null) {
    return raw;
  }
  final String? legacyReference = asNullableString(json['reference']);
  if (legacyReference != null) {
    return legacyReference;
  }
  if (conversation != null && conversation.isNotEmpty) {
    final EvalJsonMap? finalResponse = conversation.last.finalResponse;
    if (finalResponse == null) {
      return null;
    }
    final List<Object?> parts = asObjectList(finalResponse['parts']);
    for (final Object? part in parts) {
      final String? text = asNullableString(asEvalJson(part)['text']);
      if (text != null) {
        return text;
      }
    }
  }
  return null;
}

EvalJsonMap _contentFromText({required String role, required String text}) {
  return <String, Object?>{
    'role': role,
    'parts': <Object?>[
      <String, Object?>{'text': text},
    ],
  };
}

Object? _parseIntermediateData(Object? rawIntermediate) {
  if (rawIntermediate == null) {
    return null;
  }
  final EvalJsonMap map = asEvalJson(rawIntermediate);
  if (map.containsKey('invocation_events') ||
      map.containsKey('invocationEvents')) {
    return InvocationEvents.fromJson(map);
  }
  if (map.containsKey('tool_uses') ||
      map.containsKey('toolUses') ||
      map.containsKey('tool_responses') ||
      map.containsKey('toolResponses') ||
      map.containsKey('intermediate_responses') ||
      map.containsKey('intermediateResponses')) {
    return IntermediateData.fromJson(map);
  }
  return rawIntermediate;
}

List<EvalJsonMap> _extractFunctionCallsFromContent(EvalJsonMap content) {
  final List<EvalJsonMap> toolCalls = <EvalJsonMap>[];
  for (final Object? part in asObjectList(content['parts'])) {
    final EvalJsonMap partMap = asEvalJson(part);
    final EvalJsonMap? functionCall =
        partMap['functionCall'] == null && partMap['function_call'] == null
        ? null
        : asEvalJson(partMap['functionCall'] ?? partMap['function_call']);
    if (functionCall != null && functionCall.isNotEmpty) {
      toolCalls.add(functionCall);
    }
  }
  return toolCalls;
}

List<EvalJsonMap> _extractFunctionResponsesFromContent(EvalJsonMap content) {
  final List<EvalJsonMap> responses = <EvalJsonMap>[];
  for (final Object? part in asObjectList(content['parts'])) {
    final EvalJsonMap partMap = asEvalJson(part);
    final EvalJsonMap? functionResponse =
        partMap['functionResponse'] == null &&
            partMap['function_response'] == null
        ? null
        : asEvalJson(
            partMap['functionResponse'] ?? partMap['function_response'],
          );
    if (functionResponse != null && functionResponse.isNotEmpty) {
      responses.add(functionResponse);
    }
  }
  return responses;
}
