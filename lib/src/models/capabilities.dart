/// Capability reporting snapshot for an LLM model instance.
library;

/// Resolved capabilities for an LLM instance.
class LlmCapabilities {
  /// Creates capability settings for an LLM adapter.
  const LlmCapabilities({
    this.outputSchemaAndTools = false,
    this.supportsAudioInput = false,
    this.supportsSystemInstruction = true,
  });

  /// Default fallback capability set.
  static const LlmCapabilities defaultCapabilities = LlmCapabilities();

  /// Whether the model can pair a structured output schema together with tool calling.
  final bool outputSchemaAndTools;

  /// Whether the model natively supports audio inputs.
  final bool supportsAudioInput;

  /// Whether the model supports system instructions.
  final bool supportsSystemInstruction;
}
