/// Typed event hierarchy for the cascaded live audio pipeline.
library;

import '../types/content.dart';

/// Base class for events emitted by a [LiveIngress] transform.
///
/// ```dart
/// final IngressEvent event = const UserTurnFinished(text: 'Hello');
/// switch (event) {
///   case PartialTranscript(:final text):
///     print('Partial: $text');
///   case UserTurnFinished(:final text):
///     print('Final: $text');
///   case UserSpeechStarted():
///     print('Speech started');
/// }
/// ```
sealed class IngressEvent {
  /// Creates an ingress event.
  const IngressEvent();

  /// Non-empty transcript text for this event, if applicable.
  String? get text => null;
}

/// Interim transcript emitted while the user is still speaking.
///
/// ```dart
/// final partial = PartialTranscript(text: 'Tell me about');
/// ```
class PartialTranscript extends IngressEvent {
  /// Creates a partial transcript event with [text].
  const PartialTranscript({required this.text});

  /// Interim transcript text.
  @override
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartialTranscript && other.text == text;

  @override
  int get hashCode => Object.hash(PartialTranscript, text);

  @override
  String toString() => 'PartialTranscript(text: $text)';
}

/// Final transcript emitted when the user finishes speaking a turn.
///
/// ```dart
/// final finished = UserTurnFinished(text: 'Tell me about Dart.');
/// ```
class UserTurnFinished extends IngressEvent {
  /// Creates a finished user turn event with [text].
  const UserTurnFinished({required this.text});

  /// Finalized transcript text for the user turn.
  @override
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserTurnFinished && other.text == text;

  @override
  int get hashCode => Object.hash(UserTurnFinished, text);

  @override
  String toString() => 'UserTurnFinished(text: $text)';
}

/// Signal emitted when user speech begins so active agent output can stop.
///
/// ```dart
/// const event = UserSpeechStarted();
/// ```
class UserSpeechStarted extends IngressEvent {
  /// Creates a user-speech-started event.
  const UserSpeechStarted();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UserSpeechStarted;

  @override
  int get hashCode => (UserSpeechStarted).hashCode;

  @override
  String toString() => 'UserSpeechStarted()';
}

/// Base class for events emitted by a [LiveEgress] transform.
///
/// ```dart
/// final EgressEvent event = const AgentSpokenOutput(text: 'Hello there.');
/// switch (event) {
///   case AudioChunk(:final blob):
///     print('Audio bytes: ${blob.data.length}');
///   case AgentSpokenOutput(:final text):
///     print('Spoken: $text');
/// }
/// ```
sealed class EgressEvent {
  /// Creates an egress event.
  const EgressEvent();
}

/// Synthesized audio chunk ready to be streamed to the caller.
///
/// ```dart
/// final chunk = AudioChunk(
///   blob: InlineData(mimeType: 'audio/pcm;rate=24000', data: [0, 1]),
/// );
/// ```
class AudioChunk extends EgressEvent {
  /// Creates an audio chunk event wrapping [blob].
  const AudioChunk({required this.blob});

  /// Binary audio payload and MIME type metadata.
  final InlineData blob;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioChunk &&
          other.blob.mimeType == blob.mimeType &&
          _bytesEqual(other.blob.data, blob.data);

  @override
  int get hashCode =>
      Object.hash(AudioChunk, blob.mimeType, Object.hashAll(blob.data));

  @override
  String toString() =>
      'AudioChunk(mimeType: ${blob.mimeType}, bytes: ${blob.data.length})';
}

/// Text segment whose corresponding audio has been emitted by the TTS stage.
///
/// ```dart
/// const spoken = AgentSpokenOutput(text: 'Hello! ');
/// ```
class AgentSpokenOutput extends EgressEvent {
  /// Creates an agent spoken output event with [text].
  const AgentSpokenOutput({required this.text});

  /// Text segment that was spoken before any interruption.
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentSpokenOutput && other.text == text;

  @override
  int get hashCode => Object.hash(AgentSpokenOutput, text);

  @override
  String toString() => 'AgentSpokenOutput(text: $text)';
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
