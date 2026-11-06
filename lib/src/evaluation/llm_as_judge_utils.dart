/// Shared evaluation models and utility helpers.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../models/llm_request.dart';
import 'app_details.dart';
import 'common.dart';
import 'eval_case.dart';
import 'eval_result.dart';
import 'eval_rubrics.dart';

/// Labels parsed from evaluator outputs.
enum Label {
  /// Affirmative boolean label (`true`).
  trueLabel('true'),

  /// Invalid response or rubric judgment.
  invalid('invalid'),

  /// Valid response or rubric judgment.
  valid('valid'),

  /// Nearly valid response or rubric judgment.
  almost('almost'),

  /// Partially valid response or rubric judgment.
  partiallyValid('partially_valid'),

  /// Negative boolean label (`false`).
  falseLabel('false'),

  /// Fallback when no label field is present in the output.
  notFound('label field not found');

  /// Creates an evaluator output label with its serialized [value].
  const Label(this.value);

  /// Serialized label value.
  final String value;
}

/// Builds a [GenerateContentConfig] for judge LLM calls with automatic function
/// calling disabled while preserving caller settings.
GenerateContentConfig buildJudgeRequestConfig(Object? userConfig) {
  final GenerateContentConfig config = userConfig is GenerateContentConfig
      ? userConfig.copyWith()
      : GenerateContentConfig();
  config.automaticFunctionCalling = AutomaticFunctionCallingConfig(
    disable: true,
  );
  return config;
}

/// Extracts plain text from an evaluation content payload.
String? getTextFromContent(EvalJsonMap? content) {
  if (content == null) {
    return null;
  }
  final List<String> textParts = asObjectList(content['parts'])
      .map((Object? p) {
        return asNullableString(asEvalJson(p)['text']) ?? '';
      })
      .where((String text) => text.isNotEmpty)
      .toList();
  if (textParts.isEmpty) {
    return null;
  }
  return textParts.join('\n');
}

/// Returns pass/fail status for [score] against [threshold].
EvalStatus getEvalStatus(double? score, double threshold) {
  if (score == null) {
    return EvalStatus.notEvaluated;
  }
  return score >= threshold ? EvalStatus.passed : EvalStatus.failed;
}

/// Returns the arithmetic mean score across [rubricScores].
double? getAverageRubricScore(List<RubricScore> rubricScores) {
  final List<double> values = rubricScores
      .map((RubricScore score) => score.score)
      .whereType<double>()
      .toList();
  if (values.isEmpty) {
    return null;
  }
  final double total = values.fold<double>(0.0, (double a, double b) => a + b);
  return total / values.length;
}

/// Serializes app tool declarations into indented JSON.
String getToolDeclarationsAsJsonStr(AppDetails appDetails) {
  final Map<String, List<Object?>> toolsByAgent =
      appDetails.getToolsByAgentName().map(
        (String agent, List<Object?> tools) => MapEntry(
          agent,
          tools
              .map(
                (Object? t) =>
                    t is ToolDeclaration ? serializeToolDeclarationToJson(t) : t,
              )
              .toList(),
        ),
      );
  final Map<String, Object?> payload = <String, Object?>{
    'tool_declarations': toolsByAgent,
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

/// Serializes tool calls and responses from intermediate invocation data.
String getToolCallsAndResponsesAsJsonStr(Object? intermediateData) {
  final List<(EvalJsonMap, EvalJsonMap?)> data = getAllToolCallsWithResponses(
    intermediateData,
  );
  if (data.isEmpty) {
    return 'No intermediate steps were taken.';
  }
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  for (int i = 0; i < data.length; i += 1) {
    final (EvalJsonMap toolCall, EvalJsonMap? toolResponse) = data[i];
    rows.add(<String, Object?>{
      'step': i,
      'tool_call': toolCall,
      'tool_response': toolResponse ?? 'None',
    });
  }
  return const JsonEncoder.withIndent(
    '  ',
  ).convert(<String, Object?>{'tool_calls_and_response': rows});
}

/// Serializes grounding metadata from [intermediateData] into indented JSON.
String getGroundingMetadataAsJsonStr(Object? intermediateData) {
  if (intermediateData is! InvocationEvents) {
    return 'No grounding metadata was provided.';
  }
  final List<Map<String, Object?>> entries = <Map<String, Object?>>[];
  for (int idx = 0; idx < intermediateData.invocationEvents.length; idx += 1) {
    final InvocationEvent event = intermediateData.invocationEvents[idx];
    if (event.groundingMetadata == null || event.groundingMetadata!.isEmpty) {
      continue;
    }
    entries.add(<String, Object?>{
      'step': idx,
      if (event.author.isNotEmpty) 'author': event.author,
      'grounding_metadata': event.groundingMetadata,
    });
  }
  if (entries.isEmpty) {
    return 'No grounding metadata was provided.';
  }
  return const JsonEncoder.withIndent(
    '  ',
  ).convert(<String, Object?>{'grounding_metadata': entries});
}

/// Async semaphore used to bound concurrent judge model requests.
class JudgeEvaluationSemaphore {
  /// Creates a semaphore with [maxConcurrency] permits.
  JudgeEvaluationSemaphore(int maxConcurrency)
    : _maxConcurrency = maxConcurrency < 1 ? 1 : maxConcurrency;

  final int _maxConcurrency;
  int _current = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  /// Runs [action] while holding one permit from this semaphore.
  Future<T> withPermit<T>(Future<T> Function() action) async {
    if (_current >= _maxConcurrency) {
      final Completer<void> waiter = Completer<void>();
      _waiters.addLast(waiter);
      await waiter.future;
    } else {
      _current += 1;
    }
    try {
      return await action();
    } finally {
      if (_waiters.isNotEmpty) {
        final Completer<void> next = _waiters.removeFirst();
        next.complete();
      } else {
        _current -= 1;
      }
    }
  }
}

/// Runs [futures] concurrently, propagating the first error and draining siblings.
Future<List<T>> gatherCancellingOnError<T>(Iterable<Future<T>> futures) async {
  final List<Future<T>> taskList = futures.toList(growable: false);
  if (taskList.isEmpty) {
    return <T>[];
  }
  try {
    return await Future.wait<T>(taskList, eagerError: true);
  } catch (error) {
    for (final Future<T> task in taskList) {
      unawaited(task.then((_) {}, onError: (_) {}));
    }
    rethrow;
  }
}
