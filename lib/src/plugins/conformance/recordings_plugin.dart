/// In-memory recording manager for CLI sessions and turns.
library;

import 'dart:convert';
import 'dart:io';

import 'recordings_schema.dart';

/// In-memory manager for CLI session recordings.
class RecordingsPlugin {
  /// Creates a recording manager backed by [recordings].
  RecordingsPlugin({List<SessionRecording>? recordings})
    : _recordings = recordings ?? <SessionRecording>[];

  final List<SessionRecording> _recordings;

  /// Immutable view of loaded session recordings.
  List<SessionRecording> get recordings =>
      List<SessionRecording>.unmodifiable(_recordings);

  /// Starts a new recording session and appends it to [recordings].
  SessionRecording startSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) {
    final SessionRecording recording = SessionRecording(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
    _recordings.add(recording);
    return recording;
  }

  /// Appends one recorded [turn] to the session identified by [sessionId].
  void appendTurn({required String sessionId, required RecordingTurn turn}) {
    final SessionRecording recording = _recordings.firstWhere(
      (SessionRecording candidate) => candidate.sessionId == sessionId,
      orElse: () => throw StateError('Recording session not found: $sessionId'),
    );
    recording.turns.add(turn);
  }

  /// Removes all loaded recordings.
  void clear() {
    _recordings.clear();
  }

  /// Persists all recordings as formatted JSON at [filePath].
  Future<void> saveToFile(String filePath) async {
    final File file = File(filePath);
    file.parent.createSync(recursive: true);
    final List<Map<String, Object?>> json = _recordings
        .map((SessionRecording recording) => recording.toJson())
        .toList(growable: false);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  /// Loads recordings from [filePath] when the file exists.
  ///
  /// Returns an empty plugin when the file is absent.
  static Future<RecordingsPlugin> loadFromFile(String filePath) async {
    final File file = File(filePath);
    if (!await file.exists()) {
      return RecordingsPlugin();
    }
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) {
      throw const FormatException('Recording file must contain a JSON list.');
    }
    final List<SessionRecording> recordings = decoded
        .whereType<Map>()
        .map(
          (Map item) => SessionRecording.fromJson(
            item.map((Object? key, Object? value) => MapEntry('$key', value)),
          ),
        )
        .toList(growable: false);
    return RecordingsPlugin(recordings: recordings);
  }
}
