import 'dart:convert';
import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Upstream v2.9.2 Batch 2 Parity Tests', () {
    test('1. InvocationNotFoundError extends NotFoundError and implements ArgumentError', () async {
      final error = InvocationNotFoundError('Invocation not found', null, 'inv_404');
      expect(error, isA<NotFoundError>());
      expect(error, isA<ArgumentError>());
      expect(error.name, equals('inv_404'));
      expect(error.message, contains('Invocation not found'));

      final service = InMemorySessionService();
      final session = await service.createSession(appName: 'app', userId: 'u1');
      final runner = Runner(
        app: App(name: 'app', rootAgent: LlmAgent(name: 'a1')),
        sessionService: service,
      );

      expect(
        () => runner.rewindAsync(
          userId: 'u1',
          sessionId: session.id,
          rewindBeforeInvocationId: 'non_existent_id',
        ),
        throwsA(isA<InvocationNotFoundError>()),
      );
    });

    test('2. Artifact reference recursion depth bound guards against cycles', () async {
      expect(maxArtifactReferenceDepth, equals(5));

      final service = InMemoryArtifactService();
      // Write circular references: art_a -> artifact://art_b, art_b -> artifact://art_a
      await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'art_a.txt',
        artifact: Part.text('artifact://art_b.txt'),
      );
      await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'art_b.txt',
        artifact: Part.text('artifact://art_a.txt'),
      );

      final result = await service.loadArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'art_a.txt',
      );

      // Recursion limit reached: returns the unresolved artifact:// reference string instead of infinite loop
      expect(result, isNotNull);
      expect(result!.text, contains('artifact://'));
    });

    test('3. MCP Client identification and user-agent tracking merge', () {
      final headers = mergeTrackingHeaders(
        <String, String>{
          'User-Agent': 'custom-agent/1.0',
          'Authorization': 'Bearer token',
        },
      );

      expect(headers.containsKey('User-Agent'), isFalse);
      expect(headers['user-agent'], contains('custom-agent/1.0'));
      expect(headers['user-agent'], contains('google-adk'));
      expect(headers['x-goog-api-client'], contains('gl-dart'));
      expect(headers['Authorization'], equals('Bearer token'));
    });

    test('4. MCP Tool description fencing and preamble injection', () {
      final rawDesc = 'Fetches current weather';
      final fenced = fenceToolDescription(rawDesc);
      expect(fenced, contains(untrustedToolDescriptionBegin));
      expect(fenced, contains(untrustedToolDescriptionEnd));
      expect(fenced, contains(rawDesc));

      final elided = elideToolDescriptionMarkers(fenced);
      expect(elided, contains('<<<ELIDED_MARKER>>>'));
      expect(elided, contains(rawDesc));

      final fencedSchema = fenceSchemaDescriptions(<String, dynamic>{
        'description': 'Schema description',
        'properties': <String, dynamic>{
          'prop1': <String, dynamic>{'description': 'Prop description'},
        },
      }) as Map<String, dynamic>;

      expect(fencedSchema['description'], contains(untrustedToolDescriptionBegin));
      expect(
        (fencedSchema['properties'] as Map<String, dynamic>)['prop1']['description'],
        contains(untrustedToolDescriptionBegin),
      );
    });

    test('5. Skill lifecycle config revalidateSkills and script tool visibility', () async {
      final config = SkillLifecycleConfig(revalidateSkills: true);
      expect(config.revalidateSkills, isTrue);

      final skillWithoutScripts = Skill(
        name: 'skill-a',
        description: 'skill without scripts',
        instructions: 'Do something',
      );

      final toolset = SkillToolset(
        skills: <Skill>[skillWithoutScripts],
        lifecycleConfig: config,
      );

      final invocationContext = InvocationContext(
        invocationId: 'inv_1',
        session: Session(id: 's_1', appName: 'app', userId: 'user'),
        agent: LlmAgent(name: 'test_agent'),
        sessionService: InMemorySessionService(),
      );
      final readonlyContext = ReadonlyContext(invocationContext);

      final tools = await toolset.getTools(readonlyContext: readonlyContext);
      // RunSkillScriptTool should be hidden when no skills have scripts
      expect(tools.any((t) => t.name == 'run_skill_script'), isFalse);
    });

    test('6. Parallel tool state concurrency merge preserves latest writes', () {
      final session = Session(id: 's1', appName: 'app', userId: 'u1');
      session.state['items'] = <dynamic>[1, 2, 3];
      session.state['meta'] = <String, dynamic>{'updated': true};

      final event1 = Event(
        invocationId: 'inv_1',
        author: 'agent',
        actions: EventActions(
          stateDelta: <String, dynamic>{
            'items': <dynamic>[1, 2],
          },
        ),
      );
      final event2 = Event(
        invocationId: 'inv_1',
        author: 'agent',
        actions: EventActions(
          stateDelta: <String, dynamic>{
            'items': <dynamic>[1, 2, 3],
            'meta': <String, dynamic>{'updated': true},
          },
        ),
      );

      final merged = mergeParallelFunctionResponseEvents(
        <Event>[event1, event2],
        session.state,
      );

      expect(merged, isNotNull);
      expect(merged.actions.stateDelta['items'], equals(<dynamic>[1, 2, 3]));
      expect(merged.actions.stateDelta['meta'], equals(<String, dynamic>{'updated': true}));
    });

    test('7. FunctionTool coerces integral floats in list[int] and int parameters', () async {
      List<int>? receivedIds;
      int? receivedCount;

      final tool = FunctionTool(
        func: ({required List<int> ids, required int count}) {
          receivedIds = ids;
          receivedCount = count;
          return {'ok': true};
        },
        declaration: FunctionDeclaration(
          name: 'test_func',
          parameters: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ids': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'integer'},
              },
              'count': <String, dynamic>{'type': 'integer'},
            },
            'required': <String>['ids', 'count'],
          },
        ),
      );

      final invocationContext = InvocationContext(
        invocationId: 'inv_1',
        session: Session(id: 's_1', appName: 'app', userId: 'user'),
        agent: LlmAgent(name: 'test_agent'),
        sessionService: InMemorySessionService(),
      );
      final context = Context(invocationContext, functionCallId: 'call_1');

      final result = await tool.run(
        args: <String, dynamic>{
          'ids': <dynamic>[1396683.0, 7.0],
          'count': 42.0,
        },
        toolContext: context,
      );

      expect(result, equals({'ok': true}));
      expect(receivedIds, equals(<int>[1396683, 7]));
      expect(receivedCount, equals(42));
    });

    test('8. Request confirmation processor skips confirmation requests authored by other agents', () async {
      final currentAgent = LlmAgent(name: 'current_agent');
      final sessionService = InMemorySessionService();
      final session = await sessionService.createSession(appName: 'app', userId: 'u1');

      final toolConfirmationArgs = <String, dynamic>{
        'originalFunctionCall': <String, dynamic>{
          'id': 'remote_fc_123',
          'name': 'remote_tool',
          'args': <String, dynamic>{'key': 'value'},
        },
        'toolConfirmation': <String, dynamic>{
          'confirmed': false,
          'hint': 'other hint',
        },
      };

      // Event from other_agent
      session.events.add(
        Event(
          invocationId: 'inv_remote',
          author: 'other_agent',
          content: Content(
            parts: <Part>[
              Part(
                functionCall: FunctionCall(
                  name: requestConfirmationFunctionCallName,
                  args: toolConfirmationArgs,
                  id: 'remote_confirm_123',
                ),
              ),
            ],
          ),
        ),
      );

      // User confirmation response
      session.events.add(
        Event(
          invocationId: 'inv_remote',
          author: 'user',
          content: Content(
            parts: <Part>[
              Part(
                functionResponse: FunctionResponse(
                  name: requestConfirmationFunctionCallName,
                  id: 'remote_confirm_123',
                  response: <String, dynamic>{
                    'response': jsonEncode(<String, dynamic>{'confirmed': true}),
                  },
                ),
              ),
            ],
          ),
        ),
      );

      final invocationContext = InvocationContext(
        invocationId: 'inv_test',
        session: session,
        agent: currentAgent,
        sessionService: sessionService,
      );

      final processor = RequestConfirmationLlmRequestProcessor();
      final emittedEvents = await processor.runAsync(invocationContext, LlmRequest()).toList();

      // Current agent should skip other agent's confirmation request without errors
      expect(emittedEvents, isEmpty);
    });

    test('9. Sensitive URL redaction in redactFileUriForLog', () {
      expect(
        redactFileUriForLog('https://example.com/bucket/artifact?X-Goog-Signature=0123456789abcdef'),
        equals('https://<redacted>/artifact'),
      );
      expect(
        redactFileUriForLog('https://example.com/'),
        equals('https://<redacted>'),
      );
      expect(
        redactFileUriForLog('file-abc123456789'),
        equals('file-<redacted>'),
      );
      expect(
        redactFileUriForLog('assistant-thread_123'),
        equals('assistant-<redacted>'),
      );
      expect(
        redactFileUriForLog('https://example.com/secret.pdf', displayName: 'my_doc.pdf'),
        equals('my_doc.pdf'),
      );
      expect(
        redactFileUriForLog('invalid_uri'),
        equals('<unknown>'),
      );
    });

    test('10. Workflow DEFAULT_ROUTE fan out to multiple nodes', () async {
      final FunctionNode router = FunctionNode(
        name: 'router',
        function: (WorkflowContext _, Object? _) => null,
      );
      final FunctionNode nodeB = FunctionNode(
        name: 'node_b',
        function: (WorkflowContext _, Object? _) => 'B',
      );
      final FunctionNode nodeC = FunctionNode(
        name: 'node_c',
        function: (WorkflowContext _, Object? _) => 'C',
      );
      final JoinNode gate = JoinNode(name: 'gate');

      final Workflow workflow = Workflow(
        name: 'default_fan_out',
        nodes: <BaseNode>[router, nodeB, nodeC, gate],
        edges: <Edge>[
          Edge(fromNode: START, toNode: router),
          Edge(fromNode: router, toNode: nodeB, route: DEFAULT_ROUTE),
          Edge(fromNode: router, toNode: nodeC, route: DEFAULT_ROUTE),
          Edge(fromNode: nodeB, toNode: gate),
          Edge(fromNode: nodeC, toNode: gate),
        ],
      );

      final result = await workflow.runWorkflow(input: 'start');
      expect(result.outputs['node_b'], equals('B'));
      expect(result.outputs['node_c'], equals('C'));
    });

    test('11. LlmEventSummarizer formatEventsForPrompt skips credential-request events', () {
      final LlmEventSummarizer summarizer = LlmEventSummarizer(
        llm: _CompactionTestLlm(),
      );

      final events = <Event>[
        Event(
          invocationId: 'inv_1',
          author: 'user',
          content: Content.userText('Read my mail'),
        ),
        Event(
          invocationId: 'inv_1',
          author: 'model',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: requestEucFunctionCallName,
                id: 'call_1',
                args: <String, Object?>{
                  'code_verifier': 'pkce-verifier',
                },
              ),
            ],
          ),
        ),
        Event(
          invocationId: 'inv_1',
          author: 'user',
          content: Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: requestEucFunctionCallName,
                id: 'call_1',
                response: <String, Object?>{
                  'auth_response_uri': 'https://example.com/callback?code=auth-code',
                  'access_token': 'granted-token',
                },
              ),
            ],
          ),
        ),
        Event(
          invocationId: 'inv_1',
          author: 'model',
          content: Content.modelText('Here is your mail.'),
        ),
      ];

      final String formatted = summarizer.formatEventsForPrompt(events);
      expect(formatted.contains('pkce-verifier'), isFalse);
      expect(formatted.contains('auth-code'), isFalse);
      expect(formatted.contains('granted-token'), isFalse);
      expect(formatted, equals('user: Read my mail\nmodel: Here is your mail.'));
    });

    test('12. createGoogleSearchAgent directs model to built-in grounding without client-side call', () {
      final LlmAgent agent = createGoogleSearchAgent('gemini-2.5-flash');
      expect(agent.description, contains('built-in search grounding'));
      final String instruction = agent.instruction.toString();
      expect(instruction, contains('built-in Google Search'));
      expect(instruction, contains('Do not attempt to invoke a client-side function'));
      expect(instruction.contains('use the `google_search` tool'), isFalse);
    });
  });
}

class _CompactionTestLlm extends BaseLlm {
  _CompactionTestLlm() : super(model: 'test');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}
