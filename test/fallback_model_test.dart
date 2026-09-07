import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeHttpStatusException implements Exception {
  _FakeHttpStatusException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'FakeHttpStatusException($statusCode): $message';
}

class _TestModel extends BaseLlm {
  _TestModel({
    required super.model,
    this.error,
    this.yieldBeforeError = false,
    this.responses = const <String>['ok'],
    this.connection,
    this.connectError,
  });

  final Object? error;
  final bool yieldBeforeError;
  final List<String> responses;
  final BaseLlmConnection? connection;
  final Object? connectError;

  int callCount = 0;
  List<LlmRequest> seenRequests = <LlmRequest>[];

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    callCount++;
    seenRequests.add(request);

    if (yieldBeforeError) {
      yield LlmResponse(content: Content.modelText('initial_chunk'));
    }

    if (error != null) {
      if (error is Exception) {
        throw error as Exception;
      }
      if (error is Error) {
        throw error as Error;
      }
      throw Exception('$error');
    }

    for (final String text in responses) {
      yield LlmResponse(content: Content.modelText(text));
    }
  }

  BaseLlmConnection connect(LlmRequest request) {
    callCount++;
    if (connectError != null) {
      if (connectError is Exception) {
        throw connectError as Exception;
      }
      throw Exception('$connectError');
    }
    return connection ?? _TestConnection();
  }
}

class _TestConnection implements BaseLlmConnection {
  @override
  Future<void> sendHistory(List<Content> history) async {}

  @override
  Future<void> sendContent(Content content) async {}

  @override
  Future<void> sendRealtime(RealtimeBlob blob) async {}

  @override
  Stream<LlmResponse> receive() async* {}

  @override
  Future<void> close() async {}
}

void main() {
  group('FallbackModel', () {
    test('validates non-empty models list', () {
      expect(
        () => FallbackModel(models: <Object>[]),
        throwsArgumentError,
      );
    });

    test('derives model name from primary entry', () {
      final FallbackModel fallback = FallbackModel(
        models: <Object>['gemini-2.5-flash', 'backup-model'],
      );
      expect(fallback.model, 'gemini-2.5-flash');
    });

    test('accepts matching explicit model name and rejects mismatched', () {
      final FallbackModel matching = FallbackModel(
        models: <Object>['primary-model', 'backup-model'],
        model: 'primary-model',
      );
      expect(matching.model, 'primary-model');

      expect(
        () => FallbackModel(
          models: <Object>['primary-model', 'backup-model'],
          model: 'mismatched-model',
        ),
        throwsArgumentError,
      );
    });

    test('generates content with primary when primary succeeds', () async {
      final _TestModel primary = _TestModel(model: 'primary', responses: <String>['resp1']);
      final _TestModel backup = _TestModel(model: 'backup');

      final FallbackModel fallback = FallbackModel(models: <Object>[primary, backup]);
      final LlmRequest request = LlmRequest(contents: <Content>[Content.userText('hi')]);

      final List<LlmResponse> responses =
          await fallback.generateContent(request).toList();

      expect(responses, hasLength(1));
      expect(responses.first.content?.parts.first.text, 'resp1');
      expect(primary.callCount, 1);
      expect(backup.callCount, 0);
    });

    test('falls back to backup model on 429 and 500 series errors', () async {
      final _TestModel primary = _TestModel(
        model: 'primary',
        error: _FakeHttpStatusException(429, 'Rate limited'),
      );
      final _TestModel backup = _TestModel(
        model: 'backup',
        responses: <String>['backup_success'],
      );

      final FallbackModel fallback = FallbackModel(models: <Object>[primary, backup]);
      final LlmRequest request = LlmRequest(contents: <Content>[Content.userText('hi')]);

      final List<LlmResponse> responses =
          await fallback.generateContent(request).toList();

      expect(responses, hasLength(1));
      expect(responses.first.content?.parts.first.text, 'backup_success');
      expect(primary.callCount, 1);
      expect(backup.callCount, 1);
    });

    test('does not fall back on non-retriable error like 400 Bad Request', () async {
      final _TestModel primary = _TestModel(
        model: 'primary',
        error: _FakeHttpStatusException(400, 'Invalid argument'),
      );
      final _TestModel backup = _TestModel(model: 'backup');

      final FallbackModel fallback = FallbackModel(models: <Object>[primary, backup]);
      final LlmRequest request = LlmRequest(contents: <Content>[Content.userText('hi')]);

      await expectLater(
        fallback.generateContent(request).toList(),
        throwsA(isA<_FakeHttpStatusException>()),
      );
      expect(primary.callCount, 1);
      expect(backup.callCount, 0);
    });

    test('does not fall back once response chunk has been yielded', () async {
      final _TestModel primary = _TestModel(
        model: 'primary',
        yieldBeforeError: true,
        error: _FakeHttpStatusException(500, 'Mid-turn crash'),
      );
      final _TestModel backup = _TestModel(model: 'backup');

      final FallbackModel fallback = FallbackModel(models: <Object>[primary, backup]);
      final LlmRequest request = LlmRequest(contents: <Content>[Content.userText('hi')]);

      await expectLater(
        fallback.generateContent(request).toList(),
        throwsA(isA<_FakeHttpStatusException>()),
      );
      expect(primary.callCount, 1);
      expect(backup.callCount, 0);
    });

    test('re-throws last error when all models fail', () async {
      final _TestModel primary = _TestModel(
        model: 'primary',
        error: _FakeHttpStatusException(503, 'Primary unavailable'),
      );
      final _TestModel backup = _TestModel(
        model: 'backup',
        error: _FakeHttpStatusException(504, 'Backup gateway timeout'),
      );

      final FallbackModel fallback = FallbackModel(models: <Object>[primary, backup]);
      final LlmRequest request = LlmRequest(contents: <Content>[Content.userText('hi')]);

      await expectLater(
        fallback.generateContent(request).toList(),
        throwsA(
          isA<_FakeHttpStatusException>().having(
            (_FakeHttpStatusException e) => e.statusCode,
            'statusCode',
            504,
          ),
        ),
      );
      expect(primary.callCount, 1);
      expect(backup.callCount, 1);
    });

    test('restores request contents and config after failed attempt', () async {
      final _TestModel primary = _TestModel(
        model: 'primary',
        error: _FakeHttpStatusException(500, 'Primary error'),
      );
      final _TestModel backup = _TestModel(
        model: 'backup',
        responses: <String>['ok'],
      );

      final FallbackModel fallback = FallbackModel(models: <Object>[primary, backup]);
      final LlmRequest request = LlmRequest(
        contents: <Content>[Content.userText('original_prompt')],
      );

      await fallback.generateContent(request).toList();

      expect(backup.seenRequests, hasLength(1));
      expect(backup.seenRequests.first.contents.first.parts.first.text, 'original_prompt');
      expect(backup.seenRequests.first.model, 'backup');
    });

    test('connect falls back to next model on recoverable error', () {
      final _TestModel primary = _TestModel(
        model: 'primary',
        connectError: _FakeHttpStatusException(503, 'Unavailable'),
      );
      final _TestConnection backupConnection = _TestConnection();
      final _TestModel backup = _TestModel(
        model: 'backup',
        connection: backupConnection,
      );

      final FallbackModel fallback = FallbackModel(models: <Object>[primary, backup]);
      final LlmRequest request = LlmRequest(contents: <Content>[]);

      final BaseLlmConnection conn = fallback.connect(request);
      expect(conn, same(backupConnection));
      expect(primary.callCount, 1);
      expect(backup.callCount, 1);
    });
  });
}
