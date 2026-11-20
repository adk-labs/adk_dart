import 'dart:async';
import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/models/malformed_function_calls.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

class _FakeA2aClient implements A2aClient {
  _FakeA2aClient(this.responses);

  final List<Object> responses;

  @override
  Stream<Object> sendMessage({
    required A2aMessage request,
    Map<String, Object?>? requestMetadata,
    A2aClientCallContext? context,
  }) async* {
    for (final Object item in responses) {
      yield item;
    }
  }
}

class _FakeA2aClientFactory implements A2aClientFactory {
  _FakeA2aClientFactory(this.client);

  final A2aClient client;

  @override
  A2aClient create(AgentCard agentCard) => client;
}

InvocationContext _newCtx(BaseAgent agent, {Content? userContent}) {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_nov20',
    agent: agent,
    session: Session(id: 'sess_nov20', appName: 'app', userId: 'user_1'),
    userContent: userContent,
  );
}

Map<String, Object?> _nonStreamingToolResponse(
  List<Object?> argumentsList,
  String finishReason, {
  String? text,
  Object? toolName,
}) {
  return <String, Object?>{
    'id': 'chatcmpl-1',
    'model': 'gpt-4o',
    'choices': <Object?>[
      <String, Object?>{
        'index': 0,
        'finish_reason': finishReason,
        'message': <String, Object?>{
          'role': 'assistant',
          'content': text,
          'tool_calls': <Object?>[
            for (int i = 0; i < argumentsList.length; i += 1)
              <String, Object?>{
                'id': 'call_$i',
                'type': 'function',
                'function': <String, Object?>{
                  'name': toolName ?? 'weather',
                  'arguments': argumentsList[i],
                },
              },
          ],
        },
      },
    ],
  };
}

Future<LlmResponse> _streamToolResponse(
  List<Object?> argumentsList,
  String finishReason, {
  String? text,
  Object? toolName,
}) async {
  final List<Map<String, Object?>> chunks = <Map<String, Object?>>[];
  if (text != null) {
    chunks.add(<String, Object?>{
      'model': 'gpt-4o',
      'choices': <Object?>[
        <String, Object?>{
          'index': 0,
          'delta': <String, Object?>{'role': 'assistant', 'content': text},
        },
      ],
    });
  }
  for (int i = 0; i < argumentsList.length; i += 1) {
    chunks.add(<String, Object?>{
      'model': 'gpt-4o',
      'choices': <Object?>[
        <String, Object?>{
          'index': 0,
          'delta': <String, Object?>{
            'tool_calls': <Object?>[
              <String, Object?>{
                'index': i,
                'id': 'call_$i',
                'type': 'function',
                'function': <String, Object?>{
                  'name': toolName ?? 'weather',
                  'arguments': argumentsList[i],
                },
              },
            ],
          },
        },
      ],
    });
  }
  chunks.add(<String, Object?>{
    'model': 'gpt-4o',
    'choices': <Object?>[
      <String, Object?>{
        'index': 0,
        'delta': <String, Object?>{},
        'finish_reason': finishReason,
      },
    ],
  });
  return _runSseChunks(chunks);
}

Future<LlmResponse> _runSseChunks(List<Map<String, Object?>> chunks) async {
  final String sseBody =
      '${chunks.map((Map<String, Object?> c) => 'data: ${jsonEncode(c)}\n\n').join()}data: [DONE]\n\n';
  final MockClient mockHttp = MockClient.streaming(
    (http.BaseRequest req, http.ByteStream bodyStream) async {
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(sseBody)),
        200,
        headers: <String, String>{'content-type': 'text/event-stream'},
      );
    },
  );
  final ChatCompletionsHttpClient client = ChatCompletionsHttpClient(
    httpClient: mockHttp,
  );
  final List<LlmResponse> responses = await client
      .generateContent(
        request: LlmRequest(model: 'gpt-4o'),
        stream: true,
        baseUrl: 'https://proxy.example/v1/chat/completions',
        headers: const <String, String>{},
      )
      .toList();
  return responses.last;
}

List<FunctionCall> _functionCallsOf(LlmResponse response) {
  final Content? content = response.content;
  if (content == null) {
    return const <FunctionCall>[];
  }
  return <FunctionCall>[
    for (final Part part in content.parts)
      if (part.functionCall != null) part.functionCall!,
  ];
}

