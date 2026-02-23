import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('model name utils parity', () {
    test('extractModelName supports vertex/apigee/models prefixes', () {
      expect(
        extractModelName(
          'projects/p/locations/us/publishers/google/models/gemini-2.5-flash',
        ),
        'gemini-2.5-flash',
      );
      expect(
        extractModelName('apigee/org/env/gemini-2.0-pro'),
        'gemini-2.0-pro',
      );
      expect(extractModelName('models/gemini-2.0-flash'), 'gemini-2.0-flash');
      expect(extractModelName('gemini-2.5-pro'), 'gemini-2.5-pro');
    });

    test('gemini checks mirror python behavior', () {
      expect(isGeminiModel('gemini-2.5-flash'), isTrue);
      expect(isGeminiModel('models/gemini-2.5-flash'), isTrue);
      expect(isGeminiModel('gpt-4.1'), isFalse);

      expect(isGemini1Model('gemini-1.5-pro'), isTrue);
      expect(isGemini1Model('gemini-2.0-flash'), isFalse);

      expect(isGemini2OrAbove('gemini-2.0-flash'), isTrue);
      expect(isGemini2OrAbove('gemini-3-pro-preview'), isTrue);
      expect(isGemini2OrAbove('gemini-1.5-flash'), isFalse);
      expect(isGemini2OrAbove('gemini-preview'), isFalse);
    });

    test('gemini model-id check disable reads env flag', () {
      expect(
        isGeminiModelIdCheckDisabled(
          environment: <String, String>{
            'ADK_DISABLE_GEMINI_MODEL_ID_CHECK': '1',
          },
        ),
        isTrue,
      );
      expect(
        isGeminiModelIdCheckDisabled(
          environment: <String, String>{
            'ADK_DISABLE_GEMINI_MODEL_ID_CHECK': 'false',
          },
        ),
        isFalse,
      );
    });
  });
}
