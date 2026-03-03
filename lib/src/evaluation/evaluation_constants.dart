/// Canonical keys used by evaluation fixtures and intermediate payloads.
class EvalConstants {
  /// Query text key.
  static const String query = 'query';

  /// Expected tool trajectory key.
  static const String expectedToolUse = 'expected_tool_use';

  /// Response text key.
  static const String response = 'response';

  /// Reference answer key.
  static const String reference = 'reference';

  /// Tool name key.
  static const String toolName = 'tool_name';

  /// Tool input key.
  static const String toolInput = 'tool_input';

  /// Mock tool output key.
  static const String mockToolOutput = 'mock_tool_output';
}
