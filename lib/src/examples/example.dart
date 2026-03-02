/// Few-shot example model definitions.
library;

import '../types/content.dart';

/// A few-shot example with user input and expected model output sequence.
class Example {
  /// Creates a few-shot [Example].
  Example({required Content input, required List<Content> output})
    : input = input.copyWith(),
      output = output
          .map((Content content) => content.copyWith())
          .toList(growable: false);

  /// Example input content.
  final Content input;

  /// Expected output sequence.
  final List<Content> output;

  /// Returns a copied example with optional overrides.
  Example copyWith({Content? input, List<Content>? output}) {
    return Example(
      input: input ?? this.input.copyWith(),
      output:
          output ??
          this.output
              .map((Content content) => content.copyWith())
              .toList(growable: false),
    );
  }
}
