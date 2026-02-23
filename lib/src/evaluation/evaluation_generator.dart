import '../agents/base_agent.dart';
import '../events/event.dart';
import '../models/llm_request.dart';
import '../plugins/base_plugin.dart';
import '../runners/runner.dart';
import '../types/content.dart';
import 'app_details.dart';
import 'common.dart';
import 'eval_case.dart';
import 'eval_set.dart';
import 'simulation/user_simulator.dart';
import 'simulation/user_simulator_provider.dart';
import '_retry_options_utils.dart';
import 'request_intercepter_plugin.dart';

const String userAuthor = 'user';
const String defaultAuthor = 'agent';

class EvalCaseResponses {
  EvalCaseResponses({required this.evalCase, List<List<Invocation>>? responses})
    : responses = responses ?? <List<Invocation>>[];

  final EvalCase evalCase;
  final List<List<Invocation>> responses;
}

class EvaluationGenerator {
  static Future<List<EvalCaseResponses>> generateResponses({
    required EvalSet evalSet,
    required BaseAgent rootAgent,
    int repeatNum = 3,
    String appName = 'EvaluationGenerator',
    String userId = 'test_user_id',
    UserSimulatorProvider? userSimulatorProvider,
  }) async {
    final UserSimulatorProvider simulatorProvider =
        userSimulatorProvider ?? UserSimulatorProvider();
    final List<EvalCaseResponses> results = <EvalCaseResponses>[];

    for (final EvalCase evalCase in evalSet.evalCases) {
      final List<List<Invocation>> responses = <List<Invocation>>[];
      for (int i = 0; i < repeatNum; i += 1) {
        final UserSimulator? userSimulator = _resolveUserSimulator(
          evalCase,
          simulatorProvider,
        );
        responses.add(
          await _runEvalCase(
            rootAgent: rootAgent,
            evalCase: evalCase,
            userSimulator: userSimulator,
            appName: evalCase.sessionInput?.appName ?? appName,
            userId: evalCase.sessionInput?.userId ?? userId,
          ),
        );
      }
      results.add(EvalCaseResponses(evalCase: evalCase, responses: responses));
    }
    return results;
  }

  static UserSimulator? _resolveUserSimulator(
    EvalCase evalCase,
    UserSimulatorProvider userSimulatorProvider,
  ) {
    final bool hasConversationData =
        evalCase.conversation != null || evalCase.conversationScenario != null;
    if (!hasConversationData) {
      // Backward compatibility: older eval cases may only have `input`.
      return null;
    }
    return userSimulatorProvider.provide(evalCase);
  }

  static Future<List<Invocation>> _runEvalCase({
    required BaseAgent rootAgent,
    required EvalCase evalCase,
    required UserSimulator? userSimulator,
    required String appName,
    required String userId,
  }) async {
    final RequestIntercepterPlugin requestIntercepterPlugin =
        RequestIntercepterPlugin();
    final EnsureRetryOptionsPlugin ensureRetryOptionsPlugin =
        EnsureRetryOptionsPlugin();
    final List<BasePlugin> plugins = <BasePlugin>[
      requestIntercepterPlugin,
      ensureRetryOptionsPlugin,
    ];
    final InMemoryRunner runner = InMemoryRunner(
      agent: rootAgent,
      appName: appName,
      plugins: plugins,
    );

    try {
      final String sessionId =
          'eval_${DateTime.now().microsecondsSinceEpoch}_${evalCase.evalId}';
      await runner.sessionService.createSession(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        state: evalCase.sessionInput?.state,
      );

      final List<Event> allEvents = <Event>[];

      if (userSimulator != null) {
        while (true) {
          final NextUserMessage nextUserMessage = await userSimulator
              .getNextUserMessage(_cloneEvents(allEvents));
          if (nextUserMessage.status != Status.success ||
              nextUserMessage.userMessage == null) {
            break;
          }

          await for (final Event event
              in _generateInferencesForSingleUserInvocation(
                runner: runner,
                userId: userId,
                sessionId: sessionId,
                userContent: nextUserMessage.userMessage!,
              )) {
            allEvents.add(event);
          }
        }
      } else {
        final List<Content> userMessages = _collectUserMessages(evalCase);
        for (final Content userContent in userMessages) {
          await for (final Event event
              in _generateInferencesForSingleUserInvocation(
                runner: runner,
                userId: userId,
                sessionId: sessionId,
                userContent: userContent,
              )) {
            allEvents.add(event);
          }
        }
      }

      final Map<String, AppDetails> appDetailsByInvocationId =
          _getAppDetailsByInvocationId(allEvents, requestIntercepterPlugin);

      return convertEventsToEvalInvocations(
        allEvents,
        appDetailsPerInvocation: appDetailsByInvocationId,
      );
    } finally {
      await runner.close();
    }
  }

