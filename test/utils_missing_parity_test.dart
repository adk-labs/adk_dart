import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopAgent extends BaseAgent {
  _NoopAgent() : super(name: 'noop_agent');

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}
}

Future<List<String>> _capturePrints(FutureOr<void> Function() action) async {
  final List<String> lines = <String>[];
  await runZoned(
    () async {
      await action();
    },
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        lines.add(line);
      },
    ),
  );
  return lines;
}

void main() {
  group('missing utils parity', () {
    setUp(() {
      resetFeatureRegistryForTest();
    });

    test('client label context and headers', () async {
      final List<String> labels = getClientLabels(
        environment: <String, String>{},
      );
      expect(labels.first, 'google-adk/$adkVersion');
      expect(labels[1], startsWith('gl-dart/'));

      final List<String> agentEngineLabels = getClientLabels(
        environment: <String, String>{
          'GOOGLE_CLOUD_AGENT_ENGINE_ID': 'projects/p/locations/l/reasons/r',
        },
      );
      expect(agentEngineLabels.first, contains('+remote_reasoning_engine'));

      final List<String> contextual = await clientLabelContext(
        'custom-label',
        () async {
          await Future<void>.delayed(Duration.zero);
          return getClientLabels(environment: <String, String>{});
        },
      );
      expect(contextual.last, 'custom-label');

      expect(
        () => clientLabelContext(
          'outer',
          () => clientLabelContext('inner', () => null),
        ),
        throwsA(isA<ArgumentError>()),
      );

      final Map<String, String> tracking = getTrackingHeaders(
        environment: <String, String>{},
      );
      expect(tracking['x-goog-api-client'], tracking['user-agent']);

      final Map<String, String> merged = mergeTrackingHeaders(<String, String>{
        'x-goog-api-client': 'custom/1 custom/1',
      }, environment: <String, String>{});
      expect(merged['x-goog-api-client'], contains('custom/1'));
      expect(
        merged['x-goog-api-client']!
            .split(' ')
            .where((String p) => p == 'custom/1'),
        hasLength(1),
      );
    });

    test('printEvent follows verbose and non-verbose contracts', () async {
      final Event event = Event(
        invocationId: 'inv',
        author: 'agent',
        content: Content(
          parts: <Part>[
            Part.text('hello'),
            Part.text(' world'),
            Part.fromFunctionCall(
              name: 'tool',
              args: <String, dynamic>{'x': 1},
            ),
            Part.fromFunctionResponse(
              name: 'tool',
              response: <String, dynamic>{'ok': true},
            ),
            Part.fromInlineData(mimeType: 'image/png', data: <int>[1, 2, 3]),
            Part.fromFileData(fileUri: 'gs://bucket/file.txt'),
          ],
        ),
      );

      final List<String> compact = await _capturePrints(() {
        printEvent(event);
      });
      expect(compact, hasLength(1));
      expect(compact.single, 'agent > hello world');

      final List<String> verbose = await _capturePrints(() {
        printEvent(event, verbose: true);
      });
      expect(verbose.length, greaterThan(1));
      expect(verbose.join('\n'), contains('Calling tool: tool'));
      expect(verbose.join('\n'), contains('Tool result'));
      expect(verbose.join('\n'), contains('Inline data: image/png'));
      expect(verbose.join('\n'), contains('File: gs://bucket/file.txt'));
    });

    test('injectSessionState populates state and artifacts', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      session.state['city'] = 'Seoul';
      session.state['app:region'] = 'kr';

      final InMemoryArtifactService artifactService = InMemoryArtifactService();
      await artifactService.saveArtifact(
        appName: session.appName,
        userId: session.userId,
        sessionId: session.id,
        filename: 'memo.txt',
        artifact: Part.text('artifact-value'),
      );

      final InvocationContext invocationContext = InvocationContext(
        artifactService: artifactService,
        sessionService: sessionService,
        invocationId: 'inv',
        agent: _NoopAgent(),
        session: session,
      );
      final ReadonlyContext readonlyContext = ReadonlyContext(
        invocationContext,
      );

      final String rendered = await injectSessionState(
        'City={city};Region={app:region};Missing={missing?};'
        'Artifact={artifact.memo.txt};Raw={1abc}',
        readonlyContext,
      );
      expect(
        rendered,
        'City=Seoul;Region=kr;Missing=;Artifact=artifact-value;Raw={1abc}',
      );

      await expectLater(
        injectSessionState('Missing={missing}', readonlyContext),
        throwsA(isA<StateError>()),
      );

      await expectLater(
        injectSessionState('ArtifactMissing={artifact.none}', readonlyContext),
        throwsA(isA<StateError>()),
      );

      expect(isValidStateName('city'), isTrue);
      expect(isValidStateName('app:region'), isTrue);
      expect(isValidStateName('invalid-name'), isFalse);
      expect(isValidStateName('system:region'), isFalse);
    });

    test('cache performance analyzer computes ratios and totals', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );

      await sessionService.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv1',
          author: 'agent',
          usageMetadata: <String, Object?>{
            'promptTokenCount': 20,
            'cachedContentTokenCount': 5,
          },
          cacheMetadata: CacheMetadata(
            cacheName: 'cache-a',
            fingerprint: 'fp-1',
            invocationsUsed: 1,
            contentsCount: 3,
          ),
        ),
      );
      await sessionService.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv2',
          author: 'agent',
          usageMetadata: <String, Object?>{
            'prompt_token_count': 30,
            'cached_content_token_count': 15,
          },
          cacheMetadata: <String, Object?>{
            'cache_name': 'cache-b',
            'fingerprint': 'fp-2',
            'invocations_used': 3,
            'contents_count': 5,
          },
        ),
      );

      final CachePerformanceAnalyzer analyzer = CachePerformanceAnalyzer(
        sessionService,
      );
      final Map<String, Object?> result = await analyzer
          .analyzeAgentCachePerformance(
            sessionId: session.id,
            userId: session.userId,
            appName: session.appName,
            agentName: 'agent',
          );

      expect(result['status'], 'active');
      expect(result['requests_with_cache'], 2);
      expect(result['avg_invocations_used'], 2.0);
      expect(result['latest_cache'], 'cache-b');
      expect(result['cache_refreshes'], 2);
      expect(result['total_invocations'], 4);
      expect(result['total_prompt_tokens'], 50);
      expect(result['total_cached_tokens'], 20);
      expect(result['cache_hit_ratio_percent'], closeTo(40.0, 0.0001));
      expect(result['cache_utilization_ratio_percent'], closeTo(100.0, 0.0001));
      expect(result['avg_cached_tokens_per_request'], 10.0);
      expect(result['total_requests'], 2);
      expect(result['requests_with_cache_hits'], 2);

      final Session emptySession = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final Map<String, Object?> empty = await analyzer
          .analyzeAgentCachePerformance(
            sessionId: emptySession.id,
            userId: emptySession.userId,
            appName: emptySession.appName,
            agentName: 'agent',
          );
      expect(empty['status'], 'no_cache_data');
    });

    test(
      'streaming response aggregator supports non-progressive mode',
      () async {
        overrideFeatureEnabled(FeatureName.progressiveSseStreaming, false);
        final StreamingResponseAggregator aggregator =
            StreamingResponseAggregator();

        final List<LlmResponse> first = await aggregator
            .processResponse(
              LlmResponse(content: Content(parts: <Part>[Part.text('Hel')])),
            )
            .toList();
        expect(first, hasLength(1));
        expect(first.single.partial, isTrue);

        final List<LlmResponse> second = await aggregator
            .processResponse(
              LlmResponse(content: Content(parts: <Part>[Part.text('lo')])),
            )
            .toList();
        expect(second, hasLength(1));
        expect(second.single.partial, isTrue);

        final List<LlmResponse> third = await aggregator
            .processResponse(
              LlmResponse(
                content: Content(
                  parts: <Part>[
                    Part.fromFunctionCall(
                      name: 'get_weather',
                      args: <String, dynamic>{'city': 'Seoul'},
                    ),
                  ],
                ),
                finishReason: 'STOP',
              ),
            )
            .toList();
        expect(third, hasLength(2));
        expect(third.first.content?.parts.first.text, 'Hello');
        expect(
          third.last.content?.parts.first.functionCall?.name,
          'get_weather',
        );
        expect(aggregator.close(), isNull);
      },
    );

    test('streaming response aggregator supports progressive mode', () async {
      overrideFeatureEnabled(FeatureName.progressiveSseStreaming, true);
      final StreamingResponseAggregator aggregator =
          StreamingResponseAggregator();

      final List<LlmResponse> chunk1 = await aggregator
          .processResponse(
            LlmResponse(content: Content(parts: <Part>[Part.text('Hello ')])),
          )
          .toList();
      expect(chunk1.single.partial, isTrue);

      await aggregator
          .processResponse(
            LlmResponse(
              content: Content(
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: 'lookup_city',
                    args: <String, dynamic>{
                      'partial_args': <Map<String, Object?>>[
                        <String, Object?>{
                          'json_path': r'$.city',
                          'string_value': 'Se',
                        },
                      ],
                      'will_continue': true,
                    },
                  ),
                ],
              ),
            ),
          )
          .toList();

      await aggregator
          .processResponse(
            LlmResponse(
              content: Content(
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: '',
                    args: <String, dynamic>{
                      'partial_args': <Map<String, Object?>>[
                        <String, Object?>{
                          'json_path': r'$.city',
                          'string_value': 'oul',
                        },
                      ],
                      'will_continue': false,
                    },
                  ),
                ],
              ),
              finishReason: 'STOP',
            ),
          )
          .toList();

      final LlmResponse? merged = aggregator.close();
      expect(merged, isNotNull);
      expect(merged!.partial, isFalse);
      expect(merged.content, isNotNull);
      expect(merged.content!.parts, hasLength(2));
      expect(merged.content!.parts.first.text, 'Hello ');
      expect(merged.content!.parts[1].functionCall?.name, 'lookup_city');
      expect(merged.content!.parts[1].functionCall?.args['city'], 'Seoul');
    });

    test('getExpressModeApiKey parity behavior', () {
      expect(
        () => getExpressModeApiKey(
          project: 'project',
          expressModeApiKey: 'key',
          environment: <String, String>{'GOOGLE_GENAI_USE_VERTEXAI': '1'},
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        getExpressModeApiKey(
          environment: <String, String>{
            'GOOGLE_GENAI_USE_VERTEXAI': 'true',
            'GOOGLE_API_KEY': 'env-key',
          },
        ),
        'env-key',
      );

      expect(
        getExpressModeApiKey(
          expressModeApiKey: 'direct-key',
          environment: <String, String>{'GOOGLE_GENAI_USE_VERTEXAI': '0'},
        ),
        isNull,
      );
    });
  });
}
