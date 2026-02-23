import 'dart:convert';

import 'app_details.dart';
import 'common.dart';
import 'eval_case.dart';
import 'eval_result.dart';
import 'eval_rubrics.dart';

enum Label {
  trueLabel('true'),
  invalid('invalid'),
  valid('valid'),
  almost('almost'),
  falseLabel('false'),
  notFound('label field not found');

  const Label(this.value);
  final String value;
}

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

EvalStatus getEvalStatus(double? score, double threshold) {
  if (score == null) {
    return EvalStatus.notEvaluated;
  }
  return score >= threshold ? EvalStatus.passed : EvalStatus.failed;
}

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

String getToolDeclarationsAsJsonStr(AppDetails appDetails) {
  final Map<String, Object?> payload = <String, Object?>{
    'tool_declarations': appDetails.getToolsByAgentName(),
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

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
