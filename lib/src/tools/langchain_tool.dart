import '../models/llm_request.dart';
import 'function_tool.dart';
import 'tool_configs.dart';
import 'tool_context.dart';

typedef LangchainToolResolver = Function Function(String toolPath);
typedef LangchainSchemaResolver =
    Map<String, dynamic>? Function(Function toolRunner);

class LangchainToolConfig extends BaseToolConfig {
  LangchainToolConfig({
    required this.tool,
    this.name = '',
    this.description = '',
    super.extras,
  });

  final String tool;
  final String name;
  final String description;
}

class LangchainTool extends FunctionTool {
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
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Map<String, dynamic> sanitized = Map<String, dynamic>.from(args);
    sanitized.remove('run_manager');
    return super.run(args: sanitized, toolContext: toolContext);
  }

  @override
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
