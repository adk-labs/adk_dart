// Tests for recovering compacted function calls during prompt assembly.
// Ported from google/adk-python
// tests/unittests/flows/llm_flows/test_contents.py (commit 0c517e76,
// fix #5602).

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Event _longRunningCallEvent() {
  return Event(
    invocationId: 'inv2',
    author: 'model',
    timestamp: 2.0,
    longRunningToolIds: <String>{'lr-1'},
    content: Content(
      role: 'model',
      parts: <Part>[
        Part(
          functionCall: FunctionCall(
            id: 'lr-1',
            name: 'lr_tool',
            args: <String, dynamic>{},
          ),
        ),
      ],
    ),
  );
}

Event _longRunningResponseEvent(Map<String, String> response, {double timestamp = 4.0}) {
  return Event(
    invocationId: 'inv2',
    author: 'user',
    timestamp: timestamp,
    content: Content(
      role: 'user',
      parts: <Part>[
        Part(
          functionResponse: FunctionResponse(
            id: 'lr-1',
            name: 'lr_tool',
            response: response,
          ),
        ),
      ],
    ),
  );
}

void main() {
  test('getContents recovers a compacted long-running call on resume', () {
    // Reproduces issue #5602: the call and its intermediate placeholder
    // response are summarized away, then the real result arrives on resume.
    // Without recovery, assembly leaves the resumed response with no matching
    // call.
    final EventCompaction compaction = EventCompaction(
      startTimestamp: 1.0,
      endTimestamp: 3.0,
      compactedContent: Content.modelText('summary of earlier turns'),
    );
    final List<Event> events = <Event>[
      Event(
        invocationId: 'inv1',
        author: 'user',
        timestamp: 1.0,
        content: Content.userText('start the long job'),
      ),
      _longRunningCallEvent(),
      // Intermediate placeholder response (same invocation as the call).
      _longRunningResponseEvent(<String, String>{'status': 'pending'},
          timestamp: 3.0),
      Event(
        invocationId: 'compacted',
        author: 'model',
        timestamp: 3.0,
        content: compaction.compactedContent,
        actions: EventActions(compaction: compaction),
      ),
      // Real result delivered on resume; timestamp is outside the compacted
      // range.
      _longRunningResponseEvent(<String, String>{'result': 'done'}),
    ];

    final List<Content> result = getContents(
      currentBranch: null,
      events: events,
      agentName: 'model',
    );

    expect(result, hasLength(3));
    expect(result[0].parts[0].text, 'summary of earlier turns');
    expect(result[1].parts[0].functionCall?.id, 'lr-1');
    expect(result[2].parts[0].functionResponse?.id, 'lr-1');
    expect(
      result[2].parts[0].functionResponse?.response,
      <String, String>{'result': 'done'},
    );
  });

  test('getContents recovers a parallel call and its sibling response', () {
    // The call event issues a long-running call (lr-1) and a regular call
    // (reg-1) together. Both, plus reg-1's response, are compacted; only lr-1
    // is resumed. The whole call event is re-injected (so parallel-call thought
    // signatures on the first part survive), and reg-1's compacted response is
    // restored so reg-1 is not surfaced as a phantom pending call.
    final Event parallelCall = Event(
      invocationId: 'inv2',
      author: 'model',
      timestamp: 2.0,
      longRunningToolIds: <String>{'lr-1'},
      content: Content(
        role: 'model',
        parts: <Part>[
          Part(
            functionCall: FunctionCall(
              id: 'lr-1',
              name: 'lr_tool',
              args: <String, dynamic>{},
            ),
          ),
          Part(
            functionCall: FunctionCall(
              id: 'reg-1',
              name: 'reg_tool',
              args: <String, dynamic>{},
            ),
          ),
        ],
      ),
    );
    final EventCompaction compaction = EventCompaction(
      startTimestamp: 1.0,
      endTimestamp: 3.5,
      compactedContent: Content.modelText('summary'),
    );
    final List<Event> events = <Event>[
      parallelCall,
      // lr-1's placeholder response, compacted.
      _longRunningResponseEvent(<String, String>{'status': 'pending'},
          timestamp: 3.0),
      // reg-1's response, compacted.
      Event(
        invocationId: 'inv2',
        author: 'user',
        timestamp: 3.5,
        content: Content(
          role: 'user',
          parts: <Part>[
            Part(
              functionResponse: FunctionResponse(
                id: 'reg-1',
                name: 'reg_tool',
                response: <String, String>{'result': 'ok'},
              ),
            ),
          ],
        ),
      ),
      Event(
        invocationId: 'compacted',
        author: 'model',
        timestamp: 3.5,
        content: compaction.compactedContent,
        actions: EventActions(compaction: compaction),
      ),
      _longRunningResponseEvent(<String, String>{'result': 'done'}),
    ];

    final List<Content> result = getContents(
      currentBranch: null,
      events: events,
      agentName: 'model',
    );

    // Dart's getContents does not merge parallel function responses into a
    // single content (unlike Python's _get_contents), so responses stay as
    // separate contents: [summary, call(lr-1+reg-1), resp(reg-1), resp(lr-1)].
    // The whole parallel call event is preserved (both parts, so a thought
    // signature on the first part is not stripped).
    final Set<String?> callIds = result
        .expand((Content content) => content.parts)
        .where((Part part) => part.functionCall != null)
        .map((Part part) => part.functionCall!.id)
        .toSet();
    expect(callIds, <String>{'lr-1', 'reg-1'});
    // Both responses are present, so neither call looks pending.
    final Set<String?> responseIds = result
        .expand((Content content) => content.parts)
        .where((Part part) => part.functionResponse != null)
        .map((Part part) => part.functionResponse!.id)
        .toSet();
    expect(responseIds, <String>{'lr-1', 'reg-1'});

    // The single call content carries both parallel calls together (verifying
    // the whole event was re-injected verbatim).
    final Content callContent = result.firstWhere(
      (Content content) => content.parts.any((Part p) => p.functionCall != null),
    );
    final Set<String?> callContentIds = callContent.parts
        .where((Part part) => part.functionCall != null)
        .map((Part part) => part.functionCall!.id)
        .toSet();
    expect(callContentIds, <String>{'lr-1', 'reg-1'});
  });
}
