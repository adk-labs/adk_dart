import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _WorkingTool extends BaseTool {
  _WorkingTool() : super(name: 'working_tool', description: 'working tool');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'status': 'ok'};
  }
}

class _ThrowingToolset extends BaseToolset {
  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    throw StateError('boom');
  }
}

void main() {
  group('LlmAgent toolset parity', () {
    test(
      'canonicalTools skips failing toolsets and keeps other tools',
      () async {
        final LlmAgent agent = LlmAgent(
          name: 'root',
          instruction: 'root',
          tools: <Object>[_ThrowingToolset(), _WorkingTool()],
        );

        final List<BaseTool> tools = await agent.canonicalTools();

        expect(tools.map((BaseTool tool) => tool.name), <String>[
          'working_tool',
        ]);
      },
    );
  });
}
