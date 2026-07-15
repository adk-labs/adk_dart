import 'event.dart';

/// Returns [events] with rewound invocations removed.
///
/// Iterates backward. When an event carries
/// `actions.rewindBeforeInvocationId == X`, drops that event together with
/// every event between it and the earliest event of invocation `X` (inclusive),
/// then resumes the backward walk from there.
///
/// This is the single source of truth for "which events are live" after rewinds.
/// Both LLM prompt building and context compaction must agree on it, otherwise
/// rewound content can leak back into prompts through a compaction summary.
List<Event> applyRewinds(List<Event> events) {
  final List<Event> kept = <Event>[];
  int i = events.length - 1;
  while (i >= 0) {
    final Event event = events[i];
    final String? rewindInvocationId = event.actions.rewindBeforeInvocationId;
    if (rewindInvocationId != null && rewindInvocationId.isNotEmpty) {
      int j = 0;
      while (j < i) {
        if (events[j].invocationId == rewindInvocationId) {
          i = j;
          break;
        }
        j++;
      }
    } else {
      kept.add(event);
    }
    i--;
  }
  return kept.reversed.toList();
}
