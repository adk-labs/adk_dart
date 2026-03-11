/// Rendering metadata for UI widgets attached to events.
library;

/// Provider-specific UI widget payload.
class UiWidget {
  /// Creates a UI widget descriptor.
  UiWidget({
    required this.id,
    required this.provider,
    Map<String, Object?>? payload,
  }) : payload = payload ?? <String, Object?>{};

  /// Unique widget identifier.
  final String id;

  /// Rendering provider identifier, for example `mcp`.
  final String provider;

  /// Provider-specific rendering payload.
  final Map<String, Object?> payload;

  /// Returns a copied widget with optional overrides.
  UiWidget copyWith({
    String? id,
    String? provider,
    Map<String, Object?>? payload,
  }) {
    return UiWidget(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      payload: payload ?? Map<String, Object?>.from(this.payload),
    );
  }

  /// Serializes this widget to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'provider': provider,
      'payload': Map<String, Object?>.from(payload),
    };
  }

  /// Deserializes a widget from JSON.
  factory UiWidget.fromJson(Map<String, Object?> json) {
    final Object? payloadValue = json['payload'];
    return UiWidget(
      id: '${json['id'] ?? ''}',
      provider: '${json['provider'] ?? ''}',
      payload: payloadValue is Map<String, Object?>
          ? Map<String, Object?>.from(payloadValue)
          : payloadValue is Map
          ? payloadValue.map(
              (Object? key, Object? value) => MapEntry('$key', value),
            )
          : <String, Object?>{},
    );
  }
}
