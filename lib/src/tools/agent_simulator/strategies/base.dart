import '../../../models/llm_request.dart';
import '../../../tools/base_tool.dart';
import '../tool_connection_map.dart';

abstract class BaseMockStrategy {
  Future<Map<String, Object?>> mock(
    BaseTool tool,
    Map<String, Object?> args,
    Object toolContext,
    ToolConnectionMap? toolConnectionMap,
    Map<String, Object?> stateStore, {
    String? environmentData,
  });
}

class TracingMockStrategy extends BaseMockStrategy {
  TracingMockStrategy({required this.llmName, required this.llmConfig});

  final String llmName;
  final GenerateContentConfig llmConfig;

  @override
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
