import 'dart:async';
import 'dart:developer' as developer;

import '../../agents/readonly_context.dart';
import '../../models/llm_request.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../tool_context.dart';
import 'base_computer.dart';
import 'computer_use_tool.dart';

const Set<String> excludedComputerMethods = <String>{
  'screen_size',
  'environment',
  'close',
};

class ComputerUseToolAdapter {
  ComputerUseToolAdapter({required this.name, required this.func});

  final String name;
  final Function func;
}

class ComputerUseToolset extends BaseToolset {
  ComputerUseToolset({required BaseComputer computer})
    : _computer = computer,
      super();

  final BaseComputer _computer;
  bool _initialized = false;
  List<ComputerUseTool>? _tools;

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await _computer.initialize();
    _initialized = true;
  }

  static Future<void> adaptComputerUseTool({
    required String methodName,
    required FutureOr<Object> Function(Function original) adapterFunc,
    required LlmRequest llmRequest,
  }) async {
    if (excludedComputerMethods.contains(methodName)) {
      developer.log(
        'Method $methodName is not a valid BaseComputer method.',
        name: 'adk_dart.computer_use',
      );
      return;
    }

    final BaseTool? rawTool = llmRequest.toolsDict[methodName];
    if (rawTool is! ComputerUseTool) {
      developer.log(
        'Method $methodName not found in toolsDict as ComputerUseTool.',
        name: 'adk_dart.computer_use',
      );
      return;
    }

    final Object adapted = await Future<Object>.value(
      adapterFunc(rawTool.func),
    );
    late final String newMethodName;
    late final Function adaptedFunc;

    if (adapted is ComputerUseToolAdapter) {
      newMethodName = adapted.name;
      adaptedFunc = adapted.func;
    } else if (adapted is Function) {
      newMethodName = methodName;
      adaptedFunc = adapted;
    } else {
      developer.log(
        'Adapter result for $methodName must be Function or ComputerUseToolAdapter.',
        name: 'adk_dart.computer_use',
      );
      return;
    }

    final ComputerUseTool adaptedTool = ComputerUseTool(
      name: newMethodName,
      func: adaptedFunc,
      screenSize: rawTool.screenSize,
      virtualScreenSize: rawTool.virtualScreenSize,
    );
    llmRequest.toolsDict[newMethodName] = adaptedTool;
    if (newMethodName != methodName) {
      llmRequest.toolsDict.remove(methodName);
    }
  }

  @override
  Future<List<ComputerUseTool>> getTools({
    ReadonlyContext? readonlyContext,
  }) async {
    if (_tools != null) {
      return _tools!;
    }

    await _ensureInitialized();
    final (int, int) screenSize = await _computer.screenSize();

    _tools = <ComputerUseTool>[
      ComputerUseTool(
        name: 'open_web_browser',
        func: () => _computer.openWebBrowser(),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'click_at',
        func: ({required int x, required int y}) => _computer.clickAt(x, y),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'hover_at',
        func: ({required int x, required int y}) => _computer.hoverAt(x, y),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'type_text_at',
        func:
            ({
              required int x,
              required int y,
              required String text,
              bool press_enter = true,
              bool clear_before_typing = true,
            }) => _computer.typeTextAt(
              x,
              y,
              text,
              pressEnter: press_enter,
              clearBeforeTyping: clear_before_typing,
            ),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'scroll_document',
        func: ({required String direction}) =>
            _computer.scrollDocument(direction),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'scroll_at',
        func:
            ({
              required int x,
              required int y,
              required String direction,
              required int magnitude,
            }) => _computer.scrollAt(x, y, direction, magnitude),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'wait',
        func: ({required int seconds}) => _computer.wait(seconds),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'go_back',
        func: () => _computer.goBack(),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'go_forward',
        func: () => _computer.goForward(),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'search',
        func: () => _computer.search(),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'navigate',
        func: ({required String url}) => _computer.navigate(url),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'key_combination',
        func: ({required List<Object?> keys}) {
          final List<String> normalized = keys
              .map((Object? value) => '$value')
              .toList(growable: false);
          return _computer.keyCombination(normalized);
        },
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'drag_and_drop',
        func:
            ({
              required int x,
              required int y,
              required int destination_x,
              required int destination_y,
            }) => _computer.dragAndDrop(x, y, destination_x, destination_y),
        screenSize: screenSize,
      ),
      ComputerUseTool(
        name: 'current_state',
        func: () => _computer.currentState(),
        screenSize: screenSize,
      ),
    ];

    return _tools!;
  }

  @override
  Future<void> close() async {
    await _computer.close();
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final List<ComputerUseTool> tools = await getTools();
    for (final ComputerUseTool tool in tools) {
      llmRequest.toolsDict[tool.name] = tool;
      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: llmRequest,
      );
    }

    final ComputerEnvironment environment = await _computer.environment();
    llmRequest.config.tools ??= <ToolDeclaration>[];
    if (!llmRequest.config.tools!.any(
      (ToolDeclaration tool) => tool.computerUse != null,
    )) {
      llmRequest.config.tools!.add(
        ToolDeclaration(
          computerUse: <String, Object?>{
            'environment': _computerEnvironmentValue(environment),
          },
        ),
      );
    }
    llmRequest.config.labels['adk_computer_use_environment'] = environment.name;
  }
}

String _computerEnvironmentValue(ComputerEnvironment environment) {
  switch (environment) {
    case ComputerEnvironment.environmentBrowser:
      return 'ENVIRONMENT_BROWSER';
    case ComputerEnvironment.environmentUnspecified:
      return 'ENVIRONMENT_UNSPECIFIED';
  }
}
