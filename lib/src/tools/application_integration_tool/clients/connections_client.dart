import 'dart:convert';
import 'dart:io';

typedef ApplicationIntegrationRequestExecutor =
    Future<ApplicationIntegrationHttpResponse> Function({
      required Uri uri,
      required String method,
      required Map<String, String> headers,
      String? body,
    });

typedef ApplicationIntegrationAccessTokenProvider =
    Future<String?> Function({String? serviceAccountJson});

class ApplicationIntegrationHttpResponse {
  ApplicationIntegrationHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

class ConnectionsClient {
  ConnectionsClient({
    required this.project,
    required this.location,
    required this.connection,
    this.serviceAccountJson,
    ApplicationIntegrationRequestExecutor? requestExecutor,
    ApplicationIntegrationAccessTokenProvider? accessTokenProvider,
    Duration? pollInterval,
    Future<void> Function(Duration duration)? sleeper,
  }) : _requestExecutor =
           requestExecutor ?? defaultApplicationIntegrationRequestExecutor,
       _accessTokenProvider =
           accessTokenProvider ??
           defaultApplicationIntegrationAccessTokenProvider,
       _pollInterval = pollInterval ?? const Duration(seconds: 1),
       _sleeper = sleeper ?? Future<void>.delayed;

  final String project;
  final String location;
  final String connection;
  final String? serviceAccountJson;

  final ApplicationIntegrationRequestExecutor _requestExecutor;
  final ApplicationIntegrationAccessTokenProvider _accessTokenProvider;
  final Duration _pollInterval;
  final Future<void> Function(Duration duration) _sleeper;

  final String connectorUrl = 'https://connectors.googleapis.com';
  String? _cachedAccessToken;

  Future<Map<String, Object?>> getConnectionDetails() async {
    final Uri url = Uri.parse(
      '$connectorUrl/v1/projects/$project/locations/$location/connections/'
      '$connection?view=BASIC',
    );

    final Map<String, Object?> connectionData = await _executeApiCall(url);
    final String connectionName = _readString(connectionData['name']) ?? '';
    String serviceName = _readString(connectionData['serviceDirectory']) ?? '';
    final String host = _readString(connectionData['host']) ?? '';
    if (host.isNotEmpty) {
      serviceName = _readString(connectionData['tlsServiceDirectory']) ?? '';
    }

    return <String, Object?>{
      'name': connectionName,
      'serviceName': serviceName,
      'host': host,
      'authOverrideEnabled':
          _readBool(connectionData['authOverrideEnabled']) ?? false,
    };
  }

  Future<({Map<String, Object?> schema, List<String> operations})>
  getEntitySchemaAndOperations(String entity) async {
    final Uri url = Uri.parse(
      '$connectorUrl/v1/projects/$project/locations/$location/connections/'
      '$connection/connectionSchemaMetadata:getEntityType?entityId=$entity',
    );

    final Map<String, Object?> response = await _executeApiCall(url);
    final String? operationId = _readString(response['name']);

    if (operationId == null || operationId.isEmpty) {
      throw ArgumentError(
        'Failed to get entity schema and operations for entity: $entity',
      );
    }

    final Map<String, Object?> operationResponse = await _pollOperation(
      operationId,
    );
    final Map<String, Object?> operationPayload = _readMap(
      _readMap(operationResponse['response']),
    );
    final Map<String, Object?> schema = _readMap(
      operationPayload['jsonSchema'],
    );
    final List<String> operations = _readList(
      operationPayload['operations'],
    ).map((Object? value) => '$value').toList(growable: false);

    return (schema: schema, operations: operations);
  }

  Future<Map<String, Object?>> getActionSchema(String action) async {
    final Uri url = Uri.parse(
      '$connectorUrl/v1/projects/$project/locations/$location/connections/'
      '$connection/connectionSchemaMetadata:getAction?actionId=$action',
    );

    final Map<String, Object?> response = await _executeApiCall(url);
    final String? operationId = _readString(response['name']);

    if (operationId == null || operationId.isEmpty) {
      throw ArgumentError('Failed to get action schema for action: $action');
    }

    final Map<String, Object?> operationResponse = await _pollOperation(
      operationId,
    );
    final Map<String, Object?> operationPayload = _readMap(
      operationResponse['response'],
    );

    return <String, Object?>{
      'inputSchema': _readMap(operationPayload['inputJsonSchema']),
      'outputSchema': _readMap(operationPayload['outputJsonSchema']),
      'description': _readString(operationPayload['description']) ?? '',
      'displayName': _readString(operationPayload['displayName']) ?? '',
    };
  }

