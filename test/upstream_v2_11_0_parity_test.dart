import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/apps/compaction.dart' as app_compaction;
import 'package:adk_dart/src/flows/llm_flows/contents.dart' as contents_flow;
import 'package:test/test.dart';

class _RecordingLlm extends BaseLlm {
  _RecordingLlm({this.responses = const <LlmResponse>[]})
    : super(model: 'recording-llm');

  final List<LlmResponse> responses;
  final List<LlmRequest> requests = <LlmRequest>[];
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    requests.add(request);
    if (_index < responses.length) {
      final LlmResponse response = responses[_index];
      _index += 1;
      yield response;
      return;
    }
    yield LlmResponse(content: Content.modelText('ok'));
  }
}

class _FakeSkillCodeExecutor extends BaseCodeExecutor {
  _FakeSkillCodeExecutor(this._handler);

  final Future<CodeExecutionResult> Function(CodeExecutionInput input) _handler;

  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) {
    return _handler(CodeExecutionInput(code: request.command));
  }

  @override
  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) {
    return _handler(codeExecutionInput);
  }
}

class _AfterRunTrackingPlugin extends BasePlugin {
  _AfterRunTrackingPlugin() : super(name: 'after_run_tracker');

  int afterRunCount = 0;
  bool? wasAbortedInAfterRun;

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    afterRunCount += 1;
    wasAbortedInAfterRun = invocationContext.isAborted;
  }
}

class _ThrowingSummarizer extends BaseEventsSummarizer {
  @override
  Future<Event?> maybeSummarizeEvents({required List<Event> events}) async {
    throw StateError('Summarizer boom');
  }
}

