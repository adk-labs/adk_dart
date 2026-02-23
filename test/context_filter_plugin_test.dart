import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

InvocationContext _newInvocationContext() {
  final LlmAgent agent = LlmAgent(
    name: 'root_agent',
    model: _NoopModel(),
    disallowTransferToParent: true,
    disallowTransferToPeers: true,
  );

  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_plugin',
    agent: agent,
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
  );
}

void main() {
  test(
    'keeps recent invocations and avoids orphaned function responses',
    () async {
      final ContextFilterPlugin plugin = ContextFilterPlugin(
        numInvocationsToKeep: 2,
      );
      final LlmRequest request = LlmRequest(
        contents: <Content>[
          Content(role: 'user', parts: <Part>[Part.text('q1')]),
          Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'lookup',
                id: 'call_1',
                args: <String, dynamic>{'q': 'x'},
              ),
            ],
          ),
          Content(role: 'user', parts: <Part>[Part.text('q2')]),
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'lookup',
                id: 'call_1',
                response: <String, dynamic>{'result': 'ok'},
              ),
            ],
          ),
          Content(role: 'model', parts: <Part>[Part.text('a2')]),
          Content(role: 'user', parts: <Part>[Part.text('q3')]),
        ],
      );

      await plugin.beforeModelCallback(
        callbackContext: Context(_newInvocationContext()),
        llmRequest: request,
      );

      expect(request.contents, hasLength(5));
      expect(request.contents.first.role, 'model');
      expect(request.contents.first.parts.first.functionCall?.id, 'call_1');
      expect(request.contents[1].parts.first.text, 'q2');
      expect(request.contents.last.parts.first.text, 'q3');
    },
  );

  test('applies custom filter after invocation trimming', () async {
    final ContextFilterPlugin plugin = ContextFilterPlugin(
      numInvocationsToKeep: 2,
      customFilter: (List<Content> contents) {
        return contents
            .where((Content content) => content.role == 'user')
            .toList(growable: false);
      },
    );
    final LlmRequest request = LlmRequest(
      contents: <Content>[
        Content(role: 'user', parts: <Part>[Part.text('q1')]),
        Content(role: 'model', parts: <Part>[Part.text('a1')]),
        Content(role: 'user', parts: <Part>[Part.text('q2')]),
      ],
    );

    await plugin.beforeModelCallback(
      callbackContext: Context(_newInvocationContext()),
      llmRequest: request,
    );

    expect(request.contents, hasLength(2));
    expect(
      request.contents.every((Content content) => content.role == 'user'),
      isTrue,
    );
  });

  test('swallows filter exceptions and keeps request intact', () async {
    final ContextFilterPlugin plugin = ContextFilterPlugin(
      customFilter: (List<Content> contents) {
        throw StateError('broken filter');
      },
    );

    final LlmRequest request = LlmRequest(
      contents: <Content>[
        Content(role: 'user', parts: <Part>[Part.text('q1')]),
        Content(role: 'model', parts: <Part>[Part.text('a1')]),
      ],
    );

    await plugin.beforeModelCallback(
      callbackContext: Context(_newInvocationContext()),
      llmRequest: request,
    );

    expect(request.contents, hasLength(2));
    expect(request.contents.first.parts.first.text, 'q1');
    expect(request.contents.last.parts.first.text, 'a1');
  });
}