  static Map<String, Object?> getConnectorBaseSpec() {
    return <String, Object?>{
      'openapi': '3.0.1',
      'info': <String, Object?>{
        'title': 'ExecuteConnection',
        'description': 'This tool can execute a query on connection',
        'version': '4',
      },
      'servers': <Map<String, String>>[
        <String, String>{'url': 'https://integrations.googleapis.com'},
      ],
      'security': <Map<String, List<String>>>[
        <String, List<String>>{
          'google_auth': <String>[
            'https://www.googleapis.com/auth/cloud-platform',
          ],
        },
      ],
      'paths': <String, Object?>{},
      'components': <String, Object?>{
        'schemas': <String, Object?>{
          'operation': <String, Object?>{
            'type': 'string',
            'default': 'LIST_ENTITIES',
            'description':
                'Operation to execute. Possible values are LIST_ENTITIES, '
                'GET_ENTITY, CREATE_ENTITY, UPDATE_ENTITY, DELETE_ENTITY '
                'in case of entities. EXECUTE_ACTION in case of actions. '
                'and EXECUTE_QUERY in case of custom queries.',
          },
          'entityId': <String, Object?>{
            'type': 'string',
            'description': 'Name of the entity',
          },
          'connectorInputPayload': <String, Object?>{'type': 'object'},
          'filterClause': <String, Object?>{
            'type': 'string',
            'default': '',
            'description': 'WHERE clause in SQL query',
          },
          'pageSize': <String, Object?>{
            'type': 'integer',
            'default': 50,
            'description': 'Number of entities to return in the response',
          },
          'pageToken': <String, Object?>{
            'type': 'string',
            'default': '',
            'description': 'Page token to return the next page of entities',
          },
          'connectionName': <String, Object?>{
            'type': 'string',
            'default': '',
            'description': 'Connection resource name to run the query for',
          },
          'serviceName': <String, Object?>{
            'type': 'string',
            'default': '',
            'description': 'Service directory for the connection',
          },
          'host': <String, Object?>{
            'type': 'string',
            'default': '',
            'description': 'Host name incase of tls service directory',
          },
          'entity': <String, Object?>{
            'type': 'string',
            'default': 'Issues',
            'description': 'Entity to run the query for',
          },
          'action': <String, Object?>{
            'type': 'string',
            'default': 'ExecuteCustomQuery',
            'description': 'Action to run the query for',
          },
          'query': <String, Object?>{
            'type': 'string',
            'default': '',
            'description': 'Custom Query to execute on the connection',
          },
          'dynamicAuthConfig': <String, Object?>{
            'type': 'object',
            'default': <String, Object?>{},
            'description': 'Dynamic auth config for the connection',
          },
          'timeout': <String, Object?>{
            'type': 'integer',
            'default': 120,
            'description': 'Timeout in seconds for execution of custom query',
          },
          'sortByColumns': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'default': <Object?>[],
            'description': 'Column to sort the results by',
          },
          'connectorOutputPayload': <String, Object?>{'type': 'object'},
          'nextPageToken': <String, Object?>{'type': 'string'},
          'execute-connector_Response': <String, Object?>{
            'required': <String>['connectorOutputPayload'],
            'type': 'object',
            'properties': <String, Object?>{
              'connectorOutputPayload': <String, Object?>{
                r'$ref': '#/components/schemas/connectorOutputPayload',
              },
              'nextPageToken': <String, Object?>{
                r'$ref': '#/components/schemas/nextPageToken',
              },
            },
          },
        },
        'securitySchemes': <String, Object?>{
          'google_auth': <String, Object?>{
            'type': 'oauth2',
            'flows': <String, Object?>{
              'implicit': <String, Object?>{
                'authorizationUrl': 'https://accounts.google.com/o/oauth2/auth',
                'scopes': <String, String>{
                  'https://www.googleapis.com/auth/cloud-platform':
                      'Auth for google cloud services',
                },
              },
            },
          },
        },
      },
    };
  }

