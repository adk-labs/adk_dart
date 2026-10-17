import 'dart:async';
import 'dart:typed_data';

import 'package:adk_dart/adk_dart.dart' as adk;
import 'package:adk_litertlm/adk_litertlm.dart';
import 'package:adk_litertlm/src/active_litert_conversation.dart';
import 'package:litertlm/litertlm.dart' as litert;
import 'package:test/test.dart';

void main() {
  group('LiteRtLmModel Tests', () {
    late FakeEngine fakeEngine;

    setUp(() {
      fakeEngine = FakeEngine(
        engineConfig: const litert.EngineConfig(modelPath: 'test_model.litertlm'),
      );
    });

    test('generateContent stream = false returns response and disposes', () async {
      final model = LiteRtLmModel(fakeEngine, model: 'test-model');

      final request = adk.LlmRequest(
        contents: [adk.Content.userText('Hello')],
      );

      final fakeConv = FakeConversation();
      fakeConv.sendMessageHandler = (msg) {
        return litert.Message.modelText('Expected response text');
      };
      fakeEngine.nextConversation = fakeConv;

      final responses = await model.generateContent(request, stream: false).toList();

      expect(responses.length, equals(1));
      expect(responses[0].content?.parts[0].text, equals('Expected response text'));
      expect(fakeConv.disposeCallCount, equals(0));

      await model.close();
      expect(fakeConv.disposeCallCount, equals(1));
    });

    test('generateContent stream = true emits streaming responses', () async {
      final model = LiteRtLmModel(fakeEngine, model: 'test-model');

      final request = adk.LlmRequest(
        contents: [adk.Content.userText('Hi')],
      );

      final fakeConv = FakeConversation();
      fakeConv.sendMessageStreamHandler = (msg) {
        return Stream.fromIterable([
          litert.Message.modelText('Hello'),
          litert.Message.modelText(' world'),
        ]);
      };
      fakeEngine.nextConversation = fakeConv;

      final responses = await model.generateContent(request, stream: true).toList();

      expect(responses.length, equals(3));
      expect(responses[0].content?.parts[0].text, equals('Hello'));
      expect(responses[0].partial, isTrue);

      expect(responses[1].content?.parts[0].text, equals(' world'));
      expect(responses[1].partial, isTrue);

      expect(responses[2].content?.parts[0].text, equals('Hello world'));
      expect(responses[2].partial, isFalse);

      await model.close();
      expect(fakeConv.disposeCallCount, equals(1));
    });

    test('generateContent reuses conversation on cache hit', () async {
      final model = LiteRtLmModel(fakeEngine, model: 'test-model');

      final fakeConv = FakeConversation();
      var sendCount = 0;
      fakeConv.sendMessageHandler = (msg) {
        sendCount++;
        return litert.Message.modelText('Response $sendCount');
      };
      fakeEngine.nextConversation = fakeConv;

      // Turn 1
      final request1 = adk.LlmRequest(
        contents: [adk.Content.userText('Turn 1 request')],
      );
      final responses1 = await model.generateContent(request1, stream: false).toList();
      expect(responses1[0].content?.parts[0].text, equals('Response 1'));

      // Turn 2 (cache hit)
      final request2 = adk.LlmRequest(
        contents: [
          adk.Content.userText('Turn 1 request'),
          adk.Content.modelText('Response 1'),
          adk.Content.userText('Turn 2 request'),
        ],
      );
      final responses2 = await model.generateContent(request2, stream: false).toList();
      expect(responses2[0].content?.parts[0].text, equals('Response 2'));

      expect(fakeEngine.createConversationCallCount, equals(1));
      expect(fakeConv.sendMessageCallCount, equals(2));

      await model.close();
      expect(fakeConv.disposeCallCount, equals(1));
    });

    test('generateContent disposes and recreates conversation on cache miss', () async {
      final model = LiteRtLmModel(fakeEngine, model: 'test-model');

      final fakeConv1 = FakeConversation();
      fakeConv1.sendMessageHandler = (msg) => litert.Message.modelText('Response 1');

      final fakeConv2 = FakeConversation();
      fakeConv2.sendMessageHandler = (msg) => litert.Message.modelText('Response 2');

      fakeEngine.conversationsToReturn = [fakeConv1, fakeConv2];

      // Turn 1
      final request1 = adk.LlmRequest(
        contents: [adk.Content.userText('Turn 1 request')],
      );
      final responses1 = await model.generateContent(request1, stream: false).toList();
      expect(responses1[0].content?.parts[0].text, equals('Response 1'));

      // Turn 2 (cache miss - different turn 1 request)
      final request2 = adk.LlmRequest(
        contents: [
          adk.Content.userText('Different turn 1 request'),
          adk.Content.modelText('Response 1'),
          adk.Content.userText('Turn 2 request'),
        ],
      );
      final responses2 = await model.generateContent(request2, stream: false).toList();
      expect(responses2[0].content?.parts[0].text, equals('Response 2'));

      expect(fakeEngine.createConversationCallCount, equals(2));
      expect(fakeConv1.disposeCallCount, equals(1));
      expect(fakeConv2.disposeCallCount, equals(0));

      await model.close();
      expect(fakeConv2.disposeCallCount, equals(1));
    });

    test('generateContent with function response part maps to TOOL role', () async {
      final model = LiteRtLmModel(fakeEngine, model: 'test-model');

      final fakeConv = FakeConversation();
      litert.Message? lastSentMessage;
      fakeConv.sendMessageHandler = (msg) {
        lastSentMessage = msg;
        return litert.Message.modelText('Response text');
      };
      fakeEngine.nextConversation = fakeConv;

      final request = adk.LlmRequest(
        contents: [
          adk.Content(
            role: 'user',
            parts: [
              adk.Part(
                functionResponse: adk.FunctionResponse(
                  name: 'test_func',
                  response: {'result': 'success'},
                ),
              ),
            ],
          ),
        ],
      );

      await model.generateContent(request, stream: false).toList();

      expect(lastSentMessage, isNotNull);
      expect(lastSentMessage!.role, equals(litert.Role.tool));

      await model.close();
    });

    test('generateContent error handling in unary and stream modes', () async {
      final model = LiteRtLmModel(fakeEngine, ownsEngine: true, model: 'test-model');

      // Empty contents error
      final emptyReq = adk.LlmRequest(contents: []);
      final emptyRes = await model.generateContent(emptyReq, stream: false).toList();
      expect(emptyRes.first.errorMessage, contains('Empty request contents'));

      final emptyStreamRes = await model.generateContent(emptyReq, stream: true).toList();
      expect(emptyStreamRes.first.errorMessage, contains('Empty request contents'));

      // Stream error during sendMessageStream
      final fakeConv = FakeConversation();
      fakeConv.sendMessageStreamHandler = (msg) {
        throw StateError('Stream failure');
      };
      fakeEngine.nextConversation = fakeConv;

      final req = adk.LlmRequest(contents: [adk.Content.userText('Hello')]);
      final streamErrors = await model.generateContent(req, stream: true).toList();
      expect(streamErrors.first.errorMessage, contains('Stream failure'));

      // Unary error during sendMessage
      final fakeConvUnary = FakeConversation();
      fakeConvUnary.sendMessageHandler = (msg) {
        throw StateError('Unary failure');
      };
      fakeEngine.nextConversation = fakeConvUnary;
      final unaryErrors = await model.generateContent(req, stream: false).toList();
      expect(unaryErrors.first.errorMessage, contains('Unary failure'));

      await model.dispose();
      expect(fakeEngine.isInitialized, isFalse);
    });

    test('tools, system instructions, and manual tool execution', () async {
      final model = LiteRtLmModel(fakeEngine, model: 'test-model');
      final fakeConv = FakeConversation();
      fakeEngine.nextConversation = fakeConv;

      final toolDecl = adk.ToolDeclaration(
        functionDeclarations: [
          adk.FunctionDeclaration(
            name: 'calc',
            description: 'Calculator',
            parameters: {'type': 'object'},
          ),
        ],
      );

      final manualTool = ManualLiteRtLmTool(toolDecl.functionDeclarations.first);
      final desc = manualTool.getToolDescription();
      expect(desc['type'], equals('function'));
      expect((desc['function'] as Map)['name'], equals('calc'));
      expect(() => manualTool.execute({}), throwsUnsupportedError);

      final req = adk.LlmRequest(
        contents: [adk.Content.userText('Calculate 2+2')],
        config: adk.GenerateContentConfig(
          systemInstruction: 'Be helpful.',
          tools: [toolDecl],
        ),
      );

      await model.generateContent(req, stream: false).toList();
      expect(fakeEngine.lastConfig?.tools.length, equals(1));
      expect(fakeEngine.lastConfig?.systemMessage, isNotNull);

      await model.close();
    });

    test('message mapping across roles, tool calls, and multimodal parts', () async {
      final model = LiteRtLmModel(fakeEngine, model: 'test-model');
      final fakeConv = FakeConversation();
      fakeEngine.nextConversation = fakeConv;

      final req = adk.LlmRequest(
        contents: [
          adk.Content(role: 'system', parts: [adk.Part.text('Sys')]),
          adk.Content(role: 'tool', parts: [adk.Part.text('Tool output')]),
          adk.Content(
            role: 'model',
            parts: [
              adk.Part(
                functionCall: adk.FunctionCall(name: 'search', args: {'q': 'dart'}),
              ),
            ],
          ),
          adk.Content(
            role: 'user',
            parts: [
              adk.Part(
                inlineData: adk.InlineData(mimeType: 'image/png', data: [1, 2, 3]),
              ),
              adk.Part(
                inlineData: adk.InlineData(mimeType: 'audio/wav', data: [4, 5, 6]),
              ),
              adk.Part(
                fileData: adk.FileData(mimeType: 'image/jpeg', fileUri: '/tmp/pic.jpg'),
              ),
              adk.Part(
                fileData: adk.FileData(mimeType: 'audio/mp3', fileUri: '/tmp/sound.mp3'),
              ),
              adk.Part(
                functionResponse: adk.FunctionResponse(name: 'fn', response: {'ok': true}),
              ),
            ],
          ),
          adk.Content(role: 'custom', parts: [adk.Part.text('Fallback to user')]),
        ],
      );

      fakeConv.sendMessageStreamHandler = (msg) {
        return Stream.value(
          litert.Message(
            role: litert.Role.model,
            contents: litert.Contents([
              const litert.TextContent('Result: '),
              litert.ImageBytesContent(Uint8List.fromList([1])),
              const litert.ImageFileContent('/img.png'),
              litert.AudioBytesContent(Uint8List.fromList([2])),
              const litert.AudioFileContent('/audio.wav'),
              const litert.ToolResponseContent(name: 'fn', response: {'res': 1}),
            ]),
            toolCalls: [
              const litert.ToolCall(name: 'done', arguments: {'status': 200}),
            ],
          ),
        );
      };

      final responses = await model.generateContent(req, stream: true).toList();
      expect(responses.length, equals(2));
      final finalRes = responses.last;
      expect(finalRes.content?.parts.any((p) => p.functionCall?.name == 'done'), isTrue);

      await model.close();
    });

    test('active conversation equality matching branches', () {
      final active = ActiveLiteRtLmConversation();
      final fakeConv = FakeConversation();

      final c1 = [
        adk.Content(
          role: 'user',
          parts: [
            adk.Part(
              functionCall: adk.FunctionCall(name: 'f1', args: {'a': 1}),
            ),
            adk.Part(
              functionResponse: adk.FunctionResponse(name: 'r1', response: {'b': 2}),
            ),
            adk.Part(
              inlineData: adk.InlineData(mimeType: 'image/png', data: [1, 2]),
            ),
            adk.Part(
              fileData: adk.FileData(mimeType: 'image/jpeg', fileUri: 'file://img'),
            ),
          ],
        ),
      ];

      active.update(fakeConv, c1);
      expect(active.matches(c1), isTrue);

      // Different function call
      final cDiffFc = [
        adk.Content(
          role: 'user',
          parts: [
            adk.Part(functionCall: adk.FunctionCall(name: 'f2', args: {'a': 1})),
            adk.Part(functionResponse: adk.FunctionResponse(name: 'r1', response: {'b': 2})),
            adk.Part(inlineData: adk.InlineData(mimeType: 'image/png', data: [1, 2])),
            adk.Part(fileData: adk.FileData(mimeType: 'image/jpeg', fileUri: 'file://img')),
          ],
        ),
      ];
      expect(active.matches(cDiffFc), isFalse);

      // Different function response
      final cDiffFr = [
        adk.Content(
          role: 'user',
          parts: [
            adk.Part(functionCall: adk.FunctionCall(name: 'f1', args: {'a': 1})),
            adk.Part(functionResponse: adk.FunctionResponse(name: 'r2', response: {'b': 2})),
            adk.Part(inlineData: adk.InlineData(mimeType: 'image/png', data: [1, 2])),
            adk.Part(fileData: adk.FileData(mimeType: 'image/jpeg', fileUri: 'file://img')),
          ],
        ),
      ];
      expect(active.matches(cDiffFr), isFalse);

      // Different inline data
      final cDiffId = [
        adk.Content(
          role: 'user',
          parts: [
            adk.Part(functionCall: adk.FunctionCall(name: 'f1', args: {'a': 1})),
            adk.Part(functionResponse: adk.FunctionResponse(name: 'r1', response: {'b': 2})),
            adk.Part(inlineData: adk.InlineData(mimeType: 'audio/wav', data: [1, 2])),
            adk.Part(fileData: adk.FileData(mimeType: 'image/jpeg', fileUri: 'file://img')),
          ],
        ),
      ];
      expect(active.matches(cDiffId), isFalse);

      // Different file data
      final cDiffFd = [
        adk.Content(
          role: 'user',
          parts: [
            adk.Part(functionCall: adk.FunctionCall(name: 'f1', args: {'a': 1})),
            adk.Part(functionResponse: adk.FunctionResponse(name: 'r1', response: {'b': 2})),
            adk.Part(inlineData: adk.InlineData(mimeType: 'image/png', data: [1, 2])),
            adk.Part(fileData: adk.FileData(mimeType: 'image/png', fileUri: 'file://other')),
          ],
        ),
      ];
      expect(active.matches(cDiffFd), isFalse);

      // Different thought
      final cDiffThought = [
        adk.Content(
          role: 'user',
          parts: [
            adk.Part(text: 'think', thought: true),
          ],
        ),
      ];
      final cNoThought = [
        adk.Content(
          role: 'user',
          parts: [
            adk.Part(text: 'think', thought: false),
          ],
        ),
      ];
      active.update(fakeConv, cDiffThought);
      expect(active.matches(cNoThought), isFalse);
    });
  });
}

