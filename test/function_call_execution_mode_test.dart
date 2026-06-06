import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

class _DelayTool extends BaseTool {
  _DelayTool({
    required super.name,
    required this.delay,
    required this.startOrder,
    required this.finishOrder,
  }) : super(description: 'Delay tool');

  final Duration delay;
  final List<String> startOrder;
  final List<String> finishOrder;

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    startOrder.add(name);
    await Future<void>.delayed(delay);
    finishOrder.add(name);
    return <String, Object?>{'name': name};
  }
}

void main() {
  group('function call execution mode parity', () {
    test('defaults to parallel execution for multiple tool calls', () async {
      final List<String> startOrder = <String>[];
      final List<String> finishOrder = <String>[];
      final _DelayTool slow = _DelayTool(
        name: 'slow',
        delay: const Duration(milliseconds: 30),
        startOrder: startOrder,
        finishOrder: finishOrder,
      );
      final _DelayTool fast = _DelayTool(
        name: 'fast',
        delay: Duration.zero,
        startOrder: startOrder,
        finishOrder: finishOrder,
      );

      final Event? event = await handleFunctionCallListAsync(
        _context(),
        <FunctionCall>[
          FunctionCall(name: 'slow', id: 'call_slow'),
          FunctionCall(name: 'fast', id: 'call_fast'),
        ],
        <String, BaseTool>{slow.name: slow, fast.name: fast},
      );

      expect(event, isNotNull);
      expect(startOrder, containsAllInOrder(<String>['slow', 'fast']));
      expect(finishOrder, <String>['fast', 'slow']);
    });

    test('sequential mode awaits tool calls in request order', () async {
      final List<String> startOrder = <String>[];
      final List<String> finishOrder = <String>[];
      final _DelayTool slow = _DelayTool(
        name: 'slow',
        delay: const Duration(milliseconds: 30),
        startOrder: startOrder,
        finishOrder: finishOrder,
      );
      final _DelayTool fast = _DelayTool(
        name: 'fast',
        delay: Duration.zero,
        startOrder: startOrder,
        finishOrder: finishOrder,
      );

      final Event? event = await handleFunctionCallListAsync(
        _context(
          runConfig: RunConfig(toolExecutionMode: ToolExecutionMode.sequential),
        ),
        <FunctionCall>[
          FunctionCall(name: 'slow', id: 'call_slow'),
          FunctionCall(name: 'fast', id: 'call_fast'),
        ],
        <String, BaseTool>{slow.name: slow, fast.name: fast},
      );

      expect(event, isNotNull);
      expect(startOrder, <String>['slow', 'fast']);
      expect(finishOrder, <String>['slow', 'fast']);
      expect(event!.content?.parts, hasLength(2));
      expect(event.content?.parts.first.functionResponse?.name, 'slow');
      expect(event.content?.parts.last.functionResponse?.name, 'fast');
    });

    test('RunConfig copies tool execution mode', () {
      final RunConfig config = RunConfig(
        toolExecutionMode: ToolExecutionMode.sequential,
      );

      expect(RunConfig().toolExecutionMode, ToolExecutionMode.none);
      expect(config.copyWith().toolExecutionMode, ToolExecutionMode.sequential);
      expect(
        config
            .copyWith(toolExecutionMode: ToolExecutionMode.parallel)
            .toolExecutionMode,
        ToolExecutionMode.parallel,
      );
    });
  });
}

InvocationContext _context({RunConfig? runConfig}) {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_tool_execution_mode',
    agent: Agent(name: 'root_agent', model: _NoopModel()),
    session: Session(id: 's_tool_execution_mode', appName: 'app', userId: 'u1'),
    runConfig: runConfig,
  );
}
