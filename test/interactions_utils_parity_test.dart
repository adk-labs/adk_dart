import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('interactions conversion parity', () {
    test(
      'text parts keep only text fields even when thought metadata exists',
      () {
        final Part part = Part.text(
          'let me think',
          thought: true,
          thoughtSignature: <int>[1, 2, 3],
        );

        final Map<String, Object?>? converted = convertPartToInteractionContent(
          part,
        );
        expect(converted, <String, Object?>{
          'type': 'text',
          'text': 'let me think',
        });
      },
    );

    test('function call arguments do not include streaming-only metadata', () {
      final Part part = Part.fromFunctionCall(
        name: 'lookup_city',
        id: 'call-1',
        args: <String, dynamic>{'city': 'Seoul'},
        partialArgs: <Map<String, Object?>>[
          <String, Object?>{'json_path': r'$.city', 'string_value': 'Seoul'},
        ],
        willContinue: true,
        thoughtSignature: <int>[9, 8, 7],
      );

      final Map<String, Object?>? converted = convertPartToInteractionContent(
        part,
      );
      expect(converted, isNotNull);
      expect(converted!['type'], 'function_call');
      expect(converted['arguments'], <String, Object?>{'city': 'Seoul'});
      expect(converted.containsKey('thought_signature'), isTrue);
    });

    test('function call output without name is skipped', () {
      final Part? part = convertInteractionOutputToPart(<String, Object?>{
        'type': 'function_call',
        'id': 'call-no-name',
        'arguments': <String, Object?>{'x': 1},
      });
      expect(part, isNull);
    });

    test(
      'function call delta without name is ignored during stream mapping',
      () {
        final List<Part> aggregatedParts = <Part>[];
        final LlmResponse? response = convertInteractionEventToLlmResponse(
          <String, Object?>{
            'eventType': 'content.delta',
            'delta': <String, Object?>{
              'type': 'function_call',
              'id': 'call-no-name',
              'arguments': <String, Object?>{'x': 1},
            },
          },
          aggregatedParts,
          interactionId: 'ix-1',
        );

        expect(response, isNull);
        expect(aggregatedParts, isEmpty);
      },
    );
  });
}
