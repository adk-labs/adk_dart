import '../types/content.dart';

class TranscriptionEntry {
  TranscriptionEntry({this.role, required this.data}) {
    if (data is! InlineData && data is! Content) {
      throw ArgumentError(
        'TranscriptionEntry.data must be InlineData or Content.',
      );
    }
  }

  final String? role;
  final Object data;
}
