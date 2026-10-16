/// Model consultation tool for querying an advisor model from an active agent.
library;

import 'dart:async';
import 'dart:convert';

import '../../agents/callback_context.dart';
import '../../agents/invocation_context.dart';
import '../../events/event.dart';
import '../../models/base_llm.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../models/registry.dart';
import '../../types/content.dart';
import '../../version.dart';
import '../base_tool.dart';
import '../tool_context.dart';

/// Client label sent on advisor LLM requests.
const String modelConsultClientLabel = 'google-adk-model-consult/$adkVersion';

/// Default tool name for [ModelConsultTool].
const String defaultConsultModelToolName = 'consult_model';

/// Default system instruction passed to the advisor model.
const String defaultAdvisorSystemInstruction =
    'You are an expert advisor assisting an AI agent. '
    'Review the provided conversation context and question, and give a clear, '
    'actionable, and concise recommendation to help the agent proceed.';

final Object _clientLabelZoneKey = Object();

/// Runs [action] in a zone tagged with [label] for tracking header attribution.
Future<T> withModelConsultClientLabel<T>(
  String label,
  Future<T> Function() action,
) {
  return runZoned(action, zoneValues: <Object?, Object?>{_clientLabelZoneKey: label});
}

/// Returns the active model-consult client label in the current [Zone], if any.
String? get currentModelConsultClientLabel =>
    Zone.current[_clientLabelZoneKey] as String?;

/// Controls how conversation history is formatted for the advisor model.
class ModelConsultContextConfig {
  /// Creates a context configuration for [ModelConsultTool].
  const ModelConsultContextConfig({
    this.includeConversationHistory = true,
    this.maxEvents = 20,
    this.includeToolCalls = true,
    this.includeThoughts = false,
    this.maxTurnCharacters = 4000,
  });

  /// Whether recent session events should be included in the advisor prompt.
  final bool includeConversationHistory;

  /// Maximum number of recent session events to include.
  final int maxEvents;

  /// Whether tool calls and tool responses are included in the transcript.
  final bool includeToolCalls;

  /// Whether model thought parts are included in the transcript.
  final bool includeThoughts;

  /// Maximum character length per formatted event entry before truncation.
  final int maxTurnCharacters;
}

/// Token usage reported by the advisor model.
class AdvisorUsage {
  /// Creates an advisor token usage summary.
  const AdvisorUsage({
    this.promptTokenCount,
    this.candidatesTokenCount,
    this.totalTokenCount,
    this.thoughtsTokenCount,
  });

  /// Creates an [AdvisorUsage] from raw LLM usage metadata, if available.
  factory AdvisorUsage.fromUsageMetadata(Object? usageMetadata) {
    if (usageMetadata is Map) {
      return AdvisorUsage(
        promptTokenCount: _asInt(
          usageMetadata['prompt_token_count'] ??
              usageMetadata['promptTokenCount'],
        ),
        candidatesTokenCount: _asInt(
          usageMetadata['candidates_token_count'] ??
              usageMetadata['candidatesTokenCount'],
        ),
        totalTokenCount: _asInt(
          usageMetadata['total_token_count'] ??
              usageMetadata['totalTokenCount'],
        ),
        thoughtsTokenCount: _asInt(
          usageMetadata['thoughts_token_count'] ??
              usageMetadata['thoughtsTokenCount'],
        ),
      );
    }
    return const AdvisorUsage();
  }

  /// Number of prompt tokens consumed by the advisor call.
  final int? promptTokenCount;

  /// Number of completion tokens produced by the advisor call.
  final int? candidatesTokenCount;

  /// Total tokens consumed by the advisor call.
  final int? totalTokenCount;

  /// Number of reasoning/thought tokens consumed by the advisor call.
  final int? thoughtsTokenCount;

  /// Serializes this usage record to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (promptTokenCount != null) 'prompt_token_count': promptTokenCount,
      if (candidatesTokenCount != null)
        'candidates_token_count': candidatesTokenCount,
      if (totalTokenCount != null) 'total_token_count': totalTokenCount,
      if (thoughtsTokenCount != null)
        'thoughts_token_count': thoughtsTokenCount,
    };
  }
}

/// Successful response payload returned by [ModelConsultTool].
class AdvisorResult {
  /// Creates an advisor consultation result.
  const AdvisorResult({
    required this.advice,
    required this.model,
    this.thoughts,
    this.usage,
  });

  /// Guidance text returned by the advisor model.
  final String advice;

  /// Identifier of the advisor model that generated [advice].
  final String model;

  /// Optional reasoning or thought summary returned by the advisor model.
  final String? thoughts;

  /// Optional token usage statistics for the consultation call.
  final AdvisorUsage? usage;

