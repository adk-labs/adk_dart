import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _RecordingAnthropicTransport implements AnthropicRestTransport {
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  final List<String> apiVersions = <String>[];
  final List<Map<String, String>> headersList = <Map<String, String>>[];

  @override
  Future<Map<String, Object?>> createMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  }) async {
    requests.add(Map<String, Object?>.from(request));
    apiVersions.add(apiVersion);
    headersList.add(Map<String, String>.from(headers));
    return <String, Object?>{
      'id': 'msg_1',
      'model': request['model'],
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': 'ok'},
      ],
      'usage': <String, Object?>{'input_tokens': 3, 'output_tokens': 4},
      'stop_reason': 'end_turn',
    };
  }

  @override
  Stream<Map<String, Object?>> streamMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  }) async* {
    requests.add(Map<String, Object?>.from(request));
    apiVersions.add(apiVersion);
    headersList.add(Map<String, String>.from(headers));
    yield <String, Object?>{
      'type': 'message_start',
      'message': <String, Object?>{
        'model': request['model'],
        'usage': <String, Object?>{'input_tokens': 3, 'output_tokens': 0},
      },
    };
    yield <String, Object?>{
      'type': 'content_block_start',
      'index': 0,
      'content_block': <String, Object?>{'type': 'text', 'text': ''},
    };
    yield <String, Object?>{
      'type': 'content_block_delta',
      'index': 0,
      'delta': <String, Object?>{'type': 'text_delta', 'text': 'ok'},
    };
    yield <String, Object?>{
      'type': 'message_delta',
      'delta': <String, Object?>{'stop_reason': 'end_turn'},
      'usage': <String, Object?>{'output_tokens': 4},
    };
    yield <String, Object?>{'type': 'message_stop'};
  }
}

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'test-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) {
    return Stream<LlmResponse>.value(
      LlmResponse(content: Content.modelText('ok')),
    );
  }
}

class _StubRunner extends InMemoryRunner {
  _StubRunner({
    required super.agent,
    required super.appName,
    required Stream<Event> Function({AdkAbortSignal? abortSignal}) eventFactory,
  }) : _eventFactory = eventFactory;

  final Stream<Event> Function({AdkAbortSignal? abortSignal}) _eventFactory;

  @override
  Stream<Event> runAsync({
    required String userId,
    required String sessionId,
    String? invocationId,
    Content? newMessage,
    Map<String, Object?>? stateDelta,
    RunConfig? runConfig,
    AdkAbortSignal? abortSignal,
  }) {
    return _eventFactory(abortSignal: abortSignal);
  }
}

