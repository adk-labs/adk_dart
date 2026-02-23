import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Context _newToolContext() {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_lc_crewai',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_lc_crewai',
      appName: 'app',
      userId: 'u1',
      state: <String, Object?>{},
    ),
  );
  return Context(invocationContext);
}

void main() {
  group('LangchainTool parity', () {
    test('removes run_manager arg and executes wrapped runner', () async {
      String runner({required String query}) => 'ok:$query';
      final LangchainTool tool = LangchainTool(
        toolRunner: runner,
        name: 'lc_search',
        description: 'langchain search',
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{'query': 'adk', 'run_manager': 'ignored'},
        toolContext: _newToolContext(),
      );

      expect(result, 'ok:adk');
    });

    test('uses provided declaration schema', () {
      final LangchainTool tool = LangchainTool(
        toolRunner: ({required String query}) => 'ok:$query',
        name: 'lc_search',
        description: 'langchain search',
        parametersJsonSchema: <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'query': <String, dynamic>{'type': 'string'},
          },
          'required': <String>['query'],
        },
      );
      final FunctionDeclaration? declaration = tool.getDeclaration();
      expect(declaration, isNotNull);
      expect(declaration!.name, 'lc_search');
      expect(declaration.parameters['required'], <String>['query']);
    });

    test('fromConfig resolves tool path and applies overrides', () async {
      final ToolArgsConfig config = ToolArgsConfig(
        values: <String, Object?>{
          'tool': 'pkg.tools.search',
          'name': 'custom_lc',
          'description': 'custom description',
        },
      );

      final LangchainTool tool = LangchainTool.fromConfig(
        config,
        resolveTool: (String path) {
          expect(path, 'pkg.tools.search');
          return ({required String query}) => 'resolved:$query';
        },
        resolveSchema: (_) => <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'query': <String, dynamic>{'type': 'string'},
          },
        },
      );

      expect(tool.name, 'custom_lc');
      expect(tool.description, 'custom description');
      final Object? result = await tool.run(
        args: <String, dynamic>{'query': 'dart'},
        toolContext: _newToolContext(),
      );
      expect(result, 'resolved:dart');
    });
  });

  group('CrewaiTool parity', () {
    test('returns guidance error when mandatory args are missing', () async {
      final CrewaiTool tool = CrewaiTool(
        toolRunner: ({required String topic}) => 'topic:$topic',
        mandatoryArgs: <String>['topic'],
        name: 'crew_tool',
        description: 'crew tool',
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{},
        toolContext: _newToolContext(),
      );

      final Map<String, Object?> payload = Map<String, Object?>.from(
        result! as Map,
      );
      expect(payload['error'], contains('mandatory input parameters'));
      expect(payload['error'], contains('topic'));
    });

    test('invokes runner when mandatory args are present', () async {
      final CrewaiTool tool = CrewaiTool(
        toolRunner: ({required String topic}) => 'topic:$topic',
        mandatoryArgs: <String>['topic'],
        name: 'crew_tool',
        description: 'crew tool',
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{'topic': 'parity', 'self': 'discarded'},
        toolContext: _newToolContext(),
      );
      expect(result, 'topic:parity');
    });

    test('fromConfig resolves runner and metadata helpers', () async {
      final ToolArgsConfig config = ToolArgsConfig(
        values: <String, Object?>{
          'tool': 'pkg.crewai.tool',
          'name': 'custom_crew',
          'description': 'custom crew description',
        },
      );

      final CrewaiTool tool = CrewaiTool.fromConfig(
        config,
        resolveTool: (String path) {
          expect(path, 'pkg.crewai.tool');
          return ({required String topic}) => 'ok:$topic';
        },
        resolveMandatoryArgs: (_) => <String>['topic'],
        resolveSchema: (_) => <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'topic': <String, dynamic>{'type': 'string'},
          },
          'required': <String>['topic'],
        },
      );

      expect(tool.name, 'custom_crew');
      expect(tool.description, 'custom crew description');
      final Object? result = await tool.run(
        args: <String, dynamic>{'topic': 'sync'},
        toolContext: _newToolContext(),
      );
      expect(result, 'ok:sync');
      expect(tool.getDeclaration()!.parameters['required'], <String>['topic']);
    });
  });
}