  /// Serializes this result to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': 'success',
      'model': model,
      'advice': advice,
      if (thoughts != null && thoughts!.isNotEmpty) 'thoughts': thoughts,
      if (usage != null) 'usage': usage!.toJson(),
    };
  }
}

/// Error payload returned when an advisor model consultation fails.
class AdvisorError {
  /// Creates an advisor consultation error record.
  const AdvisorError({
    required this.error,
    required this.errorCode,
    this.model,
  });

  /// Human-readable error message.
  final String error;

  /// Machine-readable error code.
  final String errorCode;

  /// Identifier of the advisor model that was queried, if known.
  final String? model;

  /// Serializes this error to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': 'error',
      'error': error,
      'error_code': errorCode,
      if (model != null) 'model': model,
    };
  }
}

/// Tool that allows an agent to consult a secondary advisor LLM for guidance.
///
/// ```dart
/// final consultTool = ModelConsultTool(
///   model: 'gemini-2.5-pro',
///   advisorInstruction: 'Provide concise architectural guidance.',
/// );
/// ```
class ModelConsultTool extends BaseTool {
  /// Creates a tool that consults [model] when invoked by an agent.
  ModelConsultTool({
    required this.model,
    super.name = defaultConsultModelToolName,
    String? description,
    this.advisorInstruction = defaultAdvisorSystemInstruction,
    this.contextConfig = const ModelConsultContextConfig(),
    this.generateContentConfig,
    int? maxConsultationsPerInvocation,
    int? maxUses,
    this.sessionMaxUses,
  }) : maxConsultationsPerInvocation = maxConsultationsPerInvocation ?? maxUses,
       super(
         description:
             description ??
             'Consults an expert advisor model for guidance on complex '
                 'questions, planning, debugging, or trade-off analysis.',
       ) {
    if (model is! String && model is! BaseLlm) {
      throw ArgumentError(
        'ModelConsultTool.model must be a model name String or BaseLlm instance.',
      );
    }
  }

  /// Default tool name for model consultation.
  static const String defaultToolName = defaultConsultModelToolName;

  /// Returns the state key for turn uses of [toolName].
  static String turnUsesStateKey({
    required String toolName,
    required String invocationId,
  }) =>
      'temp:model_consult:$toolName:$invocationId:uses';

  /// Returns the state key for session uses of [toolName].
  static String sessionUsesStateKey({required String toolName}) =>
      'model_consult:$toolName:session_uses';

  /// Advisor model specification, either a model name [String] or a [BaseLlm].
  final Object model;

  /// System instruction sent to the advisor model.
  final String advisorInstruction;

  /// Context formatting configuration for conversation history.
  final ModelConsultContextConfig contextConfig;

  /// Optional generation configuration overrides for the advisor request.
  final GenerateContentConfig? generateContentConfig;

  /// Optional cap on how many consultations may occur in one invocation.
  final int? maxConsultationsPerInvocation;

  /// Optional cap on how many consultations may occur in one invocation (alias).
  int? get maxUses => maxConsultationsPerInvocation;

  /// Optional cap on how many consultations may occur across a multi-turn session.
  final int? sessionMaxUses;

  /// Resolved advisor [BaseLlm] instance.
  BaseLlm get resolvedModel {
    if (model is BaseLlm) {
      return model as BaseLlm;
    }
    return LLMRegistry.newLlm(model as String);
  }

  /// Returns whether this tool still has remaining budget for [context].
  bool hasRemainingBudget(Object context) {
    if (sessionMaxUses != null && sessionUses(context) >= sessionMaxUses!) {
      return false;
    }
    final int? turnCap = maxConsultationsPerInvocation;
    if (turnCap != null && turnUses(context) >= turnCap) {
      return false;
    }
    return true;
  }

  /// Returns the number of consultations performed in the current turn for [context].
  int turnUses(Object context) {
    final String? invocationId = _extractInvocationId(context);
    final Map<String, Object?>? state = _extractState(context);
    if (invocationId == null || state == null) return 0;
    final String key = turnUsesStateKey(toolName: name, invocationId: invocationId);
    final Object? val = state[key];
    return val is num ? val.toInt() : 0;
  }

  /// Returns the number of consultations performed in the session for [context].
  int sessionUses(Object context) {
    final Map<String, Object?>? state = _extractState(context);
    if (state == null) return 0;
    final String key = sessionUsesStateKey(toolName: name);
    final Object? val = state[key];
    return val is num ? val.toInt() : 0;
  }

