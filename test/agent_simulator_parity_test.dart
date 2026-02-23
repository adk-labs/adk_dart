import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('agent simulator config parity', () {
    test('injection config requires exactly one injected target', () {
      expect(() => InjectionConfig(), throwsA(isA<ArgumentError>()));
      expect(
        () => InjectionConfig(
          injectedError: InjectedError(
            injectedHttpErrorCode: 500,
            errorMessage: 'boom',
          ),
          injectedResponse: <String, Object?>{'status': 'ok'},
        ),
        throwsA(isA<ArgumentError>()),
      );

      final InjectionConfig config = InjectionConfig(
        injectionProbability: 1.0,
        injectedError: InjectedError(
          injectedHttpErrorCode: 404,
          errorMessage: 'not found',
        ),
      );
      expect(config.toJson()['injected_error'], isA<Map>());
    });

    test('tool and agent simulator configs validate contracts', () {
      expect(
        () => ToolSimulationConfig(toolName: 'lookup'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => AgentSimulatorConfig(
          toolSimulationConfigs: <ToolSimulationConfig>[],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => AgentSimulatorConfig(
          toolSimulationConfigs: <ToolSimulationConfig>[
            ToolSimulationConfig(
              toolName: 'dup',
              injectionConfigs: <InjectionConfig>[
                InjectionConfig(
                  injectedResponse: <String, Object?>{'ok': true},
                ),
              ],
            ),
            ToolSimulationConfig(
              toolName: 'dup',
              injectionConfigs: <InjectionConfig>[
                InjectionConfig(
                  injectedResponse: <String, Object?>{'ok': true},
                ),
              ],
            ),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('agent simulator engine/plugin parity', () {
    test('simulate returns null when tool is not configured', () async {
      final AgentSimulatorEngine engine = AgentSimulatorEngine(
        AgentSimulatorConfig(
          toolSimulationConfigs: <ToolSimulationConfig>[
            ToolSimulationConfig(
              toolName: 'known_tool',
              injectionConfigs: <InjectionConfig>[
                InjectionConfig(
                  injectedResponse: <String, Object?>{'status': 'ok'},
                ),
              ],
            ),
          ],
        ),
      );

      final Map<String, Object?>? simulated = await engine.simulate(
        _FakeTool(name: 'other_tool'),
        <String, Object?>{},
        Object(),
      );
      expect(simulated, isNull);
    });

    test('simulate applies matching injection and injected error', () async {
      final AgentSimulatorEngine engine = AgentSimulatorEngine(
        AgentSimulatorConfig(
          toolSimulationConfigs: <ToolSimulationConfig>[
            ToolSimulationConfig(
              toolName: 'lookup',
              injectionConfigs: <InjectionConfig>[
                InjectionConfig(
                  matchArgs: <String, Object?>{'id': '1'},
                  injectedResponse: <String, Object?>{
                    'status': 'success',
                    'value': 'one',
                  },
                ),
              ],
            ),
            ToolSimulationConfig(
              toolName: 'error_tool',
              injectionConfigs: <InjectionConfig>[
                InjectionConfig(
                  injectedError: InjectedError(
                    injectedHttpErrorCode: 503,
                    errorMessage: 'service unavailable',
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      final Map<String, Object?>? hit = await engine.simulate(
        _FakeTool(name: 'lookup'),
        <String, Object?>{'id': '1'},
        Object(),
      );
      expect(hit, containsPair('status', 'success'));
      expect(hit, containsPair('value', 'one'));

      final Map<String, Object?>? miss = await engine.simulate(
        _FakeTool(name: 'lookup'),
        <String, Object?>{'id': '2'},
        Object(),
      );
      expect(miss, isNull);

      final Map<String, Object?>? injectedError = await engine.simulate(
        _FakeTool(name: 'error_tool'),
        <String, Object?>{},
        Object(),
      );
      expect(injectedError, containsPair('error_code', 503));
      expect(
        injectedError,
        containsPair('error_message', 'service unavailable'),
      );
    });

    test(
      'simulate falls back to configured mock strategy when no injection',
      () async {
        final AgentSimulatorEngine engine = AgentSimulatorEngine(
          AgentSimulatorConfig(
            toolSimulationConfigs: <ToolSimulationConfig>[
              ToolSimulationConfig(
                toolName: 'create_ticket',
                mockStrategyType: MockStrategy.mockStrategyToolSpec,
              ),
            ],
          ),
          strategyFactory:
              (
                MockStrategy mockStrategyType,
                String llmName,
                GenerateContentConfig llmConfig,
              ) {
                return _StaticMockStrategy(<String, Object?>{
                  'status': 'mocked',
                  'ticket_id': 'T-1',
                });
              },
        );

        final Map<String, Object?>? simulated = await engine.simulate(
          _FakeTool(name: 'create_ticket'),
          <String, Object?>{'user_id': 'u1'},
          Object(),
        );

        expect(simulated, containsPair('status', 'mocked'));
        expect(simulated, containsPair('ticket_id', 'T-1'));
      },
    );

    test('plugin delegates beforeToolCallback to simulator engine', () async {
      final AgentSimulatorPlugin plugin = AgentSimulatorFactory.createPlugin(
        AgentSimulatorConfig(
          toolSimulationConfigs: <ToolSimulationConfig>[
            ToolSimulationConfig(
              toolName: 'lookup',
              injectionConfigs: <InjectionConfig>[
                InjectionConfig(
                  injectedResponse: <String, Object?>{'status': 'from_plugin'},
                ),
              ],
            ),
          ],
        ),
      );

      final Map<String, dynamic>? result = await plugin.beforeToolCallback(
        tool: _FakeTool(name: 'lookup'),
        toolArgs: <String, dynamic>{'query': 'ticket'},
        toolContext: _toolContext(),
      );

      expect(result, isNotNull);
      expect(result, containsPair('status', 'from_plugin'));
    });
  });

  group('agent simulator strategy/analyzer parity', () {
    test('tool spec strategy updates state for mutative tool', () async {
      final _StaticModel llm = _StaticModel(<String>[
        '{"ticket_id":"ticket-1","status":"created"}',
      ]);
      final ToolSpecMockStrategy strategy = ToolSpecMockStrategy(
        llmName: 'mock-model',
        llmConfig: GenerateContentConfig(),
        llm: llm,
      );

      final ToolConnectionMap connectionMap = ToolConnectionMap(
        statefulParameters: <StatefulParameter>[
          StatefulParameter(
            parameterName: 'ticket_id',
            creatingTools: <String>['create_ticket'],
            consumingTools: <String>['get_ticket'],
          ),
        ],
      );

      final Map<String, Object?> stateStore = <String, Object?>{};
      final Map<String, Object?> response = await strategy.mock(
        _FakeTool(
          name: 'create_ticket',
          declaration: FunctionDeclaration(
            name: 'create_ticket',
            description: 'Create a support ticket',
            parameters: <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'user_id': <String, Object?>{'type': 'string'},
              },
            },
          ),
        ),
        <String, Object?>{'user_id': 'u1'},
        Object(),
        connectionMap,
        stateStore,
      );

      expect(response, containsPair('ticket_id', 'ticket-1'));
      expect((stateStore['ticket_id'] as Map)['ticket-1'], isA<Map>());
      expect(
        llm.lastRequest?.contents.first.parts.first.text,
        contains('Tool Name: create_ticket'),
      );
    });

    test('tool connection analyzer parses llm JSON output', () async {
      final _StaticModel llm = _StaticModel(<String>[
        '''```json
{"stateful_parameters":[{"parameter_name":"ticket_id","creating_tools":["create_ticket"],"consuming_tools":["get_ticket"]}]}
```''',
      ]);
      final ToolConnectionAnalyzer analyzer = ToolConnectionAnalyzer(
        llmName: 'mock-model',
        llmConfig: GenerateContentConfig(),
        llm: llm,
      );

      final ToolConnectionMap result = await analyzer.analyze(<BaseTool>[
        _FakeTool(
          name: 'create_ticket',
          declaration: FunctionDeclaration(
            name: 'create_ticket',
            description: 'Create a support ticket',
            parameters: <String, Object?>{},
          ),
        ),
      ]);

      expect(result.statefulParameters, hasLength(1));
      expect(result.statefulParameters.single.parameterName, 'ticket_id');
      expect(result.statefulParameters.single.creatingTools, <String>[
        'create_ticket',
      ]);
    });
  });
}

class _StaticMockStrategy extends BaseMockStrategy {
  _StaticMockStrategy(this._response);

  final Map<String, Object?> _response;

  @override
  Future<Map<String, Object?>> mock(
    BaseTool tool,
    Map<String, Object?> args,
    Object toolContext,
    ToolConnectionMap? toolConnectionMap,
    Map<String, Object?> stateStore, {
    String? environmentData,
  }) async {
    return Map<String, Object?>.from(_response);
  }
}

class _StaticModel extends BaseLlm {
  _StaticModel(this._outputs) : super(model: 'mock-model');

  final List<String> _outputs;
  LlmRequest? lastRequest;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    lastRequest = request;
    for (final String output in _outputs) {
      yield LlmResponse(content: Content.modelText(output));
    }
  }
}

class _FakeTool extends BaseTool {
  _FakeTool({
    required super.name,
    this.declaration,
    String description = 'fake tool',
  }) : super(description: description);

  final FunctionDeclaration? declaration;

  @override
  FunctionDeclaration? getDeclaration() => declaration;

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'ok': true};
  }
}

ToolContext _toolContext() {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: _FakeSessionService(),
    invocationId: 'invocation',
    agent: Agent(name: 'root', model: _StaticModel(const <String>[])),
    session: Session(id: 'session', appName: 'app', userId: 'user'),
  );
  return Context(invocationContext);
}

class _FakeSessionService extends BaseSessionService {
  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    return Session(
      id: sessionId ?? 'session',
      appName: appName,
      userId: userId,
      state: state,
    );
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {}

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    return null;
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    return ListSessionsResponse();
  }
}
