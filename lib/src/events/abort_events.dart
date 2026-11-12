/// Helpers for sealing an aborted invocation in session history.
library;

import '../agents/llm/task/finish_task_tool.dart';
import '../types/content.dart';
import 'event.dart';

/// Error code assigned to synthetic abort events.
const String invocationAbortedErrorCode = 'INVOCATION_ABORTED';

/// Default error message for synthetic abort events.
const String invocationAbortedErrorMessage =
    'Invocation was aborted by client.';

/// Returns whether [event] was synthesized to seal an aborted invocation.
bool isAbortEvent(Event event) {
  return event.errorCode == invocationAbortedErrorCode;
}

/// Whether a task agent already paused on [event] to wait for the user.
///
/// When [invocationEvents] is provided, returns `false` if the task isolation
/// scope has already emitted a terminal `finish_task` response (so a trailing
/// `afterAgentCallback` event is not mistaken for a paused task reply).
bool isPausedTaskReply(Event event, {List<Event>? invocationEvents}) {
  final String? scope = event.isolationScope;
  if (scope == null ||
      scope.isEmpty ||
      event.author == 'user' ||
      !event.isFinalResponse()) {
    return false;
  }
  if (invocationEvents != null &&
      invocationEvents.any(
        (Event candidate) =>
            candidate.isolationScope == scope &&
            isFinishTaskTerminalFr(candidate),
      )) {
    return false;
  }
  return true;
}

/// Returns whether [events] has any function calls in [invocationId] without a
/// matching function response, excluding call IDs in [keepOpen].
bool hasUnsealedToolCalls(
  List<Event> events, {
  required String invocationId,
  Set<String> keepOpen = const <String>{},
}) {
  final Set<String> answeredCallIds = <String>{};
  final Set<String> callIds = <String>{};
  for (final Event event in events) {
    if (event.invocationId != invocationId) {
      continue;
    }
    final Content? content = event.content;
    if (content == null) {
      continue;
    }
    for (final Part part in content.parts) {
      final String? callId = part.functionCall?.id;
      if (callId != null && callId.isNotEmpty) {
        callIds.add(callId);
      }
      final String? responseId = part.functionResponse?.id;
      if (responseId != null && responseId.isNotEmpty) {
        answeredCallIds.add(responseId);
      }
    }
  }
  return callIds.difference(answeredCallIds).difference(keepOpen).isNotEmpty;
}

/// Returns the events that seal an aborted invocation.
///
/// Each dangling function call gets a synthetic error response carrying the
/// author, branch and isolation scope of the event that issued it, so the
/// response pairs with its call in the issuing agent's own view. Calls sharing
/// those three values are grouped into one event.
///
/// Dangling call IDs in [keepOpen] are left unsealed so the invocation can
/// resume later; if every dangling call is in [keepOpen], an empty list is
/// returned. Otherwise, if nothing is dangling, a single content-less abort
/// event authored by [rootAgentName] is returned.
List<Event> buildAbortEvents(
  List<Event> events, {
  required String invocationId,
  required String rootAgentName,
  String? branch,
  Set<String> keepOpen = const <String>{},
}) {
  final List<Event> invocationEvents = events
      .where((Event e) => e.invocationId == invocationId)
      .toList();

  if (invocationEvents.isNotEmpty &&
      isPausedTaskReply(
        invocationEvents.last,
        invocationEvents: invocationEvents,
      )) {
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

  final Map<
    String,
    ({
      String author,
      String? branch,
      String? isolationScope,
      List<FunctionCall> calls,
    })
  >
  groupedCalls =
      <
        String,
        ({
          String author,
          String? branch,
          String? isolationScope,
          List<FunctionCall> calls,
        })
      >{};

  bool keptOpen = false;
  for (final Event event in invocationEvents) {
    for (final FunctionCall fc in event.getFunctionCalls()) {
      final String? callId = fc.id;
      if (callId == null ||
          callId.isEmpty ||
          answeredCallIds.contains(callId)) {
        continue;
      }
      if (keepOpen.contains(callId)) {
        keptOpen = true;
        continue;
      }
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

  if (groupedCalls.isEmpty) {
    if (keptOpen) {
      return <Event>[];
    }
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
