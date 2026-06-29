import 'dart:async';

import 'package:adk_dart/adk_dart.dart' as adk;
import 'package:adk_litertlm/adk_litertlm.dart';
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
  }) {
    throw UnimplementedError();
  }

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
