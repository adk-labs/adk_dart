/// Operational status of an interactive voice input session.
enum AdkVoiceStatus {
  /// Mic is idle and not capturing.
  idle,

  /// Mic is actively listening and recording audio.
  listening,

  /// Speech is being transcribed or processed by the agent.
  processing,

  /// Agent audio response is currently playing.
  speaking,

  /// An error occurred during audio recording/transcription.
  error,
}

/// State model for [AdkVoiceMicButton] and [AdkAudioWaveVisualizer].
class AdkVoiceState {
  /// Creates an [AdkVoiceState].
  const AdkVoiceState({
    this.status = .idle,
    this.decibels = 0.0,
    this.isMuted = false,
    this.errorMessage,
  });

  /// The active voice status.
  final AdkVoiceStatus status;

  /// Current audio amplitude / volume level (0.0 to 1.0 or dB normalized).
  final double decibels;

  /// Whether the microphone is currently muted.
  final bool isMuted;

  /// Error message if [status] is [AdkVoiceStatus.error].
  final String? errorMessage;

  /// Whether recording or playback is active.
  bool get isActive =>
      status == .listening ||
      status == .processing ||
      status == .speaking;

  /// Copies this [AdkVoiceState] with updated values.
  AdkVoiceState copyWith({
    AdkVoiceStatus? status,
    double? decibels,
    bool? isMuted,
    String? errorMessage,
  }) {
    return AdkVoiceState(
      status: status ?? this.status,
      decibels: decibels ?? this.decibels,
      isMuted: isMuted ?? this.isMuted,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
