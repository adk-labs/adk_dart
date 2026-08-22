import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Live API & VAD parity', () {
    test('VoiceActivity and RunConfig explicitVadSignal are configured', () {
      final RunConfig runConfig = RunConfig(explicitVadSignal: true);
      expect(runConfig.explicitVadSignal, isTrue);

      final LiveConnectConfig liveConnect = LiveConnectConfig(
        explicitVadSignal: true,
      );
      expect(liveConnect.explicitVadSignal, isTrue);

      final VoiceActivity va = VoiceActivity(
        voiceActivityType: VoiceActivityType.activityStart,
        audioOffset: '123ms',
      );
      expect(va.voiceActivityType, equals(VoiceActivityType.activityStart));
      expect(va.audioOffset, equals('123ms'));

      final FunctionResponse response = FunctionResponse(
        name: 'testTool',
        response: <String, Object?>{'result': 'ok'},
        scheduling: FunctionResponseScheduling.whenIdle,
      );
      expect(response.scheduling, equals(FunctionResponseScheduling.whenIdle));
    });
  });

  group('Workflow as Tool parity', () {
    test('Workflow.asTool() returns a functional WorkflowTool', () async {
      final FunctionNode step1 = FunctionNode(
        name: 'step1',
        function: (WorkflowContext ctx, Object? input) async {
          return 'hello $input';
        },
      );

      final Workflow workflow = Workflow(
        name: 'greeter_workflow',
        description: 'Greets the input user',
        nodes: <BaseNode>[step1],
        edges: <Edge>[Edge(fromNode: START, toNode: 'step1')],
      );

      final BaseTool tool = workflow.asTool();
      expect(tool, isA<WorkflowTool>());
      expect(tool.name, equals('greeter_workflow'));
      expect(tool.description, equals('Greets the input user'));
      expect(tool.isLongRunning, isTrue);

      final Object? result = await tool.run(
        args: <String, dynamic>{'request': 'world'},
        toolContext: Context(
          InvocationContext(
            invocationId: 'test-inv',
            agent: workflow,
            session: Session(
              id: 's1',
              appName: 'test-app',
              userId: 'user1',
            ),
            sessionService: InMemorySessionService(),
          ),
        ),
      );
      expect(result, isA<Map<String, Object?>>());
      final Map<String, Object?> resultMap = result as Map<String, Object?>;
      expect(resultMap['step1'], equals('hello world'));
    });
  });

  group('Eventarc parity', () {
    test('EventarcToolset initializes and provides publish_message tool', () async {
      final EventarcToolset toolset = EventarcToolset();
      final List<BaseTool> tools = await toolset.getTools();
      expect(tools.length, equals(1));
      expect(tools.first.name, equals('publish_message'));
    });
  });

  group('Daytona environment parity', () {
    test('DaytonaEnvironment instantiates with custom configuration', () {
      final DaytonaEnvironment env = DaytonaEnvironment(
        apiKey: 'test-key',
        apiUrl: 'https://custom.daytona.io/api',
        image: 'python:3.11',
      );
      expect(env.apiKey, equals('test-key'));
      expect(env.apiUrl, equals('https://custom.daytona.io/api'));
      expect(env.image, equals('python:3.11'));
    });
  });

  group('LlmAudioUserSimulator parity', () {
    test('LlmAudioUserSimulator initializes with audio and text configuration', () {
      final LlmAudioUserSimulatorConfig config = LlmAudioUserSimulatorConfig(
        model: 'gemini-2.5-flash',
        audioModel: 'cloud_tts',
        includeTextWithAudio: true,
      );
      expect(config.model, equals('gemini-2.5-flash'));
      expect(config.audioModel, equals('cloud_tts'));
      expect(config.includeTextWithAudio, isTrue);

      final LlmAudioUserSimulator simulator = LlmAudioUserSimulator(
        config: config,
        conversationScenario: ConversationScenario(
          startingPrompt: 'Hello',
          conversationPlan: 'Greet the assistant',
          userPersona: UserPersona(
            id: 'alice',
            description: 'Friendly buyer',
          ),
        ),
      );
      expect(simulator.config.audioModel, equals('cloud_tts'));
    });
  });

  group('DatabaseSessionService prepareTables parity', () {
    test('prepareTables completes successfully', () async {
      final DatabaseSessionService service = DatabaseSessionService(
        'sqlite:///:memory:',
      );
      await expectLater(service.prepareTables(), completes);
    });
  });

  group('Gemma 4 model matching parity', () {
    test('GemmaLlm matches gemma-3 and gemma-4 models', () {
      final List<RegExp> regexes = GemmaLlm.supportedModels();
      final bool matchesGemma4 = regexes.any((RegExp r) => r.hasMatch('gemma-4-31b-it'));
      expect(matchesGemma4, isTrue);
    });
  });

  group('DataAgent modification parity', () {
    test('DataAgentToolset provides modification tools when enabled', () async {
      final DataAgentToolset toolset = DataAgentToolset(
        dataAgentToolConfig: DataAgentToolConfig(
          enableDataAgentModification: true,
        ),
      );
      final List<BaseTool> tools = await toolset.getTools();
      final List<String> toolNames = tools.map((BaseTool t) => t.name).toList();
      expect(toolNames, contains('create_data_agent'));
      expect(toolNames, contains('delete_data_agent'));
      expect(toolNames, contains('update_data_agent'));
      expect(toolNames, contains('ask_data_agent'));
      expect(toolNames, contains('get_data_agent_info'));
      expect(toolNames, contains('list_accessible_data_agents'));
    });
  });
}
