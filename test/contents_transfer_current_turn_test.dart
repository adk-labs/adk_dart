// Tests that user input is retained across a transfer_to_agent handoff when
// include_contents='none'. Ported from google/adk-python
// tests/unittests/flows/llm_flows/test_contents.py::
// test_events_with_transfer_to_agent_are_included (commit ad5445a1,
// fix #3535).

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'current turn anchors on the latest user input, not trailing '
    'transfer_to_agent events',
    () {
      final List<Event> events = <Event>[
        Event(
          invocationId: 'inv1',
          author: 'user',
          content: Content.userText('First user message'),
        ),
        Event(
          invocationId: 'inv1',
          author: 'parent',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part(
                functionCall: FunctionCall(
                  id: 'call_inv1',
                  name: 'transfer_to_agent',
                  args: <String, dynamic>{'agent_name': 'test_agent'},
                ),
              ),
            ],
          ),
        ),
        Event(
          invocationId: 'inv1',
          author: 'parent',
          content: Content(
            role: 'user',
            parts: <Part>[
              Part(
                functionResponse: FunctionResponse(
                  id: 'call_inv1',
                  name: 'transfer_to_agent',
                  response: <String, dynamic>{'result': null},
                ),
              ),
            ],
          ),
          actions: EventActions(transferToAgent: 'test_agent'),
        ),
      ];

      final List<Content> contents = getCurrentTurnContents(
        currentBranch: null,
        events: events,
        agentName: 'test_agent',
      );

      expect(contents, hasLength(3));
      // Anchored on the latest user input.
      expect(contents[0].role, 'user');
      expect(contents[0].parts.first.text, 'First user message');
      // The transfer events are still included, presented as context.
      expect(contents[1].role, 'user');
      expect(contents[1].parts.first.text, 'For context:');
      expect(
        contents[1].parts[1].text,
        contains('[parent] called tool `transfer_to_agent` with parameters:'),
      );
      expect(contents[2].role, 'user');
      expect(contents[2].parts.first.text, 'For context:');
      expect(
        contents[2].parts[1].text,
        contains('[parent] `transfer_to_agent` tool returned result:'),
      );
    },
  );

  test(
    'current turn still anchors on a non-transfer other-agent reply',
    () {
      // A plain reply from another agent (no transfer) remains a valid anchor.
      final List<Event> events = <Event>[
        Event(
          invocationId: 'inv1',
          author: 'user',
          content: Content.userText('Earlier user message'),
        ),
        Event(
          invocationId: 'inv1',
          author: 'other_agent',
          content: Content.modelText('a plain reply'),
        ),
      ];

      final List<Content> contents = getCurrentTurnContents(
        currentBranch: null,
        events: events,
        agentName: 'test_agent',
      );

      expect(contents, hasLength(1));
      expect(contents[0].parts.first.text, 'For context:');
      expect(
        contents[0].parts[1].text,
        contains('[other_agent] said: a plain reply'),
      );
    },
  );
}
