import '../models/llm_request.dart';
import 'function_tool.dart';
import 'tool_configs.dart';
import 'tool_context.dart';

typedef CrewaiToolResolver = Function Function(String toolPath);
typedef CrewaiSchemaResolver =
    Map<String, dynamic>? Function(Function toolRunner);
typedef CrewaiMandatoryArgsResolver =
    List<String> Function(Function toolRunner);

class CrewaiToolConfig extends BaseToolConfig {
  CrewaiToolConfig({
    required this.tool,
    this.name = '',
    this.description = '',
    super.extras,
  });

  final String tool;
  final String name;
  final String description;
}

class CrewaiTool extends FunctionTool {
  CrewaiTool({
    required Function toolRunner,
    required List<String> mandatoryArgs,
    String? name,
    String? description,
    Map<String, dynamic>? parametersJsonSchema,
  }) : _mandatoryArgs = List<String>.from(mandatoryArgs),
       _parametersJsonSchema = parametersJsonSchema,
       super(
         func: toolRunner,
         name: name ?? 'crewai_tool',
         description: description ?? '',
       );

  final List<String> _mandatoryArgs;
  final Map<String, dynamic>? _parametersJsonSchema;

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Map<String, dynamic> argsToCall = Map<String, dynamic>.from(args);
    argsToCall.remove('self');

    final List<String> missing = _mandatoryArgs
        .where((String arg) => !argsToCall.containsKey(arg))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      final String missingArgs = missing.join('\n');
      final String errorStr =
          'Invoking `$name()` failed as the following mandatory input parameters are not present:\n'
          '$missingArgs\n'
          'You could retry calling this tool, but it is IMPORTANT for you to provide all the mandatory parameters.';
      return <String, Object?>{'error': errorStr};
    }

    return super.run(args: argsToCall, toolContext: toolContext);
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

  static CrewaiTool fromConfig(
    ToolArgsConfig config, {
    required CrewaiToolResolver resolveTool,
    CrewaiMandatoryArgsResolver? resolveMandatoryArgs,
    CrewaiSchemaResolver? resolveSchema,
  }) {
    final String? toolPath = config['tool'] as String?;
    if (toolPath == null || toolPath.isEmpty) {
      throw ArgumentError(
        'CrewaiTool config must contain non-empty `tool` path.',
      );
    }
    final String? name = config['name'] as String?;
    final String? description = config['description'] as String?;
    final Function runner = resolveTool(toolPath);
    return CrewaiTool(
      toolRunner: runner,
      name: (name?.isNotEmpty ?? false) ? name : null,
      description: (description?.isNotEmpty ?? false) ? description : null,
      mandatoryArgs: resolveMandatoryArgs?.call(runner) ?? const <String>[],
      parametersJsonSchema: resolveSchema?.call(runner),
    );
  }
}
