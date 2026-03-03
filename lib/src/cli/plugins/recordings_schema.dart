import 'dart:convert';

/// One recorded user/assistant turn for CLI replay workflows.
class RecordingTurn {
  /// Creates a recording turn entry.
  RecordingTurn({
    required this.userText,
    this.replyText,
    Map<String, Object?>? metadata,
  }) : metadata = metadata ?? <String, Object?>{};

  /// User input text.
  final String userText;

  /// Assistant reply text, when captured.
  final String? replyText;

  /// Additional structured metadata.
  final Map<String, Object?> metadata;

  /// Encodes this turn for persistence.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'user_text': userText,
      'reply_text': replyText,
      'metadata': metadata,
    };
  }

  /// Decodes a recording turn from JSON.
  factory RecordingTurn.fromJson(Map<String, Object?> json) {
    return RecordingTurn(
      userText: '${json['user_text'] ?? ''}',
      replyText: json['reply_text'] as String?,
      metadata:
          (json['metadata'] as Map?)?.map(
            (Object? key, Object? value) => MapEntry('$key', value),
          ) ??
          <String, Object?>{},
    );
  }
}

/// Full session recording used by CLI record/replay plugins.
class SessionRecording {
  /// Creates a session recording.
  SessionRecording({
    required this.appName,
    required this.userId,
    required this.sessionId,
    List<RecordingTurn>? turns,
  }) : turns = turns ?? <RecordingTurn>[];

  /// Application name.
  final String appName;

  /// User identifier.
  final String userId;

  /// Session identifier.
  final String sessionId;

  /// Recorded turns in chronological order.
  final List<RecordingTurn> turns;

  /// Encodes this recording for persistence.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'app_name': appName,
      'user_id': userId,
      'session_id': sessionId,
      'turns': turns.map((RecordingTurn turn) => turn.toJson()).toList(),
    };
  }

  /// Decodes a session recording from JSON.
  factory SessionRecording.fromJson(Map<String, Object?> json) {
    return SessionRecording(
      appName: '${json['app_name'] ?? ''}',
      userId: '${json['user_id'] ?? ''}',
      sessionId: '${json['session_id'] ?? ''}',
      turns:
          (json['turns'] as List?)
              ?.whereType<Map>()
              .map(
                (Map item) => RecordingTurn.fromJson(
                  item.map(
                    (Object? key, Object? value) => MapEntry('$key', value),
                  ),
                ),
              )
              .toList(growable: false) ??
          <RecordingTurn>[],
    );
  }

  /// Encodes this recording as pretty-printed JSON text.
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
