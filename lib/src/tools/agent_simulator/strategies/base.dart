import '../../../models/llm_request.dart';
import '../../../tools/base_tool.dart';
import '../tool_connection_map.dart';

/// Base interface for mock strategies used by the simulator engine.
abstract class BaseMockStrategy {
  /// Produces a simulated tool response.
  Future<Map<String, Object?>> mock(
    BaseTool tool,
    Map<String, Object?> args,
    Object toolContext,
    ToolConnectionMap? toolConnectionMap,
    Map<String, Object?> stateStore, {
    String? environmentData,
  });
}

/// Fallback strategy that reports tracing-mode unavailability.
class TracingMockStrategy extends BaseMockStrategy {
  /// Creates a tracing mock strategy.
  TracingMockStrategy({required this.llmName, required this.llmConfig});

  /// Model name associated with this strategy.
  final String llmName;

  /// Model configuration associated with this strategy.
  final GenerateContentConfig llmConfig;

  @override
  /// Returns a standardized error payload indicating tracing is unavailable.
  Future<Map<String, Object?>> mock(
    BaseTool tool,
    Map<String, Object?> args,
    Object toolContext,
    ToolConnectionMap? toolConnectionMap,
    Map<String, Object?> stateStore, {
    String? environmentData,
  }) async {
    return <String, Object?>{
      'status': 'error',
      'error_message':
          'Tracing mock strategy is unavailable for tool `${tool.name}`.',
    };
  }
}
