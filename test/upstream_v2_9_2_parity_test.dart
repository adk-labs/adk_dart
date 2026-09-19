import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Context _createToolContext({String? invocationId, Session? session}) {
  final InvocationContext invCtx = InvocationContext(
    sessionService: InMemorySessionService(),
    agent: LlmAgent(name: 'test_agent'),
    session: session ?? Session(id: 's', appName: 'a', userId: 'u'),
    invocationId: invocationId ?? 'inv_1',
  );
  return Context(invCtx);
}

void main() {
  group('Upstream ADK v2.9.2 Parity Tests', () {
    group('Step 1: ServiceTier', () {
      test('RunConfig and LlmRequest support serviceTier', () {
        final RunConfig config = RunConfig(serviceTier: ServiceTier.flex.name);
        expect(config.serviceTier, 'flex');

        final RunConfig copied = config.copyWith(
          serviceTier: ServiceTier.deferred.name,
        );
        expect(copied.serviceTier, 'deferred');

        final LlmRequest request = LlmRequest(
          model: 'gemini-2.5-flash',
          serviceTier: ServiceTier.priority.name,
        );
        expect(request.serviceTier, 'priority');
      });

      test('Gemini rejects streaming with deferred service tier', () {
        final Gemini llm = Gemini(model: 'gemini-2.5-flash');
        final LlmRequest request = LlmRequest(
          model: 'gemini-2.5-flash',
          serviceTier: 'deferred',
          contents: <Content>[
            Content(role: 'user', parts: <Part>[Part.text('test')]),
          ],
        );
        expect(
          llm.generateContent(request, stream: true).first,
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Step 2: Output schema routing unification', () {
      test('canSetNativeOutputSchema identifies native schema support', () {
        final LlmAgent nativeAgent = LlmAgent(
          name: 'test_agent',
          outputSchema: <String, Object?>{'type': 'object'},
        );
        expect(canSetNativeOutputSchema(nativeAgent), isTrue);

        final LlmAgent noSchemaAgent = LlmAgent(name: 'no_schema');
        expect(canSetNativeOutputSchema(noSchemaAgent), isFalse);
      });
    });

    group('Step 4: Private reasoning protection from code execution', () {
      test('CodeExecutionUtils separates thoughts and executable blocks', () {
        final List<Part> parts = <Part>[
          Part.text('Thinking deeply...')..thought = true,
          Part.text('```python\nprint("hello")\n```'),
        ];
        final Content content = Content(role: 'model', parts: parts);
        final (Content contentWithoutThoughts, List<Part> thoughts) =
            CodeExecutionUtils.splitThoughts(content);
        expect(contentWithoutThoughts.parts.length, 1);
        expect(
          contentWithoutThoughts.parts.first.text,
          contains('print("hello")'),
        );
        expect(thoughts.length, 1);
        expect(thoughts.first.thought, isTrue);
      });
    });

    group('Step 5: ToolBehavior for Live Non-Blocking Function Calls', () {
      test('BaseTool supports behavior property', () {
        final FunctionTool tool = FunctionTool(
          name: 'background_job',
          description: 'Runs in background',
          behavior: ToolBehavior.nonBlocking,
          func: (Map<String, dynamic> args) => 'ok',
        );
        expect(tool.behavior, ToolBehavior.nonBlocking);

        final FunctionTool blockingTool = FunctionTool(
          name: 'sync_job',
          description: 'Runs blocking',
          behavior: ToolBehavior.blocking,
          func: (Map<String, dynamic> args) => 'ok',
        );
        expect(blockingTool.behavior, ToolBehavior.blocking);
      });
    });

    group('Step 6: Tool confirmation hook and default hint', () {
      test('checkRequireConfirmation returns boolean', () async {
        final FunctionTool tool = FunctionTool(
          name: 'dangerous_action',
          description: 'Needs confirm',
          requireConfirmation: true,
          func: (Map<String, dynamic> args) => 'done',
        );
        final Context toolCtx = _createToolContext();
        final bool required = await tool.checkRequireConfirmation(
          <String, dynamic>{},
          toolCtx,
        );
        expect(required, isTrue);
      });
    });

    group('Step 7: Abort signal in context', () {
      test('InvocationContext and Context abort() propagates isAborted', () {
        final InvocationContext invCtx = InvocationContext(
          sessionService: InMemorySessionService(),
          invocationId: 'inv_1',
          agent: LlmAgent(name: 'agent'),
          session: Session(id: 's', appName: 'a', userId: 'u'),
        );
        final Context ctx = Context(invCtx);
        expect(ctx.isAborted, isFalse);
        expect(invCtx.isAborted, isFalse);

        bool abortSignalFired = false;
        invCtx.abortSignal?.addListener((Object? reason) {
          abortSignalFired = true;
        });

        ctx.abort('User cancelled');
        expect(ctx.isAborted, isTrue);
        expect(invCtx.isAborted, isTrue);
        expect(abortSignalFired, isTrue);
      });
    });

    group('Step 8: JudgeModelOptions numSamples validation', () {
      test('rejects numSamples < 1 with ArgumentError', () {
        expect(
          () => JudgeModelOptions(numSamples: 0),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => JudgeModelOptions(numSamples: -1),
          throwsA(isA<ArgumentError>()),
        );
        final JudgeModelOptions valid = JudgeModelOptions(numSamples: 3);
        expect(valid.numSamples, 3);
      });
    });

    group('Step 9: MCP Session Discard on Server Termination', () {
      test('isSessionTerminatedError correctly classifies errors', () {
        // Legacy code 32600
        expect(
          isSessionTerminatedError(
            McpJsonRpcException(
              method: 'tools/call',
              code: 32600,
              message: 'Anything',
            ),
          ),
          isTrue,
        );

        // Standard -32600 with 'Session terminated'
        expect(
          isSessionTerminatedError(
            McpJsonRpcException(
              method: 'tools/call',
              code: -32600,
              message: 'Session terminated',
            ),
          ),
          isTrue,
        );

        // Standard -32600 with ordinary bad request -> not session terminated
        expect(
          isSessionTerminatedError(
            McpJsonRpcException(
              method: 'tools/call',
              code: -32600,
              message: 'Unexpected content type: text/plain',
            ),
          ),
          isFalse,
        );

        // Internal error -32603 -> not session terminated
        expect(
          isSessionTerminatedError(
            McpJsonRpcException(
              method: 'tools/call',
              code: -32603,
              message: 'Invalid arguments',
            ),
          ),
          isFalse,
        );

        // HTTP 404 with Session terminated
        expect(
          isSessionTerminatedError(
            McpHttpStatusException(
              uri: Uri.parse('http://localhost/mcp'),
              statusCode: 404,
              body: 'Session terminated by server',
            ),
          ),
          isTrue,
        );

        // Other errors
        expect(isSessionTerminatedError(Exception('connection lost')), isFalse);
        expect(isSessionTerminatedError(null), isFalse);
      });
    });

    group('Step 10: Skill Lifecycle & Discovery Modes', () {
      test('SkillLifecycleConfig validates maxActiveSkills', () {
        expect(
          () => SkillLifecycleConfig(maxActiveSkills: 0),
          throwsA(isA<ArgumentError>()),
        );
        final SkillLifecycleConfig config = SkillLifecycleConfig(
          maxActiveSkills: 2,
          defaultMode: SkillLifecycleMode.bounded,
        );
        expect(config.maxActiveSkills, 2);
        expect(config.defaultMode, SkillLifecycleMode.bounded);
      });

      test('Bounded skills evict FIFO when over cap', () async {
        final Skill skillA = Skill(
          instructions: 'instructions a',
          frontmatter: Frontmatter(name: 'skill-a', description: 'desc a'),
        );
        final Skill skillB = Skill(
          instructions: 'instructions b',
          frontmatter: Frontmatter(name: 'skill-b', description: 'desc b'),
        );
        final Skill skillC = Skill(
          instructions: 'instructions c',
          frontmatter: Frontmatter(name: 'skill-c', description: 'desc c'),
        );

        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[skillA, skillB, skillC],
          lifecycleConfig: SkillLifecycleConfig(
            defaultMode: SkillLifecycleMode.bounded,
            maxActiveSkills: 2,
          ),
        );

        final Context toolCtx = _createToolContext(invocationId: 'inv_1');

        // Load A, then B -> both active
        await toolset.loadSkill(toolCtx, 'skill-a');
        await toolset.loadSkill(toolCtx, 'skill-b');
        expect(toolset.listActiveSkills(toolCtx), <String>[
          'skill-a',
          'skill-b',
        ]);

        // Load C -> cap is 2, oldest bounded (A) is evicted
        await toolset.loadSkill(toolCtx, 'skill-c');
        expect(toolset.listActiveSkills(toolCtx), <String>[
          'skill-b',
          'skill-c',
        ]);
      });

      test('Ephemeral skills expire across different invocations', () async {
        final Skill skillEphem = Skill(
          instructions: 'ephemeral instructions',
          frontmatter: Frontmatter(
            name: 'ephemeral-skill',
            description: 'ephem desc',
          ),
        );

        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[skillEphem],
          lifecycleConfig: SkillLifecycleConfig(
            defaultMode: SkillLifecycleMode.ephemeral,
          ),
        );

        final Session session = Session(id: 's', appName: 'a', userId: 'u');
        final Context toolCtx1 = _createToolContext(
          invocationId: 'inv_1',
          session: session,
        );

        await toolset.loadSkill(toolCtx1, 'ephemeral-skill');
        expect(toolset.listActiveSkills(toolCtx1), <String>['ephemeral-skill']);

        // Next invocation turn
        final Context toolCtx2 = _createToolContext(
          invocationId: 'inv_2',
          session: session,
        );
        expect(toolset.listActiveSkills(toolCtx2), isEmpty);
      });

      test('UnloadSkillTool unloads active skill', () async {
        final Skill skillA = Skill(
          instructions: 'instructions a',
          frontmatter: Frontmatter(name: 'skill-a', description: 'desc a'),
        );
        final SkillToolset toolset = SkillToolset(skills: <Skill>[skillA]);

        final Context toolCtx = _createToolContext();

        await toolset.loadSkill(toolCtx, 'skill-a');
        expect(toolset.listActiveSkills(toolCtx), <String>['skill-a']);

        final UnloadSkillTool unloadTool = UnloadSkillTool(toolset);
        final Object? result = await unloadTool.run(
          args: <String, dynamic>{'skill_name': 'skill-a'},
          toolContext: toolCtx,
        );
        expect(result, isA<Map<String, Object?>>());
        final Map<String, Object?> resultMap = result! as Map<String, Object?>;
        expect(resultMap['unloaded'], isTrue);
        expect(toolset.listActiveSkills(toolCtx), isEmpty);
      });

      test(
        'SkillDiscoveryMode.eager inlines catalog and omits list_skills tool',
        () async {
          final Skill skillA = Skill(
            instructions: 'instructions a',
            frontmatter: Frontmatter(name: 'skill-a', description: 'desc a'),
          );
          final SkillToolset toolset = SkillToolset(
            skills: <Skill>[skillA],
            discoveryMode: SkillDiscoveryMode.eager,
          );

          final List<BaseTool> tools = await toolset.getTools();
          expect(
            tools.any((BaseTool t) => t.name == listSkillsToolName),
            isFalse,
          );
          expect(
            tools.any((BaseTool t) => t.name == loadSkillToolName),
            isTrue,
          );

          final Context toolCtx = _createToolContext();
          final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');
          await toolset.processLlmRequest(
            toolContext: toolCtx,
            llmRequest: request,
          );
          expect(request.config.systemInstruction, contains('skill-a'));
        },
      );
    });

    group('Step 11: BaseSessionService commitEventToSession', () {
      test(
        'commitEventToSession commits event and updates in-memory session',
        () {
          final InMemorySessionService service = InMemorySessionService();
          final Session session = Session(
            id: 's1',
            appName: 'app',
            userId: 'u1',
          );
          final Event event = Event(
            invocationId: 'inv1',
            author: 'agent',
            actions: EventActions(
              stateDelta: <String, Object?>{
                'persisted_key': 'val1',
                'temp:scratch': 'ephemeral',
              },
            ),
          );

          final Event committed = service.commitEventToSession(
            session: session,
            event: event,
          );
          expect(committed.actions.stateDelta['persisted_key'], 'val1');
          // temp keys stripped from stored history
          expect(committed.actions.stateDelta['temp:scratch'], isNull);
          // but present in live session state
          expect(session.state['temp:scratch'], 'ephemeral');
          expect(session.state['persisted_key'], 'val1');
          expect(session.events.length, 1);
        },
      );
    });
  });
}
