import '../../events/event.dart';
import '../../types/content.dart';
import '../eval_case.dart';
import '../eval_config.dart';
import '../evaluator.dart';
import 'user_simulator.dart';

typedef StaticConversation = List<Invocation>;

class StaticUserSimulator extends UserSimulator<BaseUserSimulatorConfig> {
  StaticUserSimulator({required this.staticConversation})
    : _invocationIdx = 0,
      super(
        config: BaseUserSimulatorConfig(),
        configDecoder: (BaseUserSimulatorConfig config) => config,
      );

  final StaticConversation staticConversation;
  int _invocationIdx;

  @override
  Future<NextUserMessage> getNextUserMessage(List<Event> events) async {
    if (_invocationIdx >= staticConversation.length) {
      return NextUserMessage(status: Status.stopSignalDetected);
    }
    final Invocation invocation = staticConversation[_invocationIdx];
    _invocationIdx += 1;
    return NextUserMessage(
      status: Status.success,
      userMessage: _contentFromEvalJson(invocation.userContent),
    );
  }

  @override
  Evaluator? getSimulationEvaluator() => null;
}

Content _contentFromEvalJson(Map<String, Object?> content) {
  final List<Part> parts = <Part>[];
  if (content['parts'] is List) {
    for (final Object? rawPart in content['parts']! as List<Object?>) {
      if (rawPart is! Map) {
        continue;
      }
      final Map<String, Object?> part = rawPart.map(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>(key.toString(), value),
      );
      final String? text = part['text'] as String?;
      if (text != null) {
        parts.add(
          Part.text(text, thought: (part['thought'] as bool?) ?? false),
        );
        continue;
      }
      final Object? rawFunctionCall =
          part['function_call'] ?? part['functionCall'];
      if (rawFunctionCall is Map) {
        final Map<String, Object?> functionCall = rawFunctionCall.map(
          (Object? key, Object? value) =>
              MapEntry<String, Object?>(key.toString(), value),
        );
        parts.add(
          Part.fromFunctionCall(
            name: (functionCall['name'] ?? '').toString(),
            args: (functionCall['args'] is Map)
                ? (functionCall['args'] as Map).cast<String, dynamic>()
                : <String, dynamic>{},
            id: functionCall['id']?.toString(),
          ),
        );
      }
    }
  }
  return Content(role: content['role'] as String?, parts: parts);
}
