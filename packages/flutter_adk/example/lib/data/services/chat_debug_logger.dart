import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_adk/flutter_adk.dart';

class ChatDebugLogger {
  const ChatDebugLogger({
    required this.enabled,
    required this.exampleId,
    required this.sessionId,
  });

  final bool enabled;
  final String exampleId;
  final String sessionId;

  void logInfo(String message) {
    if (!enabled) {
      return;
    }
    debugPrint(
      '[ADK_EXAMPLE][${DateTime.now().toIso8601String()}]'
      '[example:$exampleId][session:$sessionId][info] $message',
    );
  }

  void logUserMessage(String text) {
    if (!enabled) {
      return;
    }
    _printJson(<String, Object?>{
      'ts': DateTime.now().toIso8601String(),
      'exampleId': exampleId,
      'sessionId': sessionId,
      'type': 'user_message',
      'text': _truncate(text),
    });
  }

  void logEvent(Event event) {
    if (!enabled) {
      return;
    }

    final String text = _extractText(event.content);
    final List<Map<String, Object?>> functionCalls = event
        .getFunctionCalls()
        .map(
          (FunctionCall call) => <String, Object?>{
            'name': call.name,
            'id': call.id,
            'args': _truncate(_safeEncode(call.args)),
            'willContinue': call.willContinue,
          },
        )
        .toList(growable: false);

    final List<Map<String, Object?>> functionResponses = event
        .getFunctionResponses()
        .map(
          (FunctionResponse response) => <String, Object?>{
            'name': response.name,
            'id': response.id,
            'response': _truncate(_safeEncode(response.response)),
          },
        )
        .toList(growable: false);

    _printJson(<String, Object?>{
      'ts': DateTime.now().toIso8601String(),
      'exampleId': exampleId,
      'sessionId': sessionId,
      'type': 'event',
      'eventId': event.id,
      'invocationId': event.invocationId,
      'author': event.author,
      'partial': event.partial ?? false,
      'finalResponse': event.isFinalResponse(),
      'turnComplete': event.turnComplete,
      'finishReason': event.finishReason,
      'errorCode': event.errorCode,
      'errorMessage': event.errorMessage,
      'text': text.isEmpty ? null : _truncate(text),
      'functionCalls': functionCalls,
      'functionResponses': functionResponses,
      'transferToAgent': event.actions.transferToAgent,
      'escalate': event.actions.escalate,
      'stateDeltaKeys': event.actions.stateDelta.keys.toList(growable: false),
    });
  }

  void logError(Object error, StackTrace stackTrace) {
    if (!enabled) {
      return;
    }
    _printJson(<String, Object?>{
      'ts': DateTime.now().toIso8601String(),
      'exampleId': exampleId,
      'sessionId': sessionId,
      'type': 'error',
      'error': '$error',
      'stackTrace': _truncate('$stackTrace', maxChars: 5000),
    });
  }

  void logUiStatus({
    required String status,
    required String phase,
    String? author,
    String? targetAgent,
  }) {
    if (!enabled) {
      return;
    }
    _printJson(<String, Object?>{
      'ts': DateTime.now().toIso8601String(),
      'exampleId': exampleId,
      'sessionId': sessionId,
      'type': 'ui_status',
      'status': _truncate(status),
      'phase': phase,
      'author': author,
      'targetAgent': targetAgent,
    });
  }

  String _extractText(Content? content) {
    if (content == null) {
      return '';
    }

    final List<String> chunks = <String>[];
    for (final Part part in content.parts) {
      final String? value = part.text;
      if (value == null) {
        continue;
      }
      final String trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        chunks.add(trimmed);
      }
    }
    return chunks.join('\n').trim();
  }

  String _truncate(String value, {int maxChars = 1200}) {
    if (value.length <= maxChars) {
      return value;
    }
    return '${value.substring(0, maxChars)}...[truncated:${value.length - maxChars}]';
  }

  String _safeEncode(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }

  void _printJson(Map<String, Object?> payload) {
    debugPrint('[ADK_EXAMPLE_DEBUG] ${_safeEncode(payload)}');
  }
}
