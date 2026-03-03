/// Lightweight prompt normalization utilities for deterministic optimization.
library;

/// Represents the outcome of a lightweight prompt optimization pass.
class PromptOptimizationResult {
  /// Creates a prompt optimization result.
  PromptOptimizationResult({
    required this.optimizedPrompt,
    this.changed = false,
    this.reason,
  });

  /// Optimized prompt text.
  final String optimizedPrompt;

  /// Whether the optimized prompt differs from the original input.
  final bool changed;

  /// Optional explanation for why the prompt changed or not.
  final String? reason;
}

/// Applies simple deterministic cleanup to prompt text.
class PromptOptimizer {
  /// Normalizes [prompt] and returns the optimization outcome.
  PromptOptimizationResult optimize(String prompt) {
    final String trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      return PromptOptimizationResult(
        optimizedPrompt: prompt,
        changed: false,
        reason: 'Prompt is empty.',
      );
    }

    final String optimized = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    final bool changed = optimized != prompt;
    return PromptOptimizationResult(
      optimizedPrompt: optimized,
      changed: changed,
      reason: changed ? 'Whitespace normalized.' : 'No optimization needed.',
    );
  }
}