  static Stream<Event> _generateInferencesForSingleUserInvocation({
    required InMemoryRunner runner,
    required String userId,
    required String sessionId,
    required Content userContent,
  }) async* {
    String? invocationId;
    await for (final Event event in runner.runAsync(
      userId: userId,
      sessionId: sessionId,
      newMessage: userContent,
    )) {
      if (invocationId == null) {
        invocationId = event.invocationId;
        yield Event(
          invocationId: invocationId,
          author: userAuthor,
          content: userContent.copyWith(),
        );
      }
      yield event;
    }
  }

  static List<Content> _collectUserMessages(EvalCase evalCase) {
    if (evalCase.conversation != null && evalCase.conversation!.isNotEmpty) {
      return evalCase.conversation!.map((Invocation invocation) {
        return _contentFromEvalJson(invocation.userContent);
      }).toList();
    }
    if (evalCase.conversationScenario != null) {
      return <Content>[
        Content.userText(evalCase.conversationScenario!.startingPrompt),
      ];
    }
    if (evalCase.input.isNotEmpty) {
      return <Content>[Content.userText(evalCase.input)];
    }
    return <Content>[];
  }

  static List<Invocation> convertEventsToEvalInvocations(
    List<Event> events, {
    Map<String, AppDetails>? appDetailsPerInvocation,
  }) {
    final Map<String, List<Event>> eventsByInvocationId =
        _collectEventsByInvocationId(events);

    final List<Invocation> invocations = <Invocation>[];
    eventsByInvocationId.forEach((String invocationId, List<Event> bucket) {
      EvalJsonMap? finalResponse;
      EvalJsonMap? userContent;
      double invocationTimestamp = 0.0;
      final List<InvocationEvent> eventsToAdd = <InvocationEvent>[];

      for (final Event event in bucket) {
        final String currentAuthor = (event.author).toLowerCase();
        if (currentAuthor == userAuthor) {
          userContent = _contentToEvalJson(event.content);
          invocationTimestamp = event.timestamp;
          continue;
        }

        if (event.content != null && event.content!.parts.isNotEmpty) {
          if (event.isFinalResponse()) {
            finalResponse = _contentToEvalJson(event.content);
          } else {
            bool shouldInclude = false;
            for (final Part part in event.content!.parts) {
              if (part.functionCall != null ||
                  part.functionResponse != null ||
                  (part.text != null && part.text!.isNotEmpty)) {
                shouldInclude = true;
                break;
              }
            }
            if (shouldInclude) {
              eventsToAdd.add(
                InvocationEvent(
                  author: event.author.isEmpty ? defaultAuthor : event.author,
                  content: _contentToEvalJson(event.content),
                ),
              );
            }
          }
        }
      }

      invocations.add(
        Invocation(
          invocationId: invocationId,
          userContent: userContent ?? <String, Object?>{},
          finalResponse: finalResponse,
          intermediateData: InvocationEvents(invocationEvents: eventsToAdd),
          creationTimestamp: invocationTimestamp,
          appDetails: appDetailsPerInvocation?[invocationId],
        ),
      );
    });

    return invocations;
  }

  static Map<String, List<Event>> _collectEventsByInvocationId(
    List<Event> events,
  ) {
    final Map<String, List<Event>> grouped = <String, List<Event>>{};
    for (final Event event in events) {
      grouped.putIfAbsent(event.invocationId, () => <Event>[]).add(event);
    }
    return grouped;
  }

