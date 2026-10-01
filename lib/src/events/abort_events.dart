/// Helpers for sealing an aborted invocation in session history.
library;

import '../types/content.dart';
import 'event.dart';

/// Error code assigned to synthetic abort events.
const String invocationAbortedErrorCode = 'INVOCATION_ABORTED';

/// Default error message for synthetic abort events.
const String invocationAbortedErrorMessage = 'Invocation was aborted by client.';

/// Returns whether [event] was synthesized to seal an aborted invocation.
bool isAbortEvent(Event event) {
  return event.errorCode == invocationAbortedErrorCode;
}

/// Whether a task agent already paused on this event to wait for the user.
bool isPausedTaskReply(Event event) {
  final String? scope = event.isolationScope;
  return (scope != null && scope.isNotEmpty) &&
      event.author != 'user' &&
      event.isFinalResponse();
}

/// Returns the events that seal an aborted invocation.
///
/// Each dangling function call gets a synthetic error response carrying the
/// author, branch and isolation scope of the event that issued it, so the
/// response pairs with its call in the issuing agent's own view. Calls sharing
/// those three values are grouped into one event. If nothing is dangling, a
/// single content-less abort event authored by the root agent is returned instead.
List<Event> buildAbortEvents(
  List<Event> events, {
  required String invocationId,
  required String rootAgentName,
  String? branch,
}) {
  final List<Event> invocationEvents = events
      .where((Event e) => e.invocationId == invocationId)
      .toList();

  if (invocationEvents.isNotEmpty && isPausedTaskReply(invocationEvents.last)) {
    return <Event>[];
  }

  final Set<String> answeredCallIds = <String>{};
  for (final Event event in invocationEvents) {
    final Content? content = event.content;
    if (content != null) {
      for (final Part part in content.parts) {
        final String? id = part.functionResponse?.id;
        if (id != null && id.isNotEmpty) {
          answeredCallIds.add(id);
        }
      }
    }
  }

  final Map<String, ({String author, String? branch, String? isolationScope, List<FunctionCall> calls})>
      groupedCalls =
      <String, ({String author, String? branch, String? isolationScope, List<FunctionCall> calls})>{};

  for (final Event event in invocationEvents) {
    final Content? content = event.content;
    if (content == null) {
      continue;
    }
    for (final Part part in content.parts) {
      final FunctionCall? fc = part.functionCall;
      if (fc != null && fc.id != null && fc.id!.isNotEmpty && !answeredCallIds.contains(fc.id)) {
        final String effectiveBranch = event.branch ?? branch ?? '';
        final String effectiveScope = event.isolationScope ?? '';
        final String key = '${event.author}::$effectiveBranch::$effectiveScope';

        final existing = groupedCalls[key];
        if (existing == null) {
          groupedCalls[key] = (
            author: event.author,
            branch: event.branch ?? branch,
            isolationScope: event.isolationScope,
            calls: <FunctionCall>[fc],
          );
        } else {
          existing.calls.add(fc);
        }
      }
    }
  }

  if (groupedCalls.isEmpty) {
    return <Event>[
      Event(
        invocationId: invocationId,
        author: rootAgentName,
        branch: branch,
        errorCode: invocationAbortedErrorCode,
        errorMessage: invocationAbortedErrorMessage,
      ),
    ];
  }

  return groupedCalls.values.map((group) {
    return Event(
      invocationId: invocationId,
      author: group.author,
      branch: group.branch,
      isolationScope: group.isolationScope,
      content: Content(
        role: 'user',
        parts: group.calls.map((FunctionCall fc) {
          return Part.fromFunctionResponse(
            id: fc.id!,
            name: fc.name,
            response: <String, Object?>{'error': invocationAbortedErrorMessage},
          );
        }).toList(),
      ),
      errorCode: invocationAbortedErrorCode,
      errorMessage: invocationAbortedErrorMessage,
    );
  }).toList();
}