void main() {
  group('1c384506e: AnthropicLlm sampling settings on API 2026-10-21 & SDK 2.x', () {
    late List<String> warnings;

    setUp(() {
      warnings = <String>[];
      anthropicWarningHandlerForTest = warnings.add;
      anthropicSdkMajorVersionForTest = null;
    });

    tearDown(() {
      anthropicWarningHandlerForTest = null;
      anthropicSdkMajorVersionForTest = null;
    });

    for (final bool stream in <bool>[false, true]) {
      test(
        'sends sampling config on pre-2026-10-21 header (stream=$stream)',
        () async {
          final _RecordingAnthropicTransport transport =
              _RecordingAnthropicTransport();
          final AnthropicLlm llm = AnthropicLlm(
            model: 'claude-sonnet-4-20250514',
            restTransport: transport,
            environment: const <String, String>{'ANTHROPIC_API_KEY': 'test-key'},
            defaultHeaders: const <String, String>{
              'anthropic-version': '2023-06-01',
            },
          );
          final LlmRequest request = LlmRequest(
            model: 'claude-sonnet-4-20250514',
            contents: <Content>[Content.userText('Hello')],
            config: GenerateContentConfig(
              temperature: 0.7,
              topP: 0.9,
              topK: 50,
            ),
          );

          await llm.generateContent(request, stream: stream).toList();

          expect(transport.requests, hasLength(1));
          final Map<String, Object?> sent = transport.requests.single;
          expect(sent['temperature'], 0.7);
          expect(sent['top_p'], 0.9);
          expect(sent['top_k'], 50);
          expect(warnings, isEmpty);
        },
      );

      for (final (String headerName, String headerValue) in <(String, String)>[
        ('anthropic-version', '2026-10-21'),
        ('Anthropic-Version', ' 2026-10-21 '),
        ('anthropic-version', '2027-01-15'),
      ]) {
        test(
          'omits sampling config and warns on $headerName=$headerValue (stream=$stream)',
          () async {
            final _RecordingAnthropicTransport transport =
                _RecordingAnthropicTransport();
            final AnthropicLlm llm = AnthropicLlm(
              model: 'claude-sonnet-4-20250514',
              restTransport: transport,
              environment: const <String, String>{
                'ANTHROPIC_API_KEY': 'test-key',
              },
              defaultHeaders: <String, String>{headerName: headerValue},
            );
            final LlmRequest request = LlmRequest(
              model: 'claude-sonnet-4-20250514',
              contents: <Content>[Content.userText('Hello')],
              config: GenerateContentConfig(
                temperature: 0.7,
                topP: 0.9,
                topK: 50,
              ),
            );

            await llm.generateContent(request, stream: stream).toList();

            final Map<String, Object?> sent = transport.requests.single;
            expect(sent.containsKey('temperature'), isFalse);
            expect(sent.containsKey('top_p'), isFalse);
            expect(sent.containsKey('top_k'), isFalse);
            expect(warnings, <String>[
              'Sampling parameters (temperature, top_p, top_k) are ignored '
                  'because Claude API version 2026-10-21 removed them.',
            ]);
          },
        );
      }
    }

    test(
      'sends sampling on SDK v2 when per-request or default header pins 2023-06-01',
      () async {
        anthropicSdkMajorVersionForTest = 2;
        final _RecordingAnthropicTransport transport =
            _RecordingAnthropicTransport();
        final AnthropicLlm llm = AnthropicLlm(
          model: 'claude-sonnet-4-20250514',
          restTransport: transport,
          environment: const <String, String>{'ANTHROPIC_API_KEY': 'test-key'},
          defaultHeaders: const <String, String>{
            'anthropic-version': '2026-10-21',
          },
        );
        final LlmRequest request = LlmRequest(
          model: 'claude-sonnet-4-20250514',
          contents: <Content>[Content.userText('Hello')],
          config: GenerateContentConfig(
            temperature: 0.7,
            topP: 0.9,
            topK: 50,
            httpOptions: HttpOptions(
              headers: <String, String>{'Anthropic-Version': '2023-06-01'},
            ),
          ),
        );

        await llm.generateContent(request, stream: false).toList();

        final Map<String, Object?> sent = transport.requests.single;
        expect(sent['temperature'], 0.7);
        expect(sent['top_p'], 0.9);
        expect(sent['top_k'], 50);
        expect(warnings, isEmpty);
        expect(
          transport.headersList.single.containsKey('anthropic-version'),
          isFalse,
        );
        expect(
          transport.headersList.single['Anthropic-Version'],
          '2023-06-01',
        );
      },
    );

    for (final String headerValue in <String>['   ', '2026-10-21-beta']) {
      test(
        'falls back to SDK v2 when anthropic-version header is non-date ($headerValue)',
        () async {
          anthropicSdkMajorVersionForTest = 2;
          final _RecordingAnthropicTransport transport =
              _RecordingAnthropicTransport();
          final AnthropicLlm llm = AnthropicLlm(
            model: 'claude-sonnet-4-20250514',
            restTransport: transport,
            environment: const <String, String>{
              'ANTHROPIC_API_KEY': 'test-key',
            },
            defaultHeaders: <String, String>{'anthropic-version': headerValue},
          );
          final LlmRequest request = LlmRequest(
            model: 'claude-sonnet-4-20250514',
            contents: <Content>[Content.userText('Hello')],
            config: GenerateContentConfig(temperature: 0.7),
          );

          await llm.generateContent(request, stream: false).toList();

          final Map<String, Object?> sent = transport.requests.single;
          expect(sent.containsKey('temperature'), isFalse);
          expect(warnings, hasLength(1));
          expect(warnings.single, contains('2026-10-21'));
        },
      );
    }

    test(
      'omits sampling on SDK v2 when no explicit apiVersion/header is set',
      () async {
        final _RecordingAnthropicTransport transport =
            _RecordingAnthropicTransport();
        final AnthropicLlm llm = AnthropicLlm(
          model: 'claude-sonnet-4-20250514',
          sdkMajorVersion: 2,
          restTransport: transport,
          environment: const <String, String>{'ANTHROPIC_API_KEY': 'test-key'},
        );
        final LlmRequest request = LlmRequest(
          model: 'claude-sonnet-4-20250514',
          contents: <Content>[Content.userText('Hello')],
          config: GenerateContentConfig(temperature: 0.5),
        );

        await llm.generateContent(request, stream: false).toList();

        expect(transport.requests.single.containsKey('temperature'), isFalse);
        expect(warnings.single, contains('2026-10-21'));
      },
    );

    test(
      'omits sampling when apiVersion or ANTHROPIC_VERSION is 2026-10-21',
      () async {
        final _RecordingAnthropicTransport transport =
            _RecordingAnthropicTransport();
        final AnthropicLlm llmViaParam = AnthropicLlm(
          model: 'claude-sonnet-4-20250514',
          apiVersion: '2026-10-21',
          restTransport: transport,
          environment: const <String, String>{'ANTHROPIC_API_KEY': 'test-key'},
        );
        final AnthropicLlm llmViaEnv = AnthropicLlm(
          model: 'claude-sonnet-4-20250514',
          restTransport: transport,
          environment: const <String, String>{
            'ANTHROPIC_API_KEY': 'test-key',
            'ANTHROPIC_VERSION': '2026-10-21',
          },
        );
        final LlmRequest request = LlmRequest(
          model: 'claude-sonnet-4-20250514',
          contents: <Content>[Content.userText('Hello')],
          config: GenerateContentConfig(temperature: 0.4),
        );

        await llmViaParam.generateContent(request).toList();
        await llmViaEnv.generateContent(request).toList();

        expect(transport.requests[0].containsKey('temperature'), isFalse);
        expect(transport.requests[1].containsKey('temperature'), isFalse);
        expect(warnings, hasLength(2));
      },
    );

    test(
      'does not warn on API 2026-10-21 when sampling params are unset',
      () async {
        final _RecordingAnthropicTransport transport =
            _RecordingAnthropicTransport();
        final AnthropicLlm llm = AnthropicLlm(
          model: 'claude-sonnet-4-20250514',
          restTransport: transport,
          environment: const <String, String>{'ANTHROPIC_API_KEY': 'test-key'},
          defaultHeaders: const <String, String>{
            'anthropic-version': '2026-10-21',
          },
        );
        final LlmRequest request = LlmRequest(
          model: 'claude-sonnet-4-20250514',
          contents: <Content>[Content.userText('Hello')],
          config: GenerateContentConfig(maxOutputTokens: 1024),
        );

        await llm.generateContent(request, stream: false).toList();

        final Map<String, Object?> sent = transport.requests.single;
        expect(sent['max_tokens'], 1024);
        expect(sent.containsKey('temperature'), isFalse);
        expect(sent.containsKey('top_p'), isFalse);
        expect(sent.containsKey('top_k'), isFalse);
        expect(warnings, isEmpty);
      },
    );

    for (final (int sdkMajor, bool shouldSend) in <(int, bool)>[
      (1, true),
      (2, false),
    ]) {
      test(
        'Vertex ignores anthropic-version header and follows SDK major $sdkMajor',
        () async {
          anthropicSdkMajorVersionForTest = sdkMajor;
          final _RecordingAnthropicTransport transport =
              _RecordingAnthropicTransport();
          final AnthropicLlm llm = Claude(
            model: 'claude-sonnet-4-6',
            isVertex: true,
            restTransport: transport,
            environment: const <String, String>{
              'ANTHROPIC_API_KEY': 'test-key',
            },
            defaultHeaders: const <String, String>{
              'anthropic-version': '2023-06-01',
            },
          );
          final LlmRequest request = LlmRequest(
            model: 'claude-sonnet-4-6',
            contents: <Content>[Content.userText('Hello')],
            config: GenerateContentConfig(
              temperature: 0.7,
              topP: 0.9,
              topK: 50,
            ),
          );

          await llm.generateContent(request, stream: false).toList();

          final Map<String, Object?> sent = transport.requests.single;
          if (shouldSend) {
            expect(sent['temperature'], 0.7);
            expect(sent['top_p'], 0.9);
            expect(sent['top_k'], 50);
            expect(warnings, isEmpty);
          } else {
            expect(sent.containsKey('temperature'), isFalse);
            expect(sent.containsKey('top_p'), isFalse);
            expect(sent.containsKey('top_k'), isFalse);
            expect(warnings.single, contains('2026-10-21'));
          }
        },
      );
    }

    test(
      'thinking and effort omit sampling with thinking/effort warning',
      () async {
        anthropicSdkMajorVersionForTest = 2;
        final _RecordingAnthropicTransport transport =
            _RecordingAnthropicTransport();
        final AnthropicLlm llm = AnthropicLlm(
          model: 'claude-sonnet-4-20250514',
          restTransport: transport,
          environment: const <String, String>{'ANTHROPIC_API_KEY': 'test-key'},
        );

        await llm
            .generateContent(
              LlmRequest(
                model: 'claude-sonnet-4-20250514',
                contents: <Content>[Content.userText('Think')],
                config: GenerateContentConfig(
                  temperature: 0.7,
                  topP: 0.9,
                  topK: 50,
                  thinkingConfig: <String, Object?>{'thinkingBudget': 1024},
                ),
              ),
            )
            .toList();

        await llm
            .generateContent(
              LlmRequest(
                model: 'claude-sonnet-4-20250514',
                contents: <Content>[Content.userText('Effort')],
                config: AnthropicGenerateContentConfig(
                  effort: 'xhigh',
                  temperature: 0.7,
                  topP: 0.9,
                  topK: 50,
                ),
              ),
            )
            .toList();

        for (final Map<String, Object?> sent in transport.requests) {
          expect(sent.containsKey('temperature'), isFalse);
          expect(sent.containsKey('top_p'), isFalse);
          expect(sent.containsKey('top_k'), isFalse);
        }
        expect(warnings, <String>[
          'Sampling parameters (temperature, top_p, top_k) are ignored '
              'because thinking/effort is enabled.',
          'Sampling parameters (temperature, top_p, top_k) are ignored '
              'because thinking/effort is enabled.',
        ]);
      },
    );
  });

  group('50961696a: A2aAgentExecutor propagates AdkAbortException from runner/converter', () {
    A2aRequestContext newRequestContext({String taskId = 'test-task-id'}) {
      return A2aRequestContext(
        taskId: taskId,
        contextId: 'test-context-id',
        message: A2aMessage(
          messageId: 'msg-1',
          role: A2aRole.user,
          parts: <A2aPart>[A2aPart.text('hello')],
        ),
      );
    }

    test(
      'propagates AdkAbortException from requestConverter without emitting failed or canceled',
      () async {
        final _StubRunner runner = _StubRunner(
          agent: Agent(name: 'root_agent', model: _NoopModel()),
          appName: 'app',
          eventFactory: ({AdkAbortSignal? abortSignal}) =>
              const Stream<Event>.empty(),
        );
        final A2aAgentExecutor executor = A2aAgentExecutor(
          runner: runner,
          config: A2aAgentExecutorConfig(
            requestConverter:
                (
                  A2aRequestContext request,
                  A2APartToGenAIPartConverter converter,
                ) {
                  throw AdkAbortException('converter cancelled');
                },
          ),
        );
        final InMemoryA2aEventQueue queue = InMemoryA2aEventQueue();

        await expectLater(
          executor.execute(newRequestContext(), queue),
          throwsA(isA<AdkAbortException>()),
        );

        final List<A2aTaskState> states = queue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .map((A2aTaskStatusUpdateEvent event) => event.status.state)
            .toList();
        expect(states, isNot(contains(A2aTaskState.failed)));
        expect(states, isNot(contains(A2aTaskState.canceled)));
      },
    );

    test(
      'propagates AdkAbortException raised inside runner.runAsync without abortSignal',
      () async {
        AdkAbortSignal? observedSignal;
        final _StubRunner runner = _StubRunner(
          agent: Agent(name: 'root_agent', model: _NoopModel()),
          appName: 'app',
          eventFactory: ({AdkAbortSignal? abortSignal}) async* {
            observedSignal = abortSignal;
            throw AdkAbortException('runner cancelled directly');
          },
        );
        final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
        final InMemoryA2aEventQueue queue = InMemoryA2aEventQueue();

        await expectLater(
          executor.execute(newRequestContext(), queue),
          throwsA(isA<AdkAbortException>()),
        );

        expect(observedSignal?.aborted, isTrue);
        final List<A2aTaskState> states = queue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .map((A2aTaskStatusUpdateEvent event) => event.status.state)
            .toList();
        expect(states, <A2aTaskState>[
          A2aTaskState.submitted,
          A2aTaskState.working,
        ]);
        expect(states, isNot(contains(A2aTaskState.failed)));
        expect(states, isNot(contains(A2aTaskState.canceled)));
      },
    );

    test(
      'absorbs AdkAbortException and emits canceled when abortSignal was triggered by executor.cancel',
      () async {
        final Completer<void> started = Completer<void>();
        final _StubRunner runner = _StubRunner(
          agent: Agent(name: 'root_agent', model: _NoopModel()),
          appName: 'app',
          eventFactory: ({AdkAbortSignal? abortSignal}) async* {
            started.complete();
            final Completer<void> aborted = Completer<void>();
            abortSignal?.addListener((Object? _) {
              if (!aborted.isCompleted) {
                aborted.complete();
              }
            });
            await aborted.future;
            throw AdkAbortException('aborted by client');
          },
        );
        final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
        final InMemoryA2aEventQueue execQueue = InMemoryA2aEventQueue();
        final InMemoryA2aEventQueue cancelQueue = InMemoryA2aEventQueue();
        final A2aRequestContext reqContext = newRequestContext(
          taskId: 'task-client-cancel',
        );

        final Future<void> execFuture = executor.execute(reqContext, execQueue);
        await started.future;
        await executor.cancel(reqContext, cancelQueue);
        await execFuture;

        final List<A2aTaskState> states = execQueue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .map((A2aTaskStatusUpdateEvent event) => event.status.state)
            .toList();
        expect(states, contains(A2aTaskState.canceled));
        expect(states, isNot(contains(A2aTaskState.failed)));
      },
    );

    test(
      'still emits failed event for non-abort exceptions from runner.runAsync',
      () async {
        final _StubRunner runner = _StubRunner(
          agent: Agent(name: 'root_agent', model: _NoopModel()),
          appName: 'app',
          eventFactory: ({AdkAbortSignal? abortSignal}) async* {
            throw StateError('boom');
          },
        );
        final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
        final InMemoryA2aEventQueue queue = InMemoryA2aEventQueue();

        await executor.execute(newRequestContext(taskId: 'task-err'), queue);

        final List<A2aTaskState> states = queue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .map((A2aTaskStatusUpdateEvent event) => event.status.state)
            .toList();
        expect(states.last, A2aTaskState.failed);
      },
    );
  });
}
