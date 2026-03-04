/// Toolset that maps Application Integration resources to ADK tools.
library;

import 'dart:convert';

import '../../agents/readonly_context.dart';
import '../../auth/auth_credential.dart';
import '../../auth/auth_schemes.dart';
import '../../auth/auth_tool.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../openapi_tool/auth/auth_helpers.dart';
import '../openapi_tool/openapi_spec_parser/openapi_spec_parser.dart';
import '../openapi_tool/openapi_spec_parser/openapi_toolset.dart';
import '../openapi_tool/openapi_spec_parser/rest_api_tool.dart';
import 'clients/connections_client.dart';
import 'clients/integration_client.dart';
import 'integration_connector_tool.dart';

/// Toolset that discovers Application Integration connectors.
class ApplicationIntegrationToolset extends BaseToolset {
  /// Creates an Application Integration toolset.
  ApplicationIntegrationToolset({
    required this.project,
    required this.location,
    this.connectionTemplateOverride,
    this.integration,
    List<String>? triggers,
    this.connection,
    Map<String, List<String>>? entityOperations,
    List<String>? actions,
    this.toolInstructions = '',
    this.serviceAccountJson,
    this.authScheme,
    this.authCredential,
    this.integrationClient,
    this.connectionsClient,
    super.toolFilter,
  }) : triggers = triggers ?? <String>[],
       entityOperations = entityOperations ?? <String, List<String>>{},
       actions = actions ?? <String>[],
       _authConfig = authScheme == null
           ? null
           : AuthConfig(
               authScheme: _serializeAuthScheme(authScheme),
               rawAuthCredential: authCredential?.copyWith(),
             ) {
    _integrationClient =
        integrationClient ??
        IntegrationClient(
          project: project,
          location: location,
          connectionTemplateOverride: connectionTemplateOverride,
          integration: integration,
          triggers: this.triggers,
          connection: connection,
          entityOperations: this.entityOperations,
          actions: this.actions,
          serviceAccountJson: serviceAccountJson,
          connectionsClient: connectionsClient,
        );

    _prepareFuture = _prepareToolset();
  }

  /// Google Cloud project id.
  final String project;

  /// Google Cloud location id.
  final String location;

  /// Optional connection template override.
  final String? connectionTemplateOverride;

  /// Optional integration resource name.
  final String? integration;

  /// Trigger ids used for integration-mode spec generation.
  final List<String> triggers;

  /// Optional connection name used for connector-mode spec generation.
  final String? connection;

  /// Requested entity operations by entity name.
  final Map<String, List<String>> entityOperations;

  /// Requested connector actions.
  final List<String> actions;

  /// Additional tool instructions injected into generated operations.
  final String toolInstructions;

  /// Optional service-account JSON string.
  final String? serviceAccountJson;

  /// Optional auth scheme used for connector tool overrides.
  final AuthScheme? authScheme;

  /// Optional auth credential used for connector tool overrides.
  final AuthCredential? authCredential;

  /// Optional preconfigured integration client.
  final IntegrationClient? integrationClient;

  /// Optional preconfigured connections client.
  final ConnectionsClient? connectionsClient;

  final AuthConfig? _authConfig;

  late final IntegrationClient _integrationClient;
  OpenAPIToolset? _openApiToolset;
  final List<BaseTool> _tools = <BaseTool>[];
  Future<void>? _prepareFuture;

  Future<void> _prepareToolset() async {
    final IntegrationClient resolvedIntegrationClient = _integrationClient;

    Map<String, Object?> spec;
    Map<String, Object?> connectionDetails = <String, Object?>{};

    if (integration != null) {
      spec = await resolvedIntegrationClient.getOpenApiSpecForIntegration();
    } else if (connection != null &&
        (entityOperations.isNotEmpty || actions.isNotEmpty)) {
      final ConnectionsClient resolvedConnectionsClient =
          connectionsClient ??
          ConnectionsClient(
            project: project,
            location: location,
            connection: connection!,
            serviceAccountJson: serviceAccountJson,
          );
      connectionDetails = await resolvedConnectionsClient
          .getConnectionDetails();
      spec = await resolvedIntegrationClient.getOpenApiSpecForConnection(
        toolInstructions: toolInstructions,
      );
    } else {
      throw ArgumentError(
        'Invalid request, Either integration or (connection and '
        '(entity_operations or actions)) should be provided.',
      );
    }

    _parseSpecToToolset(spec, connectionDetails);
  }

