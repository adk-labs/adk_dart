import 'dart:async';

import '../types/content.dart';
import '../utils/content_utils.dart';
import '../utils/variant_utils.dart';
import 'base_llm.dart';
import 'base_llm_connection.dart';
import 'llm_request.dart';
import 'llm_response.dart';

class GeminiTranscriptionEvent {
  GeminiTranscriptionEvent({this.text, this.finished = false});

  final String? text;
  final bool finished;
}

class GeminiUsageMetadata {
  GeminiUsageMetadata({
    this.promptTokenCount,
    this.candidatesTokenCount,
    this.totalTokenCount,
  });

  final int? promptTokenCount;
  final int? candidatesTokenCount;
  final int? totalTokenCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (promptTokenCount != null) 'prompt_token_count': promptTokenCount,
      if (candidatesTokenCount != null)
        'candidates_token_count': candidatesTokenCount,
      if (totalTokenCount != null) 'total_token_count': totalTokenCount,
    };
  }
}

class GeminiToolCallPayload {
  GeminiToolCallPayload({List<FunctionCall>? functionCalls})
    : functionCalls = functionCalls ?? <FunctionCall>[];

  final List<FunctionCall> functionCalls;
}

class GeminiServerContentPayload {
  GeminiServerContentPayload({
    this.modelTurn,
    this.interrupted = false,
    this.turnComplete = false,
    this.generationComplete = false,
    this.inputTranscription,
    this.outputTranscription,
  });

  final Content? modelTurn;
  final bool interrupted;
  final bool turnComplete;
  final bool generationComplete;
  final GeminiTranscriptionEvent? inputTranscription;
  final GeminiTranscriptionEvent? outputTranscription;
}

class GeminiLiveSessionMessage {
  GeminiLiveSessionMessage({
    this.usageMetadata,
    this.serverContent,
    this.toolCall,
    this.sessionResumptionUpdate,
  });

  final GeminiUsageMetadata? usageMetadata;
  final GeminiServerContentPayload? serverContent;
  final GeminiToolCallPayload? toolCall;
  final Object? sessionResumptionUpdate;
}

abstract class GeminiLiveSession {
  Future<void> sendContent({
    required List<Content> turns,
    required bool turnComplete,
  });

  Future<void> sendToolResponses({
    required List<FunctionResponse> functionResponses,
  });

  Future<void> sendRealtimeInput({required RealtimeBlob blob});

  Stream<GeminiLiveSessionMessage> receive();

  Future<void> close();
}

class GeminiLlmConnection extends BaseLlmConnection {
  GeminiLlmConnection({
    required BaseLlm model,
    LlmRequest? initialRequest,
    GeminiLiveSession? liveSession,
    GoogleLLMVariant apiBackend = GoogleLLMVariant.vertexAi,
    String? modelVersion,
  }) : _model = model,
       _initialRequest =
           initialRequest?.sanitizedForModelCall() ?? LlmRequest(),
       _liveSession = liveSession,
       _apiBackend = apiBackend,
       _modelVersion = modelVersion;

  final BaseLlm _model;
  final LlmRequest _initialRequest;
  final GeminiLiveSession? _liveSession;
  final GoogleLLMVariant _apiBackend;
  final String? _modelVersion;
  final StreamController<LlmResponse> _responses =
      StreamController<LlmResponse>.broadcast();

  final List<Content> _history = <Content>[];
  StreamSubscription<GeminiLiveSessionMessage>? _liveSubscription;
  String _inputTranscriptionText = '';
  String _outputTranscriptionText = '';
  String _textBuffer = '';
  Future<void> _lastDispatch = Future<void>.value();
  bool _closed = false;

