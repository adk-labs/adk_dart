import 'dart:convert';

class RecordingTurn {
  RecordingTurn({
    required this.userText,
    this.replyText,
    Map<String, Object?>? metadata,
  }) : metadata = metadata ?? <String, Object?>{};

  final String userText;
  final String? replyText;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'user_text': userText,
      'reply_text': replyText,
      'metadata': metadata,
    };
  }

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

class SessionRecording {
  SessionRecording({
    required this.appName,
    required this.userId,
    required this.sessionId,
    List<RecordingTurn>? turns,
  }) : turns = turns ?? <RecordingTurn>[];

  final String appName;
  final String userId;
  final String sessionId;
  final List<RecordingTurn> turns;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'app_name': appName,
      'user_id': userId,
      'session_id': sessionId,
      'turns': turns.map((RecordingTurn turn) => turn.toJson()).toList(),
    };
  }

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

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
