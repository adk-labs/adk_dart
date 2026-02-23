import 'dart:convert';
import 'dart:io';

import '../../../agents/readonly_context.dart';
import '../../../auth/auth_credential.dart';
import '../../../auth/auth_schemes.dart';
import '../../../auth/auth_tool.dart';
import '../../../utils/yaml_utils.dart';
import '../../base_tool.dart';
import '../../base_toolset.dart';
import 'openapi_spec_parser.dart';
import 'rest_api_tool.dart';

class OpenAPIToolset extends BaseToolset {
  OpenAPIToolset({
    Map<String, Object?>? specDict,
    String? specStr,
    String specStrType = 'json',
    Object? authScheme,
    AuthCredential? authCredential,
    String? credentialKey,
    super.toolFilter,
    super.toolNamePrefix,
    Object? sslVerify,
    HeaderProvider? headerProvider,
    RestApiRequestExecutor? requestExecutor,
  }) : _headerProvider = headerProvider,
       _sslVerify = sslVerify,
       _requestExecutor = requestExecutor,
       _authConfig = authScheme == null
           ? null
           : AuthConfig(
               authScheme: _serializeAuthScheme(authScheme),
               rawAuthCredential: authCredential?.copyWith(),
               credentialKey: credentialKey,
             ) {
    final Map<String, Object?> parsedSpec =
        specDict ?? _loadSpec(specStr, specStrType);
    _tools = _parse(parsedSpec);

    if (authScheme != null || authCredential != null) {
      _configureAuthAll(authScheme, authCredential);
    }
    if (credentialKey != null && credentialKey.isNotEmpty) {
      _configureCredentialKeyAll(credentialKey);
    }
  }

  final HeaderProvider? _headerProvider;
  final AuthConfig? _authConfig;
  final RestApiRequestExecutor? _requestExecutor;

  Object? _sslVerify;
  late final List<RestApiTool> _tools;

  void _configureAuthAll(Object? authScheme, AuthCredential? authCredential) {
    for (final RestApiTool tool in _tools) {
      if (authScheme != null) {
        tool.configureAuthScheme(authScheme);
      }
      if (authCredential != null) {
        tool.configureAuthCredential(authCredential);
      }
    }
  }

  void _configureCredentialKeyAll(String credentialKey) {
    for (final RestApiTool tool in _tools) {
      tool.configureCredentialKey(credentialKey);
    }
  }

  void configureSslVerifyAll([Object? sslVerify]) {
    _sslVerify = sslVerify;
    for (final RestApiTool tool in _tools) {
      tool.configureSslVerify(sslVerify);
    }
  }

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return _tools
        .where((RestApiTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  RestApiTool? getTool(String toolName) {
    for (final RestApiTool tool in _tools) {
      if (tool.name == toolName) {
        return tool;
      }
    }
    return null;
  }

  Map<String, Object?> _loadSpec(String? specStr, String specType) {
    if (specStr == null || specStr.trim().isEmpty) {
      throw ArgumentError('Either specDict or specStr must be provided.');
    }

    if (specType == 'json') {
      final Object? decoded = jsonDecode(specStr);
      return _readMap(decoded);
    }

    if (specType == 'yaml') {
      return _loadYamlSpec(specStr);
    }

    throw ArgumentError('Unsupported spec type: $specType');
  }

  Map<String, Object?> _loadYamlSpec(String specStr) {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'adk_openapi_',
    );
    try {
      final File file = File('${tempDir.path}/spec.yaml');
      file.writeAsStringSync(specStr);
      final Object? parsed = loadYamlFile(file.path);
      return _readMap(parsed);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  }

  List<RestApiTool> _parse(Map<String, Object?> openapiSpecDict) {
    final List<ParsedOperation> operations = OpenApiSpecParser().parse(
      openapiSpecDict,
    );

    final List<RestApiTool> tools = <RestApiTool>[];
    for (final ParsedOperation operation in operations) {
      final RestApiTool tool = RestApiTool.fromParsedOperation(
        operation,
        sslVerify: _sslVerify,
        headerProvider: _headerProvider,
        requestExecutor: _requestExecutor,
      );
      tools.add(tool);
    }
    return tools;
  }

  @override
  Future<void> close() async {}

  @override
  AuthConfig? getAuthConfig() {
    return _authConfig?.copyWith();
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
