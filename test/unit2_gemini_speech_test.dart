import 'dart:async';
import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _MockSpeechLlm extends BaseLlm {
  _MockSpeechLlm({required super.model});

  final List<LlmRequest> requests = <LlmRequest>[];
  bool throwOnConnect = false;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    requests.add(request);
    final String prompt = request.contents.first.parts.first.text ?? '';
    // Emit dummy audio bytes for the synthesized text
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[
          Part(
            inlineData: InlineData(
              mimeType: 'audio/pcm;rate=24000',
              data: prompt.codeUnits,
            ),
          ),
        ],
      ),
      turnComplete: true,
    );
  }

  BaseLlmConnection connect(LlmRequest request) {
    if (throwOnConnect) {
      throw StateError('Cannot connect');
    }
    requests.add(request);
    return _MockSpeechConnection();
  }
}

class _MockSpeechConnection extends BaseLlmConnection {
  final StreamController<LlmResponse> _responseController =
      StreamController<LlmResponse>.broadcast();
  final List<RealtimeBlob> sentBlobs = <RealtimeBlob>[];
  bool isClosed = false;

  @override
  Future<void> close() async {
    isClosed = true;
    await _responseController.close();
  }

  @override
  Stream<LlmResponse> receive() => _responseController.stream;

  @override
  Future<void> sendContent(Content content) async {}

  @override
  Future<void> sendHistory(List<Content> history) async {}

  @override
  Future<void> sendRealtime(RealtimeBlob blob) async {
    sentBlobs.add(blob);
    // Simulate server transcription response after receiving audio
    _responseController.add(
      LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[Part.text('Hello')],
        ),
      ),
    );
    _responseController.add(
      LlmResponse(
        turnComplete: true,
      ),
    );
  }
}

void main() {
  group('GeminiTTS Unit Tests', () {
    test('synthesizes text segments and emits AudioChunk and AgentSpokenOutput',
        () async {
      final mockLlm = _MockSpeechLlm(model: 'gemini-3.8-flash-lite-tts');
      final tts = GeminiTTS(
        model: mockLlm,
        voiceName: 'Puck',
        minSegmentChars: 5,
        maxSegmentChars: 50,
      );

      final textController = StreamController<String>();
      final cancel = CancelSignal();

      final eventsFuture = tts(textController.stream, cancel: cancel).toList();

      textController.add('Hello world! ');
      textController.add('This is a live cascaded agent speaking.');
      await textController.close();

      final events = await eventsFuture;

      expect(events, isNotEmpty);
      final audioChunks = events.whereType<AudioChunk>().toList();
      final spokenOutputs = events.whereType<AgentSpokenOutput>().toList();

      expect(audioChunks, isNotEmpty);
      expect(spokenOutputs, isNotEmpty);
      expect(spokenOutputs.map((e) => e.text).join(),
          'Hello world! This is a live cascaded agent speaking.');
    });

    test('barge-in stops synthesis via CancelSignal', () async {
      final mockLlm = _MockSpeechLlm(model: 'gemini-3.8-flash-lite-tts');
      final tts = GeminiTTS(
        model: mockLlm,
        minSegmentChars: 5,
        maxSegmentChars: 50,
      );

      final textController = StreamController<String>();
      final cancel = CancelSignal();

      final events = <EgressEvent>[];
      final subscription = tts(textController.stream, cancel: cancel).listen(
        events.add,
      );

      textController.add('First sentence. ');
      cancel.set();
      textController.add('Second sentence should be dropped.');
      await textController.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      // Only the first sentence or nothing should be emitted, not the second sentence
      final spoken = events.whereType<AgentSpokenOutput>().toList();
      expect(spoken.any((e) => e.text.contains('Second sentence')), isFalse);
    });

    test('validates constructor arguments', () {
      expect(
        () => GeminiTTS(maxSegmentChars: 0),
        throwsArgumentError,
      );
      expect(
        () => GeminiTTS(minSegmentChars: -1),
        throwsArgumentError,
      );
      expect(
        () => GeminiTTS(prefetchSegments: -1),
        throwsArgumentError,
      );
    });
  });

  group('GeminiSTT Unit Tests', () {
    test('streams audio chunks and receives transcription events', () async {
      final mockLlm = _MockSpeechLlm(model: 'gemini-3.5-transcribe-live');
      final stt = GeminiSTT(
        model: mockLlm,
        silenceDurationMs: 500,
        maxReplayMs: 5000,
      );

      final audioController = StreamController<InlineData>();
      final eventsFuture = stt(audioController.stream).toList();

      audioController.add(
        InlineData(
          mimeType: 'audio/pcm;rate=16000',
          data: <int>[0, 1, 2, 3],
        ),
      );
      await audioController.close();

      final events = await eventsFuture;

      expect(events, isNotEmpty);
      expect(events.any((e) => e is UserSpeechStarted), isTrue);
      expect(events.any((e) => e is PartialTranscript && e.text == 'Hello'),
          isTrue);
      expect(events.any((e) => e is UserTurnFinished && e.text == 'Hello'),
          isTrue);
    });

    test('validates maxReplayMs non-negative', () {
      expect(
        () => GeminiSTT(maxReplayMs: -10),
        throwsArgumentError,
      );
    });
  });
}
