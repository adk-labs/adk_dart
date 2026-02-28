import 'dart:math';

import '../agents/llm_agent.dart';
import '../events/event.dart';
import '../models/base_llm.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../runners/runner.dart';
import '../sessions/base_session_service.dart';
import '../sessions/session.dart';
import '../tools/function_tool.dart';
import '../types/content.dart';
import 'project.dart';

const String getCurrentTimeToolName = 'get_current_time';

class DevAgentRuntime {
  DevAgentRuntime({required this.config})
    : runner = InMemoryRunner(
        appName: config.appName,
        agent: Agent(
          name: config.agentName,
          description: config.description,
          instruction:
              "You are a helpful assistant that tells the current time in cities. "
              "Use '$getCurrentTimeToolName' when users ask for the current time.",
          model: DemoTimeModel(),
          tools: <Object>[
            FunctionTool(
              name: getCurrentTimeToolName,
              description: 'Returns the current time in a specified city.',
              func: getCurrentTime,
            ),
          ],
        ),
      );

  final DevProjectConfig config;
  final InMemoryRunner runner;

  Future<Session> createSession({required String userId, String? sessionId}) {
    return runner.sessionService.createSession(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  Future<Session> createSessionWithState({
    required String userId,
    String? sessionId,
    Map<String, Object?>? state,
  }) {
    return runner.sessionService.createSession(
      appName: runner.appName,
      userId: userId,
      state: state,
      sessionId: sessionId,
    );
  }

  Future<Session> ensureSession({
    required String userId,
    required String sessionId,
  }) async {
    final Session? existing = await runner.sessionService.getSession(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
    );
    if (existing != null) {
      return existing;
    }
    return createSession(userId: userId, sessionId: sessionId);
  }

  Future<List<Session>> listSessions({required String userId}) async {
    final ListSessionsResponse response = await runner.sessionService
        .listSessions(appName: runner.appName, userId: userId);
    return response.sessions;
  }

  Future<Session?> getSession({
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) {
    return runner.sessionService.getSession(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
      config: config,
    );
  }

  Future<List<Event>> sendMessage({
    required String userId,
    required String sessionId,
    required String message,
  }) async {
    await ensureSession(userId: userId, sessionId: sessionId);
    return runner
        .runAsync(
          userId: userId,
          sessionId: sessionId,
          newMessage: Content.userText(message),
        )
        .toList();
  }
}

Map<String, Object> getCurrentTime({required String city}) {
  final DateTime now = DateTime.now();
  return <String, Object>{
    'status': 'success',
    'city': city,
    'time': now.toIso8601String(),
  };
}

class DemoTimeModel extends BaseLlm {
  DemoTimeModel() : super(model: 'demo-time-model');

  static final RegExp _cityRegExp = RegExp(
    r'\b(?:in|at|for)\s+([a-zA-Z][a-zA-Z\s\-]{1,40})',
    caseSensitive: false,
  );

  static final Set<String> _timeKeywords = <String>{
    'time',
    'clock',
    'hour',
    'what time',
    'current time',
    'now',
  };

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final FunctionResponse? recentToolResponse = _lastToolResponse(request);
    if (recentToolResponse != null &&
        recentToolResponse.name == getCurrentTimeToolName) {
      final String city =
          '${recentToolResponse.response['city'] ?? 'the city'}';
      final String time = '${recentToolResponse.response['time'] ?? 'unknown'}';
      yield LlmResponse(
        content: Content.modelText('The current time in $city is $time.'),
      );
      return;
    }

    final String prompt = _lastUserText(request) ?? '';
    if (prompt.isEmpty) {
      yield LlmResponse(
        content: Content.modelText(
          "Ask me about time in a city, for example: 'What time is it in Seoul?'",
        ),
      );
      return;
    }

    if (_asksForTime(prompt)) {
      final String city = _extractCity(prompt) ?? _fallbackCity(prompt);
      yield LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: getCurrentTimeToolName,
              args: <String, Object>{'city': city},
            ),
          ],
        ),
      );
      return;
    }

    yield LlmResponse(
      content: Content.modelText(
        "I can help with time lookups. Try: 'What time is it in Tokyo?'",
      ),
    );
  }

  FunctionResponse? _lastToolResponse(LlmRequest request) {
    for (int i = request.contents.length - 1; i >= 0; i -= 1) {
      final Content content = request.contents[i];
      for (int j = content.parts.length - 1; j >= 0; j -= 1) {
        final FunctionResponse? response = content.parts[j].functionResponse;
        if (response != null) {
          return response;
        }
      }
    }
    return null;
  }

  String? _lastUserText(LlmRequest request) {
    for (int i = request.contents.length - 1; i >= 0; i -= 1) {
      final Content content = request.contents[i];
      if (content.role != 'user') {
        continue;
      }
      for (int j = content.parts.length - 1; j >= 0; j -= 1) {
        final String? text = content.parts[j].text;
        if (text != null && text.trim().isNotEmpty) {
          return text.trim();
        }
      }
    }
    return null;
  }

  bool _asksForTime(String text) {
    final String lower = text.toLowerCase();
    for (final String keyword in _timeKeywords) {
      if (lower.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  String? _extractCity(String text) {
    final Match? match = _cityRegExp.firstMatch(text);
    if (match == null) {
      return null;
    }
    final String raw = match.group(1)?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return raw[0].toUpperCase() + raw.substring(1);
  }

  String _fallbackCity(String prompt) {
    final List<String> fallbackCities = <String>[
      'Seoul',
      'San Francisco',
      'London',
      'Tokyo',
    ];
    final int idx =
        prompt.codeUnits.fold<int>(0, (int sum, int unit) => sum + unit) %
        max(1, fallbackCities.length);
    return fallbackCities[idx];
  }
}
