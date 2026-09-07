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

    test('function response result map is not pre-serialized', () {
      final Part part = Part.fromFunctionResponse(
        name: 'lookup',
        id: 'call-1',
        response: <String, dynamic>{
          'result': <String, Object?>{
            'ok': true,
            'items': <Object?>[1, 2],
          },
        },
      );

      final Map<String, Object?>? converted = convertPartToInteractionContent(
        part,
      );

      expect(converted, isNotNull);
      expect(converted!['type'], 'function_result');
      expect(converted['result'], <String, Object?>{
        'result': <String, Object?>{
          'ok': true,
          'items': <Object?>[1, 2],
        },
      });
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

  group('buildGenerationConfig parity', () {
    setUp(() {
      resetWarnedSamplingParamsForTest();
      interactionsLogHandlerForTest = null;
    });

    tearDown(() {
      resetWarnedSamplingParamsForTest();
      interactionsLogHandlerForTest = null;
    });

    test('only parameters that reach interactions API are kept', () {
      final GenerateContentConfig config = GenerateContentConfig(
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        maxOutputTokens: 100,
        stopSequences: <String>['END'],
        presencePenalty: 0.5,
        frequencyPenalty: 0.3,
        seed: 7,
      );

      final Map<String, Object?> result = buildGenerationConfig(config);
      expect(result, <String, Object?>{
        'max_output_tokens': 100,
        'stop_sequences': <String>['END'],
        'seed': 7,
      });
    });

    test('empty config returns empty map', () {
      final GenerateContentConfig config = GenerateContentConfig();
      final Map<String, Object?> result = buildGenerationConfig(config);
      expect(result, isEmpty);
    });

    test('undeclared parameters point at client library', () {
      final List<String> warnings = <String>[];
      interactionsLogHandlerForTest = (String message, {int? level, String? name}) {
        warnings.add(message);
      };

      final GenerateContentConfig config = GenerateContentConfig(
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
      );
      buildGenerationConfig(config);

      expect(warnings, hasLength(1));
      expect(warnings.first, contains('temperature'));
      expect(warnings.first, contains('top_p'));
      expect(warnings.first, contains('top_k'));
      expect(warnings.first, contains('google-genai'));
      expect(warnings.first, isNot(contains('use_interactions_api')));
    });

    test('unsupported parameters point at interactions api', () {
      final List<String> warnings = <String>[];
      interactionsLogHandlerForTest = (String message, {int? level, String? name}) {
        warnings.add(message);
      };

      final GenerateContentConfig config = GenerateContentConfig(
        presencePenalty: 0.5,
        frequencyPenalty: 0.3,
      );
      buildGenerationConfig(config);

      expect(warnings, hasLength(1));
      expect(warnings.first, contains('presence_penalty'));
      expect(warnings.first, contains('frequency_penalty'));
      expect(warnings.first, contains('use_interactions_api'));
    });

    test('the two causes are reported separately', () {
      final List<String> warnings = <String>[];
      interactionsLogHandlerForTest = (String message, {int? level, String? name}) {
        warnings.add(message);
      };

      final GenerateContentConfig config = GenerateContentConfig(
        temperature: 0.7,
        presencePenalty: 0.5,
      );
      buildGenerationConfig(config);

      expect(warnings, hasLength(2));
      final String client = warnings.firstWhere(
        (String w) => !w.contains('use_interactions_api'),
      );
      final String api = warnings.firstWhere(
        (String w) => w.contains('use_interactions_api'),
      );
      expect(client, contains('temperature'));
      expect(client, isNot(contains('presence_penalty')));
      expect(api, contains('presence_penalty'));
      expect(api, isNot(contains('temperature')));
    });

    test('dropped parameters are logged once', () {
      final List<String> warnings = <String>[];
      interactionsLogHandlerForTest = (String message, {int? level, String? name}) {
        warnings.add(message);
      };

      final GenerateContentConfig config = GenerateContentConfig(
        temperature: 0.7,
      );
      buildGenerationConfig(config);
      buildGenerationConfig(config);

      expect(warnings, hasLength(1));
    });

    test('supported parameters only do not warn', () {
      final List<String> warnings = <String>[];
      interactionsLogHandlerForTest = (String message, {int? level, String? name}) {
        warnings.add(message);
      };

      final GenerateContentConfig config = GenerateContentConfig(
        maxOutputTokens: 100,
        stopSequences: <String>['END'],
        seed: 7,
      );
      buildGenerationConfig(config);

      expect(warnings, isEmpty);
    });
  });

  group('interleaved function call streaming by step index', () {
    test('interleave argument deltas: routes by step index', () {
      final InteractionsStreamState state = InteractionsStreamState();

      // Start step 0: get_weather
      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.start',
          'index': 0,
          'step': <String, Object?>{
            'type': 'function_call',
            'id': 'call_0',
            'name': 'get_weather',
            'arguments': <String, Object?>{},
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      // Start step 1: get_time
      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.start',
          'index': 1,
          'step': <String, Object?>{
            'type': 'function_call',
            'id': 'call_1',
            'name': 'get_time',
            'arguments': <String, Object?>{},
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      // Interleave argument deltas: index 0 first, then index 1
      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.delta',
          'index': 0,
          'delta': <String, Object?>{
            'type': 'arguments_delta',
            'arguments': '{"city": "Paris"}',
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.delta',
          'index': 1,
          'delta': <String, Object?>{
            'type': 'arguments_delta',
            'arguments': '{"zone": "UTC"}',
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      // Stop both steps
      for (final int idx in <int>[0, 1]) {
        convertInteractionEventToLlmResponse(
          <String, Object?>{
            'event_type': 'step.stop',
            'index': idx,
          },
          state.parts,
          streamState: state,
          interactionId: 'int_multi',
        );
      }

      expect(state.parts[0].functionCall!.name, 'get_weather');
      expect(state.parts[0].functionCall!.args, <String, Object?>{'city': 'Paris'});
      expect(state.parts[1].functionCall!.name, 'get_time');
      expect(state.parts[1].functionCall!.args, <String, Object?>{'zone': 'UTC'});
    });

    test('step.stop with unmatched index does not finalize active function call', () {
      final InteractionsStreamState state = InteractionsStreamState();

      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.start',
          'index': 0,
          'step': <String, Object?>{
            'type': 'function_call',
            'id': 'call_0',
            'name': 'get_weather',
            'arguments': <String, Object?>{},
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.delta',
          'index': 0,
          'delta': <String, Object?>{
            'type': 'arguments_delta',
            'arguments': '{"city": ',
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      // StepStop for an unrelated step (index 1). Must not finalize step 0's call.
      final LlmResponse? res = convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.stop',
          'index': 1,
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );
      expect(res, isNull);

      // Step 0 receives rest of args and stops cleanly
      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.delta',
          'index': 0,
          'delta': <String, Object?>{
            'type': 'arguments_delta',
            'arguments': '"Paris"}',
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.stop',
          'index': 0,
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      expect(state.parts[0].functionCall!.name, 'get_weather');
      expect(state.parts[0].functionCall!.args, <String, Object?>{'city': 'Paris'});
    });

    test('arguments delta with unmatched index does not alter active function call', () {
      final InteractionsStreamState state = InteractionsStreamState();

      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.start',
          'index': 0,
          'step': <String, Object?>{
            'type': 'function_call',
            'id': 'call_0',
            'name': 'get_weather',
            'arguments': <String, Object?>{},
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.delta',
          'index': 0,
          'delta': <String, Object?>{
            'type': 'arguments_delta',
            'arguments': '{"city": ',
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      // ArgumentsDelta for unrelated step index 1. Must return null.
      final LlmResponse? res = convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.delta',
          'index': 1,
          'delta': <String, Object?>{
            'type': 'arguments_delta',
            'arguments': '{"extra": 1}',
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );
      expect(res, isNull);

      // Step 0 finishes cleanly
      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.delta',
          'index': 0,
          'delta': <String, Object?>{
            'type': 'arguments_delta',
            'arguments': '"Paris"}',
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );
      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.stop',
          'index': 0,
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      expect(state.parts[0].functionCall!.name, 'get_weather');
      expect(state.parts[0].functionCall!.args, <String, Object?>{'city': 'Paris'});
    });

    test('arguments delta for finalized call returns null', () {
      final InteractionsStreamState state = InteractionsStreamState();

      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.start',
          'index': 0,
          'step': <String, Object?>{
            'type': 'function_call',
            'id': 'call_0',
            'name': 'get_weather',
            'arguments': <String, Object?>{},
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.delta',
          'index': 0,
          'delta': <String, Object?>{
            'type': 'arguments_delta',
            'arguments': '{"city": "Paris"}',
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.stop',
          'index': 0,
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );

      expect(state.parts[0].functionCall!.partialArgs, isNull);
      expect(state.parts[0].functionCall!.args, <String, Object?>{'city': 'Paris'});

      // Routine delta with null arguments is a no-op
      final LlmResponse? resNull = convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.delta',
          'index': 0,
          'delta': <String, Object?>{
            'type': 'arguments_delta',
            'arguments': null,
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );
      expect(resNull, isNull);

      // Late arguments delta for finalized call returns null
      final LlmResponse? resLate = convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'step.delta',
          'index': 0,
          'delta': <String, Object?>{
            'type': 'arguments_delta',
            'arguments': '{"extra": 1}',
          },
        },
        state.parts,
        streamState: state,
        interactionId: 'int_multi',
      );
      expect(resLate, isNull);
      expect(state.parts[0].functionCall!.args, <String, Object?>{'city': 'Paris'});
    });
  });
}