  static Map<String, Object?> getActionOperation(
    String action,
    String operation,
    String actionDisplayName, {
    String toolName = '',
    String toolInstructions = '',
  }) {
    String description = 'Use this tool to execute $action';
    if (operation == 'EXECUTE_QUERY') {
      description +=
          ' Use pageSize = 50 and timeout = 120 until user specifies a '
          'different value otherwise. If user provides a query in natural '
          'language, convert it to SQL query and then execute it using the '
          'tool.';
    }

    return <String, Object?>{
      'post': <String, Object?>{
        'summary': actionDisplayName,
        'description': '$description $toolInstructions',
        'operationId': '${toolName}_$actionDisplayName',
        'x-action': action,
        'x-operation': operation,
        'requestBody': <String, Object?>{
          'content': <String, Object?>{
            'application/json': <String, Object?>{
              'schema': <String, Object?>{
                r'$ref': '#/components/schemas/${actionDisplayName}_Request',
              },
            },
          },
        },
        'responses': <String, Object?>{
          '200': <String, Object?>{
            'description': 'Success response',
            'content': <String, Object?>{
              'application/json': <String, Object?>{
                'schema': <String, Object?>{
                  r'$ref': '#/components/schemas/${actionDisplayName}_Response',
                },
              },
            },
          },
        },
      },
    };
  }

  static Map<String, Object?> listOperation(
    String entity, {
    String schemaAsString = '',
    String toolName = '',
    String toolInstructions = '',
  }) {
    return <String, Object?>{
      'post': <String, Object?>{
        'summary': 'List $entity',
        'description':
            'Returns the list of $entity data. If the page token was '
            'available in the response, let users know there are more records '
            'available. Ask if the user wants to fetch the next page of '
            'results. When passing filter use the following format: '
            '`field_name1=\'value1\' AND field_name2=\'value2\' `. '
            '$toolInstructions',
        'x-operation': 'LIST_ENTITIES',
        'x-entity': entity,
        'operationId': '${toolName}_list_$entity',
        'requestBody': <String, Object?>{
          'content': <String, Object?>{
            'application/json': <String, Object?>{
              'schema': <String, Object?>{
                r'$ref': '#/components/schemas/list_${entity}_Request',
              },
            },
          },
        },
        'responses': <String, Object?>{
          '200': <String, Object?>{
            'description': 'Success response',
            'content': <String, Object?>{
              'application/json': <String, Object?>{
                'schema': <String, Object?>{
                  'description':
                      'Returns a list of $entity of json schema: $schemaAsString',
                  r'$ref': '#/components/schemas/execute-connector_Response',
                },
              },
            },
          },
        },
      },
    };
  }

  static Map<String, Object?> getOperation(
    String entity, {
    String schemaAsString = '',
    String toolName = '',
    String toolInstructions = '',
  }) {
    return <String, Object?>{
      'post': <String, Object?>{
        'summary': 'Get $entity',
        'description': 'Returns the details of the $entity. $toolInstructions',
        'operationId': '${toolName}_get_$entity',
        'x-operation': 'GET_ENTITY',
        'x-entity': entity,
        'requestBody': <String, Object?>{
          'content': <String, Object?>{
            'application/json': <String, Object?>{
              'schema': <String, Object?>{
                r'$ref': '#/components/schemas/get_${entity}_Request',
              },
            },
          },
        },
        'responses': <String, Object?>{
          '200': <String, Object?>{
            'description': 'Success response',
            'content': <String, Object?>{
              'application/json': <String, Object?>{
                'schema': <String, Object?>{
                  'description':
                      'Returns $entity of json schema: $schemaAsString',
                  r'$ref': '#/components/schemas/execute-connector_Response',
                },
              },
            },
          },
        },
      },
    };
  }

