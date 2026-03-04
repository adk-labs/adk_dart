/// Replay cursor helpers for recorded CLI sessions.
library;

import 'recordings_schema.dart';

/// Cursor-based helper for replaying recorded CLI turns.
class ReplayPlugin {
  /// Creates a replay cursor for [recording].
  ReplayPlugin(this.recording);

  /// Recording currently bound to this cursor.
  final SessionRecording recording;
  int _cursor = 0;

  /// Whether at least one unread turn remains.
  bool get hasNext => _cursor < recording.turns.length;

  /// Returns the next recorded turn and advances the cursor.
  RecordingTurn? nextTurn() {
    if (!hasNext) {
      return null;
    }
    final RecordingTurn turn = recording.turns[_cursor];
    _cursor += 1;
    return turn;
  }

  /// Resets this cursor to the first turn.
  void reset() {
    _cursor = 0;
  }
}
