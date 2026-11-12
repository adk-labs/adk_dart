/// Public CLI entrypoints and interactive HITL helpers exposed for external
/// integrations.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:adk_dart/src/utils/function_call_names.dart';

export 'package:adk_dart/src/utils/function_call_names.dart'
    show requestConfirmationFunctionCallName, requestInputFunctionCallName;
export '../dev/cli.dart' show runAdkCli;

/// Returns `true` when [input] represents an affirmative CLI confirmation.
bool isPositiveCliResponse(String input) {
  switch (input.trim().toLowerCase()) {
    case 'y':
    case 'yes':
    case 'true':
    case 'confirm':
      return true;
    default:
      return false;
  }
}

/// Returns `true` when [schema] accepts only string values (or `null`).
///
/// Text answers for such a schema must be preserved as raw text rather than
/// JSON-decoded so numeric-looking strings (e.g. `"94103"`) and boolean-looking
/// strings (e.g. `"true"`) are not coerced into non-string types.
bool schemaExpectsText(Object? schema) {
  if (schema is! Map) {
    return false;
  }
  final Object? typeValue = schema['type'];
  if (typeValue == 'string') {
    return true;
  }
  if (typeValue is List && typeValue.isNotEmpty) {
    return typeValue.contains('string') &&
        typeValue.every((Object? item) => item == 'string' || item == 'null');
  }
  final Object? options = schema['anyOf'] ?? schema['oneOf'];
  if (options is List && options.isNotEmpty) {
    final Set<Object?> optionTypes = <Object?>{
      for (final Object? option in options)
        option is Map ? option['type'] : null,
    };
    return optionTypes.contains('string') &&
        optionTypes.every((Object? item) => item == 'string' || item == 'null');
  }
  return false;
}

/// Collects pending HITL function calls from [events] whose IDs appear in
/// `event.longRunningToolIds`.
List<({String id, String name, Map<String, Object?> args})>
collectPendingHitlFunctionCalls(List<Event> events) {
  final List<({String id, String name, Map<String, Object?> args})> pending =
      <({String id, String name, Map<String, Object?> args})>[];
  for (final Event event in events) {
    final Set<String>? longRunningIds = event.longRunningToolIds;
    if (longRunningIds == null || longRunningIds.isEmpty) {
      continue;
    }
    final Content? content = event.content;
    if (content == null || content.parts.isEmpty) {
      continue;
    }
    for (final Part part in content.parts) {
      final FunctionCall? fc = part.functionCall;
      if (fc != null && fc.id != null && longRunningIds.contains(fc.id)) {
        pending.add((
          id: fc.id!,
          name: fc.name,
          args: Map<String, Object?>.from(fc.args),
        ));
      }
    }
  }
  return pending;
}

/// Prompts the user for a pending HITL function call and builds the resulting
/// `user` [Content] carrying a [FunctionResponse].
Future<Content> promptForFunctionCall({
  required String functionCallId,
  required String functionName,
  required Map<String, Object?> args,
  required FutureOr<String> Function(String prompt) readLine,
  IOSink? out,
}) async {
  if (functionName == requestInputFunctionCallName) {
    final String message =
        (args['message'] is String && (args['message'] as String).isNotEmpty)
            ? args['message'] as String
            : 'Input requested';
    final Object? schema = args['response_schema'];
    out?.writeln('[HITL input] $message');
    if (schema != null) {
      out?.writeln('  Schema: ${jsonEncode(schema)}');
    }
  } else if (functionName == requestConfirmationFunctionCallName) {
    final Map<String, Object?> toolConfirmation = args['toolConfirmation'] is Map
        ? Map<String, Object?>.from(args['toolConfirmation'] as Map)
        : const <String, Object?>{};
    final String hint = '${toolConfirmation['hint'] ?? ''}';
    final Map<String, Object?> originalFc = args['originalFunctionCall'] is Map
        ? Map<String, Object?>.from(args['originalFunctionCall'] as Map)
        : const <String, Object?>{};
    final String originalName =
        (originalFc['name'] is String &&
                (originalFc['name'] as String).isNotEmpty)
            ? originalFc['name'] as String
            : 'unknown';
    out?.writeln(
      '[HITL confirm] ${hint.isNotEmpty ? hint : 'Confirm $originalName?'}',
    );
    out?.writeln('  Type "yes" to confirm, anything else to reject.');
  } else {
    out?.writeln('[HITL] Waiting for input for $functionName($args)');
  }

  final String userInput = await readLine('[user]: ');

  final Map<String, dynamic> response;
  if (functionName == requestConfirmationFunctionCallName) {
    response = <String, dynamic>{'confirmed': isPositiveCliResponse(userInput)};
  } else if (functionName == requestInputFunctionCallName &&
      schemaExpectsText(args['response_schema'])) {
    response = <String, dynamic>{'result': userInput};
  } else {
    Map<String, dynamic>? parsedResponse;
    try {
      final Object? parsed = jsonDecode(userInput);
      if (parsed is Map) {
        parsedResponse = Map<String, dynamic>.from(parsed);
      } else {
        parsedResponse = <String, dynamic>{'result': parsed};
      }
    } on FormatException {
      parsedResponse = <String, dynamic>{'result': userInput};
    }
    response = parsedResponse;
  }

  return Content(
    role: 'user',
    parts: <Part>[
      Part.fromFunctionResponse(
        id: functionCallId,
        name: functionName,
        response: response,
      ),
    ],
  );
}
