import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeLlm extends BaseLlm {
  _FakeLlm(String model) : super(model: model);

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

void main() {
  group('content/variant/output schema utils parity', () {
    test('audio part detection and filtering', () {
      final Part text = Part.text('hello');
      final Part audioInline = Part(
        inlineData: InlineData(mimeType: 'audio/wav', data: <int>[1]),
      );
      final Part audioFile = Part(
        fileData: FileData(fileUri: 'gs://a.wav', mimeType: 'audio/mpeg'),
      );

      expect(isAudioPart(text), isFalse);
      expect(isAudioPart(audioInline), isTrue);
      expect(isAudioPart(audioFile), isTrue);

      final Content mixed = Content(
        role: 'user',
        parts: <Part>[audioInline, text, audioFile],
      );
      final Content? filtered = filterAudioParts(mixed);
      expect(filtered, isNotNull);
      expect(filtered!.parts, hasLength(1));
      expect(filtered.parts.single.text, 'hello');

      final Content onlyAudio = Content(
        role: 'user',
        parts: <Part>[audioInline],
      );
      expect(filterAudioParts(onlyAudio), isNull);
    });

    test('variant and output schema compatibility checks', () {
      expect(
        getGoogleLlmVariant(
          environment: <String, String>{'GOOGLE_GENAI_USE_VERTEXAI': '1'},
        ),
        GoogleLLMVariant.vertexAi,
      );
      expect(
        getGoogleLlmVariant(environment: <String, String>{}),
        GoogleLLMVariant.geminiApi,
      );

      expect(
        canUseOutputSchemaWithTools(
          'gemini-2.5-flash',
          environment: <String, String>{'GOOGLE_GENAI_USE_VERTEXAI': 'true'},
        ),
        isTrue,
      );
      expect(
        canUseOutputSchemaWithTools(
          'gemini-1.5-flash',
          environment: <String, String>{'GOOGLE_GENAI_USE_VERTEXAI': 'true'},
        ),
        isFalse,
      );
      expect(
        canUseOutputSchemaWithTools(
          _FakeLlm('gemini-2.0-pro'),
          environment: <String, String>{'GOOGLE_GENAI_USE_VERTEXAI': 'true'},
        ),
        isTrue,
      );
      expect(
        canUseOutputSchemaWithTools(
          _FakeLlm('gemini-2.0-pro'),
          environment: <String, String>{},
        ),
        isFalse,
      );
    });
  });
}
