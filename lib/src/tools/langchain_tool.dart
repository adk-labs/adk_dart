/// LangChain adapter tool and configuration models.
library;

import '../models/llm_request.dart';
import 'function_tool.dart';
import 'tool_configs.dart';
import 'tool_context.dart';

/// Resolves a LangChain tool path to an executable function.
typedef LangchainToolResolver = Function Function(String toolPath);

/// Resolves an optional JSON schema for a LangChain tool runner.
typedef LangchainSchemaResolver =
    Map<String, dynamic>? Function(Function toolRunner);

/// Configuration model for [LangchainTool].
class LangchainToolConfig extends BaseToolConfig {
  /// Creates a LangChain tool configuration.
  LangchainToolConfig({
    required this.tool,
    this.name = '',
    this.description = '',
    super.extras,
  });

  /// Path used by the resolver to locate the LangChain tool.
  final String tool;

  /// Optional override name for the ADK tool.
  final String name;

  /// Optional description for the ADK tool.
  final String description;
}

/// Adapter that exposes LangChain tools through ADK [FunctionTool].
class LangchainTool extends FunctionTool {
  /// Creates a LangChain tool adapter.
  LangchainTool({
    required Function toolRunner,
    String? name,
    String? description,
    Map<String, dynamic>? parametersJsonSchema,
  }) : _parametersJsonSchema = parametersJsonSchema,
       super(
         func: toolRunner,
         name: name ?? 'langchain_tool',
         description: description ?? '',
       );

  final Map<String, dynamic>? _parametersJsonSchema;

  @override
  /// Removes `run_manager` arg before invoking the wrapped tool function.
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Map<String, dynamic> sanitized = Map<String, dynamic>.from(args);
    sanitized.remove('run_manager');
    return super.run(args: sanitized, toolContext: toolContext);
  }

  @override
  /// Returns the configured schema override when available.
  FunctionDeclaration? getDeclaration() {
    final Map<String, dynamic>? schema = _parametersJsonSchema;
    if (schema != null) {
      return FunctionDeclaration(
        name: name,
        description: description,
        parameters: Map<String, dynamic>.from(schema),
      );
    }
    return super.getDeclaration();
  }

  /// Builds a [LangchainTool] from serialized config values.
  static LangchainTool fromConfig(
    ToolArgsConfig config, {
    required LangchainToolResolver resolveTool,
    LangchainSchemaResolver? resolveSchema,
  }) {
    final String? toolPath = config['tool'] as String?;
    if (toolPath == null || toolPath.isEmpty) {
      throw ArgumentError(
        'LangchainTool config must contain non-empty `tool` path.',
      );
    }
    final String? name = config['name'] as String?;
    final String? description = config['description'] as String?;
    final Function runner = resolveTool(toolPath);
    return LangchainTool(
      toolRunner: runner,
      name: (name?.isNotEmpty ?? false) ? name : null,
      description: (description?.isNotEmpty ?? false) ? description : null,
      parametersJsonSchema: resolveSchema?.call(runner),
    );
  }
}