void main() {
  group('Upstream v2.11.0+ prompt and runtime parity', () {
    test('injectSessionState skips dollar-prefixed and escaped placeholders', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        state: <String, Object?>{'user_name': 'Alice', 'var': 'SHOULD_NOT_USE'},
      );
      final InMemoryArtifactService artifactService = InMemoryArtifactService();
      await artifactService.saveArtifact(
        appName: 'app',
        userId: 'user',
        sessionId: session.id,
        filename: 'doc.bin',
        artifact: Part.fromInlineData(
          mimeType: 'application/x-custom-binary',
          data: <int>[1, 2, 3, 4],
        ),
      );
      final InvocationContext context = InvocationContext(
        sessionService: sessionService,
        artifactService: artifactService,
        invocationId: 'inv-1',
        agent: LlmAgent(name: 'root', instruction: 'hi'),
        session: session,
      );

      final String rendered = await injectSessionState(
        r'Hello {user_name}, bash ${var}, escaped \{user_name}, artifact {artifact.doc.bin}',
        ReadonlyContext(context),
      );
      expect(
        rendered,
        equals(
          r'Hello Alice, bash ${var}, escaped \{user_name}, artifact [Binary artifact: doc.bin, type: application/x-custom-binary, size: 0.0 KB. Content cannot be displayed inline.]',
        ),
      );
    });

    test('asSafePartForLlm converts unsupported inlineData to text placeholder', () {
      final Part supported = Part.fromInlineData(
        mimeType: 'application/pdf',
        data: <int>[1, 2, 3],
      );
      expect(
        asSafePartForLlm(supported, 'file.pdf').inlineData?.mimeType,
        equals('application/pdf'),
      );

      final Part unsupported = Part.fromInlineData(
        mimeType: 'application/x-tar',
        data: <int>[10, 20, 30],
        displayName: 'archive.tar',
      );
      final Part converted = asSafePartForLlm(unsupported, 'archive.tar');
      expect(
        converted.text,
        equals(
          '[Binary artifact: archive.tar, type: application/x-tar, size: 0.0 KB. Content cannot be displayed inline.]',
        ),
      );
    });

    test('HallucinationsV1Evaluator includes Grounding metadata prompt & context and disables AFC', () async {
      final _RecordingLlm judgeLlm = _RecordingLlm(
        responses: <LlmResponse>[
          LlmResponse(
            content: Content.modelText('<sentence>The sky is blue.</sentence>'),
          ),
          LlmResponse(
            content: Content.modelText('''
sentence: The sky is blue.
label: supported
rationale: Supported by grounding metadata.
supporting_excerpt: sky is blue
contradicting_excerpt: null
'''),
          ),
        ],
      );
      final HallucinationsV1Evaluator evaluator = HallucinationsV1Evaluator(
        EvalMetricSpec(
          metricName: 'hallucinations_v1',
          threshold: 0.8,
          criterion: HallucinationsCriterion(
            threshold: 0.8,
            evaluateIntermediateNlResponses: true,
          ),
        ),
        llmFactory: (_) => judgeLlm,
      );

      expect(
        evaluator.sentenceValidatorPrompt,
        contains(
          '6. "Grounding metadata" contains source attribution from model-internal tools (e.g. search)',
        ),
      );
      expect(
        evaluator.sentenceValidatorPrompt,
        contains(
          '7. If you need to cite multiple supporting excerpts, simply concatenate them.',
        ),
      );

      final Invocation actual = Invocation(
        userContent: <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{'text': 'What color is the sky?'},
          ],
        },
        finalResponse: <String, Object?>{
          'role': 'model',
          'parts': <Object?>[
            <String, Object?>{'text': 'The sky is blue.'},
          ],
        },
        intermediateData: InvocationEvents(
          invocationEvents: <InvocationEvent>[
            InvocationEvent(
              author: 'search_agent',
              groundingMetadata: <String, Object?>{
                'grounding_supports': <Object?>['sky is blue'],
              },
            ),
          ],
        ),
      );

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[actual],
      );
      expect(result.overallScore, equals(1.0));
      expect(judgeLlm.requests, hasLength(2));
      expect(
        judgeLlm.requests.first.config.automaticFunctionCalling?.disable,
        isTrue,
      );
      final String validatorRequestText =
          judgeLlm.requests.last.contents.first.parts.first.text ?? '';
      expect(validatorRequestText, contains('Grounding metadata:'));
      expect(validatorRequestText, contains('"grounding_supports"'));
    });

    test('Label enum includes partiallyValid and buildJudgeRequestConfig disables AFC', () {
      expect(Label.partiallyValid.value, equals('partially_valid'));
      final GenerateContentConfig userConfig = GenerateContentConfig(
        temperature: 0.2,
      );
      final GenerateContentConfig judgeConfig = buildJudgeRequestConfig(
        userConfig,
      );
      expect(judgeConfig.temperature, equals(0.2));
      expect(judgeConfig.automaticFunctionCalling?.disable, isTrue);
      expect(userConfig.automaticFunctionCalling, isNull);
    });

    test('PlanReActPlanner preserves parallel function calls starting at index 0', () async {
      final PlanReActPlanner planner = PlanReActPlanner();
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext context = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-plan',
        agent: LlmAgent(name: 'planner_agent'),
        session: session,
      );

      final List<Part>? processed = planner.processPlanningResponse(
        CallbackContext(context),
        <Part>[
          Part.fromFunctionCall(name: 'tool_a', args: <String, dynamic>{'x': 1}),
          Part.fromFunctionCall(name: 'tool_b', args: <String, dynamic>{'y': 2}),
        ],
      );
      expect(processed, isNotNull);
      expect(processed, hasLength(2));
      expect(processed![0].functionCall?.name, equals('tool_a'));
      expect(processed[1].functionCall?.name, equals('tool_b'));
    });

    test('BashToolPolicy validates tokenized command prefixes and reports <none> when empty', () async {
      final ExecuteBashTool lsTool = ExecuteBashTool(
        policy: BashToolPolicy(allowedCommandPrefixes: <String>['ls']),
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext context = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-bash',
        agent: LlmAgent(name: 'bash_agent'),
        session: session,
      );

      final Object? lsofResult = await lsTool.run(
        args: <String, dynamic>{'command': 'lsof -i'},
        toolContext: Context(context),
      );
      expect(
        (lsofResult as Map<String, Object?>)['error'],
        equals('Command blocked. Permitted prefixes are: ls'),
      );

      final ExecuteBashTool emptyTool = ExecuteBashTool(
        policy: BashToolPolicy(allowedCommandPrefixes: const <String>[]),
      );
      expect(emptyTool.description, contains('Allowed: commands matching prefixes: <none>.'));
      final Object? emptyResult = await emptyTool.run(
        args: <String, dynamic>{'command': 'ls'},
        toolContext: Context(context),
      );
      expect(
        (emptyResult as Map<String, Object?>)['error'],
        equals('Command blocked. Permitted prefixes are: <none>'),
      );
    });

    test('mcpReservedToolNames contains set_model_response', () {
      expect(mcpReservedToolNames, contains('set_model_response'));
    });

    test('InMemoryArtifactService validates ref before mutating state and copies customMetadata', () async {
      final InMemoryArtifactService service = InMemoryArtifactService();
      expect(
        () => service.saveArtifact(
          appName: 'app',
          userId: 'user',
          sessionId: 's1',
          filename: 'bad.txt',
          artifact: Part.fromFileData(
            fileUri: 'artifact://invalid-uri',
            mimeType: 'text/plain',
          ),
        ),
        throwsA(isA<InputValidationError>()),
      );
      expect(
        await service.listArtifactKeys(
          appName: 'app',
          userId: 'user',
          sessionId: 's1',
        ),
        isEmpty,
      );

      final Map<String, Object?> callerMeta = <String, Object?>{'k': 'v1'};
      await service.saveArtifact(
        appName: 'app',
        userId: 'user',
        sessionId: 's1',
        filename: 'good.txt',
        artifact: Part.text('hello'),
        customMetadata: callerMeta,
      );
      callerMeta['k'] = 'mutated';
      final ArtifactVersion? version = await service.getArtifactVersion(
        appName: 'app',
        userId: 'user',
        sessionId: 's1',
        filename: 'good.txt',
      );
      expect(version?.customMetadata['k'], equals('v1'));
    });

    test('GcpSkillRegistry.searchSkills calls skills:search with search_string', () async {
      Uri? capturedUri;
      Map<String, Object?>? capturedBody;
      final GcpSkillRegistry registry = GcpSkillRegistry(
        projectId: 'proj',
        location: 'us-central1',
        authHeadersProvider: () async => <String, String>{},
        httpPostProvider: (
          Uri uri, {
          required Map<String, String> headers,
          required Map<String, Object?> body,
        }) async {
          capturedUri = uri;
          capturedBody = body;
          return GcpSkillRegistryHttpResponse(
            statusCode: 200,
            body: <String, Object?>{
              'skills': <Object?>[
                <String, Object?>{
                  'name': 'projects/proj/locations/us-central1/skills/my-skill',
                  'description': 'My skill description',
                },
              ],
            },
          );
        },
      );

      final List<Frontmatter> found = await registry.searchSkills(
        query: 'bigquery',
      );
      expect(capturedUri.toString(), endsWith('/skills:search'));
      expect(capturedBody, equals(<String, Object?>{'search_string': 'bigquery'}));
      expect(found, hasLength(1));
      expect(found.first.name, equals('my-skill'));
    });

    test('SkillToolset saveOutputArtifacts extracts and persists generated files', () async {
      final Skill skill = Skill(
        frontmatter: Frontmatter(name: 'gen-skill', description: 'Gen skill'),
        instructions: 'Run script',
        resources: Resources(
          scripts: <String, Script>{
            'make.py': Script(src: 'print("done")'),
          },
        ),
      );
      final _FakeSkillCodeExecutor codeExecutor = _FakeSkillCodeExecutor(
        (CodeExecutionInput input) async {
          final String payload = jsonEncode(<Object?>[
            <String, Object?>{
              'name': 'out/report.txt',
              'content_b64': base64Encode(utf8.encode('generated report')),
            },
          ]);
          return CodeExecutionResult(
            stdout:
                'script output\n__ADK_SKILL_GENERATED_FILES_START__${payload}__ADK_SKILL_GENERATED_FILES_END__',
          );
        },
      );
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[skill],
        codeExecutor: codeExecutor,
        saveOutputArtifacts: true,
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final InMemoryArtifactService artifactService = InMemoryArtifactService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext context = InvocationContext(
        sessionService: sessionService,
        artifactService: artifactService,
        invocationId: 'inv-skill',
        agent: LlmAgent(name: 'skill_agent'),
        session: session,
      );

      final List<BaseTool> tools = await toolset.getTools(
        readonlyContext: ReadonlyContext(context),
      );
      final BaseTool runTool = tools.firstWhere(
        (BaseTool t) => t.name == 'run_skill_script',
      );
      final Map<String, Object?> result =
          (await runTool.run(
                args: <String, dynamic>{
                  'skill_name': 'gen-skill',
                  'file_path': 'scripts/make.py',
                },
                toolContext: Context(context),
              ))
              as Map<String, Object?>;

      expect(result['stdout'], equals('script output\n'));
      final List<Object?> artifacts = result['artifacts'] as List<Object?>;
      expect(artifacts, hasLength(1));
      final Part? savedPart = await artifactService.loadArtifact(
        appName: 'app',
        userId: 'user',
        sessionId: session.id,
        filename: 'out_report.txt',
      );
      expect(savedPart?.inlineData, isNotNull);
      expect(
        utf8.decode(savedPart!.inlineData!.data),
        equals('generated report'),
      );
    });

    test('isEventBelongsToBranch excludes tool sub-branch events from root context', () {
      final Event normalEvent = Event(
        invocationId: 'inv-1',
        author: 'agent',
        branch: 'sub_agent',
        content: Content.modelText('hello'),
      );
      final Event toolSubBranchEvent = Event(
        invocationId: 'inv-1',
        author: 'tool_agent',
        branch: 'agent.tool@call_1',
        content: Content.modelText('internal tool step'),
      );

      expect(contents_flow.isEventBelongsToBranch(null, normalEvent), isTrue);
      expect(
        contents_flow.isEventBelongsToBranch(null, toolSubBranchEvent),
        isFalse,
      );
      expect(
        contents_flow.isEventBelongsToBranch(
          'agent.tool@call_1',
          toolSubBranchEvent,
        ),
        isTrue,
      );
    });

    test('Runner does not mutate caller newMessage.role and runs afterRunCallback on abort', () async {
      final _AfterRunTrackingPlugin plugin = _AfterRunTrackingPlugin();
      final AdkAbortSignal abortSignal = AdkAbortSignal();
      final LlmAgent agent = LlmAgent(
        name: 'abort_agent',
        beforeAgentCallback: (CallbackContext ctx) {
          ctx.invocationContext.abort('stop');
          return null;
        },
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final Runner runner = Runner(
        appName: 'app',
        agent: agent,
        sessionService: sessionService,
        plugins: <BasePlugin>[plugin],
      );

      final Content callerMessage = Content(
        role: null,
        parts: <Part>[Part.text('hello')],
      );
      await runner
          .runAsync(
            userId: 'user',
            sessionId: session.id,
            newMessage: callerMessage,
            abortSignal: abortSignal,
          )
          .drain<void>();

      expect(callerMessage.role, isNull);
      expect(plugin.afterRunCount, equals(1));
      expect(plugin.wasAbortedInAfterRun, isTrue);
    });

    test('Compaction ignores provably dead function calls and skips gracefully on summarizer failure', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );

      final Event user1 = Event(
        invocationId: 'inv-1',
        author: 'user',
        timestamp: 1.0,
        content: Content.userText('turn 1'),
      );
      final Event orphanCall = Event(
        invocationId: 'inv-1',
        author: 'root',
        timestamp: 2.0,
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'abandoned_tool',
              id: 'dead_call_1',
              args: <String, dynamic>{},
            ),
          ],
        ),
      );
      final Event user2 = Event(
        invocationId: 'inv-2',
        author: 'user',
        timestamp: 3.0,
        content: Content.userText('turn 2'),
      );
      final Event model2 = Event(
        invocationId: 'inv-2',
        author: 'root',
        timestamp: 4.0,
        content: Content.modelText('done 2'),
      );
      await sessionService.appendEvent(session: session, event: user1);
      await sessionService.appendEvent(session: session, event: orphanCall);
      await sessionService.appendEvent(session: session, event: user2);
      await sessionService.appendEvent(session: session, event: model2);

      // Failing summarizer skips compaction without throwing.
      final App failingApp = App(
        name: 'app',
        rootAgent: LlmAgent(name: 'root'),
        eventsCompactionConfig: EventsCompactionConfig(
          compactionInterval: 2,
          overlapSize: 1,
          summarizer: _ThrowingSummarizer(),
        ),
      );
      final List<Event> failingResult = await app_compaction
          .runCompactionForSlidingWindow(
            app: failingApp,
            session: session,
            sessionService: sessionService,
          )
          .toList();
      expect(failingResult, isEmpty);

      // Default summarizer compacts inv-1 despite orphanCall because dead_call_1 is in an older invocation.
      final App workingApp = App(
        name: 'app',
        rootAgent: LlmAgent(name: 'root'),
        eventsCompactionConfig: EventsCompactionConfig(
          compactionInterval: 2,
          overlapSize: 1,
        ),
      );
      final List<Event> compactedEvents = await app_compaction
          .runCompactionForSlidingWindow(
            app: workingApp,
            session: session,
            sessionService: sessionService,
          )
          .toList();
      expect(compactedEvents, hasLength(1));
      expect(
        compactedEvents.first.actions.compaction?.endTimestamp,
        equals(2.0),
      );
    });

    test('RemoteA2aAgent resolves card description during transfer instruction building and caches it', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp('a2a_card_');
      addTearDown(() => tempDir.delete(recursive: true));
      final File cardFile = File('${tempDir.path}/agent.json');
      await cardFile.writeAsString(
        jsonEncode(<String, Object?>{
          'name': 'remote_helper',
          'description': 'Resolved description from agent card',
          'url': 'https://example.com/a2a',
          'version': '1.0.0',
          'capabilities': <String, Object?>{},
          'defaultInputModes': <String>['text/plain'],
          'defaultOutputModes': <String>['text/plain'],
          'skills': <Object?>[],
        }),
      );

      final RemoteA2aAgent remoteAgent = RemoteA2aAgent(
        name: 'remote_helper',
        agentCard: cardFile.path,
      );
      final LlmAgent rootAgent = LlmAgent(
        name: 'root',
        subAgents: <BaseAgent>[remoteAgent],
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext context = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-transfer',
        agent: rootAgent,
        session: session,
      );
      final LlmRequest request = LlmRequest();

      await AgentTransferLlmRequestProcessor()
          .runAsync(context, request)
          .drain<void>();

      expect(
        request.config.systemInstruction,
        contains('Resolved description from agent card'),
      );
      expect(
        context.privateMetadata['_transfer_target_info_remote_helper'],
        isA<TransferTargetInfo>(),
      );
    });

    test('InvocationContext nodePath disambiguates agent state keys', () {
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = Session(
        id: 's1',
        appName: 'app',
        userId: 'user',
      );
      final LlmAgent worker = LlmAgent(name: 'worker');
      final InvocationContext context = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-node',
        nodePath: 'pipeline.step_1.worker',
        agent: worker,
        session: session,
      );

      context.setAgentState(
        'worker',
        agentState: BaseAgentState(data: <String, Object?>{'step': 1}),
      );
      expect(
        context.agentStates.containsKey('pipeline.step_1.worker'),
        isTrue,
      );
      expect(worker.loadAgentState(context)?.data['step'], equals(1));
    });
  });
}
