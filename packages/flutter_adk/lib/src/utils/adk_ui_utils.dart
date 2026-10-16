import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:adk_dart/adk_dart.dart' as core;

import '../models/adk_token_usage_model.dart';
import '../models/adk_tool_call_info.dart';
import '../widgets/adk_workflow_graph_view.dart';

/// Formatting and string presentation utilities for ADK Flutter applications.
class AdkFormatters {
  const AdkFormatters._();

  /// Formats raw token count into human-readable representation.
  ///
  /// Examples:
  /// - `1200` -> `'1,200 tokens'` (or `'1.2k'` if [compact] is true)
  /// - `1250000` -> `'1.25M tokens'`
  static String formatTokens(int tokens, {bool compact = false}) {
    if (tokens < 1000) {
      return compact ? '$tokens' : '$tokens tokens';
    }
    if (tokens < 1000000) {
      final double k = tokens / 1000.0;
      final String val = k.toStringAsFixed(k >= 10 ? 0 : 1);
      return compact ? '${val}k' : '${val}k tokens';
    }
    final double m = tokens / 1000000.0;
    final String val = m.toStringAsFixed(1);
    return compact ? '${val}M' : '${val}M tokens';
  }

  /// Formats a [Duration] into clean human-readable latency.
  ///
  /// Examples:
  /// - `Duration(milliseconds: 145)` -> `'145ms'`
  /// - `Duration(milliseconds: 2340)` -> `'2.34s'`
  /// - `Duration(minutes: 2, seconds: 15)` -> `'2m 15s'`
  static String formatDuration(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds}ms';
    }
    if (duration.inSeconds < 60) {
      final double sec = duration.inMilliseconds / 1000.0;
      return '${sec.toStringAsFixed(2)}s';
    }
    final int minutes = duration.inMinutes;
    final int remainingSec = duration.inSeconds % 60;
    return '${minutes}m ${remainingSec}s';
  }

  /// Formats byte count into human-readable size string.
  ///
  /// Examples:
  /// - `512` -> `'512 B'`
  /// - `1024 * 320` -> `'320 KB'`
  /// - `1024 * 1024 * 4` -> `'4.0 MB'`
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Safely formats JSON or map data with 2-space indentation.
  static String formatJson(Object? data) {
    if (data == null) return '';
    try {
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    } catch (_) {
      return data.toString();
    }
  }
}

/// Helper utilities for extracting UI models and state from ADK event streams.
class AdkEventStreamUtils {
  const AdkEventStreamUtils._();

  /// Scans [events] and returns all open, unresolved long-running tool interrupts.
  ///
  /// Delegates to `core.indexOpenInterrupts(events)`.
  static Map<String, core.OpenInterrupt> extractOpenInterrupts(List<core.Event> events) {
    return core.indexOpenInterrupts(events);
  }

  /// Whether [events] currently contains at least one open, unanswered interrupt.
  static bool hasOpenInterrupts(List<core.Event> events) {
    return extractOpenInterrupts(events).isNotEmpty;
  }

  /// Extracts [AdkToolCallInfo] objects from a single ADK [event].
  static List<AdkToolCallInfo> extractToolCalls(core.Event event) {
    final core.Content? content = event.content;
    if (content == null || content.parts.isEmpty) {
      return const <AdkToolCallInfo>[];
    }

    final List<AdkToolCallInfo> result = <AdkToolCallInfo>[];
    for (final core.Part part in content.parts) {
      final core.FunctionCall? call = part.functionCall;
      if (call != null) {
        result.add(
          AdkToolCallInfo(
            toolName: call.name,
            callId: call.id,
            arguments: call.args.cast<String, dynamic>(),
            startTime: DateTime.fromMillisecondsSinceEpoch(
              (event.timestamp * 1000).toInt(),
            ),
          ),
        );
      }
    }
    return result;
  }

