/// Evaluation trajectory generation helpers for eval sets.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

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

/// Author value used for synthetic user events.
const String userAuthor = 'user';

/// Fallback author label for agent-generated events.
const String defaultAuthor = 'agent';

/// Generated responses for one [EvalCase] across repeated runs.
class EvalCaseResponses {
  /// Creates generated responses for one eval case.
  EvalCaseResponses({required this.evalCase, List<List<Invocation>>? responses})
    : responses = responses ?? <List<Invocation>>[];

  /// Source eval case.
  final EvalCase evalCase;

  /// Repeated invocation trajectories produced for the case.
  final List<List<Invocation>> responses;
}

/// Generates inference trajectories from eval sets.
class EvaluationGenerator {
  /// Runs [evalSet] against [rootAgent] and returns generated trajectories.
  ///
  /// When [parallelism] is provided (must be `>= 1`), at most [parallelism]
  /// eval case runs execute concurrently while preserving the output ordering
  /// of `evalSet.evalCases` and repetitions.
  static Future<List<EvalCaseResponses>> generateResponses({
    required EvalSet evalSet,
    required BaseAgent rootAgent,
    int repeatNum = 3,
    String appName = 'EvaluationGenerator',
    String userId = 'test_user_id',
    UserSimulatorProvider? userSimulatorProvider,
    int? parallelism,
  }) async {
    if (repeatNum < 1) {
      throw ArgumentError.value(
        repeatNum,
        'repeatNum',
        'Input should be greater than or equal to 1',
      );
    }
    if (parallelism != null && parallelism < 1) {
      throw ArgumentError.value(
        parallelism,
        'parallelism',
        'Input should be greater than or equal to 1',
      );
    }
    final UserSimulatorProvider simulatorProvider =
        userSimulatorProvider ?? UserSimulatorProvider();

    if (parallelism == null || parallelism == 1) {
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
        results.add(
          EvalCaseResponses(evalCase: evalCase, responses: responses),
        );
      }
      return results;
    }

    final _EvalSemaphore semaphore = _EvalSemaphore(parallelism);
    final List<List<Future<List<Invocation>>>> futureMatrix =
        <List<Future<List<Invocation>>>>[];
    for (final EvalCase evalCase in evalSet.evalCases) {
      final List<Future<List<Invocation>>> caseFutures =
          <Future<List<Invocation>>>[];
      for (int i = 0; i < repeatNum; i += 1) {
        caseFutures.add(
          semaphore.withPermit(() async {
            final UserSimulator? userSimulator = _resolveUserSimulator(
              evalCase,
              simulatorProvider,
            );
            return _runEvalCase(
              rootAgent: rootAgent,
              evalCase: evalCase,
              userSimulator: userSimulator,
              appName: evalCase.sessionInput?.appName ?? appName,
              userId: evalCase.sessionInput?.userId ?? userId,
            );
          }),
        );
      }
      futureMatrix.add(caseFutures);
    }

    final List<EvalCaseResponses> results = <EvalCaseResponses>[];
    for (int caseIdx = 0; caseIdx < evalSet.evalCases.length; caseIdx += 1) {
      final List<List<Invocation>> responses = await Future.wait(
        futureMatrix[caseIdx],
      );
      results.add(
        EvalCaseResponses(
          evalCase: evalSet.evalCases[caseIdx],
          responses: responses,
        ),
      );
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

  /// Runs one user invocation and yields normalized user/agent events.
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
    if (invocationId == null) {
      // The runner produced no events (for example, a silent turn or an early
      // before_agent_callback exit). Emit a synthetic user event with a fresh
      // invocation_id so the turn is still represented in the trajectory and
      // later turns stay aligned with expected invocations.
      yield Event(
        invocationId: 'e-${Event.newId()}',
        author: userAuthor,
        content: userContent.copyWith(),
      );
    }
  }

  /// Collects initial user messages from an [EvalCase].
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

