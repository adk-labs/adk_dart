import 'dart:convert';

/// Captures confirmation state for tools that require user approval.
class ToolConfirmation {
  /// Creates a tool confirmation payload.
  ToolConfirmation({
    this.hint = '',
    this.payload,
    bool? confirmed,
  }) : confirmed = confirmed ?? false;

  /// Creates a [ToolConfirmation] from a JSON map.
  ///
  /// Null-valued keys for `hint` and `confirmed` are omitted so defaults apply.
  factory ToolConfirmation.fromJson(Map<String, dynamic> json) {
    final Object? rawHint = json['hint'];
    final Object? rawConfirmed = json['confirmed'];
    return ToolConfirmation(
      hint: rawHint is String ? rawHint : '',
      payload: json['payload'],
      confirmed: rawConfirmed is bool ? rawConfirmed : false,
    );
  }

  /// Parses a [ToolConfirmation] from a `FunctionResponse.response` dictionary.
  ///
  /// Handles both a direct confirmation dictionary and one wrapped under a
  /// `'response'` key (as a Map, JSON-encoded String, or UTF-8 byte list).
  /// Null-valued keys are stripped before constructing the instance so default
  /// field values (`hint = ''`, `confirmed = false`) apply.
  factory ToolConfirmation.fromResponseDict(Map<String, dynamic> response) {
    Object? values = response.containsKey('response')
        ? response['response']
        : response;
    if (values is List<int>) {
      values = jsonDecode(utf8.decode(values));
    } else if (values is String) {
      values = jsonDecode(values);
    }
    if (values is Map) {
      final Map<String, dynamic> cleaned = <String, dynamic>{
        for (final MapEntry<Object?, Object?> entry in values.entries)
          if (entry.value != null) '${entry.key}': entry.value,
      };
      return ToolConfirmation.fromJson(cleaned);
    }
    throw FormatException(
      'Expected ToolConfirmation dictionary payload, got ${values.runtimeType}.',
    );
  }

  /// Human-readable confirmation hint shown to the user.
  String? hint;

  /// Optional payload associated with the confirmation request.
  Object? payload;

  /// Whether the user confirmed the request.
  bool confirmed;

  /// Serializes this confirmation payload to a JSON map.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'hint': hint ?? '',
      'confirmed': confirmed,
      if (payload != null) 'payload': payload,
    };
  }
}
