/// Content-part helpers for multimodal filtering.
library;

import '../types/content.dart';

/// Whether [part] contains audio data.
bool isAudioPart(Part part) {
  return (part.inlineData != null &&
          part.inlineData!.mimeType.toLowerCase().startsWith('audio/')) ||
      (part.fileData != null &&
          (part.fileData!.mimeType ?? '').toLowerCase().startsWith('audio/'));
}

/// Whether [part] references an internal `_adk_live` artifact.
bool isAdkLiveArtifactPart(Part part) {
  final String? fileUri = part.fileData?.fileUri;
  if (fileUri == null) {
    return false;
  }
  return fileUri.startsWith('artifact://') && fileUri.contains('/_adk_live/');
}

/// The [content] copy without audio parts.
///
/// Returns `null` when [content] is empty or all parts are audio.
Content? filterAudioParts(Content content) {
  if (content.parts.isEmpty) {
    return null;
  }
  final List<Part> filtered = content.parts
      .where((Part part) => !isAudioPart(part))
      .map((Part part) => part.copyWith())
      .toList(growable: false);
  if (filtered.isEmpty) {
    return null;
  }
  return Content(role: content.role, parts: filtered);
}

/// Filters media parts out of history replayed to a live connection.
///
/// Removes internal `_adk_live` artifact references (audio and other media
/// persisted when `save_live_blob` is enabled) and any remaining audio parts.
/// Inline image and video parts (e.g. sent via `send_content`) are kept.
Content? filterMediaParts(Content content) {
  if (content.parts.isEmpty) {
    return null;
  }
  final List<Part> filtered = content.parts
      .where((Part part) => !isAudioPart(part) && !isAdkLiveArtifactPart(part))
      .map((Part part) => part.copyWith())
      .toList(growable: false);
  if (filtered.isEmpty) {
    return null;
  }
  return Content(role: content.role, parts: filtered);
}

/// Extracts non-thought text from [content] joined by [separator].
///
/// Returns `null` when [content] is `null` or contains no non-empty non-thought
/// text parts.
String? extractTextFromContent(Content? content, {String separator = ' '}) {
  if (content == null || content.parts.isEmpty) {
    return null;
  }
  final List<String> texts = <String>[];
  for (final Part part in content.parts) {
    if (part.thought) {
      continue;
    }
    final String? text = part.text;
    if (text != null && text.isNotEmpty) {
      texts.add(text);
    }
  }
  if (texts.isEmpty) {
    return null;
  }
  return texts.join(separator);
}