  static String? _extractInvocationId(Object context) {
    if (context is ToolContext) return context.invocationId;
    if (context is CallbackContext) return context.invocationId;
    if (context is InvocationContext) return context.invocationId;
    try {
      final dynamic dyn = context;
      final Object? id = dyn.invocationId;
      return id?.toString();
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?>? _extractState(Object context) {
    if (context is ToolContext) return context.state;
    if (context is CallbackContext) return context.state;
    if (context is InvocationContext) return context.session.state;
    if (context is Map<String, Object?>) return context;
    try {
      final dynamic dyn = context;
      final Object? state = dyn.state;
      if (state is Map<String, Object?>) return state;
      if (state != null) {
        final dynamic s = state;
        return s as Map<String, Object?>;
      }
    } catch (_) {}
    return null;
  }

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'question': <String, Object?>{
            'type': 'string',
            'description':
                'The specific question, dilemma, or problem to ask the advisor model.',
          },
          'context': <String, Object?>{
            'type': 'string',
            'description':
                'Optional additional context, constraints, or findings to share with the advisor.',
          },
        },
        'required': <String>['question'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? rawQuestion = args['question'] ?? args['query'];
    if (rawQuestion is! String || rawQuestion.trim().isEmpty) {
      return const AdvisorError(
        error: "Argument 'question' is required and must be a non-empty string.",
        errorCode: 'INVALID_ARGUMENTS',
      ).toJson();
    }

    final BaseLlm advisorLlm;
    try {
      advisorLlm = resolvedModel;
    } catch (error) {
      return AdvisorError(
        error: 'Failed to resolve advisor model: $error',
        errorCode: 'MODEL_RESOLUTION_ERROR',
        model: '$model',
      ).toJson();
    }

    if (sessionMaxUses != null) {
      final int currentSessionUses = sessionUses(toolContext);
      if (currentSessionUses >= sessionMaxUses!) {
        return AdvisorError(
          error:
              'Maximum number of model consultations ($sessionMaxUses) '
              'reached for this session.',
          errorCode: 'SESSION_CONSULTATION_LIMIT_EXCEEDED',
          model: advisorLlm.model,
        ).toJson();
      }
    }

    if (maxConsultationsPerInvocation != null) {
      final int currentTurnUses = turnUses(toolContext);
      if (currentTurnUses >= maxConsultationsPerInvocation!) {
        return AdvisorError(
          error:
              'Maximum number of model consultations ($maxConsultationsPerInvocation) '
              'reached for this invocation.',
          errorCode: 'CONSULTATION_LIMIT_EXCEEDED',
          model: advisorLlm.model,
        ).toJson();
      }
    }

    final String question = rawQuestion.trim();
    final String? extraContext =
        args['context'] is String && (args['context'] as String).trim().isNotEmpty
        ? (args['context'] as String).trim()
        : null;

    final String prompt = _buildAdvisorPrompt(
      question: question,
      extraContext: extraContext,
      toolContext: toolContext,
    );

    final GenerateContentConfig requestConfig =
        (generateContentConfig?.copyWith() ?? GenerateContentConfig())
          ..systemInstruction = advisorInstruction;
    final Map<String, String> existingHeaders =
        requestConfig.httpOptions?.headers ?? const <String, String>{};
    final String existingApiClient = existingHeaders['x-goog-api-client'] ?? '';
    final String mergedApiClient = existingApiClient.isEmpty
        ? modelConsultClientLabel
        : '$existingApiClient $modelConsultClientLabel';
    requestConfig.httpOptions = HttpOptions(
      apiVersion: requestConfig.httpOptions?.apiVersion,
      retryOptions: requestConfig.httpOptions?.retryOptions,
      headers: <String, String>{
        ...existingHeaders,
        'x-goog-api-client': mergedApiClient,
      },
    );

    final LlmRequest request = LlmRequest(
      model: advisorLlm.model,
      contents: <Content>[
        Content(role: 'user', parts: <Part>[Part.text(prompt)]),
      ],
      config: requestConfig,
    );

    try {
      return await withModelConsultClientLabel(modelConsultClientLabel, () async {
        final StringBuffer adviceBuffer = StringBuffer();
        final StringBuffer thoughtBuffer = StringBuffer();
        Object? usageMetadata;
        String? errorCode;
        String? errorMessage;

        await for (final LlmResponse response in advisorLlm.generateContent(
          request,
          stream: false,
        )) {
          if (response.errorCode != null || response.errorMessage != null) {
            errorCode = response.errorCode ?? 'MODEL_ERROR';
            errorMessage =
                response.errorMessage ?? 'Advisor model returned an error.';
          }
          if (response.usageMetadata != null) {
            usageMetadata = response.usageMetadata;
          }
          final Content? content = response.content;
          if (content == null) {
            continue;
          }
          for (final Part part in content.parts) {
            if (part.thought) {
              if (part.text != null && part.text!.isNotEmpty) {
                thoughtBuffer.write(part.text);
              }
              continue;
            }
            if (part.text != null && part.text!.isNotEmpty) {
              adviceBuffer.write(part.text);
            }
          }
        }

        if (errorMessage != null && adviceBuffer.isEmpty) {
          return AdvisorError(
            error: errorMessage,
            errorCode: errorCode ?? 'MODEL_ERROR',
            model: advisorLlm.model,
          ).toJson();
        }

        final String advice = adviceBuffer.toString().trim();
        final String thoughts = thoughtBuffer.toString().trim();

        final String sessionKey = sessionUsesStateKey(toolName: name);
        toolContext.state[sessionKey] = sessionUses(toolContext) + 1;

        final String turnKey = turnUsesStateKey(
          toolName: name,
          invocationId: toolContext.invocationId,
        );
        toolContext.state[turnKey] = turnUses(toolContext) + 1;

        return AdvisorResult(
          advice: advice,
          model: advisorLlm.model,
          thoughts: thoughts.isEmpty ? null : thoughts,
          usage: usageMetadata != null
              ? AdvisorUsage.fromUsageMetadata(usageMetadata)
              : null,
        ).toJson();
      });
    } catch (error) {
      return AdvisorError(
        error: 'Advisor consultation failed: $error',
        errorCode: 'EXECUTION_ERROR',
        model: advisorLlm.model,
      ).toJson();
    }
  }

  @override
  String? detectErrorInResponse(Object? response) {
    if (response is Map && response['error'] != null) {
      final Object? code = response['error_code'];
      return code is String && code.isNotEmpty ? code : 'TOOL_ERROR';
    }
    return null;
  }

  String _buildAdvisorPrompt({
    required String question,
    required String? extraContext,
    required ToolContext toolContext,
  }) {
    final StringBuffer buffer = StringBuffer();
    if (contextConfig.includeConversationHistory) {
      final String history = _formatConversationHistory(
        toolContext.session.events,
      );
      if (history.isNotEmpty) {
        buffer.writeln('### Conversation Context');
        buffer.writeln(history);
        buffer.writeln();
      }
    }
    if (extraContext != null && extraContext.isNotEmpty) {
      buffer.writeln('### Additional Context');
      buffer.writeln(extraContext);
      buffer.writeln();
    }
    buffer.writeln('### Question for Advisor');
    buffer.write(question);
    return buffer.toString();
  }

  String _formatConversationHistory(List<Event> events) {
    if (events.isEmpty || contextConfig.maxEvents <= 0) {
      return '';
    }
    final int start = events.length > contextConfig.maxEvents
        ? events.length - contextConfig.maxEvents
        : 0;
    final List<String> lines = <String>[];
    for (int i = start; i < events.length; i += 1) {
      final Event event = events[i];
      final Content? content = event.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }
      final String author = event.author.isNotEmpty
          ? event.author
          : (content.role ?? 'unknown');
      for (final Part part in content.parts) {
        if (part.thought && !contextConfig.includeThoughts) {
          continue;
        }
        if (part.text != null && part.text!.trim().isNotEmpty) {
          final String prefix = part.thought ? '[$author (thought)]' : '[$author]';
          lines.add('$prefix: ${_truncate(part.text!.trim())}');
        } else if (contextConfig.includeToolCalls && part.functionCall != null) {
          final FunctionCall call = part.functionCall!;
          if (call.name == name) {
            continue;
          }
          lines.add(
            '[$author -> tool:${call.name}]: ${_truncate(jsonEncode(call.args))}',
          );
        } else if (contextConfig.includeToolCalls &&
            part.functionResponse != null) {
          final FunctionResponse resp = part.functionResponse!;
          if (resp.name == name) {
            continue;
          }
          lines.add(
            '[tool:${resp.name} -> $author]: ${_truncate(jsonEncode(resp.response))}',
          );
        }
      }
    }
    return lines.join('\n');
  }

  String _truncate(String value) {
    final int limit = contextConfig.maxTurnCharacters;
    if (limit <= 0 || value.length <= limit) {
      return value;
    }
    return '${value.substring(0, limit)}...';
  }
}

/// Alias class for [ModelConsultTool] providing the `ConsultModelTool` name.
///
/// ```dart
/// final tool = ConsultModelTool(model: 'gemini-2.5-pro');
/// ```
class ConsultModelTool extends ModelConsultTool {
  /// Creates a [ConsultModelTool] that queries [model] for advice.
  ConsultModelTool({
    required super.model,
    super.name,
    super.description,
    super.advisorInstruction,
    super.contextConfig,
    super.generateContentConfig,
    super.maxConsultationsPerInvocation,
  });
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