class FakeEngine implements litert.Engine {
  @override
  bool isInitialized = false;

  int createConversationCallCount = 0;
  litert.ConversationConfig? lastConfig;

  FakeConversation? nextConversation;
  List<FakeConversation> conversationsToReturn = [];

  @override
  final litert.EngineConfig engineConfig;

  FakeEngine({required this.engineConfig});

  @override
  Future<void> initialize() async {
    isInitialized = true;
  }

  @override
  Future<litert.Conversation> createConversation([
    litert.ConversationConfig conversationConfig = const litert.ConversationConfig(),
  ]) async {
    createConversationCallCount += 1;
    lastConfig = conversationConfig;
    if (conversationsToReturn.isNotEmpty) {
      return conversationsToReturn.removeAt(0);
    }
    return nextConversation ?? FakeConversation();
  }

  @override
  Future<litert.Session> createSession([
    litert.SessionConfig sessionConfig = const litert.SessionConfig(),
  ]) {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {
    isInitialized = false;
  }
}

class FakeConversation implements litert.Conversation {
  int sendMessageCallCount = 0;
  litert.Message? lastMessageSent;
  litert.Message Function(litert.Message)? sendMessageHandler;
  Stream<litert.Message> Function(litert.Message)? sendMessageStreamHandler;
  int disposeCallCount = 0;