  @override
  Future<void> sendHistory(List<Content> history) async {
    if (_closed) {
      return;
    }

    if (_liveSession != null) {
      final GeminiLiveSession liveSession = _liveSession;
      final List<Content> filtered = history
          .map(filterAudioParts)
          .whereType<Content>()
          .map((Content content) => content.copyWith())
          .toList();
      if (filtered.isEmpty) {
        return;
      }
      await liveSession.sendContent(
        turns: filtered,
        turnComplete: filtered.last.role == 'user',
      );
      await _ensureLiveReceiveLoop();
      return;
    }

    _history
      ..clear()
      ..addAll(history.map((Content content) => content.copyWith()));
    final Content? last = _history.isEmpty ? null : _history.last;
    if (last != null && last.role == 'user') {
      await _dispatchFallback();
    }
  }

  @override
  Future<void> sendContent(Content content) async {
    if (_closed) {
      return;
    }

    if (_liveSession != null) {
      final GeminiLiveSession liveSession = _liveSession;
      final List<FunctionResponse> functionResponses = content.parts
          .map((Part part) => part.functionResponse)
          .whereType<FunctionResponse>()
          .toList();
      if (functionResponses.length == content.parts.length &&
          functionResponses.isNotEmpty) {
        await liveSession.sendToolResponses(
          functionResponses: functionResponses,
        );
      } else {
        await liveSession.sendContent(
          turns: <Content>[content.copyWith()],
          turnComplete: true,
        );
      }
      await _ensureLiveReceiveLoop();
      return;
    }

    _history.add(content.copyWith());
    await _dispatchFallback();
  }

  @override
  Future<void> sendRealtime(RealtimeBlob blob) {
    if (_liveSession != null) {
      return _liveSession.sendRealtimeInput(blob: blob);
    }

    final Content realtimeContent = Content(
      role: 'user',
      parts: <Part>[
        Part.fromInlineData(mimeType: blob.mimeType, data: blob.data),
      ],
    );
    return sendContent(realtimeContent);
  }

  @override
  Stream<LlmResponse> receive() => _responses.stream;

  @override
  Future<void> close() async {
    _closed = true;
    if (_liveSubscription != null) {
      await _liveSubscription!.cancel();
      _liveSubscription = null;
    }
    await _lastDispatch;
    if (_liveSession != null) {
      await _liveSession.close();
    }
    await _responses.close();
  }

  Future<void> _dispatchFallback() {
    _lastDispatch = _lastDispatch.then((_) async {
      if (_closed) {
        return;
      }

      final LlmRequest request = _initialRequest.sanitizedForModelCall();
      request.contents = _history
          .map((Content content) => content.copyWith())
          .toList();

      await for (final LlmResponse response in _model.generateContent(
        request,
        stream: true,
      )) {
        if (_closed) {
          return;
        }
        _responses.add(response.copyWith());
      }
    });
    return _lastDispatch;
  }

