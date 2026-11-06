/// Coordination barrier between LLM flow steps and runner persistence.
///
/// @docImport '../../runners/runner.dart';
library;

import 'dart:async';

import '../../agents/invocation_context.dart';
import '../../events/event.dart';

const String _enabledKey = 'adk.flows.llm_flows.persist_barrier.enabled';
const String _barriersKey = 'adk.flows.llm_flows.persist_barrier.barriers';

/// Lets multi-step LLM flows wait until the runner has persisted step events.
///
/// The runner is the event persister, while the flow builds follow-up requests
/// from the session event list. This barrier prevents the next flow step from
/// reading a stale session when event persistence is asynchronous or replaced by
/// a custom service.
abstract final class PersistBarrier {
  /// Enables barrier coordination for a runner-driven invocation.
  static void enable(InvocationContext context) {
    context.callbackContextData[_enabledKey] = true;
  }

  /// Completes after all non-null event IDs have been marked persisted.
  ///
  /// Direct flow unit tests usually do not run through [Runner], so the method
  /// is a no-op unless [enable] was called.
  static Future<void> awaitPersisted(
    InvocationContext context,
    List<Event> events,
  ) async {
    if (context.callbackContextData[_enabledKey] != true || context.isAborted) {
      return;
    }
    for (final Event event in events) {
      if (context.isAborted) {
        return;
      }
      final String eventId = event.id;
      if (eventId.isEmpty) {
        continue;
      }
      final Completer<void> barrier = _barrier(context, eventId);
      if (barrier.isCompleted) {
        continue;
      }
      final Completer<void> waiter = Completer<void>();
      void onAbort(Object? _) {
        if (!waiter.isCompleted) {
          waiter.complete();
        }
      }

      context.onAbortSignal.addListener(onAbort);
      unawaited(
        barrier.future.then(
          (_) {
            context.onAbortSignal.removeListener(onAbort);
            if (!waiter.isCompleted) {
              waiter.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            context.onAbortSignal.removeListener(onAbort);
            if (!waiter.isCompleted) {
              waiter.completeError(error, stackTrace);
            }
          },
        ),
      );
      await waiter.future;
    }
  }

  /// Signals that [eventId] was persisted.
  static void markPersisted(InvocationContext context, String? eventId) {
    if (eventId == null || eventId.isEmpty) {
      return;
    }
    final Completer<void> completer = _barrier(context, eventId);
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  /// Signals that persisting [eventId] failed.
  static void markFailed(
    InvocationContext context,
    String? eventId,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    if (eventId == null || eventId.isEmpty) {
      return;
    }
    final Completer<void> completer = _barrier(context, eventId);
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }

  /// Number of awaited or marked events that have not resolved yet.
  static int pendingCount(InvocationContext context) {
    return _barriers(context).values
        .where((Completer<void> completer) => !completer.isCompleted)
        .length;
  }

  static Completer<void> _barrier(InvocationContext context, String eventId) {
    return _barriers(context).putIfAbsent(eventId, () => Completer<void>());
  }

  static Map<String, Completer<void>> _barriers(InvocationContext context) {
    final Object? existing = context.callbackContextData[_barriersKey];
    if (existing is Map<String, Completer<void>>) {
      return existing;
    }
    final Map<String, Completer<void>> created = <String, Completer<void>>{};
    context.callbackContextData[_barriersKey] = created;
    return created;
  }
}