  static Map<String, Object?> createOperation(
    String entity, {
    String toolName = '',
    String toolInstructions = '',
  }) {
    return <String, Object?>{
      'post': <String, Object?>{
        'summary': 'Creates a new $entity',
        'description': 'Creates a new $entity. $toolInstructions',
        'x-operation': 'CREATE_ENTITY',
        'x-entity': entity,
        'operationId': '${toolName}_create_$entity',
        'requestBody': <String, Object?>{
          'content': <String, Object?>{
            'application/json': <String, Object?>{
              'schema': <String, Object?>{
                r'$ref': '#/components/schemas/create_${entity}_Request',
              },
            },
          },
        },
        'responses': <String, Object?>{
          '200': <String, Object?>{
            'description': 'Success response',
            'content': <String, Object?>{
              'application/json': <String, Object?>{
                'schema': <String, Object?>{
                  r'$ref': '#/components/schemas/execute-connector_Response',
                },
              },
            },
          },
        },
      },
    };
  }

  static Map<String, Object?> updateOperation(
    String entity, {
    String toolName = '',
    String toolInstructions = '',
  }) {
    return <String, Object?>{
      'post': <String, Object?>{
        'summary': 'Updates the $entity',
        'description': 'Updates the $entity. $toolInstructions',
        'x-operation': 'UPDATE_ENTITY',
        'x-entity': entity,
        'operationId': '${toolName}_update_$entity',
        'requestBody': <String, Object?>{
          'content': <String, Object?>{
            'application/json': <String, Object?>{
              'schema': <String, Object?>{
                r'$ref': '#/components/schemas/update_${entity}_Request',
              },
            },
          },
        },
        'responses': <String, Object?>{
          '200': <String, Object?>{
            'description': 'Success response',
            'content': <String, Object?>{
              'application/json': <String, Object?>{
                'schema': <String, Object?>{
                  r'$ref': '#/components/schemas/execute-connector_Response',
                },
              },
            },
          },
        },
      },
    };
  }

  static Map<String, Object?> deleteOperation(
    String entity, {
    String toolName = '',
    String toolInstructions = '',
  }) {
    return <String, Object?>{
      'post': <String, Object?>{
        'summary': 'Delete the $entity',
        'description': 'Deletes the $entity. $toolInstructions',
        'x-operation': 'DELETE_ENTITY',
        'x-entity': entity,
        'operationId': '${toolName}_delete_$entity',
        'requestBody': <String, Object?>{
          'content': <String, Object?>{
            'application/json': <String, Object?>{
              'schema': <String, Object?>{
                r'$ref': '#/components/schemas/delete_${entity}_Request',
              },
            },
          },
        },
        'responses': <String, Object?>{
          '200': <String, Object?>{
            'description': 'Success response',
            'content': <String, Object?>{
              'application/json': <String, Object?>{
                'schema': <String, Object?>{
                  r'$ref': '#/components/schemas/execute-connector_Response',
                },
              },
            },
          },
        },
      },
    };
  }

  static Map<String, Object?> createOperationRequest(String entity) {
    return <String, Object?>{
      'type': 'object',
      'required': <String>[
        'connectorInputPayload',
        'operation',
        'connectionName',
        'serviceName',
        'host',
        'entity',
      ],
      'properties': <String, Object?>{
        'connectorInputPayload': <String, Object?>{
          r'$ref': '#/components/schemas/connectorInputPayload_$entity',
        },
        'operation': <String, Object?>{
          r'$ref': '#/components/schemas/operation',
        },
        'connectionName': <String, Object?>{
          r'$ref': '#/components/schemas/connectionName',
        },
        'serviceName': <String, Object?>{
          r'$ref': '#/components/schemas/serviceName',
        },
        'host': <String, Object?>{r'$ref': '#/components/schemas/host'},
        'entity': <String, Object?>{r'$ref': '#/components/schemas/entity'},
        'dynamicAuthConfig': <String, Object?>{
          r'$ref': '#/components/schemas/dynamicAuthConfig',
        },
      },
    };
  }

