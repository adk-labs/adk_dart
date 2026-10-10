/// Speech-to-text and text-to-speech stream transform contracts.
library;

import 'dart:async';

import '../types/content.dart';
import 'cascade_live_events.dart';

/// Cooperative cancellation signal passed to [LiveEgress] transforms.
///
/// ```dart
/// final cancel = CancelSignal();
/// cancel.set();
/// print(cancel.isSet); // true
/// cancel.reset();
/// ```
class CancelSignal {
  /// Creates an unset cancellation signal.
  CancelSignal();

  Completer<void> _completer = Completer<void>();

  /// Whether cancellation has been requested.
  bool get isSet => _completer.isCompleted;

  /// Future that completes when [set] is called.
  Future<void> get onSet => _completer.future;

  /// Waits until [set] is called.
  Future<void> wait() => _completer.future;

  /// Signals cancellation to any listeners.
  void set() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  /// Resets the signal to an unset state.
  void reset() {
    if (_completer.isCompleted) {
      _completer = Completer<void>();
    }
  }

  /// Alias for [reset] matching `asyncio.Event.clear()`.
  void clear() => reset();
}

/// Speech-to-text stream transform converting audio chunks to [IngressEvent]s.
///
/// ```dart
/// class EchoIngress extends LiveIngress {
///   @override
///   Stream<IngressEvent> call(Stream<InlineData> audio) async* {
///     await for (final _ in audio) {
///       yield const UserTurnFinished(text: 'hello');
///     }
///   }
/// }
/// ```
abstract class LiveIngress {
  /// Creates a [LiveIngress] transform.
  const LiveIngress();

  /// Transforms an input stream of [audio] blobs into [IngressEvent]s.
  Stream<IngressEvent> call(Stream<InlineData> audio);
}

/// Text-to-speech stream transform converting text deltas to [EgressEvent]s.
///
/// ```dart
/// classSilentEgress extends LiveEgress {
///   @override
///   Stream<EgressEvent> call(
///     Stream<String> text, {
///     required CancelSignal cancel,
///   }) async* {
///     await for (final chunk in text) {
///       if (cancel.isSet) break;
///       yield AgentSpokenOutput(text: chunk);
///     }
///   }
/// }
/// ```
abstract class LiveEgress {
  /// Creates a [LiveEgress] transform.
  const LiveEgress();

  /// Transforms an input stream of [text] deltas into [EgressEvent]s until
  /// completed or [cancel] is set.
  Stream<EgressEvent> call(
    Stream<String> text, {
    required CancelSignal cancel,
  });
}
