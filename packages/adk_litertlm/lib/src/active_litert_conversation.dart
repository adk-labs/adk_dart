import 'package:adk_dart/adk_dart.dart' as adk;
import 'package:collection/collection.dart';
import 'package:litertlm/litertlm.dart' as litert;

/// Tracks the active LiteRT-LM conversation session and matches history for KV cache reuse.
class ActiveLiteRtLmConversation {
  litert.Conversation? conversation;
  List<adk.Content>? history;

  /// Updates the active conversation and its history.
  void update(litert.Conversation conversation, List<adk.Content> history) {
    this.conversation = conversation;
    this.history = history;
  }

  /// Checks if the active conversation history matches the given history.
  bool matches(List<adk.Content> history) {
    if (conversation == null || this.history == null) return false;
    return _isHistoryEqual(this.history!, history);
  }

  /// Closes the active conversation and clears the conversation history.
  void clear() {
    conversation?.dispose();
    conversation = null;
    history = null;
  }

  bool _isHistoryEqual(List<adk.Content> a, List<adk.Content> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_isContentEqual(a[i], b[i])) return false;
    }
    return true;
  }

  bool _isContentEqual(adk.Content a, adk.Content b) {
    if (a.role != b.role) return false;
    if (a.parts.length != b.parts.length) return false;
    for (var i = 0; i < a.parts.length; i++) {
      if (!_isPartEqual(a.parts[i], b.parts[i])) return false;
    }
    return true;
  }

  bool _isPartEqual(adk.Part a, adk.Part b) {
    if (a.text != b.text) return false;
    if (a.thought != b.thought) return false;
    if (!_isFunctionCallEqual(a.functionCall, b.functionCall)) return false;
    if (!_isFunctionResponseEqual(a.functionResponse, b.functionResponse)) {
      return false;
    }
    if (!_isInlineDataEqual(a.inlineData, b.inlineData)) return false;
    if (!_isFileDataEqual(a.fileData, b.fileData)) return false;
    return true;
  }

  bool _isFunctionCallEqual(adk.FunctionCall? a, adk.FunctionCall? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.name != b.name) return false;
    return const DeepCollectionEquality().equals(a.args, b.args);
  }

  bool _isFunctionResponseEqual(
    adk.FunctionResponse? a,
    adk.FunctionResponse? b,
  ) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.name != b.name) return false;
    return const DeepCollectionEquality().equals(a.response, b.response);
  }

  bool _isInlineDataEqual(adk.InlineData? a, adk.InlineData? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.mimeType != b.mimeType) return false;
    return const ListEquality().equals(a.data, b.data);
  }

  bool _isFileDataEqual(adk.FileData? a, adk.FileData? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.fileUri != b.fileUri) return false;
    if (a.mimeType != b.mimeType) return false;
    return true;
  }
}