  static Map<String, AppDetails> _getAppDetailsByInvocationId(
    List<Event> events,
    RequestIntercepterPlugin requestIntercepter,
  ) {
    final Map<String, List<Event>> eventsByInvocationId =
        _collectEventsByInvocationId(events);
    final Map<String, AppDetails> appDetailsByInvocationId =
        <String, AppDetails>{};

    eventsByInvocationId.forEach((String invocationId, List<Event> bucket) {
      final AppDetails appDetails = AppDetails(
        agentDetails: <String, AgentDetails>{},
      );
      appDetailsByInvocationId[invocationId] = appDetails;

      for (final Event event in bucket) {
        if (event.author == userAuthor) {
          continue;
        }

        final LlmRequest? llmRequest = requestIntercepter.getModelRequest(
          event,
        );
        if (llmRequest == null) {
          continue;
        }

        if (!appDetails.agentDetails.containsKey(event.author)) {
          appDetails.agentDetails[event.author] = AgentDetails(
            name: event.author,
            instructions: llmRequest.config.systemInstruction ?? '',
            toolDeclarations: _serializeToolDeclarations(
              llmRequest.config.tools,
            ),
          );
        }
      }
    });

    return appDetailsByInvocationId;
  }

  static List<Event> _cloneEvents(List<Event> events) {
    return events.map((Event event) => event.copyWith()).toList();
  }
}

List<Object?> _serializeToolDeclarations(List<ToolDeclaration>? tools) {
  if (tools == null || tools.isEmpty) {
    return <Object?>[];
  }
  return tools.map((ToolDeclaration tool) {
    return <String, Object?>{
      'function_declarations': _serializeFunctionDeclarations(
        tool.functionDeclarations,
      ),
    };
  }).toList();
}

List<Object?> _serializeFunctionDeclarations(
  List<FunctionDeclaration> declarations,
) {
  return declarations.map((FunctionDeclaration declaration) {
    return <String, Object?>{
      'name': declaration.name,
      'description': declaration.description,
      'parameters': Map<String, Object?>.from(declaration.parameters),
    };
  }).toList();
}

Content _contentFromEvalJson(EvalJsonMap content) {
  final List<Part> parts = <Part>[];
  for (final Object? rawPart in asObjectList(content['parts'])) {
    final EvalJsonMap part = asEvalJson(rawPart);
    if (part['function_call'] != null || part['functionCall'] != null) {
      final EvalJsonMap call = asEvalJson(
        part['function_call'] ?? part['functionCall'],
      );
      parts.add(
        Part.fromFunctionCall(
          name: (call['name'] ?? '').toString(),
          args: asEvalJson(call['args']).cast<String, dynamic>(),
          id: call['id']?.toString(),
        ),
      );
      continue;
    }
    if (part['function_response'] != null || part['functionResponse'] != null) {
      final EvalJsonMap response = asEvalJson(
        part['function_response'] ?? part['functionResponse'],
      );
      parts.add(
        Part.fromFunctionResponse(
          name: (response['name'] ?? '').toString(),
          response: asEvalJson(response['response']).cast<String, dynamic>(),
          id: response['id']?.toString(),
        ),
      );
      continue;
    }
    final String? text = asNullableString(part['text']);
    if (text != null) {
      parts.add(Part.text(text));
    }
  }
  return Content(role: asNullableString(content['role']), parts: parts);
}

EvalJsonMap? _contentToEvalJson(Content? content) {
  if (content == null) {
    return null;
  }
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map((Part part) {
      if (part.functionCall != null) {
        return <String, Object?>{
          'function_call': <String, Object?>{
            'name': part.functionCall!.name,
            'args': part.functionCall!.args,
            if (part.functionCall!.id != null) 'id': part.functionCall!.id,
          },
        };
      }
      if (part.functionResponse != null) {
        return <String, Object?>{
          'function_response': <String, Object?>{
            'name': part.functionResponse!.name,
            'response': part.functionResponse!.response,
            if (part.functionResponse!.id != null)
              'id': part.functionResponse!.id,
          },
        };
      }
      return <String, Object?>{'text': part.text ?? ''};
    }).toList(),
  };
}
