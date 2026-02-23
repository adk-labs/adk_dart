import '../sessions/session.dart';
import '../types/content.dart';
import 'base_example_provider.dart';
import 'example.dart';

const String _examplesIntro =
    '<EXAMPLES>\nBegin few-shot\nThe following are examples of user queries '
    'and model responses using the available tools.\n\n';
const String _examplesEnd = 'End few-shot\n<EXAMPLES>';
const String _exampleStart = 'EXAMPLE %d:\nBegin example\n';
const String _exampleEnd = 'End example\n\n';
const String _userPrefix = '[user]\n';
const String _modelPrefix = '[model]\n';
const String _functionPrefix = '```\n';
const String _functionCallPrefix = '```tool_code\n';
const String _functionCallSuffix = '\n```\n';
const String _functionResponsePrefix = '```tool_outputs\n';
const String _functionResponseSuffix = '\n```\n';

String convertExamplesToText(List<Example> examples, String? model) {
  final StringBuffer examplesBuffer = StringBuffer();
  for (int i = 0; i < examples.length; i += 1) {
    final Example example = examples[i];
    final StringBuffer output = StringBuffer();
    output.write(_exampleStart.replaceFirst('%d', '${i + 1}'));
    output.write(_userPrefix);

    if (example.input.parts.isNotEmpty) {
      final String text = example.input.parts
          .where((Part part) => part.text != null && part.text!.isNotEmpty)
          .map((Part part) => part.text!)
          .join('\n');
      if (text.isNotEmpty) {
        output.write('$text\n');
      }
    }

    final bool gemini2 = model == null || model.contains('gemini-2');
    String? previousRole;

    for (final Content content in example.output) {
      final String role = content.role == 'model' ? _modelPrefix : _userPrefix;
      if (previousRole != role) {
        output.write(role);
      }
      previousRole = role;

      for (final Part part in content.parts) {
        final FunctionCall? functionCall = part.functionCall;
        if (functionCall != null) {
          final List<String> args = <String>[];
          functionCall.args.forEach((String key, dynamic value) {
            if (value is String) {
              args.add("$key='${_escapeSingleQuotes(value)}'");
            } else {
              args.add('$key=$value');
            }
          });
          final String prefix = gemini2 ? _functionPrefix : _functionCallPrefix;
          output.write(
            '$prefix${functionCall.name}(${args.join(', ')})'
            '$_functionCallSuffix',
          );
          continue;
        }

        final FunctionResponse? functionResponse = part.functionResponse;
        if (functionResponse != null) {
          final String prefix = gemini2
              ? _functionPrefix
              : _functionResponsePrefix;
          final Map<String, Object?> responsePayload = <String, Object?>{
            if (functionResponse.id != null) 'id': functionResponse.id,
            'name': functionResponse.name,
            'response': Map<String, dynamic>.from(functionResponse.response),
          };
          output.write('$prefix$responsePayload$_functionResponseSuffix');
          continue;
        }

        if (part.text != null) {
          output.write('${part.text}\n');
        }
      }
    }

    output.write(_exampleEnd);
    examplesBuffer.write(output.toString());
  }

  return '$_examplesIntro${examplesBuffer.toString()}$_examplesEnd';
}

String getLatestMessageFromUser(Session session) {
  if (session.events.isEmpty) {
    return '';
  }

  final event = session.events.last;
  if (event.author == 'user' && event.getFunctionResponses().isEmpty) {
    if (event.content != null &&
        event.content!.parts.isNotEmpty &&
        event.content!.parts.first.text != null) {
      return event.content!.parts.first.text!;
    }
  }

  return '';
}

String buildExampleSi(Object examples, String query, String? model) {
  if (examples is List<Example>) {
    return convertExamplesToText(examples, model);
  }
  if (examples is BaseExampleProvider) {
    return convertExamplesToText(examples.getExamples(query), model);
  }

  throw ArgumentError('Invalid example configuration');
}

String _escapeSingleQuotes(String value) {
  return value.replaceAll("'", r"\'");
}
