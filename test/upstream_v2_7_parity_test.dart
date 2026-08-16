import 'dart:convert';
import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _CustomLlm extends BaseLlm {
  _CustomLlm({required super.model, this.customCapabilities});

  final LlmCapabilities? customCapabilities;

  @override
  LlmCapabilities get capabilities =>
      customCapabilities ?? super.capabilities;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse();
  }
}

void main() {
  group('Upstream parity updates', () {
    test('isGeminiEapOr2OrAbove recognizes gemini-early-exp', () {
      expect(isGeminiEapOr2OrAbove('gemini-early-exp'), isTrue);
      expect(isGeminiEapOr2OrAbove('gemini-flash-early-exp'), isTrue);
      expect(isGeminiEapOr2OrAbove('gemini-flash-early-exp3'), isTrue);
      expect(isGeminiEapOr2OrAbove('gemini-2.5-flash'), isTrue);
      expect(isGeminiEapOr2OrAbove('gemini-1.5-pro'), isFalse);
    });

    test('InMemoryMemoryService isolates slashed identifiers', () async {
      final memory = InMemoryMemoryService();
      await memory.addSessionToMemory(
        Session(
          id: 's_1',
          appName: 'app/other-user',
          userId: 'user',
          events: <Event>[
            Event(
              id: 'e_1',
              invocationId: 'inv_1',
              author: 'user',
              timestamp: 1000,
              content: Content(
                parts: <Part>[Part.text('Confidential password info.')],
              ),
            ),
          ],
        ),
      );

      final result = await memory.searchMemory(
        appName: 'app',
        userId: 'other-user/user',
        query: 'password',
      );

      expect(result.memories, isEmpty);
    });

    test('getContents drops orphaned function responses without matching call', () {
      final events = <Event>[
        Event(
          invocationId: 'inv_1',
          author: 'user',
          content: Content.userText('Regular message 1'),
        ),
        Event(
          invocationId: 'inv_2',
          author: 'user',
          content: Content(
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'orphan_tool',
                id: 'orphan_call_id',
                response: <String, dynamic>{'error': 'no matching call'},
              ),
            ],
          ),
        ),
        Event(
          invocationId: 'inv_3',
          author: 'user',
          content: Content.userText('Regular message 2'),
        ),
      ];

      final contents = getContents(
        currentBranch: null,
        events: events,
      );

      expect(contents.length, equals(2));
      expect(contents[0].parts[0].text, equals('Regular message 1'));
      expect(contents[1].parts[0].text, equals('Regular message 2'));
    });

    test('StreamingResponseAggregator preserves thought signature across split text chunks', () async {
      final aggregator = StreamingResponseAggregator();
      final chunk1 = LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.text('First part of reasoning ', thought: true),
          ],
        ),
        partial: true,
      );
      final chunk2 = LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.text(
              'second part of reasoning.',
              thought: true,
              thoughtSignature: utf8.encode('reasoning-signature-123'),
            ),
          ],
        ),
        finishReason: 'STOP',
        partial: true,
      );

      await for (final _ in aggregator.processResponse(chunk1)) {}
      await for (final _ in aggregator.processResponse(chunk2)) {}

      final closed = aggregator.close();
      expect(closed, isNotNull);
      final parts = closed!.content!.parts;
      expect(parts.length, equals(1));
      expect(parts[0].thought, isTrue);
      expect(parts[0].text, equals('First part of reasoning second part of reasoning.'));
      expect(
        parts[0].thoughtSignature,
        equals(utf8.encode('reasoning-signature-123')),
      );
    });

    test('canUseOutputSchemaWithTools respects BaseLlm.capabilities', () {
      final supportedLlm = _CustomLlm(
        model: 'custom_model',
        customCapabilities: const LlmCapabilities(outputSchemaAndTools: true),
      );
      final unsupportedLlm = _CustomLlm(
        model: 'custom_model',
        customCapabilities: const LlmCapabilities(outputSchemaAndTools: false),
      );

      expect(canUseOutputSchemaWithTools(supportedLlm), isTrue);
      expect(canUseOutputSchemaWithTools(unsupportedLlm), isFalse);
    });
  });
}
