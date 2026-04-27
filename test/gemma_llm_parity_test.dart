import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('gemma llm parity', () {
    test(
      'moves tool declarations into system instruction and clears tools',
      () async {
        LlmRequest? capturedRequest;
        final GemmaLlm model = GemmaLlm(
          generateHook: (LlmRequest request, bool stream) async* {
            capturedRequest = request;
            yield LlmResponse(content: Content.modelText('plain response'));
          },
        );

        final LlmRequest request = LlmRequest(
          contents: <Content>[Content.userText('Hello')],
          config: GenerateContentConfig(
            systemInstruction: 'Original system instruction',
            tools: <ToolDeclaration>[
              ToolDeclaration(
                functionDeclarations: <FunctionDeclaration>[
                  FunctionDeclaration(
                    name: 'lookup_weather',
                    description: 'Lookup weather data.',
                    parameters: <String, Object?>{
                      'type': 'object',
                      'properties': <String, Object?>{
                        'city': <String, Object?>{'type': 'string'},
                      },
                      'required': <String>['city'],
                    },
                  ),
                ],
              ),
            ],
          ),
        );

        await model.generateContent(request).toList();

        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.config.tools, isEmpty);
        expect(capturedRequest!.config.systemInstruction, isNull);
        expect(capturedRequest!.contents.first.role, 'user');
        expect(
          capturedRequest!.contents.first.parts.first.text,
          contains('You have access to the following functions'),
        );
        expect(
          capturedRequest!.contents.first.parts.first.text,
          contains('Original system instruction'),
        );
        expect(
          capturedRequest!.contents.first.parts.first.text,
          contains(
            '{"name":"lookup_weather","description":"Lookup weather data.","parameters":',
          ),
        );
      },
    );

    test('omits null-like declaration fields from Gemma tool prompt', () async {
      LlmRequest? capturedRequest;
      final GemmaLlm model = GemmaLlm(
        generateHook: (LlmRequest request, bool stream) async* {
          capturedRequest = request;
          yield LlmResponse(content: Content.modelText('plain response'));
        },
      );

      await model
          .generateContent(
            LlmRequest(
              contents: <Content>[Content.userText('Hello')],
              config: GenerateContentConfig(
                tools: <ToolDeclaration>[
                  ToolDeclaration(
                    functionDeclarations: <FunctionDeclaration>[
                      FunctionDeclaration(name: 'no_schema'),
                    ],
                  ),
                ],
              ),
            ),
          )
          .toList();

      final String prompt = capturedRequest!.contents.first.parts.first.text!;
      expect(prompt, contains('{"name":"no_schema"}'));
      expect(prompt, isNot(contains('"description":""')));
      expect(prompt, isNot(contains('"parameters":{}')));
    });

    test('extracts function call JSON from response text', () async {
      final GemmaLlm model = GemmaLlm(
        generateHook: (LlmRequest request, bool stream) async* {
          yield LlmResponse(
            content: Content.modelText(
              '{"name":"lookup_weather","parameters":{"city":"Seoul"}}',
            ),
          );
        },
      );

      final LlmResponse response = await model
          .generateContent(
            LlmRequest(contents: <Content>[Content.userText('hi')]),
          )
          .first;

      final Part firstPart = response.content!.parts.first;
      expect(firstPart.functionCall, isNotNull);
      expect(firstPart.functionCall!.name, 'lookup_weather');
      expect(firstPart.functionCall!.args['city'], 'Seoul');
    });
  });
}
