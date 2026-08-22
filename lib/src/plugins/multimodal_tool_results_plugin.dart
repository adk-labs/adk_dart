/// Plugin hooks and implementations for ADK runtime pipelines.
library;

import '../agents/callback_context.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../tools/base_tool.dart';
import '../tools/tool_context.dart';
import '../types/content.dart';
import 'base_plugin.dart';

/// State key used to store tool-returned multimodal [Part] values.
const String partsReturnedByToolsStateKey = 'temp:PARTS_RETURNED_BY_TOOLS_ID';

/// State key used to store session-retained multimodal parts across turns.
const String sessionPartsReturnedByToolsStateKey =
    'multimodal_tool_results_plugin:PARTS_RETURNED_BY_TOOLS_ID';

const String _currentTurnPartsKey =
    'temp:multimodal_tool_results_plugin:current_turn_parts';
const String _sessionUpdatedKey =
    'temp:multimodal_tool_results_plugin:updated_in_invocation';

/// Retention policy for multimodal tool results.
enum MultimodalToolResultsRetention {
  /// Attaches saved parts once on the next model call and then clears them.
  nextModelCall,

  /// Keeps re-attaching saved file_data and text parts across session turns.
  session,
}

Map<String, Object?> _partToJson(Part part) {
  return <String, Object?>{
    if (part.text != null) 'text': part.text,
    if (part.thought) 'thought': true,
    if (part.thoughtSignature != null) 'thought_signature': part.thoughtSignature,
    if (part.fileData != null)
      'file_data': <String, Object?>{
        'file_uri': part.fileData!.fileUri,
        if (part.fileData!.mimeType != null) 'mime_type': part.fileData!.mimeType,
        if (part.fileData!.displayName != null)
          'display_name': part.fileData!.displayName,
      },
    if (part.inlineData != null)
      'inline_data': <String, Object?>{
        'mime_type': part.inlineData!.mimeType,
        'data': part.inlineData!.data,
        if (part.inlineData!.displayName != null)
          'display_name': part.inlineData!.displayName,
      },
  };
}

Part _partFromJson(Map<String, Object?> map) {
  final Object? fileDataObj = map['file_data'] ?? map['fileData'];
  if (fileDataObj is Map) {
    return Part.fromFileData(
      fileUri: (fileDataObj['file_uri'] ?? fileDataObj['fileUri'] ?? '')
          .toString(),
      mimeType: (fileDataObj['mime_type'] ?? fileDataObj['mimeType'])
          ?.toString(),
      displayName: (fileDataObj['display_name'] ?? fileDataObj['displayName'])
          ?.toString(),
    );
  }
  final Object? inlineDataObj = map['inline_data'] ?? map['inlineData'];
  if (inlineDataObj is Map) {
    final Object? rawData = inlineDataObj['data'];
    final List<int> bytes = rawData is List
        ? rawData.whereType<int>().toList()
        : <int>[];
    return Part.fromInlineData(
      mimeType: (inlineDataObj['mime_type'] ?? inlineDataObj['mimeType'] ?? '')
          .toString(),
      data: bytes,
      displayName: (inlineDataObj['display_name'] ??
              inlineDataObj['displayName'])
          ?.toString(),
    );
  }
  final String? text = map['text']?.toString();
  return Part.text(
    text ?? '',
    thought: map['thought'] == true,
  );
}

List<Part>? _extractParts(Object? value) {
  if (value is Part) {
    return <Part>[value];
  }
  if (value is List) {
    if (value.isEmpty) {
      return null;
    }
    if (value.every((Object? item) => item is Part)) {
      return value.cast<Part>().toList(growable: false);
    }
  }
  return null;
}

List<Part>? _deserializeSavedParts(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is List) {
    final List<Part> list = <Part>[];
    for (final Object? item in value) {
      if (item is Part) {
        list.add(item);
      } else if (item is Map) {
        list.add(_partFromJson(Map<String, Object?>.from(item)));
      }
    }
    return list;
  }
  return _extractParts(value);
}

bool _isSamePart(Part a, Part b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.text != null && b.text != null) {
    return a.text == b.text && a.thought == b.thought;
  }
  if (a.fileData != null && b.fileData != null) {
    return a.fileData!.fileUri == b.fileData!.fileUri;
  }
  return false;
}

/// Persists multimodal tool results and reattaches them before model calls.
class MultimodalToolResultsPlugin extends BasePlugin {
  /// Creates a multimodal tool results plugin.
  MultimodalToolResultsPlugin({
    super.name = 'multimodal_tool_results_plugin',
    Object retention = 'next_model_call',
  }) : _retention = _parseRetention(retention);