  void _parseSpecToToolset(
    Map<String, Object?> specDict,
    Map<String, Object?> connectionDetails,
  ) {
    Object? resolvedAuthScheme;
    AuthCredential? resolvedAuthCredential;

    if (serviceAccountJson != null && serviceAccountJson!.trim().isNotEmpty) {
      final Map<String, Object?> serviceAccountConfig = _readMap(
        jsonDecode(serviceAccountJson!),
      );

      final ServiceAccountCredential
      serviceAccountCredential = ServiceAccountCredential(
        projectId: _readString(serviceAccountConfig['project_id']) ?? '',
        privateKeyId: _readString(serviceAccountConfig['private_key_id']) ?? '',
        privateKey: _readString(serviceAccountConfig['private_key']) ?? '',
        clientEmail: _readString(serviceAccountConfig['client_email']) ?? '',
        clientId: _readString(serviceAccountConfig['client_id']) ?? '',
        authUri: _readString(serviceAccountConfig['auth_uri']) ?? '',
        tokenUri: _readString(serviceAccountConfig['token_uri']) ?? '',
      );

      final (
        authScheme: Object serviceAccountScheme,
        authCredential: AuthCredential serviceAccountCredentialAuth,
      ) = serviceAccountSchemeCredential(
        ServiceAccountAuth(
          serviceAccountCredential: serviceAccountCredential,
          scopes: const <String>[
            'https://www.googleapis.com/auth/cloud-platform',
          ],
        ),
      );
      resolvedAuthScheme = serviceAccountScheme;
      resolvedAuthCredential = serviceAccountCredentialAuth;
    } else {
      resolvedAuthCredential = AuthCredential(
        authType: AuthCredentialType.serviceAccount,
        serviceAccount: ServiceAccountAuth(
          useDefaultCredential: true,
          scopes: const <String>[
            'https://www.googleapis.com/auth/cloud-platform',
          ],
        ),
      );
      resolvedAuthScheme = SecurityScheme(
        type: AuthSchemeType.http,
        scheme: 'bearer',
        bearerFormat: 'JWT',
      );
    }

    if (integration != null) {
      _openApiToolset = OpenAPIToolset(
        specDict: specDict,
        authCredential: resolvedAuthCredential,
        authScheme: resolvedAuthScheme,
        toolFilter: toolFilter,
      );
      return;
    }

    final List<ParsedOperation> operations = OpenApiSpecParser().parse(
      specDict,
    );

    for (final ParsedOperation openApiOperation in operations) {
      final String? parsedOperation = _readString(
        openApiOperation.operation['x-operation'],
      );
      String? parsedEntity;
      String? parsedAction;

      if (openApiOperation.operation.containsKey('x-entity')) {
        parsedEntity = _readString(openApiOperation.operation['x-entity']);
      } else if (openApiOperation.operation.containsKey('x-action')) {
        parsedAction = _readString(openApiOperation.operation['x-action']);
      }

      final RestApiTool restApiTool = RestApiTool.fromParsedOperation(
        openApiOperation,
      );
      restApiTool.configureAuthScheme(resolvedAuthScheme);
      restApiTool.configureAuthCredential(resolvedAuthCredential);

      final bool authOverrideEnabled =
          _readBool(connectionDetails['authOverrideEnabled']) ?? false;

      Object? connectorAuthScheme;
      AuthCredential? connectorAuthCredential;
      if (authScheme != null &&
          authCredential != null &&
          !authOverrideEnabled) {
        connectorAuthScheme = null;
        connectorAuthCredential = null;
      } else {
        connectorAuthScheme = authScheme;
        connectorAuthCredential = authCredential;
      }

      _tools.add(
        IntegrationConnectorTool(
          name: restApiTool.name,
          description: restApiTool.description,
          connectionName: _readString(connectionDetails['name']) ?? '',
          connectionHost: _readString(connectionDetails['host']) ?? '',
          connectionServiceName:
              _readString(connectionDetails['serviceName']) ?? '',
          entity: parsedEntity,
          action: parsedAction,
          operation: parsedOperation,
          restApiTool: restApiTool,
          authScheme: connectorAuthScheme,
          authCredential: connectorAuthCredential,
        ),
      );
    }
  }

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    await (_prepareFuture ??= _prepareToolset());

    if (_openApiToolset != null) {
      return _openApiToolset!.getTools(readonlyContext: readonlyContext);
    }

    return _tools
        .where((BaseTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  @override
  Future<void> close() async {
    await _openApiToolset?.close();
  }

  @override
  AuthConfig? getAuthConfig() {
    return _authConfig;
  }
}

String _serializeAuthScheme(Object authScheme) {
  if (authScheme is SecurityScheme) {
    return jsonEncode(authScheme.toJson());
  }
  if (authScheme is Map) {
    return jsonEncode(authScheme);
  }
  return '$authScheme';
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  return '$value';
}

bool? _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    switch (value.toLowerCase()) {
      case 'true':
        return true;
      case 'false':
        return false;
    }
  }
  return null;
}
