/// Toolset that provides model consultation tools and system guidance.
library;

import '../../agents/readonly_context.dart';
import '../../models/base_llm.dart';
import '../../models/llm_request.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../tool_context.dart';
import 'model_consult_tool.dart';

/// Default guidance appended to the host agent's system instruction when
/// [ModelConsultToolset] is attached.
String buildModelConsultSystemInstruction({
  required String toolName,
  String? customGuidance,
}) {
  final String base =
      'You have access to the `$toolName` tool to consult a secondary advisor '
      'model when facing complex reasoning, ambiguous requirements, architectural '
      'trade-offs, or difficult debugging steps. Provide a clear `question` and '
      'any relevant `context` when calling `$toolName`, then incorporate its '
      'advice into your execution.';
  if (customGuidance == null || customGuidance.trim().isEmpty) {
    return base;
  }
  return '$base\n${customGuidance.trim()}';
}

/// Toolset that exposes a [ModelConsultTool] and injects usage instructions.
///
/// ```dart
/// final toolset = ModelConsultToolset(
///   model: 'gemini-2.5-pro',
///   advisorInstruction: 'Focus on security and correctness.',
/// );
/// ```
class ModelConsultToolset extends BaseToolset {
  /// Creates a model consultation toolset backed by [model].
  ModelConsultToolset({
    required this.model,
    this.toolName = defaultConsultModelToolName,
    this.toolDescription,
    this.advisorInstruction = defaultAdvisorSystemInstruction,
    this.contextConfig = const ModelConsultContextConfig(),
    this.generateContentConfig,
    this.maxConsultationsPerInvocation,
    this.injectSystemInstruction = true,
    this.systemInstructionGuidance,
    super.toolFilter,
    super.toolNamePrefix,
  }) : _tool = ModelConsultTool(
         model: model,
         name: toolName,
         description: toolDescription,
         advisorInstruction: advisorInstruction,
         contextConfig: contextConfig,
         generateContentConfig: generateContentConfig,
         maxConsultationsPerInvocation: maxConsultationsPerInvocation,
       );

  /// Advisor model specification, either a model name [String] or a [BaseLlm].
  final Object model;

  /// Name of the consultation tool exposed to the agent.
  final String toolName;

  /// Optional custom description for the consultation tool.
  final String? toolDescription;

  /// System instruction sent to the advisor model.
  final String advisorInstruction;

  /// Context formatting configuration for conversation history.
  final ModelConsultContextConfig contextConfig;

  /// Optional generation configuration overrides for the advisor request.
  final GenerateContentConfig? generateContentConfig;

  /// Optional cap on how many consultations may occur in one invocation.
  final int? maxConsultationsPerInvocation;

  /// Whether to append advisor usage guidance to the host agent's LLM request.
  final bool injectSystemInstruction;

  /// Optional additional guidance appended to the host agent's system prompt.
  final String? systemInstructionGuidance;

  final ModelConsultTool _tool;

  /// Underlying [ModelConsultTool] instance managed by this toolset.
  ModelConsultTool get consultTool => _tool;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    if (!isToolSelected(_tool, readonlyContext)) {
      return const <BaseTool>[];
    }
    return <BaseTool>[_tool];
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    if (!injectSystemInstruction) {
      return;
    }
    if (!isToolSelected(_tool, toolContext)) {
      return;
    }
    final String effectiveName =
        toolNamePrefix != null && toolNamePrefix!.isNotEmpty
        ? '${toolNamePrefix}_$toolName'
        : toolName;
    llmRequest.appendInstructions(<String>[
      buildModelConsultSystemInstruction(
        toolName: effectiveName,
        customGuidance: systemInstructionGuidance,
      ),
    ]);
  }
}

/// Alias class for [ModelConsultToolset] providing the `ConsultModelToolset` name.
///
/// ```dart
/// final toolset = ConsultModelToolset(model: 'gemini-2.5-pro');
/// ```
class ConsultModelToolset extends ModelConsultToolset {
  /// Creates a [ConsultModelToolset] backed by [model].
  ConsultModelToolset({
    required super.model,
    super.toolName,
    super.toolDescription,
    super.advisorInstruction,
    super.contextConfig,
    super.generateContentConfig,
    super.maxConsultationsPerInvocation,
    super.injectSystemInstruction,
    super.systemInstructionGuidance,
    super.toolFilter,
    super.toolNamePrefix,
  });
}
