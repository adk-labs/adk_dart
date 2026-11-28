import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _ClosableMockClient implements ModelArmorClient {
  bool closed = false;
  final Completer<void> inFlight = Completer<void>();
  final Completer<void> release = Completer<void>();

  Future<void> close() async {
    closed = true;
  }

  @override
  Future<ModelArmorSanitizationResult> sanitizeUserPrompt({
    required String text,
    required String templateName,
  }) async {
    if (!inFlight.isCompleted) {
      inFlight.complete();
    }
    await release.future;
    if (closed) {
      throw StateError('Client closed');
    }
    return const ModelArmorSanitizationResult(
      filterMatchState: ModelArmorFilterMatchState.noMatchFound,
      invocationResult: ModelArmorInvocationResult.success,
    );
  }

  @override
  Future<ModelArmorSanitizationResult> sanitizeModelResponse({
    required String text,
    required String templateName,
  }) async {
    return const ModelArmorSanitizationResult(
      filterMatchState: ModelArmorFilterMatchState.noMatchFound,
      invocationResult: ModelArmorInvocationResult.success,
    );
  }
}

class _StubModel extends BaseLlm {
  _StubModel(this._replyText) : super(model: 'stub-model');

  final String _replyText;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content(role: 'model', parts: <Part>[Part.text(_replyText)]),
    );
  }
}

ModelArmorConfig _testConfig() {
  return ModelArmorConfig(
    promptTemplateName: 'projects/test-project/locations/us-central1/templates/test-prompt',
    responseTemplateName:
        'projects/test-project/locations/us-central1/templates/test-response',
  );
}

void main() {
  group('ModelArmorPlugin.close() parity (bee78e7ce)', () {
    test('close leaves supplied client untouched', () async {
      final _ClosableMockClient supplied = _ClosableMockClient();
      final ModelArmorPlugin plugin = ModelArmorPlugin(
        config: _testConfig(),
        client: supplied,
      );

      await plugin.close();

      expect(supplied.closed, isFalse);
      expect(identical(plugin.client, supplied), isTrue);
    });

    test('close does not close or replace default shared client', () async {
      final ModelArmorPlugin plugin = ModelArmorPlugin(config: _testConfig());
      final ModelArmorClient sharedClient = plugin.client;

      await plugin.close();

      expect(identical(plugin.client, sharedClient), isTrue);
    });

    test('closing one runner keeps sibling runners screening', () async {
      final _ClosableMockClient sharedClient = _ClosableMockClient();
      final ModelArmorPlugin plugin = ModelArmorPlugin(
        config: _testConfig(),
        client: sharedClient,
      );
      final LlmAgent agent = LlmAgent(
        name: 'test_agent',
        model: _StubModel('Hello from sibling runner!'),
      );
      final App app = App(
        name: 'test_app',
        rootAgent: agent,
        plugins: <BasePlugin>[plugin],
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      await sessionService.createSession(
        appName: 'test_app',
        userId: 'u',
        sessionId: 's',
      );

      final Runner runnerClosing = Runner(
        app: app,
        sessionService: sessionService,
      );
      final Runner runnerBusy = Runner(
        app: app,
        sessionService: sessionService,
      );

      final Future<List<Event>> busyTurn = runnerBusy
          .runAsync(
            userId: 'u',
            sessionId: 's',
            newMessage: Content.userText('hello'),
          )
          .toList();

      await sharedClient.inFlight.future.timeout(const Duration(seconds: 5));

      await runnerClosing.close();
      expect(sharedClient.closed, isFalse);

      sharedClient.release.complete();
      final List<Event> events = await busyTurn.timeout(
        const Duration(seconds: 5),
      );
      final List<String> texts = <String>[
        for (final Event event in events)
          if (event.content != null)
            for (final Part part in event.content!.parts)
              if (part.text != null && part.text!.isNotEmpty) part.text!,
      ];
      expect(texts, <String>['Hello from sibling runner!']);
      expect(sharedClient.closed, isFalse);
    });
  });
}
