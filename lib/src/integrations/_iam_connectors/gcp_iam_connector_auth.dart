/// GCP IAM Connector auth scheme models.
library;

/// Externally managed authentication scheme types.
enum ManagedAuthSchemeType { gcpIamConnectorAuth }

/// Authentication scheme that delegates OAuth flow handling to a GCP IAM connector.
class GcpIamConnectorAuth {
  /// Creates a managed GCP IAM connector auth scheme.
  GcpIamConnectorAuth({
    required this.connectorName,
    List<String>? scopes,
    this.continueUri,
  }) : scopes = scopes == null ? null : List<String>.from(scopes);

  /// Managed auth scheme type.
  final ManagedAuthSchemeType type = ManagedAuthSchemeType.gcpIamConnectorAuth;

  /// IAM connector resource name.
  final String connectorName;

  /// Optional OAuth scopes requested via the connector.
  final List<String>? scopes;

  /// Optional URI used to resume the managed auth flow.
  final String? continueUri;

  /// Serializes this auth scheme into the wire payload used by [AuthConfig].
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type.name,
      'connector_name': connectorName,
      if (scopes != null) 'scopes': scopes,
      if (continueUri != null) 'continue_uri': continueUri,
    };
  }

  /// Creates a managed auth scheme from JSON.
  factory GcpIamConnectorAuth.fromJson(Map<String, Object?> json) {
    return GcpIamConnectorAuth(
      connectorName: '${json['connector_name'] ?? ''}',
      scopes: (json['scopes'] as List?)
          ?.map((Object? value) => '$value')
          .toList(),
      continueUri: json['continue_uri'] as String?,
    );
  }
}