  static Map<String, Object?> updateOperationRequest(String entity) {
    return <String, Object?>{
      'type': 'object',
      'required': <String>[
        'connectorInputPayload',
        'entityId',
        'operation',
        'connectionName',
        'serviceName',
        'host',
        'entity',
      ],
      'properties': <String, Object?>{
        'connectorInputPayload': <String, Object?>{
          r'$ref': '#/components/schemas/connectorInputPayload_$entity',
        },
        'entityId': <String, Object?>{r'$ref': '#/components/schemas/entityId'},
        'operation': <String, Object?>{
          r'$ref': '#/components/schemas/operation',
        },
        'connectionName': <String, Object?>{
          r'$ref': '#/components/schemas/connectionName',
        },
        'serviceName': <String, Object?>{
          r'$ref': '#/components/schemas/serviceName',
        },
        'host': <String, Object?>{r'$ref': '#/components/schemas/host'},
        'entity': <String, Object?>{r'$ref': '#/components/schemas/entity'},
        'dynamicAuthConfig': <String, Object?>{
          r'$ref': '#/components/schemas/dynamicAuthConfig',
        },
        'filterClause': <String, Object?>{
          r'$ref': '#/components/schemas/filterClause',
        },
      },
    };
  }

  static Map<String, Object?> getOperationRequest() {
    return <String, Object?>{
      'type': 'object',
      'required': <String>[
        'entityId',
        'operation',
        'connectionName',
        'serviceName',
        'host',
        'entity',
      ],
      'properties': <String, Object?>{
        'entityId': <String, Object?>{r'$ref': '#/components/schemas/entityId'},
        'operation': <String, Object?>{
          r'$ref': '#/components/schemas/operation',
        },
        'connectionName': <String, Object?>{
          r'$ref': '#/components/schemas/connectionName',
        },
        'serviceName': <String, Object?>{
          r'$ref': '#/components/schemas/serviceName',
        },
        'host': <String, Object?>{r'$ref': '#/components/schemas/host'},
        'entity': <String, Object?>{r'$ref': '#/components/schemas/entity'},
        'dynamicAuthConfig': <String, Object?>{
          r'$ref': '#/components/schemas/dynamicAuthConfig',
        },
      },
    };
  }

  static Map<String, Object?> deleteOperationRequest() {
    return <String, Object?>{
      'type': 'object',
      'required': <String>[
        'entityId',
        'operation',
        'connectionName',
        'serviceName',
        'host',
        'entity',
      ],
      'properties': <String, Object?>{
        'entityId': <String, Object?>{r'$ref': '#/components/schemas/entityId'},
        'operation': <String, Object?>{
          r'$ref': '#/components/schemas/operation',
        },
        'connectionName': <String, Object?>{
          r'$ref': '#/components/schemas/connectionName',
        },
        'serviceName': <String, Object?>{
          r'$ref': '#/components/schemas/serviceName',
        },
        'host': <String, Object?>{r'$ref': '#/components/schemas/host'},
        'entity': <String, Object?>{r'$ref': '#/components/schemas/entity'},
        'dynamicAuthConfig': <String, Object?>{
          r'$ref': '#/components/schemas/dynamicAuthConfig',
        },
        'filterClause': <String, Object?>{
          r'$ref': '#/components/schemas/filterClause',
        },
      },
    };
  }

  static Map<String, Object?> listOperationRequest() {
    return <String, Object?>{
      'type': 'object',
      'required': <String>[
        'operation',
        'connectionName',
        'serviceName',
        'host',
        'entity',
      ],
      'properties': <String, Object?>{
        'filterClause': <String, Object?>{
          r'$ref': '#/components/schemas/filterClause',
        },
        'pageSize': <String, Object?>{r'$ref': '#/components/schemas/pageSize'},
        'pageToken': <String, Object?>{
          r'$ref': '#/components/schemas/pageToken',
        },
        'operation': <String, Object?>{
          r'$ref': '#/components/schemas/operation',
        },
        'connectionName': <String, Object?>{
          r'$ref': '#/components/schemas/connectionName',
        },
        'serviceName': <String, Object?>{
          r'$ref': '#/components/schemas/serviceName',
        },
        'host': <String, Object?>{r'$ref': '#/components/schemas/host'},
        'entity': <String, Object?>{r'$ref': '#/components/schemas/entity'},
        'sortByColumns': <String, Object?>{
          r'$ref': '#/components/schemas/sortByColumns',
        },
        'dynamicAuthConfig': <String, Object?>{
          r'$ref': '#/components/schemas/dynamicAuthConfig',
        },
      },
    };
  }