  Future<void> _ensureLiveReceiveLoop() async {
    if (_liveSession == null || _liveSubscription != null || _closed) {
      return;
    }

    _liveSubscription = _liveSession.receive().listen(
      (GeminiLiveSessionMessage message) {
        _handleLiveMessage(message);
      },
      onDone: () {
        _liveSubscription = null;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_closed) {
          return;
        }
        _responses.add(
          LlmResponse(
            errorCode: 'live_session_error',
            errorMessage: '$error',
            interrupted: true,
          ),
        );
      },
      cancelOnError: false,
    );
  }

  void _handleLiveMessage(GeminiLiveSessionMessage message) {
    if (_closed) {
      return;
    }

    final GeminiUsageMetadata? usageMetadata = message.usageMetadata;
    if (usageMetadata != null) {
      _responses.add(
        LlmResponse(
          usageMetadata: usageMetadata.toJson(),
          modelVersion: _modelVersion,
        ),
      );
    }

    final GeminiServerContentPayload? serverContent = message.serverContent;
    if (serverContent != null) {
      _handleServerContent(serverContent);
    }

    final GeminiToolCallPayload? toolCall = message.toolCall;
    if (toolCall != null && toolCall.functionCalls.isNotEmpty) {
      _flushTextIfPresent();
      final List<Part> parts = toolCall.functionCalls
          .map(
            (FunctionCall functionCall) =>
                Part(functionCall: functionCall.copyWith()),
          )
          .toList();
      _responses.add(
        LlmResponse(
          content: Content(role: 'model', parts: parts),
        ),
      );
    }

    if (message.sessionResumptionUpdate != null) {
      _responses.add(
        LlmResponse(
          customMetadata: <String, dynamic>{
            'live_session_resumption_update': message.sessionResumptionUpdate,
          },
        ),
      );
    }
  }

  void _handleServerContent(GeminiServerContentPayload serverContent) {
    final Content? content = serverContent.modelTurn;
    if (content != null && content.parts.isNotEmpty) {
      final Part firstPart = content.parts.first;
      if (firstPart.text != null && firstPart.text!.isNotEmpty) {
        _textBuffer += firstPart.text!;
        _responses.add(
          LlmResponse(
            content: content.copyWith(),
            interrupted: serverContent.interrupted,
            partial: true,
          ),
        );
      } else {
        _flushTextIfPresent();
        _responses.add(
          LlmResponse(
            content: content.copyWith(),
            interrupted: serverContent.interrupted,
          ),
        );
      }
    }

    _processTranscription(
      event: serverContent.inputTranscription,
      isInput: true,
    );
    _processTranscription(
      event: serverContent.outputTranscription,
      isInput: false,
    );

    if (_apiBackend == GoogleLLMVariant.geminiApi &&
        (serverContent.interrupted ||
            serverContent.turnComplete ||
            serverContent.generationComplete)) {
      _flushPendingTranscriptions(force: true);
    }

    if (serverContent.turnComplete) {
      _flushTextIfPresent();
      _responses.add(
        LlmResponse(turnComplete: true, interrupted: serverContent.interrupted),
      );
      return;
    }

    if (serverContent.interrupted) {
      _flushTextIfPresent();
      _responses.add(LlmResponse(interrupted: true));
    }
  }

  void _processTranscription({
    required GeminiTranscriptionEvent? event,
    required bool isInput,
  }) {
    if (event == null) {
      return;
    }
    if (event.text != null && event.text!.isNotEmpty) {
      if (isInput) {
        _inputTranscriptionText += event.text!;
      } else {
        _outputTranscriptionText += event.text!;
      }
      _responses.add(
        LlmResponse(
          partial: true,
          inputTranscription: isInput
              ? <String, Object?>{'text': event.text!, 'finished': false}
              : null,
          outputTranscription: !isInput
              ? <String, Object?>{'text': event.text!, 'finished': false}
              : null,
        ),
      );
    }

    if (event.finished) {
      _flushPendingTranscriptions(force: true, onlyInput: isInput);
      _flushPendingTranscriptions(force: true, onlyInput: !isInput);
    }
  }

  void _flushPendingTranscriptions({bool force = false, bool? onlyInput}) {
    if (onlyInput == null || onlyInput) {
      if (_inputTranscriptionText.isNotEmpty || force) {
        if (_inputTranscriptionText.isNotEmpty) {
          _responses.add(
            LlmResponse(
              partial: false,
              inputTranscription: <String, Object?>{
                'text': _inputTranscriptionText,
                'finished': true,
              },
            ),
          );
          _inputTranscriptionText = '';
        }
      }
    }
    if (onlyInput == null || !onlyInput) {
      if (_outputTranscriptionText.isNotEmpty || force) {
        if (_outputTranscriptionText.isNotEmpty) {
          _responses.add(
            LlmResponse(
              partial: false,
              outputTranscription: <String, Object?>{
                'text': _outputTranscriptionText,
                'finished': true,
              },
            ),
          );
          _outputTranscriptionText = '';
        }
      }
    }
  }

  void _flushTextIfPresent() {
    if (_textBuffer.isEmpty) {
      return;
    }
    _responses.add(LlmResponse(content: Content.modelText(_textBuffer)));
    _textBuffer = '';
  }
}