  @override
  bool get isAlive => disposeCallCount == 0;

  @override
  Future<litert.Message> sendMessage(
    litert.Message message, {
    Map<String, Object?>? extraContext,
    int? maxOutputTokens,
  }) async {
    sendMessageCallCount += 1;
    lastMessageSent = message;
    if (sendMessageHandler != null) {
      return sendMessageHandler!(message);
    }
    return const litert.Message(role: litert.Role.model);
  }

  @override
  Stream<litert.Message> sendMessageStream(
    litert.Message message, {
    Map<String, Object?>? extraContext,
    int? maxOutputTokens,
  }) {
    sendMessageCallCount += 1;
    lastMessageSent = message;
    if (sendMessageStreamHandler != null) {
      return sendMessageStreamHandler!(message);
    }
    return Stream.value(const litert.Message(role: litert.Role.model));
  }

  @override
  Future<void> sendMessageWithCallback(
    litert.Message message,
    litert.MessageCallback callback, {
    Map<String, Object?>? extraContext,
    int? maxOutputTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> renderPreface() async => '';

  @override
  Future<int> getTokenCount() async => 0;

  @override
  Future<litert.BenchmarkInfo> getBenchmarkInfo() {
    throw UnimplementedError();
  }

  @override
  Future<String> renderMessageIntoString(litert.Message message) async => '';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    disposeCallCount += 1;
  }
}
