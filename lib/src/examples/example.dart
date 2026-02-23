import '../types/content.dart';

/// A few-shot example with user input and expected model output sequence.
class Example {
  Example({required Content input, required List<Content> output})
    : input = input.copyWith(),
      output = output
          .map((Content content) => content.copyWith())
          .toList(growable: false);

  final Content input;
  final List<Content> output;

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
