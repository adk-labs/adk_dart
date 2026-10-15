import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeModel extends BaseLlm {
  _FakeModel({required super.model, this.fail = false, this.reply = 'ok'});

  final bool fail;
  final String reply;
  int callCount = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    callCount++;
    if (fail) {
      throw StateError('Model $model failed');
    }
    yield LlmResponse(
      content: Content(role: 'model', parts: <Part>[Part.text(reply)]),
    );
  }
}

void main() {
  group('RoutedLlm', () {
    test('routes to the model chosen by router function', () async {
      final primary = _FakeModel(model: 'primary', reply: 'from primary');
      final fallback = _FakeModel(model: 'fallback', reply: 'from fallback');

      final routed = RoutedLlm(
        models: {'primary': primary, 'fallback': fallback},
        router: (models, request, {errorContext}) => 'primary',
      );

      final req = LlmRequest(contents: [Content.userText('hello')]);
      final responses = await routed.generateContent(req).toList();

      expect(responses.length, equals(1));
      expect(responses.first.content?.parts.first.text, equals('from primary'));
      expect(primary.callCount, equals(1));
      expect(fallback.callCount, equals(0));
    });

    test('fails over to fallback model when primary throws', () async {
      final primary = _FakeModel(model: 'primary', fail: true);
      final fallback = _FakeModel(model: 'fallback', reply: 'recovered');

      final routed = RoutedLlm(
        models: {'primary': primary, 'fallback': fallback},
        router: (models, request, {errorContext}) {
          if (errorContext == null) {
            return 'primary';
          }
          if (errorContext.failedKeys.contains('primary')) {
            return 'fallback';
          }
          return null;
        },
      );

      final req = LlmRequest(contents: [Content.userText('test failover')]);
      final responses = await routed.generateContent(req).toList();

      expect(responses.length, equals(1));
      expect(responses.first.content?.parts.first.text, equals('recovered'));
      expect(primary.callCount, equals(1));
      expect(fallback.callCount, equals(1));
    });

    test('rethrows error when router returns null on error', () async {
      final primary = _FakeModel(model: 'primary', fail: true);

      final routed = RoutedLlm(
        models: {'primary': primary},
        router: (models, request, {errorContext}) =>
            errorContext == null ? 'primary' : null,
      );

      final req = LlmRequest(contents: [Content.userText('test failover')]);
      expect(
        () => routed.generateContent(req).toList(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
