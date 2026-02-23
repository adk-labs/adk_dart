import 'dart:convert';
import 'dart:io';

import 'connections_client.dart';

class IntegrationClient {
  IntegrationClient({
    required this.project,
    required this.location,
    this.connectionTemplateOverride,
    this.integration,
    List<String>? triggers,
    this.connection,
    Map<String, List<String>>? entityOperations,
    List<String>? actions,
    this.serviceAccountJson,
    ApplicationIntegrationRequestExecutor? requestExecutor,
    ApplicationIntegrationAccessTokenProvider? accessTokenProvider,
    ConnectionsClient? connectionsClient,
    Duration? pollInterval,
    Future<void> Function(Duration duration)? sleeper,
  }) : triggers = triggers ?? <String>[],
       entityOperations = entityOperations ?? <String, List<String>>{},
       actions = actions ?? <String>[],
       _requestExecutor =
           requestExecutor ?? defaultApplicationIntegrationRequestExecutor,
       _accessTokenProvider =
           accessTokenProvider ??
           defaultApplicationIntegrationAccessTokenProvider,
       _connectionsClient = connectionsClient,
       _pollInterval = pollInterval ?? const Duration(seconds: 1),
       _sleeper = sleeper ?? Future<void>.delayed;

  final String project;
  final String location;
  final String? connectionTemplateOverride;
  final String? integration;
  final List<String> triggers;
  final String? connection;
  final Map<String, List<String>> entityOperations;
  final List<String> actions;
  final String? serviceAccountJson;

  final ApplicationIntegrationRequestExecutor _requestExecutor;
  final ApplicationIntegrationAccessTokenProvider _accessTokenProvider;
  final ConnectionsClient? _connectionsClient;
  final Duration _pollInterval;
  final Future<void> Function(Duration duration) _sleeper;

  String? _cachedAccessToken;
  String? _quotaProjectId;

