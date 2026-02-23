import 'dart:async';

import '../types/content.dart';
import 'base_llm.dart';
import 'base_llm_connection.dart';
import 'llm_request.dart';
import 'llm_response.dart';

class GeminiLlmConnection extends BaseLlmConnection {
  GeminiLlmConnection({required BaseLlm model, LlmRequest? initialRequest})
    : _model = model,
      _initialRequest = initialRequest?.sanitizedForModelCall() ?? LlmRequest();

  final BaseLlm _model;
  final LlmRequest _initialRequest;
  final StreamController<LlmResponse> _responses =
      StreamController<LlmResponse>.broadcast();

  final List<Content> _history = <Content>[];
  Future<void> _lastDispatch = Future<void>.value();
  bool _closed = false;

  @override
  Future<void> sendHistory(List<Content> history) async {
    if (_closed) {
      return;
    }
    _history
      ..clear()
      ..addAll(history.map((Content content) => content.copyWith()));
    final Content? last = _history.isEmpty ? null : _history.last;
    if (last != null && last.role == 'user') {
      await _dispatch();
    }
  }

  @override
  Future<void> sendContent(Content content) async {
    if (_closed) {
      return;
    }
    _history.add(content.copyWith());
    await _dispatch();
  }

  @override
  Future<void> sendRealtime(RealtimeBlob blob) {
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
    await _lastDispatch;
    await _responses.close();
  }

  Future<void> _dispatch() {
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
}