  /// Extracts an [AdkTokenUsage] object from an [event] if token metrics are present.
  static AdkTokenUsage? extractTokenUsage(core.Event event) {
    final Object? rawUsage = event.usageMetadata;
    if (rawUsage == null) {
      return null;
    }

    if (rawUsage is Map) {
      final int prompt = (rawUsage['prompt_token_count'] as num?)?.toInt() ??
          (rawUsage['promptTokenCount'] as num?)?.toInt() ??
          0;
      final int completion = (rawUsage['candidates_token_count'] as num?)?.toInt() ??
          (rawUsage['candidatesTokenCount'] as num?)?.toInt() ??
          (rawUsage['completion_tokens'] as num?)?.toInt() ??
          0;
      final int total = (rawUsage['total_token_count'] as num?)?.toInt() ??
          (rawUsage['totalTokenCount'] as num?)?.toInt() ??
          (prompt + completion);
      final int thought = (rawUsage['thought_tokens'] as num?)?.toInt() ??
          (rawUsage['thoughtTokens'] as num?)?.toInt() ??
          0;
      return AdkTokenUsage(
        promptTokens: prompt,
        completionTokens: completion,
        totalTokens: total,
        thoughtTokens: thought,
      );
    }

    try {
      final dynamic d = rawUsage;
      final int prompt = (d.promptTokenCount as num?)?.toInt() ??
          (d.prompt_token_count as num?)?.toInt() ??
          0;
      final int completion = (d.candidatesTokenCount as num?)?.toInt() ??
          (d.candidates_token_count as num?)?.toInt() ??
          0;
      final int total = (d.totalTokenCount as num?)?.toInt() ??
          (d.total_token_count as num?)?.toInt() ??
          (prompt + completion);
      return AdkTokenUsage(
        promptTokens: prompt,
        completionTokens: completion,
        totalTokens: total,
      );
    } catch (_) {
      return null;
    }
  }

  /// Whether [event] indicates an advisor model consultation was performed
  /// via `ModelConsultTool` or `ForceEscalationPlugin`.
  static bool isModelConsultEvent(core.Event event) {
    final core.Content? content = event.content;
    if (content != null) {
      for (final core.Part part in content.parts) {
        final String? name = part.functionCall?.name ?? part.functionResponse?.name;
        if (name == 'consult_model' || name == 'model_consult') {
          return true;
        }
      }
    }
    return event.customMetadata?['model_consult'] == true ||
        event.customMetadata?['escalated'] == true;
  }

  /// Extracts model consultation metadata from an [event].
  static ({
    String? advisorModel,
    String? escalationReason,
    int? turnCount,
    int? turnBudget,
  }) extractModelConsultInfo(core.Event event) {
    final Map<String, dynamic>? meta = event.customMetadata?.cast<String, dynamic>();

    String? advisor = meta?['advisor_model'] as String?;
    String? reason = meta?['escalation_reason'] as String?;
    int? turn = meta?['turn_count'] as int?;
    int? budget = meta?['turn_budget'] as int?;

    if (advisor == null && event.content != null) {
      for (final core.Part part in event.content!.parts) {
        final core.FunctionCall? call = part.functionCall;
        if (call != null && (call.name == 'consult_model' || call.name == 'model_consult')) {
          advisor ??= call.args['model'] as String? ?? call.args['advisor_model'] as String?;
          reason ??= call.args['reason'] as String?;
          break;
        }
      }
    }

    return (
      advisorModel: advisor,
      escalationReason: reason,
      turnCount: turn,
      turnBudget: budget,
    );
  }
}

/// Color resolution helpers for statuses, confidence scores, and node lifecycles.
class AdkColorUtils {
  const AdkColorUtils._();

  /// Resolves an appropriate status color based on classification or model confidence.
  static Color confidenceColor(BuildContext context, double confidence) {
    if (confidence >= 0.8) return Colors.green.shade600;
    if (confidence >= 0.5) return Colors.orange.shade700;
    return Theme.of(context).colorScheme.error;
  }

  /// Resolves theme-friendly status colors for workflow graph nodes.
  static Color nodeStatusColor(BuildContext context, AdkGraphNodeStatus status) {
    final ThemeData theme = Theme.of(context);
    switch (status) {
      case AdkGraphNodeStatus.completed:
        return Colors.green.shade600;
      case AdkGraphNodeStatus.running:
        return theme.colorScheme.primary;
      case AdkGraphNodeStatus.failed:
        return theme.colorScheme.error;
      case AdkGraphNodeStatus.skipped:
        return theme.colorScheme.outline;
      case AdkGraphNodeStatus.pending:
        return theme.colorScheme.outlineVariant;
    }
  }
}
