/// Transcription payload model for multimodal agent flows.
library;

import '../types/content.dart';

/// One transcription entry containing audio/text payload data.
class TranscriptionEntry {
  /// Creates a transcription entry.
  TranscriptionEntry({this.role, required this.data}) {
    if (data is! InlineData && data is! Content) {
      throw ArgumentError(
        'TranscriptionEntry.data must be InlineData or Content.',
      );
    }
  }

  /// Optional role associated with the transcription entry.
  final String? role;

  /// Payload data, either [InlineData] or [Content].
  final Object data;
}
