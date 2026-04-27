import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/flows/llm_flows/output_schema_processor.dart'
    as output_schema;
import 'package:test/test.dart';

void main() {
  group('system prompt parity', () {
    test('appendInstructions renders Python-compatible non-text references', () {
      final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');

      final List<Content> userContents = request.appendInstructions(
        Content(
          role: 'user',
          parts: <Part>[
            Part.text('Analyze this image:'),
            Part.fromInlineData(
              mimeType: 'image/png',
              data: <int>[1, 2, 3],
              displayName: 'test_image.png',
            ),
            Part.fromFileData(
              fileUri: 'files/test123',
              mimeType: 'text/plain',
              displayName: 'test_file.txt',
            ),
            Part.text('Focus on the key elements.'),
          ],
        ),
      );

      expect(
        request.config.systemInstruction,
        "Analyze this image:\n\n"
        "[Reference to inline binary data: inline_data_0 ('test_image.png', type: image/png)]\n\n"
        "[Reference to file data: file_data_1 ('test_file.txt', URI: files/test123, type: text/plain)]\n\n"
        "Focus on the key elements.",
      );
      expect(userContents, hasLength(2));
      expect(
        userContents[0].parts[0].text,
        'Referenced inline data: inline_data_0',
      );
      expect(userContents[0].parts[1].inlineData?.data, <int>[1, 2, 3]);
      expect(
        userContents[1].parts[0].text,
        'Referenced file data: file_data_1',
      );
      expect(userContents[1].parts[1].fileData?.fileUri, 'files/test123');
      expect(request.contents, hasLength(2));
    });

    test('getStructuredModelResponse unwraps wrapped tool result', () {
      final Event event = Event(
        invocationId: 'inv',
        author: 'root_agent',
        content: Content(
          role: 'user',
          parts: <Part>[
            Part.fromFunctionResponse(
              name: 'set_model_response',
              response: <String, dynamic>{
                'result': <String, dynamic>{'answer': 'done'},
              },
            ),
          ],
        ),
      );

      expect(
        output_schema.getStructuredModelResponse(event),
        '{"answer":"done"}',
      );
    });
  });
}