  static Map<String, Object?> actionRequest(String action) {
    return <String, Object?>{
      'type': 'object',
      'required': <String>[
        'operation',
        'connectionName',
        'serviceName',
        'host',
        'action',
        'connectorInputPayload',
      ],
      'properties': <String, Object?>{
        'operation': <String, Object?>{
          r'$ref': '#/components/schemas/operation',
        },
        'connectionName': <String, Object?>{
          r'$ref': '#/components/schemas/connectionName',
        },
        'serviceName': <String, Object?>{
          r'$ref': '#/components/schemas/serviceName',
        },
        'host': <String, Object?>{r'$ref': '#/components/schemas/host'},
        'action': <String, Object?>{r'$ref': '#/components/schemas/action'},
        'connectorInputPayload': <String, Object?>{
          r'$ref': '#/components/schemas/connectorInputPayload_$action',
        },
        'dynamicAuthConfig': <String, Object?>{
          r'$ref': '#/components/schemas/dynamicAuthConfig',
        },
      },
    };
  }

  static Map<String, Object?> actionResponse(String action) {
    return <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'connectorOutputPayload': <String, Object?>{
          r'$ref': '#/components/schemas/connectorOutputPayload_$action',
        },
      },
    };
  }

  static Map<String, Object?> executeCustomQueryRequest() {
    return <String, Object?>{
      'type': 'object',
      'required': <String>[
        'operation',
        'connectionName',
        'serviceName',
        'host',
        'action',
        'query',
        'timeout',
        'pageSize',
      ],
      'properties': <String, Object?>{
        'operation': <String, Object?>{
          r'$ref': '#/components/schemas/operation',
        },
        'connectionName': <String, Object?>{
          r'$ref': '#/components/schemas/connectionName',
        },
        'serviceName': <String, Object?>{
          r'$ref': '#/components/schemas/serviceName',
        },
        'host': <String, Object?>{r'$ref': '#/components/schemas/host'},
        'action': <String, Object?>{r'$ref': '#/components/schemas/action'},
        'query': <String, Object?>{r'$ref': '#/components/schemas/query'},
        'timeout': <String, Object?>{r'$ref': '#/components/schemas/timeout'},
        'pageSize': <String, Object?>{r'$ref': '#/components/schemas/pageSize'},
        'dynamicAuthConfig': <String, Object?>{
          r'$ref': '#/components/schemas/dynamicAuthConfig',
        },
      },
    };
  }

  Map<String, Object?> connectorPayload(Map<String, Object?> jsonSchema) {
    return _convertJsonSchemaToOpenApiSchema(jsonSchema);
  }

  Map<String, Object?> _convertJsonSchemaToOpenApiSchema(
    Map<String, Object?> jsonSchema,
  ) {
    final Map<String, Object?> openApiSchema = <String, Object?>{};

    if (jsonSchema.containsKey('description')) {
      openApiSchema['description'] = jsonSchema['description'];
    }

    if (jsonSchema.containsKey('type')) {
      final Object? schemaType = jsonSchema['type'];
      if (schemaType is List) {
        if (schemaType.contains('null')) {
          openApiSchema['nullable'] = true;
          final List<Object?> otherTypes = schemaType
              .where((Object? value) => value != 'null')
              .toList(growable: false);
          if (otherTypes.isNotEmpty) {
            openApiSchema['type'] = otherTypes.first;
          }
        } else if (schemaType.isNotEmpty) {
          openApiSchema['type'] = schemaType.first;
        }
      } else {
        openApiSchema['type'] = schemaType;
      }
    }

    if (openApiSchema['type'] == 'object' && jsonSchema['properties'] is Map) {
      final Map<String, Object?> properties = <String, Object?>{};
      final Map<String, Object?> sourceProperties = _readMap(
        jsonSchema['properties'],
      );
      for (final MapEntry<String, Object?> entry in sourceProperties.entries) {
        properties[entry.key] = _convertJsonSchemaToOpenApiSchema(
          _readMap(entry.value),
        );
      }
      openApiSchema['properties'] = properties;
    } else if (openApiSchema['type'] == 'array' &&
        jsonSchema.containsKey('items')) {
      final Object? items = jsonSchema['items'];
      if (items is List) {
        openApiSchema['items'] = items
            .map(
              (Object? item) =>
                  _convertJsonSchemaToOpenApiSchema(_readMap(item)),
            )
            .toList(growable: false);
      } else {
        openApiSchema['items'] = _convertJsonSchemaToOpenApiSchema(
          _readMap(items),
        );
      }
    }

    return openApiSchema;
  }

  Future<Map<String, Object?>> _executeApiCall(Uri url) async {
    try {
      final ApplicationIntegrationHttpResponse response =
          await _requestExecutor(
            uri: url,
            method: 'GET',
            headers: <String, String>{
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.authorizationHeader:
                  'Bearer ${await _getAccessToken()}',
            },
          );

      if (response.statusCode >= 400) {
        throw HttpException(
          'GET $url failed (${response.statusCode}): ${response.body}',
        );
      }

      final String body = response.body.trim();
      if (body.isEmpty) {
        return <String, Object?>{};
      }

      final Object? decoded = jsonDecode(body);
      return _readMap(decoded);
    } catch (error) {
      final String message = '$error';
      if (message.contains('404') ||
          message.contains('Not found') ||
          message.contains('400') ||
          message.contains('Bad request')) {
        throw ArgumentError(
          'Invalid request. Please check the provided values of '
          'project($project), location($location), connection($connection).',
        );
      }
      throw ArgumentError('Request error: $error');
    }
  }

  Future<Map<String, Object?>> _pollOperation(String operationId) async {
    bool operationDone = false;
    Map<String, Object?> operationResponse = <String, Object?>{};

    while (!operationDone) {
      final Uri getOperationUrl = Uri.parse('$connectorUrl/v1/$operationId');
      operationResponse = await _executeApiCall(getOperationUrl);
      operationDone = _readBool(operationResponse['done']) ?? false;
      if (!operationDone) {
        await _sleeper(_pollInterval);
      }
    }

    return operationResponse;
  }

  Future<String> _getAccessToken() async {
    if (_cachedAccessToken != null && _cachedAccessToken!.isNotEmpty) {
      return _cachedAccessToken!;
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

    _cachedAccessToken = resolved;
    return resolved;
  }
}

