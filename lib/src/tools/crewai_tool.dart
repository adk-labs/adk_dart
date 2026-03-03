/// CrewAI adapter tool and configuration models.
library;

import '../models/llm_request.dart';
import 'function_tool.dart';
import 'tool_configs.dart';
import 'tool_context.dart';

/// Resolves a CrewAI tool path to an executable function.
typedef CrewaiToolResolver = Function Function(String toolPath);

/// Resolves a JSON schema for a CrewAI tool runner.
typedef CrewaiSchemaResolver =
    Map<String, dynamic>? Function(Function toolRunner);

/// Resolves mandatory argument names for a CrewAI tool runner.
typedef CrewaiMandatoryArgsResolver =
    List<String> Function(Function toolRunner);

/// Configuration model for [CrewaiTool].
class CrewaiToolConfig extends BaseToolConfig {
  /// Creates a CrewAI tool configuration.
  CrewaiToolConfig({
    required this.tool,
    this.name = '',
    this.description = '',
    super.extras,
  });

  /// Path used by the resolver to locate the CrewAI tool.
  final String tool;

  /// Optional override name for the ADK tool.
  final String name;

  /// Optional description for the ADK tool.
  final String description;
}

/// Adapter that exposes CrewAI tools through ADK [FunctionTool].
class CrewaiTool extends FunctionTool {
  /// Creates a CrewAI tool adapter.
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
  /// Validates mandatory args before invoking the wrapped tool function.
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

  /// Builds a [CrewaiTool] from serialized config values.
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
