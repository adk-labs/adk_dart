import 'package:flutter/widgets.dart';

/// A rich prompt suggestion chip model for [AdkPromptSuggestionsBar].
class AdkPromptSuggestion {
  /// Creates an [AdkPromptSuggestion].
  const AdkPromptSuggestion({
    required this.text,
    this.label,
    this.icon,
    this.category,
    this.metadata = const <String, dynamic>{},
  });

  /// The full prompt string injected into the input bar upon selection.
  final String text;

  /// Optional shorter label displayed on the chip (defaults to [text]).
  final String? label;

  /// Optional leading icon for visual categorization.
  final IconData? icon;

  /// Category or tag (e.g., 'coding', 'general', 'creative').
  final String? category;

  /// Additional metadata.
  final Map<String, dynamic> metadata;

  /// The label to display on screen.
  String get displayLabel => label ?? text;
}
