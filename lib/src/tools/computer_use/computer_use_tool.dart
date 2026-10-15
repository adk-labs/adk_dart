/// Function-tool adapter for computer-use actions.
library;

import 'dart:convert';

import '../../models/llm_request.dart';
import '../function_tool.dart';
import '../tool_context.dart';
import 'base_computer.dart';

/// Callback that wraps a [ComputerUseTool] invocation (for example to serialize
/// access to the underlying [BaseComputer] and call [BaseComputer.prepare]).
typedef ComputerUseToolExecutor =
    Future<Object?> Function(
      ToolContext toolContext,
      Future<Object?> Function() action,
    );

/// Function tool wrapper for computer-use actions with screen metadata.
class ComputerUseTool extends FunctionTool {
  /// Creates a computer-use tool that normalizes virtual coordinates.
  ComputerUseTool({
    required super.func,
    required this.screenSize,
    this.virtualScreenSize = const (1000, 1000),
    String? name,
    String? description,
    this.executor,
  }) : super(
         name: name ?? 'computer_use_tool',
         description: description ?? 'Computer use tool',
       ) {
    if (screenSize.$1 <= 0 || screenSize.$2 <= 0) {
      throw ArgumentError('screenSize dimensions must be positive.');
    }
    if (virtualScreenSize.$1 <= 0 || virtualScreenSize.$2 <= 0) {
      throw ArgumentError('virtualScreenSize dimensions must be positive.');
    }
  }

  /// Physical screen size in pixels.
  final (int, int) screenSize;

  /// Virtual coordinate space exposed to the model.
  final (int, int) virtualScreenSize;

  /// Optional execution wrapper used by `ComputerUseToolset` to serialize
  /// tool executions and prepare the computer backend.
  final ComputerUseToolExecutor? executor;

  int _normalizeX(Object? x) {
    if (x is! num) {
      throw ArgumentError('x coordinate must be numeric, got ${x.runtimeType}');
    }
    final int normalized = (x / virtualScreenSize.$1 * screenSize.$1).toInt();
    return normalized.clamp(0, screenSize.$1 - 1);
  }

  int _normalizeY(Object? y) {
    if (y is! num) {
      throw ArgumentError('y coordinate must be numeric, got ${y.runtimeType}');
    }
    final int normalized = (y / virtualScreenSize.$2 * screenSize.$2).toInt();
    return normalized.clamp(0, screenSize.$2 - 1);
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    Future<Object?> execute() async {
      final Map<String, dynamic> normalizedArgs = Map<String, dynamic>.from(
        args,
      );

      for (final String key in const <String>[
        'x',
        'destination_x',
        'start_x',
        'end_x',
      ]) {
        if (normalizedArgs.containsKey(key) && normalizedArgs[key] != null) {
          normalizedArgs[key] = _normalizeX(normalizedArgs[key]);
        }
      }
      for (final String key in const <String>[
        'y',
        'destination_y',
        'start_y',
        'end_y',
      ]) {
        if (normalizedArgs.containsKey(key) && normalizedArgs[key] != null) {
          normalizedArgs[key] = _normalizeY(normalizedArgs[key]);
        }
      }

      final Object? coord = normalizedArgs['coordinate'];
      if (coord is List &&
          coord.length == 2 &&
          coord[0] is num &&
          coord[1] is num) {
        normalizedArgs['coordinate'] = <int>[
          _normalizeX(coord[0]),
          _normalizeY(coord[1]),
        ];
      }

      if (normalizedArgs.containsKey('start_x')) {
        final FunctionDeclaration? decl = getDeclaration();
        final Object? props = decl?.parameters['properties'];
        final bool acceptsStartX =
            props is Map && props.containsKey('start_x');
        if (!acceptsStartX) {
          normalizedArgs['x'] = normalizedArgs.remove('start_x');
          if (normalizedArgs.containsKey('start_y')) {
            normalizedArgs['y'] = normalizedArgs.remove('start_y');
          }
          if (normalizedArgs.containsKey('end_x')) {
            normalizedArgs['destination_x'] = normalizedArgs.remove('end_x');
          }
          if (normalizedArgs.containsKey('end_y')) {
            normalizedArgs['destination_y'] = normalizedArgs.remove('end_y');
          }
        }
      }

      final Object? result = await super.run(
        args: normalizedArgs,
        toolContext: toolContext,
      );
      if (result is ComputerState) {
        return <String, Object?>{
          'image': <String, Object?>{
            'mimetype': 'image/png',
            'data': base64Encode(result.screenshot),
          },
          'url': result.url,
        };
      }
      return result;
    }

    if (executor != null) {
      return executor!(toolContext, execute);
    }
    return execute();
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {}
}
