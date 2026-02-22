class EvalCase {
  EvalCase({
    required this.evalId,
    required this.input,
    this.expectedOutput,
    Map<String, Object?>? metadata,
  }) : metadata = metadata ?? <String, Object?>{};

  final String evalId;
  final String input;
  final String? expectedOutput;
  final Map<String, Object?> metadata;
}
