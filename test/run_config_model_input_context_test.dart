// Tests for RunConfig.modelInputContext: transient per-invocation context
// injected into the LLM request without being persisted to the session.
// Ported from google/adk-python
// tests/unittests/agents/test_llm_agent_include_contents.py and
// tests/unittests/agents/test_run_config.py (commit 2aeb1e1b, closes #5990).

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class MockModel extends BaseLlm {
  MockModel({required this.responses}) : super(model: 'mock-model');

  final List<LlmResponse> responses;
  final List<LlmRequest> requests = <LlmRequest>[];
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    requests.add(request);
    if (_index >= responses.length) {
      return;
    }
    yield responses[_index++].copyWith();
  }
}

List<(String?, String?)> _simplifyContents(List<Content> contents) {
  return contents
      .map(
        (Content content) => (
          content.role,
          content.parts
              .map((Part part) {
                if (part.text != null) {
                  return part.text!;
                }
                if (part.functionCall != null) {
                  return 'call:${part.functionCall!.name}';
                }
                if (part.functionResponse != null) {
                  return 'response:${part.functionResponse!.name}';
                }
                return '?';
              })
              .join('|'),
        ),
      )
      .toList();
}

void main() {
  test('RunConfig accepts transient contents', () {
    final Content contextContent = Content.userText(
      'Relevant context for this turn',
    );
    final RunConfig runConfig = RunConfig(
      modelInputContext: <Content>[contextContent],
    );

    expect(runConfig.modelInputContext, <Content>[contextContent]);
  });

  test(
    'model input context is sent to model without persisting to session',
    () async {
      final MockModel model = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('Answer')),
        ],
      );
      final Agent agent = Agent(name: 'test_agent', model: model);
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 's_transient',
      );

      await runner
          .runAsync(
            userId: 'user_1',
            sessionId: session.id,
            newMessage: Content.userText('Question'),
            runConfig: RunConfig(
              modelInputContext: <Content>[
                Content.userText('Relevant context for this turn'),
              ],
            ),
          )
          .toList();

      expect(_simplifyContents(model.requests.first.contents), <(String?, String?)>[
        ('user', 'Relevant context for this turn'),
        ('user', 'Question'),
      ]);

      final Session? updated = await runner.sessionService.getSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: session.id,
      );
      // The transient context never lands in session.events.
      expect(
        updated!.events.map((Event event) => event.content?.parts.first.text),
        isNot(contains('Relevant context for this turn')),
      );
      expect(updated.events.first.content?.parts.first.text, 'Question');
    },
  );

  test(
    'model input context stays before user message after tool call',
    () async {
      Map<String, Object?> simpleTool(Map<String, dynamic> args) {
        return <String, Object?>{
          'result': 'Tool processed: ${args['message']}',
        };
      }

      final MockModel model = MockModel(
        responses: <LlmResponse>[
          LlmResponse(
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'simple_tool',
                  args: <String, dynamic>{'message': 'payload'},
                ),
              ],
            ),
          ),
          LlmResponse(content: Content.modelText('Answer')),
        ],
      );
      final Agent agent = Agent(
        name: 'test_agent',
        model: model,
        tools: <Object>[
          FunctionTool(
            func: simpleTool,
            name: 'simple_tool',
            description: 'A simple tool',
          ),
        ],
      );
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 's_tool_loop',
      );

      await runner
          .runAsync(
            userId: 'user_1',
            sessionId: session.id,
            newMessage: Content.userText('Question'),
            runConfig: RunConfig(
              modelInputContext: <Content>[
                Content.userText('Relevant context for this turn'),
              ],
            ),
          )
          .toList();

      expect(model.requests, hasLength(2));
      expect(_simplifyContents(model.requests[0].contents), <(String?, String?)>[
        ('user', 'Relevant context for this turn'),
        ('user', 'Question'),
      ]);
      // After the tool loop, the transient context keeps its position before
      // the invocation user content.
      final List<(String?, String?)> secondRequest = _simplifyContents(
        model.requests[1].contents,
      );
      expect(secondRequest.first, ('user', 'Relevant context for this turn'));
      expect(secondRequest[1], ('user', 'Question'));
      expect(secondRequest[2].$2, 'call:simple_tool');
      expect(secondRequest[3].$2, 'response:simple_tool');
    },
  );

  test(
    'model input context with include_contents none sub-agent',
    () async {
      final MockModel agent1Model = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('Agent1 response: XYZ')),
        ],
      );
      final Agent agent1 = Agent(name: 'agent1', model: agent1Model);
      final MockModel agent2Model = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('Agent2 final response')),
        ],
      );
      final Agent agent2 = Agent(
        name: 'agent2',
        model: agent2Model,
        includeContents: 'none',
      );
      final SequentialAgent sequentialAgent = SequentialAgent(
        name: 'sequential_test_agent',
        subAgents: <BaseAgent>[agent1, agent2],
      );
      final InMemoryRunner runner = InMemoryRunner(agent: sequentialAgent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 's_sequential',
      );

      await runner
          .runAsync(
            userId: 'user_1',
            sessionId: session.id,
            newMessage: Content.userText('Original user request'),
            runConfig: RunConfig(
              modelInputContext: <Content>[
                Content.userText('Relevant context for this turn'),
              ],
            ),
          )
          .toList();

      expect(
        _simplifyContents(agent1Model.requests.first.contents),
        <(String?, String?)>[
          ('user', 'Relevant context for this turn'),
          ('user', 'Original user request'),
        ],
      );
      // agent2 uses include_contents='none': its current turn anchors on
      // agent1's reply (presented as context) and the transient context is
      // prepended before it.
      final List<(String?, String?)> agent2Contents = _simplifyContents(
        agent2Model.requests.first.contents,
      );
      expect(
        agent2Contents.first,
        ('user', 'Relevant context for this turn'),
      );
      expect(
        agent2Contents[1].$2,
        contains('[agent1] said: Agent1 response: XYZ'),
      );
    },
  );
}
