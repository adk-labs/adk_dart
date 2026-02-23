import 'recordings_schema.dart';

class ReplayPlugin {
  ReplayPlugin(this.recording);

  final SessionRecording recording;
  int _cursor = 0;

  bool get hasNext => _cursor < recording.turns.length;

  RecordingTurn? nextTurn() {
    if (!hasNext) {
      return null;
    }
    final RecordingTurn turn = recording.turns[_cursor];
    _cursor += 1;
    return turn;
  }

  void reset() {
    _cursor = 0;
  }
}
