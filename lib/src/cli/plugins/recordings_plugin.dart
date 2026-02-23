import 'dart:convert';
import 'dart:io';

import 'recordings_schema.dart';

class RecordingsPlugin {
  RecordingsPlugin({List<SessionRecording>? recordings})
    : _recordings = recordings ?? <SessionRecording>[];

  final List<SessionRecording> _recordings;

  List<SessionRecording> get recordings =>
      List<SessionRecording>.unmodifiable(_recordings);

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

  void appendTurn({required String sessionId, required RecordingTurn turn}) {
    final SessionRecording recording = _recordings.firstWhere(
      (SessionRecording candidate) => candidate.sessionId == sessionId,
      orElse: () => throw StateError('Recording session not found: $sessionId'),
    );
    recording.turns.add(turn);
  }

  void clear() {
    _recordings.clear();
  }

  Future<void> saveToFile(String filePath) async {
    final File file = File(filePath);
    file.parent.createSync(recursive: true);
    final List<Map<String, Object?>> json = _recordings
        .map((SessionRecording recording) => recording.toJson())
        .toList(growable: false);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

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