  Future<Map<String, Object?>> getOpenApiSpecForIntegration() async {
    try {
      final String integrationName = integration ?? '';
      final Uri url = Uri.parse(
        'https://$location-integrations.googleapis.com/v1/projects/$project/'
        'locations/$location:generateOpenApiSpec',
      );
      final Map<String, String> headers = <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.authorizationHeader: 'Bearer ${await _getAccessToken()}',
      };
      if (serviceAccountJson == null || serviceAccountJson!.trim().isEmpty) {
        headers['x-goog-user-project'] = _quotaProjectId ?? project;
      }

      final Map<String, Object?> payload = <String, Object?>{
        'apiTriggerResources': <Map<String, Object?>>[
          <String, Object?>{
            'integrationResource': integrationName,
            'triggerId': triggers,
          },
        ],
        'fileFormat': 'JSON',
      };

      final ApplicationIntegrationHttpResponse response =
          await _requestExecutor(
            uri: url,
            method: 'POST',
            headers: headers,
            body: jsonEncode(payload),
          );
      if (response.statusCode >= 400) {
        throw HttpException(
          'POST $url failed (${response.statusCode}): ${response.body}',
        );
      }

      final Object? decodedBody = response.body.trim().isEmpty
          ? <String, Object?>{}
          : jsonDecode(response.body);
      final Map<String, Object?> body = _readMap(decodedBody);
      final Object? specValue = body['openApiSpec'];
      if (specValue is String) {
        final Object? decodedSpec = specValue.trim().isEmpty
            ? <String, Object?>{}
            : jsonDecode(specValue);
        return _readMap(decodedSpec);
      }
      return _readMap(specValue);
    } catch (error) {
      final String message = '$error';
      if (message.contains('404') ||
          message.contains('Not found') ||
          message.contains('400') ||
          message.contains('Bad request')) {
        throw ArgumentError(
          'Invalid request. Please check the provided values of '
          'project($project), location($location), integration($integration).',
        );
      }
      throw ArgumentError('Request error: $error');
    }
  }

  Future<Map<String, Object?>> getOpenApiSpecForConnection({
    String toolName = '',
    String toolInstructions = '',
  }) async {
    final String integrationName =
        connectionTemplateOverride ?? 'ExecuteConnection';
    final ConnectionsClient connectionsClient = _resolveConnectionsClient();

    if (entityOperations.isEmpty && actions.isEmpty) {
      throw ArgumentError(
        'No entity operations or actions provided. Please provide at least '
        'one of them.',
      );
    }

    final Map<String, Object?> connectorSpec =
        ConnectionsClient.getConnectorBaseSpec();
    final Map<String, Object?> schemas = _schemas(connectorSpec);
    final Map<String, Object?> paths = _paths(connectorSpec);

    for (final MapEntry<String, List<String>> entry
        in entityOperations.entries) {
      final String entity = entry.key;
      final ({Map<String, Object?> schema, List<String> operations})
      schemaAndOperations = await connectionsClient
          .getEntitySchemaAndOperations(entity);

      List<String> operations = entry.value;
      if (operations.isEmpty) {
        operations = schemaAndOperations.operations;
      }

      final String jsonSchemaAsString = jsonEncode(schemaAndOperations.schema);
      final String entityLower = entity;
      schemas['connectorInputPayload_$entityLower'] = connectionsClient
          .connectorPayload(schemaAndOperations.schema);

      for (final String operation in operations) {
        final String operationLower = operation.toLowerCase();
        final String path =
            '/v2/projects/$project/locations/$location/integrations/'
            '$integrationName:execute?triggerId=api_trigger/'
            '$integrationName#$operationLower'
            '_$entityLower';

        switch (operationLower) {
          case 'create':
            paths[path] = ConnectionsClient.createOperation(
              entityLower,
              toolName: toolName,
              toolInstructions: toolInstructions,
            );
            schemas['create_${entityLower}_Request'] =
                ConnectionsClient.createOperationRequest(entityLower);
          case 'update':
            paths[path] = ConnectionsClient.updateOperation(
              entityLower,
              toolName: toolName,
              toolInstructions: toolInstructions,
            );
            schemas['update_${entityLower}_Request'] =
                ConnectionsClient.updateOperationRequest(entityLower);
          case 'delete':
            paths[path] = ConnectionsClient.deleteOperation(
              entityLower,
              toolName: toolName,
              toolInstructions: toolInstructions,
            );
            schemas['delete_${entityLower}_Request'] =
                ConnectionsClient.deleteOperationRequest();
          case 'list':
            paths[path] = ConnectionsClient.listOperation(
              entityLower,
              schemaAsString: jsonSchemaAsString,
              toolName: toolName,
              toolInstructions: toolInstructions,
            );
            schemas['list_${entityLower}_Request'] =
                ConnectionsClient.listOperationRequest();
          case 'get':
            paths[path] = ConnectionsClient.getOperation(
              entityLower,
              schemaAsString: jsonSchemaAsString,
              toolName: toolName,
              toolInstructions: toolInstructions,
            );
            schemas['get_${entityLower}_Request'] =
                ConnectionsClient.getOperationRequest();
          default:
            throw ArgumentError(
              'Invalid operation: $operation for entity: $entity',
            );
        }
      }
    }

    for (final String action in actions) {
      final Map<String, Object?> actionDetails = await connectionsClient
          .getActionSchema(action);
      final Map<String, Object?> inputSchema = _readMap(
        actionDetails['inputSchema'],
      );
      final Map<String, Object?> outputSchema = _readMap(
        actionDetails['outputSchema'],
      );
      final String actionDisplayName =
          (_readString(actionDetails['displayName']) ?? '').replaceAll(' ', '');

      String operation = 'EXECUTE_ACTION';
      if (action == 'ExecuteCustomQuery') {
        schemas['${actionDisplayName}_Request'] =
            ConnectionsClient.executeCustomQueryRequest();
        operation = 'EXECUTE_QUERY';
      } else {
        schemas['${actionDisplayName}_Request'] =
            ConnectionsClient.actionRequest(actionDisplayName);
        schemas['connectorInputPayload_$actionDisplayName'] = connectionsClient
            .connectorPayload(inputSchema);
      }

      schemas['connectorOutputPayload_$actionDisplayName'] = connectionsClient
          .connectorPayload(outputSchema);
      schemas['${actionDisplayName}_Response'] =
          ConnectionsClient.actionResponse(actionDisplayName);

      final String path =
          '/v2/projects/$project/locations/$location/integrations/'
          '$integrationName:execute?triggerId=api_trigger/$integrationName'
          '#$action';
      paths[path] = ConnectionsClient.getActionOperation(
        action,
        operation,
        actionDisplayName,
        toolName: toolName,
        toolInstructions: toolInstructions,
      );
    }

    return connectorSpec;
  }

  ConnectionsClient _resolveConnectionsClient() {
    final ConnectionsClient? existingClient = _connectionsClient;
    if (existingClient != null) {
      return existingClient;
    }
    final String connectionName = connection ?? '';
    return ConnectionsClient(
      project: project,
      location: location,
      connection: connectionName,
      serviceAccountJson: serviceAccountJson,
      requestExecutor: _requestExecutor,
      accessTokenProvider: _accessTokenProvider,
      pollInterval: _pollInterval,
      sleeper: _sleeper,
    );
  }

  Future<String> _getAccessToken() async {
    if (_cachedAccessToken != null && _cachedAccessToken!.isNotEmpty) {
      return _cachedAccessToken!;
    }

    if (serviceAccountJson != null && serviceAccountJson!.trim().isNotEmpty) {
      final Object? decoded = jsonDecode(serviceAccountJson!);
      final Map<String, Object?> payload = _readMap(decoded);
      _quotaProjectId = _readString(payload['project_id']) ?? _quotaProjectId;
    }

    final String? resolved = await _accessTokenProvider(
      serviceAccountJson: serviceAccountJson,
    );
    if (resolved == null || resolved.isEmpty) {
      throw ArgumentError(
        'Please provide a service account that has the required permissions '
        'to access the connection.',
      );
    }

    _quotaProjectId ??= project;
    _cachedAccessToken = resolved;
    return resolved;
  }
}

Map<String, Object?> _schemas(Map<String, Object?> spec) {
  final Map<String, Object?> components = _readMap(spec['components']);
  spec['components'] = components;

  final Map<String, Object?> schemas = _readMap(components['schemas']);
  components['schemas'] = schemas;
  return schemas;
}

Map<String, Object?> _paths(Map<String, Object?> spec) {
  final Map<String, Object?> paths = _readMap(spec['paths']);
  spec['paths'] = paths;
  return paths;
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
