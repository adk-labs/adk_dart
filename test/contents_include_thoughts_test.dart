// Tests RunConfig.includeThoughtsFromOtherAgents: other-agent thought parts are
// excluded by default and surfaced as `[agent] thought: ...` context text when
// the flag is enabled. Ported from google/adk-python
// tests/unittests/flows/llm_flows/test_contents_other_agent.py (commit
// 6290aec5, PR #5572).

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  List<Event> otherAgentEvents() {
    return <Event>[
      Event(
        invocationId: 'inv1',
        author: 'user',
        content: Content.userText('hello'),
      ),
      Event(
        invocationId: 'inv1',
        author: 'other_agent',
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.text('let me reason about this', thought: true),
            Part.text('the visible answer'),
          ],
        ),
      ),
    ];
  }

  test('other-agent thoughts are excluded by default', () {
    final List<Content> contents = getContents(
      currentBranch: null,
      events: otherAgentEvents(),
      agentName: 'test_agent',
    );

    final Iterable<String> texts = contents
        .expand((Content content) => content.parts)
        .map((Part part) => part.text ?? '');
    expect(
      texts.any(
        (String t) => t.contains('said:') && t.contains('the visible answer'),
      ),
      isTrue,
    );
    expect(texts.any((String t) => t.contains('thought:')), isFalse);
  });

  test(
    'other-agent thoughts are surfaced when includeThoughtsFromOtherAgents',
    () {
      final List<Content> contents = getContents(
        currentBranch: null,
        events: otherAgentEvents(),
        agentName: 'test_agent',
        includeThoughtsFromOtherAgents: true,
      );

      final Iterable<String> texts = contents
          .expand((Content content) => content.parts)
          .map((Part part) => part.text ?? '');
      expect(
        texts.any(
          (String t) =>
              t.contains('[other_agent] thought:') &&
              t.contains('let me reason about this'),
        ),
        isTrue,
      );
      expect(
        texts.any(
          (String t) => t.contains('said:') && t.contains('the visible answer'),
        ),
        isTrue,
      );
    },
  );

  test('the RunConfig flag defaults to false', () {
    expect(RunConfig().includeThoughtsFromOtherAgents, isFalse);
    expect(
      RunConfig(includeThoughtsFromOtherAgents: true)
          .includeThoughtsFromOtherAgents,
      isTrue,
    );
    expect(
      RunConfig()
          .copyWith(includeThoughtsFromOtherAgents: true)
          .includeThoughtsFromOtherAgents,
      isTrue,
    );
  });
}