void main() {
  group('1. Telemetry gen_ai.response.model parity (ecc6b6e01)', () {
    setUp(() {
      tracer.clear();
      resetOtelLoggerForTest();
    });

    test('genAiResponseModel constant matches OpenTelemetry semconv', () {
      expect(genAiResponseModel, 'gen_ai.response.model');
    });

    test('traceCallLlm sets gen_ai.response.model with fallback chain', () {
      final LlmAgent parent = LlmAgent(
        name: 'parent',
        model: 'gemini-2.0-flash',
      );
      final LlmAgent child = LlmAgent(name: 'child', model: '');
      parent.subAgents.add(child);
      child.parentAgent = parent;
      final InvocationContext ctx = _newCtx(child);

      // 1) Prefers llmResponse.modelVersion
      final TraceSpanRecord span1 = TraceSpanRecord('call_llm');
      traceCallLlm(
        ctx,
        'ev_1',
        LlmRequest(model: 'gemini-pro'),
        LlmResponse(modelVersion: 'gemini-2.5-flash-001', finishReason: 'STOP'),
        span: span1,
      );
      expect(span1.attributes[genAiResponseModel], 'gemini-2.5-flash-001');

      // 2) Falls back to llmRequest.model when modelVersion is absent
      final TraceSpanRecord span2 = TraceSpanRecord('call_llm');
      traceCallLlm(
        ctx,
        'ev_2',
        LlmRequest(model: 'gemini-pro'),
        LlmResponse(finishReason: 'STOP'),
        span: span2,
      );
      expect(span2.attributes[genAiResponseModel], 'gemini-pro');

      // 3) Falls back to inherited agent model when request & response lack model
      final TraceSpanRecord span3 = TraceSpanRecord('call_llm');
      traceCallLlm(
        ctx,
        'ev_3',
        LlmRequest(),
        LlmResponse(finishReason: 'STOP'),
        span: span3,
      );
      expect(span3.attributes[genAiResponseModel], 'gemini-2.0-flash');
    });

    test('traceGenerateContentResult sets gen_ai.response.model', () {
      final TraceSpanRecord span = TraceSpanRecord('generate_content');
      // ignore: deprecated_member_use_from_same_package
      traceGenerateContentResult(
        span,
        LlmResponse(modelVersion: 'gemini-2.5-flash-001', finishReason: 'STOP'),
      );
      expect(span.attributes[genAiResponseModel], 'gemini-2.5-flash-001');

      final TraceSpanRecord partialSpan = TraceSpanRecord('generate_content');
      // ignore: deprecated_member_use_from_same_package
      traceGenerateContentResult(
        partialSpan,
        LlmResponse(modelVersion: 'gemini-2.5-flash-001', partial: true),
      );
      expect(partialSpan.attributes.containsKey(genAiResponseModel), isFalse);
    });

    test(
      'traceInferenceResult sets gen_ai.response.model from modelVersion, request, or inherited agent',
      () {
        final LlmAgent parent = LlmAgent(
          name: 'parent_agent',
          model: 'gemini-2.0-flash',
        );
        final LlmAgent subAgent = LlmAgent(name: 'sub_agent', model: '');
        parent.subAgents.add(subAgent);
        subAgent.parentAgent = parent;
        final InvocationContext ctx = _newCtx(subAgent);

        // From modelVersion
        final TraceSpanRecord span1 = TraceSpanRecord('gc_1');
        traceInferenceResult(
          span1,
          LlmResponse(turnComplete: true, modelVersion: 'served-model-v2'),
          invocationContext: ctx,
        );
        expect(span1.attributes[genAiResponseModel], 'served-model-v2');

        // Fallback to inherited agent model
        final TraceSpanRecord span2 = TraceSpanRecord('gc_2');
        traceInferenceResult(
          span2,
          LlmResponse(turnComplete: true),
          invocationContext: ctx,
        );
        expect(span2.attributes[genAiResponseModel], 'gemini-2.0-flash');

        // Omitted when no model is known anywhere
        final TraceSpanRecord span3 = TraceSpanRecord('gc_3');
        traceInferenceResult(span3, LlmResponse(turnComplete: true));
        expect(span3.attributes.containsKey(genAiResponseModel), isFalse);
      },
    );

    test(
      'useInferenceSpan stores llmRequest on GenerateContentSpan and passes it to _inferenceSystemName',
      () async {
        final LlmAgent agent = LlmAgent(name: 'claude_agent', model: '');
        final InvocationContext ctx = _newCtx(agent);
        final LlmRequest request = LlmRequest(model: 'claude-3-5-sonnet');
        final Event event = Event(invocationId: 'inv_nov20', author: 'a');

        await useInferenceSpan<void>(
          request,
          ctx,
          event,
          (GenerateContentSpan? gcSpan) async {
            expect(gcSpan, isNotNull);
            expect(gcSpan!.llmRequest, same(request));

            traceInferenceResult(
              gcSpan,
              LlmResponse(
                content: Content.modelText('hello'),
                finishReason: 'STOP',
              ),
              environment: const <String, String>{},
            );

            expect(
              gcSpan.span.attributes[genAiResponseModel],
              'claude-3-5-sonnet',
            );
          },
          environment: const <String, String>{},
        );

        final OTelLogRecord choiceLog = otelLogger.records.lastWhere(
          (OTelLogRecord r) => r.eventName == 'gen_ai.choice',
        );
        expect(choiceLog.attributes['gen_ai.system'], 'anthropic');
      },
    );
  });

  group('2. Malformed function calls & ApigeeLlm parity (7b07e7df7)', () {
    test('reportMalformedFunctionCalls leaves response untouched when empty', () {
      final LlmResponse response = LlmResponse(
        content: Content(role: 'model', parts: <Part>[]),
        finishReason: 'STOP',
      );
      final LlmResponse result = reportMalformedFunctionCalls(
        response,
        const <Object?>[],
      );
      expect(identical(result, response), isTrue);
      expect(response.content, isNotNull);
      expect(response.finishReason, 'STOP');
      expect(response.errorCode, isNull);
      expect(response.errorMessage, isNull);
    });

    test('reportMalformedFunctionCalls keeps remaining parts and drops empty content', () {
      final Part textPart = Part.text('Checking.');
      final Part callPart = Part.fromFunctionCall(
        name: 'time',
        args: <String, dynamic>{'zone': 'UTC'},
      );
      final LlmResponse withParts = LlmResponse(
        content: Content(role: 'model', parts: <Part>[textPart, callPart]),
        finishReason: 'STOP',
      );
      reportMalformedFunctionCalls(withParts, const <Object?>['weather']);
      expect(withParts.content, isNotNull);
      expect(withParts.content!.parts, hasLength(2));
      expect(withParts.finishReason, 'MALFORMED_FUNCTION_CALL');
      expect(withParts.errorCode, 'MALFORMED_FUNCTION_CALL');

      final LlmResponse emptyParts = LlmResponse(
        content: Content(role: 'model', parts: <Part>[]),
        finishReason: 'STOP',
      );
      reportMalformedFunctionCalls(emptyParts, const <Object?>['weather']);
      expect(emptyParts.content, isNull);
    });

    test('reportMalformedFunctionCalls finishReason preservation rules', () {
      final Map<String?, String> cases = <String?, String>{
        null: 'MALFORMED_FUNCTION_CALL',
        'STOP': 'MALFORMED_FUNCTION_CALL',
        'OTHER': 'MALFORMED_FUNCTION_CALL',
        'FINISH_REASON_UNSPECIFIED': 'MALFORMED_FUNCTION_CALL',
        'MAX_TOKENS': 'MAX_TOKENS',
        'SAFETY': 'SAFETY',
      };
      cases.forEach((String? initial, String expected) {
        final LlmResponse response = LlmResponse(
          content: Content(role: 'model', parts: <Part>[]),
          finishReason: initial,
        );
        reportMalformedFunctionCalls(response, const <Object?>['weather']);
        expect(response.finishReason, expected);
        expect(response.errorCode, expected);
      });
    });

    test('reportMalformedFunctionCalls formats names and preserves existing errorMessage', () {
      final LlmResponse r1 = LlmResponse(finishReason: 'STOP');
      reportMalformedFunctionCalls(r1, const <Object?>['weather', null, 5, '']);
      expect(
        r1.errorMessage,
        'Arguments for the following function calls were not a valid JSON '
        'object: weather, <unnamed>, <unnamed>, <unnamed>',
      );

      final LlmResponse r2 = LlmResponse(
        finishReason: 'MAX_TOKENS',
        errorMessage: 'Maximum tokens reached',
      );
      reportMalformedFunctionCalls(r2, const <Object?>['weather']);
      expect(
        r2.errorMessage,
        'Maximum tokens reached. Arguments for the following function calls '
        'were not a valid JSON object: weather',
      );
    });

    for (final bool streaming in const <bool>[false, true]) {
      final String mode = streaming ? 'streaming' : 'non-streaming';

      test(
        'ApigeeLlm ($mode) reports malformed tool call arguments across finish reasons',
        () async {
          for (final String finishReason in const <String>[
            'tool_calls',
            'stop',
            'unknown',
          ]) {
            for (final String badArgs in const <String>[
              '[1, 2]',
              '"x"',
              '5',
              'null',
              '{"city":"Pa',
              ' ',
            ]) {
              final LlmResponse response = streaming
                  ? await _streamToolResponse(<Object?>[badArgs], finishReason)
                  : ApigeeLlm.parseChatCompletionsResponse(
                      _nonStreamingToolResponse(<Object?>[badArgs], finishReason),
                    );
              expect(response.partial, isNot(isTrue));
              expect(response.content, isNull);
              expect(response.finishReason, 'MALFORMED_FUNCTION_CALL');
              expect(response.errorCode, 'MALFORMED_FUNCTION_CALL');
              expect(response.errorMessage, contains('weather'));
            }
          }
        },
      );

      test(
        'ApigeeLlm ($mode) drops only malformed call and keeps valid sibling + text',
        () async {
          for (final int badIndex in const <int>[0, 1]) {
            for (final String badArgs in const <String>[
              '[1, 2]',
              '{"city":"Pa',
            ]) {
              final List<Object?> args = <Object?>[
                '{"city":"Paris"}',
                '{"city":"Paris"}',
              ];
              args[badIndex] = badArgs;
              final LlmResponse response = streaming
                  ? await _streamToolResponse(
                      args,
                      'tool_calls',
                      text: 'Checking.',
                    )
                  : ApigeeLlm.parseChatCompletionsResponse(
                      _nonStreamingToolResponse(
                        args,
                        'tool_calls',
                        text: 'Checking.',
                      ),
                    );
              expect(response.content, isNotNull);
              expect(response.content!.parts.first.text, 'Checking.');
              final List<FunctionCall> calls = _functionCallsOf(response);
              expect(calls, hasLength(1));
              expect(calls.single.args, <String, dynamic>{'city': 'Paris'});
              expect(response.errorCode, 'MALFORMED_FUNCTION_CALL');
            }
          }
        },
      );

      test(
        'ApigeeLlm ($mode) preserves content_filter finish reason as SAFETY',
        () async {
          final LlmResponse response = streaming
              ? await _streamToolResponse(
                  const <Object?>['[1, 2]'],
                  'content_filter',
                )
              : ApigeeLlm.parseChatCompletionsResponse(
                  _nonStreamingToolResponse(
                    const <Object?>['[1, 2]'],
                    'content_filter',
                  ),
                );
          expect(response.finishReason, 'SAFETY');
          expect(response.errorCode, 'SAFETY');
          expect(_functionCallsOf(response), isEmpty);
        },
      );

      test(
        'ApigeeLlm ($mode) reports non-string tool name as <unnamed>',
        () async {
          final LlmResponse response = streaming
              ? await _streamToolResponse(
                  const <Object?>['[1, 2]'],
                  'stop',
                  toolName: 5,
                )
              : ApigeeLlm.parseChatCompletionsResponse(
                  _nonStreamingToolResponse(
                    const <Object?>['[1, 2]'],
                    'stop',
                    toolName: 5,
                  ),
                );
          expect(response.errorCode, 'MALFORMED_FUNCTION_CALL');
          expect(response.errorMessage, contains('<unnamed>'));
        },
      );

      test(
        'ApigeeLlm ($mode) allows null or empty tool arguments without error',
        () async {
          for (final Object? emptyArgs in const <Object?>[null, '']) {
            final LlmResponse response = streaming
                ? await _streamToolResponse(<Object?>[emptyArgs], 'tool_calls')
                : ApigeeLlm.parseChatCompletionsResponse(
                    _nonStreamingToolResponse(<Object?>[emptyArgs], 'tool_calls'),
                  );
            expect(response.errorCode, isNull);
            final List<FunctionCall> calls = _functionCallsOf(response);
            expect(calls, hasLength(1));
            expect(calls.single.name, 'weather');
            expect(calls.single.args, isEmpty);
          }
        },
      );
    }

    test(
      'ApigeeLlm streaming does not salvage an array wrapping an object into arguments',
      () async {
        final LlmResponse response = await _runSseChunks(<Map<String, Object?>>[
          for (final String frag in const <String>[
            '[',
            '{"city":"Paris"}',
            ']',
          ])
            <String, Object?>{
              'model': 'gpt-4o',
              'choices': <Object?>[
                <String, Object?>{
                  'index': 0,
                  'delta': <String, Object?>{
                    'tool_calls': <Object?>[
                      <String, Object?>{
                        'index': 0,
                        'id': 'call_0',
                        'type': 'function',
                        'function': <String, Object?>{
                          'name': 'weather',
                          'arguments': frag,
                        },
                      },
                    ],
                  },
                },
              ],
            },
          <String, Object?>{
            'model': 'gpt-4o',
            'choices': <Object?>[
              <String, Object?>{
                'index': 0,
                'delta': <String, Object?>{},
                'finish_reason': 'tool_calls',
              },
            ],
          },
        ]);
        expect(_functionCallsOf(response), isEmpty);
        expect(response.errorCode, 'MALFORMED_FUNCTION_CALL');
      },
    );

    test(
      'ApigeeLlm non-streaming checks legacy function_call and keeps valid legacy beside bad tool_call',
      () {
        final Map<String, Object?> badLegacy = <String, Object?>{
          'model': 'gpt-4o',
          'choices': <Object?>[
            <String, Object?>{
              'index': 0,
              'finish_reason': 'stop',
              'message': <String, Object?>{
                'role': 'assistant',
                'function_call': <String, Object?>{
                  'name': 'weather',
                  'arguments': '[1, 2]',
                },
              },
            },
          ],
        };
        final LlmResponse r1 = ApigeeLlm.parseChatCompletionsResponse(
          badLegacy,
        );
        expect(_functionCallsOf(r1), isEmpty);
        expect(r1.errorCode, 'MALFORMED_FUNCTION_CALL');

        final Map<String, Object?> mixed = _nonStreamingToolResponse(
          const <Object?>['[1, 2]'],
          'stop',
        );
        final Map<String, Object?> msg =
            (mixed['choices']! as List<Object?>).first! as Map<String, Object?>;
        (msg['message']! as Map<String, Object?>)['function_call'] =
            <String, Object?>{
              'name': 'time',
              'arguments': '{"zone":"UTC"}',
            };
        final LlmResponse r2 = ApigeeLlm.parseChatCompletionsResponse(mixed);
        final List<FunctionCall> calls = _functionCallsOf(r2);
        expect(calls, hasLength(1));
        expect(calls.single.name, 'time');
        expect(calls.single.args, <String, dynamic>{'zone': 'UTC'});
        expect(r2.errorCode, 'MALFORMED_FUNCTION_CALL');
      },
    );
  });

  group('3. RemoteA2aAgent streamed artifact revert parity (5523aa733)', () {
    AgentCard makeCard() => AgentCard(
      name: 'remote_agent',
      description: 'remote',
      url: 'https://example.invalid/a2a',
      version: '1.0.0',
      capabilities: AgentCapabilities(streaming: true),
      defaultInputModes: <String>['text/plain'],
      defaultOutputModes: <String>['text/plain'],
      skills: <AgentSkill>[],
    );

    test(
      'streamed chunks without lastChunk do not emit a duplicate aggregated non-partial event',
      () async {
        final A2aTask working = A2aTask(
          id: 'task_rev_1',
          contextId: 'ctx_rev_1',
          status: A2aTaskStatus(state: A2aTaskState.working),
        );
        final A2aTask completed = A2aTask(
          id: 'task_rev_1',
          contextId: 'ctx_rev_1',
          status: A2aTaskStatus(state: A2aTaskState.completed),
        );
        final _FakeA2aClient client = _FakeA2aClient(<Object>[
          (
            working,
            A2aTaskArtifactUpdateEvent(
              taskId: 'task_rev_1',
              artifact: A2aArtifact(
                artifactId: 'ans_1',
                parts: <A2aPart>[A2aPart.text('Chunk 1 ')],
              ),
              append: false,
              lastChunk: false,
            ),
          ),
          (
            working,
            A2aTaskArtifactUpdateEvent(
              taskId: 'task_rev_1',
              artifact: A2aArtifact(
                artifactId: 'ans_1',
                parts: <A2aPart>[A2aPart.text('Chunk 2')],
              ),
              append: true,
              lastChunk: false,
            ),
          ),
          (
            completed,
            A2aTaskStatusUpdateEvent(
              taskId: 'task_rev_1',
              status: A2aTaskStatus(state: A2aTaskState.completed),
              finalEvent: true,
            ),
          ),
        ]);

        final RemoteA2aAgent agent = RemoteA2aAgent(
          name: 'remote_agent',
          agentCard: makeCard(),
          a2aClientFactory: _FakeA2aClientFactory(client),
        );
        final List<Event> events = await agent
            .runAsync(_newCtx(agent, userContent: Content.userText('hi')))
            .toList();

        final List<Event> partials = events
            .where((Event e) => e.partial == true)
            .toList();
        final List<Event> nonPartialText = events
            .where(
              (Event e) =>
                  e.partial != true && (e.content?.parts.isNotEmpty ?? false),
            )
            .toList();
        expect(partials, hasLength(2));
        expect(nonPartialText, isEmpty);
      },
    );
  });
}
