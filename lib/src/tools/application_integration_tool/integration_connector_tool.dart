import '../../auth/auth_credential.dart';
import '../../features/_feature_registry.dart';
import '../../models/llm_request.dart';
import '../_gemini_schema_util.dart';
import '../base_tool.dart';
import '../openapi_tool/openapi_spec_parser/rest_api_tool.dart';
import '../openapi_tool/openapi_spec_parser/tool_auth_handler.dart';
import '../tool_context.dart';

class IntegrationConnectorTool extends BaseTool {
  IntegrationConnectorTool({
    required super.name,
    required super.description,
    required this.connectionName,
    required this.connectionHost,
    required this.connectionServiceName,
    this.entity,
    this.operation,
    this.action,
    required RestApiTool restApiTool,
    this.authScheme,
    this.authCredential,
  }) : _restApiTool = restApiTool;

  static const List<String> excludeFields = <String>[
    'connection_name',
    'service_name',
    'host',
    'entity',
    'operation',
    'action',
    'dynamic_auth_config',
  ];

  static const List<String> optionalFields = <String>[
    'page_size',
    'page_token',
    'filter',
    'sortByColumns',
    'sort_by_columns',
  ];

  final String connectionName;
  final String connectionHost;
  final String connectionServiceName;
  final String? entity;
  final String? operation;
  final String? action;

  final RestApiTool _restApiTool;
  final Object? authScheme;
  final AuthCredential? authCredential;

  @override
  FunctionDeclaration? getDeclaration() {
    final FunctionDeclaration? baseDeclaration = _restApiTool.getDeclaration();
    final Map<String, Object?> schema = _readMap(baseDeclaration?.parameters);

    final Map<String, Object?> properties = _readMap(schema['properties']);
    final List<Object?> required = _readList(schema['required']);

    for (final String field in excludeFields) {
      properties.remove(field);
    }

    final Set<String> removable = <String>{...optionalFields, ...excludeFields};
    required.removeWhere((Object? item) => removable.contains('$item'));

    schema['properties'] = properties;
    schema['required'] = required;

    if (isFeatureEnabled(FeatureName.jsonSchemaForFuncDecl)) {
      return FunctionDeclaration(
        name: name,
        description: description,
        parameters: schema,
      );
    }

    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: toGeminiSchema(schema.cast<String, dynamic>()),
    );
  }

  String? _prepareDynamicEuc(AuthCredential authCredential) {
    return authCredential.http?.credentials.token;
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final ToolAuthHandler toolAuthHandler = ToolAuthHandler.fromToolContext(
      toolContext,
      authScheme,
      authCredential,
    );
    final AuthPreparationResult authResult = await toolAuthHandler
        .prepareAuthCredentials();

    if (authResult.state == 'pending') {
      return <String, Object?>{
        'pending': true,
        'message': 'Needs your authorization to access your data.',
      };
    }

    if (authResult.authCredential != null) {
      final String? authCredentialToken = _prepareDynamicEuc(
        authResult.authCredential!,
      );
      if (authCredentialToken != null) {
        args['dynamic_auth_config'] = <String, Object?>{
          'oauth2_auth_code_flow.access_token': authCredentialToken,
        };
      } else {
        args['dynamic_auth_config'] = <String, Object?>{
          'oauth2_auth_code_flow.access_token': <String, Object?>{},
        };
      }
    }

    args['connection_name'] = connectionName;
    args['service_name'] = connectionServiceName;
    args['host'] = connectionHost;
    args['entity'] = entity;
    args['operation'] = operation;
    args['action'] = action;

    return _restApiTool.call(args: args, toolContext: toolContext);
  }

  @override
  String toString() {
    return 'IntegrationConnectorTool(name="$name", '
        'description="$description", connection_name="$connectionName", '
        'entity="$entity", operation="$operation", action="$action")';
  }
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map<String, dynamic>) {
    return value.map((String key, dynamic item) => MapEntry(key, item));
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<Object?> _readList(Object? value) {
  if (value is List<Object?>) {
    return List<Object?>.from(value);
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
}
