import '../../events/event.dart';
import '../../types/content.dart';
import '../common.dart';
import '../eval_config.dart';
import '../evaluator.dart';

enum Status {
  success('success'),
  turnLimitReached('turn_limit_reached'),
  stopSignalDetected('stop_signal_detected'),
  noMessageGenerated('no_message_generated');

  const Status(this.wireName);
  final String wireName;

  static Status fromWireName(Object? value) {
    final String normalized = (value ?? '').toString().trim().toLowerCase();
    for (final Status status in Status.values) {
      if (status.wireName == normalized) {
        return status;
      }
    }
    return Status.noMessageGenerated;
  }
}

class NextUserMessage {
  NextUserMessage({required this.status, this.userMessage}) {
    final bool success = status == Status.success;
    final bool hasMessage = userMessage != null;
    if (success != hasMessage) {
      throw ArgumentError(
        'A userMessage should be provided if and only if status is SUCCESS.',
      );
    }
  }

  final Status status;
  final Content? userMessage;

  factory NextUserMessage.fromJson(Map<String, Object?> json) {
    final Object? rawUserMessage = json['user_message'] ?? json['userMessage'];
    return NextUserMessage(
      status: Status.fromWireName(json['status']),
      userMessage: rawUserMessage == null
          ? null
          : _contentFromMap(asEvalJson(rawUserMessage)),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireName,
      if (userMessage != null) 'user_message': _contentToMap(userMessage!),
    };
  }
}

typedef UserSimulatorConfigDecoder<T extends BaseUserSimulatorConfig> =
    T Function(BaseUserSimulatorConfig config);

abstract class UserSimulator<T extends BaseUserSimulatorConfig> {
  UserSimulator({
    required BaseUserSimulatorConfig config,
    required UserSimulatorConfigDecoder<T> configDecoder,
  }) : config = configDecoder(config);

  final T config;

  Future<NextUserMessage> getNextUserMessage(List<Event> events);

  Evaluator? getSimulationEvaluator();
}

Content _contentFromMap(EvalJson content) {
  final List<Part> parts = <Part>[];
  for (final Object? rawPart in asObjectList(content['parts'])) {
    final EvalJson part = asEvalJson(rawPart);
    final String? text = asNullableString(part['text']);
    if (text != null) {
      parts.add(Part.text(text, thought: (part['thought'] as bool?) ?? false));
      continue;
    }

    final Object? rawFunctionCall =
        part['functionCall'] ?? part['function_call'];
    if (rawFunctionCall != null) {
      final EvalJson functionCall = asEvalJson(rawFunctionCall);
      parts.add(
        Part.fromFunctionCall(
          name: asNullableString(functionCall['name']) ?? '',
          args: asEvalJson(functionCall['args']).cast<String, dynamic>(),
          id: asNullableString(functionCall['id']),
        ),
      );
      continue;
    }

    final Object? rawFunctionResponse =
        part['functionResponse'] ?? part['function_response'];
    if (rawFunctionResponse != null) {
      final EvalJson functionResponse = asEvalJson(rawFunctionResponse);
      parts.add(
        Part.fromFunctionResponse(
          name: asNullableString(functionResponse['name']) ?? '',
          response: asEvalJson(
            functionResponse['response'],
          ).cast<String, dynamic>(),
          id: asNullableString(functionResponse['id']),
        ),
      );
    }
  }
  return Content(role: asNullableString(content['role']), parts: parts);
}

Map<String, Object?> _contentToMap(Content content) {
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map((Part part) {
      if (part.functionCall != null) {
        return <String, Object?>{
          'function_call': <String, Object?>{
            'name': part.functionCall!.name,
            'args': part.functionCall!.args,
            if (part.functionCall!.id != null) 'id': part.functionCall!.id,
          },
        };
      }
      if (part.functionResponse != null) {
        return <String, Object?>{
          'function_response': <String, Object?>{
            'name': part.functionResponse!.name,
            'response': part.functionResponse!.response,
            if (part.functionResponse!.id != null)
              'id': part.functionResponse!.id,
          },
        };
      }
      return <String, Object?>{
        if (part.text != null) 'text': part.text,
        if (part.thought) 'thought': true,
      };
    }).toList(),
  };
}
