/// Function-tool adapter for computer-use actions.
library;

import 'dart:convert';

import '../../models/llm_request.dart';
import '../function_tool.dart';
import '../tool_context.dart';
import 'base_computer.dart';

/// Function tool wrapper for computer-use actions with screen metadata.
class ComputerUseTool extends FunctionTool {
  /// Creates a computer-use tool that normalizes virtual coordinates.
  ComputerUseTool({
    required super.func,
    required this.screenSize,
    this.virtualScreenSize = const (1000, 1000),
    String? name,
    String? description,
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
    final Map<String, dynamic> normalizedArgs = Map<String, dynamic>.from(args);

    if (normalizedArgs.containsKey('x')) {
      normalizedArgs['x'] = _normalizeX(normalizedArgs['x']);
    }
    if (normalizedArgs.containsKey('y')) {
      normalizedArgs['y'] = _normalizeY(normalizedArgs['y']);
    }
    if (normalizedArgs.containsKey('destination_x')) {
      normalizedArgs['destination_x'] = _normalizeX(
        normalizedArgs['destination_x'],
      );
    }
    if (normalizedArgs.containsKey('destination_y')) {
      normalizedArgs['destination_y'] = _normalizeY(
        normalizedArgs['destination_y'],
      );
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

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {}
}