  final MultimodalToolResultsRetention _retention;

  static MultimodalToolResultsRetention _parseRetention(Object retention) {
    if (retention is MultimodalToolResultsRetention) {
      return retention;
    }
    if (retention == 'next_model_call') {
      return MultimodalToolResultsRetention.nextModelCall;
    }
    if (retention == 'session') {
      return MultimodalToolResultsRetention.session;
    }
    throw ArgumentError(
      "retention must be 'next_model_call' or 'session', got $retention",
    );
  }

  /// Retention policy for tool-returned multimodal parts.
  MultimodalToolResultsRetention get retention => _retention;

  /// Captures multimodal parts returned by tools in callback state.
  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    List<Part>? parts = _extractParts(result);
    parts ??= _extractParts(result['result']);

    if (parts == null || parts.isEmpty) {
      return result;
    }

    if (_retention == MultimodalToolResultsRetention.session) {
      final List<Part> sessionParts = <Part>[];
      for (final Part p in parts) {
        if (p.inlineData == null) {
          sessionParts.add(p);
        }
      }

      if (sessionParts.isNotEmpty) {
        final List<Map<String, Object?>> serialized = sessionParts
            .map((Part p) => _partToJson(p))
            .toList();
        if (toolContext.state.containsKey(_sessionUpdatedKey)) {
          final Object? current =
              toolContext.state[sessionPartsReturnedByToolsStateKey];
          final List<Object?> list = current is List
              ? List<Object?>.from(current)
              : <Object?>[];
          list.addAll(serialized);
          toolContext.state[sessionPartsReturnedByToolsStateKey] = list;
        } else {
          toolContext.state[_sessionUpdatedKey] = true;
          toolContext.state[sessionPartsReturnedByToolsStateKey] = serialized;
        }
      }

      if (toolContext.state.containsKey(_currentTurnPartsKey)) {
        final Object? current = toolContext.state[_currentTurnPartsKey];
        final List<Part> list = _extractParts(current) ?? <Part>[];
        list.addAll(parts);
        toolContext.state[_currentTurnPartsKey] = list;
      } else {
        toolContext.state[_currentTurnPartsKey] = parts;
      }
    } else {
      final Object? saved = toolContext.state[partsReturnedByToolsStateKey];
      final List<Part> merged = <Part>[];
      final List<Part>? existing = _extractParts(saved);
      if (existing != null) {
        merged.addAll(existing);
      }
      merged.addAll(parts.map((Part part) => part.copyWith()));
      toolContext.state[partsReturnedByToolsStateKey] = merged;
    }

    return null;
  }

  /// Appends previously captured multimodal parts to the latest user turn.
  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    if (llmRequest.contents.isEmpty) {
      return null;
    }

    if (_retention == MultimodalToolResultsRetention.session) {
      final List<Part> sessionParts = <Part>[];
      final Object? saved =
          callbackContext.state[sessionPartsReturnedByToolsStateKey];
      if (saved != null) {
        final List<Part>? extracted = _deserializeSavedParts(saved);
        if (extracted != null) {
          sessionParts.addAll(extracted);
        }
      }

      final List<Part> currentParts = <Part>[];
      if (callbackContext.state.containsKey(_currentTurnPartsKey)) {
        final Object? current =
            callbackContext.state[_currentTurnPartsKey];
        final List<Part>? extracted = _extractParts(current);
        if (extracted != null) {
          currentParts.addAll(extracted);
        }
      }

      final List<Part> filteredSessionParts = sessionParts
          .where((Part sp) => !currentParts.any((Part cp) => _isSamePart(cp, sp)))
          .toList();

      final List<Part> partsToAttach = <Part>[
        ...filteredSessionParts,
        ...currentParts,
      ];

      if (currentParts.isNotEmpty) {
        callbackContext.state[_currentTurnPartsKey] = <Part>[];
      }

      if (partsToAttach.isNotEmpty) {
        llmRequest.contents.last.parts.addAll(
          partsToAttach.map((Part p) => p.copyWith()),
        );
      }
    } else {
      final List<Part>? savedParts = _extractParts(
        callbackContext.state[partsReturnedByToolsStateKey],
      );
      if (savedParts != null && savedParts.isNotEmpty) {
        llmRequest.contents.last.parts.addAll(
          savedParts.map((Part part) => part.copyWith()),
        );
        callbackContext.state[partsReturnedByToolsStateKey] = <Part>[];
      }
    }
    return null;
  }
}
