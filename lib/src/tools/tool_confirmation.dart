/// Captures confirmation state for tools that require user approval.
class ToolConfirmation {
  /// Creates a tool confirmation payload.
  ToolConfirmation({this.hint, this.payload, this.confirmed});

  /// Human-readable confirmation hint shown to the user.
  String? hint;

  /// Optional payload associated with the confirmation request.
  Object? payload;

  /// Whether the user confirmed the request.
  bool? confirmed;
}
