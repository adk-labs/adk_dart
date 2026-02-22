class PromptOptimizationResult {
  PromptOptimizationResult({
    required this.optimizedPrompt,
    this.changed = false,
    this.reason,
  });

  final String optimizedPrompt;
  final bool changed;
  final String? reason;
}

class PromptOptimizer {
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
