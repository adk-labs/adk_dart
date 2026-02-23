import '../types/content.dart';

bool isAudioPart(Part part) {
  return (part.inlineData != null &&
          part.inlineData!.mimeType.toLowerCase().startsWith('audio/')) ||
      (part.fileData != null &&
          (part.fileData!.mimeType ?? '').toLowerCase().startsWith('audio/'));
}

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
