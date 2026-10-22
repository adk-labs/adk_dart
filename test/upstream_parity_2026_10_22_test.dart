import 'dart:convert';
import 'dart:typed_data';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _MockClassifierLlm extends BaseLlm {
  _MockClassifierLlm(this.responseJson) : super(model: 'mock-classifier-llm');

  final Map<String, Object?> responseJson;
  LlmRequest? lastRequest;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    lastRequest = request;
    yield LlmResponse(
      modelVersion: 'mock-classifier-llm-v1',
      content: Content.modelText(jsonEncode(responseJson)),
    );
  }
}

void main() {
  group('Features & Warning Suppression (ea298d4bd, b592dee0a, ed76f9450)', () {
    tearDown(() {
      resetFeatureRegistryForTest();
    });

    test('promotes 12 mature features to stable and registers toolArgsMatcher', () {
      const List<FeatureName> promoted = <FeatureName>[
        FeatureName.agentConfig,
        FeatureName.agentState,
        FeatureName.authenticatedFunctionTool,
        FeatureName.baseAuthenticatedTool,
        FeatureName.googleCredentialsConfig,
        FeatureName.googleTool,
        FeatureName.jsonSchemaForFuncDecl,
        FeatureName.mcpGracefulErrorHandling,
        FeatureName.progressiveSseStreaming,
        FeatureName.toolConfig,
        FeatureName.toolConfirmation,
        FeatureName.pluggableAuth,
      ];
      for (final FeatureName feature in promoted) {
        final FeatureConfig? config = getFeatureConfig(feature);
        expect(config, isNotNull, reason: '${feature.value} should exist');
        expect(
          config!.stage,
          FeatureStage.stable,
          reason: '${feature.value} should be stable',
        );
        expect(config.defaultOn, isTrue);
      }

      final FeatureConfig? matcherConfig = getFeatureConfig(
        FeatureName.toolArgsMatcher,
      );
      expect(matcherConfig, isNotNull);
      expect(matcherConfig!.stage, FeatureStage.experimental);
      expect(matcherConfig.defaultOn, isFalse);
    });

    test('ADK_SUPPRESS_EXPERIMENTAL_FEATURE_WARNINGS suppresses experimental warnings', () {
      expect(
        isExperimentalWarningSuppressed(
          environment: <String, String>{
            experimentalWarningSuppressionEnvVar: 'true',
          },
        ),
        isTrue,
      );
      expect(
        isExperimentalWarningSuppressed(
          environment: <String, String>{
            experimentalWarningSuppressionEnvVar: 'false',
          },
        ),
        isFalse,
      );
    });
  });

  group('LlmClassifier & TypesafeClassifier (772b5773b, ddf8c55eb)', () {
    test('LlmClassifier classifies Choice, Binary, and Score questions and normalizes probabilities', () async {
      final _MockClassifierLlm mockLlm = _MockClassifierLlm(<String, Object?>{
        'route': <String, Object?>{'billing': 8.0, 'support': 2.0},
        'urgent': <String, Object?>{'probability': 0.85},
        'severity': <String, Object?>{'0': 1.0, '1': 1.0, '2': 2.0},
      });

      final LlmClassifier classifier = LlmClassifier(model: mockLlm);
      final ClassifierResponse response = await classifier.classify(
        input: 'My invoice was charged twice!',
        questions: <String, ClassifierQuestion>{
          'route': Choice(
            instructions: 'Pick a department',
            criteria: <String, Object?>{
              'billing': 'Invoice or payment question',
              'support': 'Technical issue',
            },
          ),
          'urgent': Binary(criteria: 'Requires immediate response'),
          'severity': Score(criteria: <Object?>['low', 'medium', 'high']),
        },
      );

      expect(response.modelVersion, 'mock-classifier-llm-v1');
      final ChoiceAnswer routeAnswer =
          response.answers['route']! as ChoiceAnswer;
      expect(routeAnswer.choice, 'billing');
      expect(routeAnswer.probabilities['billing'], closeTo(0.8, 1e-6));
      expect(routeAnswer.probabilities['support'], closeTo(0.2, 1e-6));

      final BinaryAnswer urgentAnswer =
          response.answers['urgent']! as BinaryAnswer;
      expect(urgentAnswer.probability, closeTo(0.85, 1e-6));

      final ScoreAnswer severityAnswer =
          response.answers['severity']! as ScoreAnswer;
      expect(severityAnswer.probabilities[0], closeTo(0.25, 1e-6));
      expect(severityAnswer.probabilities[1], closeTo(0.25, 1e-6));
      expect(severityAnswer.probabilities[2], closeTo(0.50, 1e-6));
      expect(severityAnswer.score, closeTo(1.25, 1e-6));
    });

    test('TypesafeClassifier retries on 429 and parses SystemOne answers', () async {
      int attempts = 0;
      final TypesafeClassifier classifier = TypesafeClassifier(
        apiKey: 'ts-test-key',
        httpTransport: ({
          required Uri url,
          required Map<String, String> headers,
          required Map<String, Object?> body,
          required Duration timeout,
        }) async {
          attempts += 1;
          expect(url.toString(), 'https://api.typesafe.ai/v1/systemone');
          expect(headers['Authorization'], 'Bearer ts-test-key');
          if (attempts == 1) {
            return const TypesafeHttpResponse(
              statusCode: 429,
              body: 'rate limited',
              headers: <String, String>{'retry-after': '0.001'},
            );
          }
          return TypesafeHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{
              'model': 'jev-2026-10',
              'answers': <String, Object?>{
                'is_safe': <String, Object?>{
                  'type': 'noul',
                  'noul': 0.95,
                  'confidence': 0.9,
                },
                'category': <String, Object?>{
                  'type': 'choice',
                  'choice': 'benign',
                  'probabilities': <String, Object?>{
                    'benign': 0.9,
                    'harmful': 0.1,
                  },
                },
              },
            }),
          );
        },
      );

      final ClassifierResponse response = await classifier.classify(
        input: 'Hello world',
        questions: <String, ClassifierQuestion>{
          'is_safe': Binary(
            instructions: 'Determine if the message is safe.',
            criteria: 'Safe message',
          ),
          'category': Choice(
            instructions: 'Classify the message category.',
            criteria: <String, Object?>{
              'benign': 'Benign input',
              'harmful': 'Harmful input',
            },
          ),
        },
      );

      expect(attempts, 2);
      expect(response.modelVersion, 'jev-2026-10');
      expect(
        (response.answers['is_safe']! as BinaryAnswer).probability,
        closeTo(0.95, 1e-6),
      );
      expect(
        (response.answers['category']! as ChoiceAnswer).choice,
        'benign',
      );
    });
  });

  group('ToolArgsMatcher (ed76f9450)', () {
    setUp(() {
      overrideFeatureEnabled(FeatureName.toolArgsMatcher, true);
    });

    tearDown(() {
      resetCustomArgMatchers();
      resetFeatureRegistryForTest();
    });

    test('matches exact, casefold, numeric, contains, ignore, and custom matchers', () {
      registerArgMatcher(
        'prefix',
        (Map<String, Object?> config) => _PrefixMatcher(
          prefix: '${config['prefix'] ?? ''}',
        ),
      );

      final ToolArgsMatcher matcher = ToolArgsMatcher.fromMapping(
        <String, Object?>{
          'city': <String, Object?>{'type': 'casefold', 'expected': 'Seoul'},
          'amount': <String, Object?>{
            'type': 'numeric',
            'expected': 100.0,
            'abs_tol': 0.5,
          },
          'notes': <String, Object?>{
            'type': 'contains',
            'expected': 'urgent',
            'case_sensitive': false,
          },
          'request_id': <String, Object?>{'type': 'ignore'},
          'code': <String, Object?>{'type': 'prefix', 'prefix': 'ORD-'},
        },
      );

      final ToolArgsMatchResult pass = matcher.match(<String, Object?>{
        'city': 'seoul',
        'amount': 100.25,
        'notes': 'Please handle as URGENT',
        'request_id': 'req-999',
        'code': 'ORD-12345',
      });
      expect(pass.matched, isTrue);

      final ToolArgsMatchResult fail = matcher.match(<String, Object?>{
        'city': 'busan',
        'amount': 102.0,
        'notes': 'normal priority',
        'request_id': 'req-999',
        'code': 'INV-12345',
        'extra': true,
      });
      expect(fail.matched, isFalse);
      expect(fail.unexpectedArgs, contains('extra'));
    });
  });

  group('ModelConsultObservabilityPlugin (f02b89c39)', () {
    test('tracks primary and advisor token usage, escalations, and cost', () async {
      final ModelConsultObservabilityPlugin plugin =
          ModelConsultObservabilityPlugin();
      final LlmAgent agent = LlmAgent(
        name: 'primary_agent',
        model: 'gemini-2.5-flash',
      );
      final Session session = Session(
        id: 's1',
        appName: 'app',
        userId: 'u1',
      );
      final InvocationContext invocationContext = InvocationContext(
        invocationId: 'inv_1',
        agent: agent,
        session: session,
        sessionService: InMemorySessionService(),
      );
      final CallbackContext callbackContext = CallbackContext(
        invocationContext,
      );

      await plugin.afterModelCallback(
        callbackContext: callbackContext,
        llmResponse: LlmResponse(
          modelVersion: 'gemini-2.5-flash',
          usageMetadata: <String, Object?>{
            'prompt_token_count': 1000,
            'candidates_token_count': 500,
          },
        ),
      );

      final ConsultModelTool consultTool = ConsultModelTool(
        model: 'gemini-2.5-pro',
      );
      final ToolContext toolContext = ToolContext(
        invocationContext,
        functionCallId: 'fc_1',
      );
      await plugin.afterToolCallback(
        tool: consultTool,
        toolArgs: <String, dynamic>{
          'question': 'How to structure this?',
          'focus': 'architecture',
        },
        toolContext: toolContext,
        result: <String, Object?>{
          'guidance': 'Use layered architecture.',
          'model': 'gemini-2.5-pro',
          'usage': <String, Object?>{
            'prompt_token_count': 2000,
            'candidates_token_count': 1000,
          },
        },
      );

      await plugin.afterRunCallback(invocationContext: invocationContext);

      final ModelConsultReport report = plugin.getReport();
      expect(report.invocations, 1);
      expect(report.escalatedInvocations, 1);
      expect(report.totalAdvisorCalls, 1);
      expect(report.escalationRate, 1.0);
      expect(report.advisorCallsByFocus['architecture'], 1);
      expect(report.totalPrimaryInputTokens, 1000);
      expect(report.totalPrimaryOutputTokens, 500);
      expect(report.totalAdvisorInputTokens, 2000);
      expect(report.totalAdvisorOutputTokens, 1000);
      expect(report.estimatedTotalCostUsd, greaterThan(0));
    });
  });

  group('VisualFrame ZIP_STORED pack and unpack (17d8a5aea)', () {
    test('round-trips visual frames through uncompressed ZIP archive', () {
      final List<VisualFrame> frames = <VisualFrame>[
        VisualFrame(
          blob: InlineData(
            mimeType: 'image/jpeg',
            data: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]),
          ),
          timestamp: 1000.0,
        ),
        VisualFrame(
          blob: InlineData(
            mimeType: 'image/png',
            data: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 4, 5, 6]),
          ),
          timestamp: 1000.25,
        ),
      ];

      final (Uint8List archiveBytes, Map<String, Object?> metadata) =
          packVisualFrames(frames);
      expect(archiveBytes, isNotEmpty);
      expect(metadata['formatVersion'], 1);
      expect(metadata['frameCount'], 2);

      final (List<VisualFrame> unpacked, Map<String, Object?> manifest) =
          unpackVisualFrames(archiveBytes);
      expect(unpacked, hasLength(2));
      expect(unpacked[0].mimeType, 'image/jpeg');
      expect(unpacked[0].data, frames[0].data);
      expect(unpacked[0].timestamp, closeTo(1000.0, 1e-3));
      expect(unpacked[1].mimeType, 'image/png');
      expect(unpacked[1].data, frames[1].data);
      expect(unpacked[1].timestamp, closeTo(1000.25, 1e-3));
      expect(manifest['formatVersion'], 1);
    });
  });

  group('Auth, Models, Tools, State & Workflow Parity', () {
    test('credentialFromString supports apiKey, http bearer, oauth2 and rejects http basic', () {
      final AuthCredential apiKeyCred = credentialFromString(
        'secret-api-key',
        <String, Object?>{'type': 'apiKey'},
      );
      expect(apiKeyCred.authType, AuthCredentialType.apiKey);
      expect(apiKeyCred.apiKey, 'secret-api-key');

      final AuthCredential bearerCred = credentialFromString(
        'bearer-token-123',
        <String, Object?>{'type': 'http', 'scheme': 'bearer'},
      );
      expect(bearerCred.authType, AuthCredentialType.http);
      expect(bearerCred.http?.credentials.token, 'bearer-token-123');

      expect(
        () => credentialFromString(
          'basic-token',
          <String, Object?>{'type': 'http', 'scheme': 'basic'},
        ),
        throwsArgumentError,
      );
    });

    test('Anthropic model_context_window_exceeded maps to MAX_TOKENS and Gemini 1.x rejects outputSchema+tools', () {
      expect(
        AnthropicLlm.toGoogleFinishReason('model_context_window_exceeded'),
        'MAX_TOKENS',
      );
      expect(
        canUseOutputSchemaWithTools(
          Gemini(model: 'gemini-1.5-pro'),
          environment: <String, String>{'GOOGLE_GENAI_USE_VERTEXAI': 'TRUE'},
        ),
        isFalse,
      );
      expect(
        canUseOutputSchemaWithTools(
          Gemini(model: 'gemini-2.5-flash'),
          environment: <String, String>{'GOOGLE_GENAI_USE_VERTEXAI': 'TRUE'},
        ),
        isTrue,
      );
    });

    test('extractTextFromContent skips thought parts', () {
      final Content content = Content(
        role: 'model',
        parts: <Part>[
          Part.text('internal reasoning', thought: true),
          Part.text('Hello'),
          Part.text('world'),
        ],
      );
      expect(extractTextFromContent(content), 'Hello world');
    });

    test('State.recordNestedWrites skips containers that do not round-trip through JSON', () {
      final Map<String, Object?> delta = <String, Object?>{};
      final State state = State(
        value: <String, Object?>{
          'valid': <String, Object?>{'count': 1},
          'invalid': <String, Object?>{'score': 1.0},
        },
        delta: delta,
      );

      final Map<String, Object?> validMap =
          state['valid']! as Map<String, Object?>;
      validMap['count'] = 2;

      final Map<String, Object?> invalidMap =
          state['invalid']! as Map<String, Object?>;
      invalidMap['score'] = double.nan;

      state.recordNestedWrites();
      expect(delta.containsKey('valid'), isTrue);
      expect((delta['valid']! as Map<String, Object?>)['count'], 2);
      expect(delta.containsKey('invalid'), isFalse);
    });

    test('BigtableParameterizedViewTool resolves viewParameterNames only from ToolContext attributes, not state', () async {
      final BigtableToolset toolset = BigtableToolset(
        viewParameterNames: <String>['user_id'],
      );
      final List<BaseTool> tools = await toolset.getTools();
      final BaseTool paramTool = tools.firstWhere(
        (BaseTool t) => t.name == 'execute_sql_parameterized',
      );
      final FunctionDeclaration? decl = paramTool.getDeclaration();
      expect(decl, isNotNull);
      final Map<String, Object?> props =
          decl!.parameters['properties']! as Map<String, Object?>;
      expect(props.containsKey('view_parameters'), isFalse);
    });
  });
}

class _PrefixMatcher extends BaseArgMatcher {
  _PrefixMatcher({required this.prefix});

  final String prefix;

  @override
  String get type => 'prefix';

  @override
  ArgMatchResult match(Object? actual) {
    final bool ok = actual is String && actual.startsWith(prefix);
    return ArgMatchResult(
      matched: ok,
      expected: prefix,
      actual: actual,
      matcherType: type,
      reason: ok ? null : 'Expected string starting with "$prefix".',
    );
  }
}
