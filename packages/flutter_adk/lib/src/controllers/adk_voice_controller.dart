import 'dart:async';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/foundation.dart';

import '../models/adk_voice_state_model.dart';

/// A reactive controller for managing real-time voice input/output state, audio levels, and live turns.
class AdkVoiceController extends ChangeNotifier {
  /// Creates an [AdkVoiceController].
  AdkVoiceController({
    this.agent,
    this.userId = 'voice_user',
    String? sessionId,
    this.onListenStart,
    this.onListenStop,
    this.onSpeak,
    this.onSpeechInterrupt,
  }) : sessionId = sessionId ?? 'voice_session_${DateTime.now().millisecondsSinceEpoch}';

  /// Optional agent associated with this voice session.
  final adk.BaseAgent? agent;

  /// User identifier.
  final String userId;

  /// Session identifier.
  final String sessionId;

  /// Optional delegate called when speech recognition starts.
  final Future<void> Function()? onListenStart;

  /// Optional delegate called when speech recognition stops.
  final Future<String?> Function()? onListenStop;

  /// Optional delegate called to synthesize speech audio from text.
  final Future<void> Function(String text)? onSpeak;

  /// Optional delegate called when speech playback is interrupted.
  final Future<void> Function()? onSpeechInterrupt;

  AdkVoiceState _state = const AdkVoiceState(status: .idle);
  String _userTranscript = '';
  String _agentTranscript = '';
  Timer? _amplitudeTimer;

  /// Current voice state (status, decibels, isMuted, errorMessage).
  AdkVoiceState get state => _state;

  /// Current audio volume / amplitude level (0.0 to 1.0).
  double get decibels => _state.decibels;

  /// Whether the microphone is currently recording.
  bool get isListening => _state.status == .listening;

  /// Whether the AI agent response audio is playing.
  bool get isSpeaking => _state.status == .speaking;

  /// Whether the microphone is muted.
  bool get isMuted => _state.isMuted;

  /// Latest transcribed user speech text.
  String get userTranscript => _userTranscript;

  /// Latest AI agent spoken response text.
  String get agentTranscript => _agentTranscript;

  /// Starts listening to microphone audio and simulates or connects amplitude stream.
  Future<void> startListening() async {
    _state = _state.copyWith(
      status: .listening,
      errorMessage: null,
    );
    notifyListeners();

    if (onListenStart != null) {
      try {
        await onListenStart!();
      } catch (e) {
        _state = _state.copyWith(
          status: .error,
          errorMessage: 'STT start error: $e',
        );
        notifyListeners();
        return;
      }
    }

    _amplitudeTimer?.cancel();
    // Lightweight amplitude pulse simulator for smooth UI reactivity if no native recorder hooked
    double phase = 0.0;
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (Timer t) {
      if (_state.status == .listening && !_state.isMuted) {
        phase += 0.3;
        final double simulatedDecibel = (0.2 + 0.6 * (0.5 + 0.5 * (phase % 3.14).abs())).clamp(0.0, 1.0);
        updateAmplitude(simulatedDecibel);
      }
    });
  }

  /// Stops listening and transitions to processing or idle state.
  Future<void> stopListening() async {
    _amplitudeTimer?.cancel();
    _state = _state.copyWith(
      status: .processing,
      decibels: 0.0,
    );
    notifyListeners();

    if (onListenStop != null) {
      try {
        final String? transcript = await onListenStop!();
        if (transcript != null && transcript.isNotEmpty) {
          updateUserTranscript(transcript);
        }
      } catch (e) {
        _state = _state.copyWith(
          status: .error,
          errorMessage: 'STT stop error: $e',
        );
        notifyListeners();
        return;
      }
    }
  }

  /// Sets audio playback as active when agent speaks.
  Future<void> startSpeaking({String? text}) async {
    if (text != null) _agentTranscript = text;
    _state = _state.copyWith(status: .speaking);
    notifyListeners();

    if (text != null && onSpeak != null) {
      try {
        await onSpeak!(text);
      } catch (e) {
        _state = _state.copyWith(
          status: .error,
          errorMessage: 'TTS playback error: $e',
        );
        notifyListeners();
      }
    }
  }

  /// Finishes speaking and returns to idle state.
  void stopSpeaking() {
    _state = _state.copyWith(status: .idle, decibels: 0.0);
    notifyListeners();
  }

  /// Interrupts ongoing agent speech and immediately returns to listening or idle.
  void interrupt() {
    onSpeechInterrupt?.call();
    _state = _state.copyWith(status: .idle, decibels: 0.0);
    notifyListeners();
  }

  /// Toggles microphone mute state.
  void toggleMute() {
    _state = _state.copyWith(isMuted: !_state.isMuted);
    notifyListeners();
  }

  /// Updates audio amplitude (0.0 to 1.0).
  void updateAmplitude(double level) {
    _state = _state.copyWith(decibels: level.clamp(0.0, 1.0));
    notifyListeners();
  }

  /// Updates transcribed text from user speech.
  void updateUserTranscript(String transcript) {
    _userTranscript = transcript;
    notifyListeners();
  }

  /// Sets custom voice status.
  void setVoiceStatus(AdkVoiceStatus status, {String? errorMessage}) {
    _state = _state.copyWith(
      status: status,
      errorMessage: errorMessage,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    super.dispose();
  }
}