  /// Converts raw runner events into eval [Invocation] objects.
  static List<Invocation> convertEventsToEvalInvocations(
    List<Event> events, {
    Map<String, AppDetails>? appDetailsPerInvocation,
  }) {
    final Map<String, List<Event>> eventsByInvocationId =
        _collectEventsByInvocationId(events);

    final List<Invocation> invocations = <Invocation>[];
    eventsByInvocationId.forEach((String invocationId, List<Event> bucket) {
      final ({
        Map<int, Event> pairedUsageByTarget,
        Set<int> consumedUsageIndices,
      })
      usagePairing = _pairStandaloneUsageEvents(bucket);
      final Map<int, Event> pairedUsageByTarget =
          usagePairing.pairedUsageByTarget;
      final Set<int> consumedUsageIndices = usagePairing.consumedUsageIndices;

      EvalJsonMap? finalResponse;
      Event? finalEvent;
      int? finalEventIdx;
      EvalJsonMap? userContent;
      double invocationTimestamp = 0.0;

      for (int idx = 0; idx < bucket.length; idx++) {
        final Event event = bucket[idx];
        final String currentAuthor = (event.author).toLowerCase();
        if (currentAuthor == userAuthor) {
          userContent = _contentToEvalJson(event.content);
          invocationTimestamp = event.timestamp;
          continue;
        }
        if (consumedUsageIndices.contains(idx)) {
          continue;
        }
        if (event.content != null &&
            event.content!.parts.isNotEmpty &&
            event.isFinalResponse()) {
          finalResponse = _contentToEvalJson(event.content);
          finalEvent = event;
          finalEventIdx = idx;
        }
      }

      final List<InvocationEvent> eventsToAdd = <InvocationEvent>[];
      for (int idx = 0; idx < bucket.length; idx++) {
        final Event event = bucket[idx];
        final String currentAuthor = (event.author).toLowerCase();
        if (currentAuthor == userAuthor) {
          continue;
        }
        if (consumedUsageIndices.contains(idx)) {
          continue;
        }

        final Event? pairedUsage = pairedUsageByTarget[idx];
        final Object? effectiveUsage =
            event.usageMetadata ?? pairedUsage?.usageMetadata;
        final String? effectiveModelVersion =
            event.modelVersion ?? pairedUsage?.modelVersion;

        if (identical(event, finalEvent) && idx == finalEventIdx) {
          if (event.groundingMetadata != null || effectiveUsage != null) {
            eventsToAdd.add(
              InvocationEvent(
                author: event.author.isEmpty ? defaultAuthor : event.author,
                content: event.getFunctionCalls().isNotEmpty
                    ? _contentToEvalJson(event.content)
                    : null,
                groundingMetadata: _metadataToEvalJson(event.groundingMetadata),
                usageMetadata: _metadataToEvalJson(effectiveUsage),
                modelVersion: effectiveModelVersion,
              ),
            );
          }
          continue;
        }

        bool shouldIncludeContent = false;
        if (event.content != null && event.content!.parts.isNotEmpty) {
          for (final Part part in event.content!.parts) {
            if (part.functionCall != null ||
                part.functionResponse != null ||
                part.inlineData != null ||
                part.fileData != null ||
                part.executableCode != null ||
                part.codeExecutionResult != null ||
                (part.text != null && part.text!.isNotEmpty)) {
              shouldIncludeContent = true;
              break;
            }
          }
        }

        if (shouldIncludeContent ||
            event.groundingMetadata != null ||
            effectiveUsage != null) {
          eventsToAdd.add(
            InvocationEvent(
              author: event.author.isEmpty ? defaultAuthor : event.author,
              content: shouldIncludeContent
                  ? _contentToEvalJson(event.content)
                  : null,
              groundingMetadata: _metadataToEvalJson(event.groundingMetadata),
              usageMetadata: _metadataToEvalJson(effectiveUsage),
              modelVersion: effectiveModelVersion,
            ),
          );
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

  static bool _isStandaloneUsageReport(Event event) {
    return event.usageMetadata != null &&
        (event.content == null || event.content!.parts.isEmpty) &&
        event.groundingMetadata == null;
  }

  static bool _isModelCallEvent(Event event) {
    if ((event.author).toLowerCase() == userAuthor) {
      return false;
    }
    if (_isStandaloneUsageReport(event)) {
      return false;
    }
    if (event.getFunctionResponses().isNotEmpty &&
        event.getFunctionCalls().isEmpty) {
      return false;
    }
    return (event.content != null && event.content!.parts.isNotEmpty) ||
        event.groundingMetadata != null ||
        event.usageMetadata != null;
  }

  static int? _findUsagePairIndex(
    List<Event> invocationEvents,
    int usageIndex,
    Set<int> claimedEventIndices,
  ) {
    final Event usageEvent = invocationEvents[usageIndex];

    bool isCompatible(int candidateIndex) {
      if (claimedEventIndices.contains(candidateIndex)) {
        return false;
      }
      final Event candidate = invocationEvents[candidateIndex];
      if (!_isModelCallEvent(candidate)) {
        return false;
      }
      if (candidate.usageMetadata != null) {
        return false;
      }
      if (candidate.author != usageEvent.author) {
        return false;
      }
      if (candidate.liveSessionId != usageEvent.liveSessionId) {
        return false;
      }
      if (candidate.modelVersion != null &&
          usageEvent.modelVersion != null &&
          candidate.modelVersion != usageEvent.modelVersion) {
        return false;
      }
      return true;
    }

    for (int idx = usageIndex - 1; idx >= 0; idx--) {
      if (isCompatible(idx)) {
        return idx;
      }
    }
    for (int idx = usageIndex + 1; idx < invocationEvents.length; idx++) {
      if (isCompatible(idx)) {
        return idx;
      }
    }
    return null;
  }

  static ({
    Map<int, Event> pairedUsageByTarget,
    Set<int> consumedUsageIndices,
  })
  _pairStandaloneUsageEvents(List<Event> invocationEvents) {
    final Set<int> claimed = <int>{
      for (int idx = 0; idx < invocationEvents.length; idx++)
        if (!_isStandaloneUsageReport(invocationEvents[idx]) &&
            invocationEvents[idx].usageMetadata != null)
          idx,
    };
    final Map<int, Event> pairedUsageByTarget = <int, Event>{};
    final Set<int> consumedUsageIndices = <int>{};

    for (int idx = 0; idx < invocationEvents.length; idx++) {
      final Event event = invocationEvents[idx];
      if (!_isStandaloneUsageReport(event)) {
        continue;
      }
      final int? targetIdx = _findUsagePairIndex(
        invocationEvents,
        idx,
        claimed,
      );
      if (targetIdx != null) {
        claimed.add(targetIdx);
        pairedUsageByTarget[targetIdx] = event;
        consumedUsageIndices.add(idx);
      }
    }
    return (
      pairedUsageByTarget: pairedUsageByTarget,
      consumedUsageIndices: consumedUsageIndices,
    );
  }

  static EvalJsonMap? _metadataToEvalJson(Object? metadata) {
    if (metadata == null) {
      return null;
    }
    if (metadata is Map) {
      return asEvalJson(metadata);
    }
    try {
      final Object? serialized = (metadata as dynamic).toJson();
      if (serialized is Map) {
        return asEvalJson(serialized);
      }
    } catch (_) {}
    return <String, Object?>{'value': '$metadata'};
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
    if (part['inline_data'] != null || part['inlineData'] != null) {
      final EvalJsonMap data = asEvalJson(
        part['inline_data'] ?? part['inlineData'],
      );
      final String? encoded = asNullableString(data['data']);
      if (encoded != null) {
        parts.add(
          Part.fromInlineData(
            mimeType:
                asNullableString(data['mime_type'] ?? data['mimeType']) ?? '',
            data: base64Decode(encoded),
          ),
        );
      }
      continue;
    }
    if (part['file_data'] != null || part['fileData'] != null) {
      final EvalJsonMap data = asEvalJson(
        part['file_data'] ?? part['fileData'],
      );
      final String? uri = asNullableString(data['file_uri'] ?? data['fileUri']);
      if (uri != null) {
        parts.add(
          Part.fromFileData(
            fileUri: uri,
            mimeType: asNullableString(data['mime_type'] ?? data['mimeType']),
          ),
        );
      }
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
      if (part.inlineData != null) {
        return <String, Object?>{
          'inline_data': <String, Object?>{
            'mime_type': part.inlineData!.mimeType,
            'data': base64Encode(part.inlineData!.data),
          },
        };
      }
      if (part.fileData != null) {
        return <String, Object?>{
          'file_data': <String, Object?>{
            'file_uri': part.fileData!.fileUri,
            if (part.fileData!.mimeType != null)
              'mime_type': part.fileData!.mimeType,
          },
        };
      }
      return <String, Object?>{'text': part.text ?? ''};
    }).toList(),
  };
}

class _EvalSemaphore {
  _EvalSemaphore(this._maxConcurrency);

  final int _maxConcurrency;
  int _current = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<T> withPermit<T>(Future<T> Function() action) async {
    if (_current >= _maxConcurrency) {
      final Completer<void> waiter = Completer<void>();
      _waiters.addLast(waiter);
      await waiter.future;
    } else {
      _current += 1;
    }
    try {
      return await action();
    } finally {
      if (_waiters.isNotEmpty) {
        final Completer<void> next = _waiters.removeFirst();
        next.complete();
      } else {
        _current -= 1;
      }
    }
  }
}