Future<ApplicationIntegrationHttpResponse>
defaultApplicationIntegrationRequestExecutor({
  required Uri uri,
  required String method,
  required Map<String, String> headers,
  String? body,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.write(body);
    }

    final HttpClientResponse response = await request.close();
    final String responseBody = await utf8.decodeStream(response);
    return ApplicationIntegrationHttpResponse(
      statusCode: response.statusCode,
      body: responseBody,
    );
  } finally {
    client.close(force: true);
  }
}

Future<String?> defaultApplicationIntegrationAccessTokenProvider({
  String? serviceAccountJson,
}) async {
  if (serviceAccountJson != null && serviceAccountJson.trim().isNotEmpty) {
    final Object? decoded;
    try {
      decoded = jsonDecode(serviceAccountJson);
    } on FormatException catch (error) {
      throw ArgumentError('Invalid service account JSON: $error');
    }

    final Map<String, Object?> json = _readMap(decoded);
    final String? token = _readString(
      json['access_token'] ??
          json['token'] ??
          _readMap(json['oauth2'])['access_token'],
    );
    if (token != null && token.isNotEmpty) {
      return token;
    }
  }

  final Map<String, String> environment = Platform.environment;
  return environment['GOOGLE_OAUTH_ACCESS_TOKEN'] ??
      environment['GOOGLE_ACCESS_TOKEN'] ??
      environment['ACCESS_TOKEN'];
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

List<Object?> _readList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
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
