import 'app_details.dart';
import 'common.dart';
import 'conversation_scenarios.dart';

typedef EvalJsonMap = Map<String, Object?>;

class IntermediateData {
  IntermediateData({
    List<EvalJsonMap>? toolUses,
    List<EvalJsonMap>? toolResponses,
    List<InvocationResponse>? intermediateResponses,
  }) : toolUses = toolUses ?? <EvalJsonMap>[],
       toolResponses = toolResponses ?? <EvalJsonMap>[],
       intermediateResponses = intermediateResponses ?? <InvocationResponse>[];

  final List<EvalJsonMap> toolUses;
  final List<EvalJsonMap> toolResponses;
  final List<InvocationResponse> intermediateResponses;

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

class InvocationResponse {
  InvocationResponse({required this.author, List<EvalJsonMap>? parts})
    : parts = parts ?? <EvalJsonMap>[];

  final String author;
  final List<EvalJsonMap> parts;

  factory InvocationResponse.fromJson(EvalJsonMap json) {
    return InvocationResponse(
      author: asNullableString(json['author']) ?? '',
      parts: asEvalJsonList(json['parts']),
    );
  }

  EvalJsonMap toJson() => <String, Object?>{'author': author, 'parts': parts};
}

class InvocationEvent {
  InvocationEvent({required this.author, this.content});

  final String author;
  final EvalJsonMap? content;

  factory InvocationEvent.fromJson(EvalJsonMap json) {
    return InvocationEvent(
      author: asNullableString(json['author']) ?? '',
      content: json['content'] == null ? null : asEvalJson(json['content']),
    );
  }

  EvalJsonMap toJson() {
    return <String, Object?>{
      'author': author,
      if (content != null) 'content': content,
    };
  }
}

class InvocationEvents {
  InvocationEvents({List<InvocationEvent>? invocationEvents})
    : invocationEvents = invocationEvents ?? <InvocationEvent>[];

  final List<InvocationEvent> invocationEvents;

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

  EvalJsonMap toJson() {
    return <String, Object?>{
      'invocation_events': invocationEvents
          .map((InvocationEvent value) => value.toJson())
          .toList(),
    };
  }
}

class Invocation {
  Invocation({
    this.invocationId = '',
    required this.userContent,
    this.finalResponse,
    this.intermediateData,
    this.creationTimestamp = 0,
    List<EvalJsonMap>? rubrics,
    this.appDetails,
  }) : rubrics = rubrics ?? <EvalJsonMap>[];

  final String invocationId;
  final EvalJsonMap userContent;
  final EvalJsonMap? finalResponse;
  final Object? intermediateData;
  final double creationTimestamp;
  final List<EvalJsonMap> rubrics;
  final AppDetails? appDetails;

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

class SessionInput {
  SessionInput({
    required this.appName,
    required this.userId,
    EvalJsonMap? state,
  }) : state = state ?? <String, Object?>{};

  final String appName;
  final String userId;
  final EvalJsonMap state;

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

  EvalJsonMap toJson() {
    return <String, Object?>{
      'app_name': appName,
      'user_id': userId,
      'state': state,
    };
  }
}

class EvalCase {
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

  final String evalId;
  final String input;
  final String? expectedOutput;
  final List<Invocation>? conversation;
  final ConversationScenario? conversationScenario;
  final SessionInput? sessionInput;
  final double creationTimestamp;
  final List<EvalJsonMap> rubrics;
  final EvalJsonMap finalSessionState;
  final EvalJsonMap metadata;

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
  if (rawConversation is! List) {
    return null;
  }
  return rawConversation.map((Object? item) {
    return Invocation.fromJson(asEvalJson(item));
  }).toList();
}

String _inferInput(EvalJsonMap json, List<Invocation>? conversation) {
  final String? rawInput = asNullableString(json['input']);
  if (rawInput != null) {
    return rawInput;
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
