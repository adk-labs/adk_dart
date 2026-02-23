import 'dart:convert';
import 'dart:io';

import '../../agents/readonly_context.dart';
import '../../auth/auth_credential.dart';
import '../../auth/auth_schemes.dart';
import '../../auth/auth_tool.dart';
import '../../utils/yaml_utils.dart';
import '../_gemini_schema_util.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../openapi_tool/openapi_spec_parser/openapi_toolset.dart';
import 'clients/apihub_client.dart';

class APIHubToolset extends BaseToolset {
  APIHubToolset({
    required String apihubResourceName,
    String? accessToken,
    String? serviceAccountJson,
    this.name = '',
    this.description = '',
    bool lazyLoadSpec = false,
    AuthScheme? authScheme,
    AuthCredential? authCredential,
    BaseAPIHubClient? apihubClient,
    super.toolFilter,
  }) : _apihubResourceName = apihubResourceName,
       _authScheme = authScheme,
       _authCredential = authCredential,
       _apihubClient =
           apihubClient ??
           APIHubClient(
             accessToken: accessToken,
             serviceAccountJson: serviceAccountJson,
           ),
       _authConfig = authScheme == null
           ? null
           : AuthConfig(
               authScheme: _serializeAuthScheme(authScheme),
               rawAuthCredential: authCredential?.copyWith(),
             ) {
    if (!lazyLoadSpec) {
      _prepareFuture = _prepareToolset();
    }
  }

  String name;
  String description;

  final String _apihubResourceName;
  final BaseAPIHubClient _apihubClient;
  final Object? _authScheme;
  final AuthCredential? _authCredential;
  final AuthConfig? _authConfig;

  OpenAPIToolset? _openApiToolset;
  Future<void>? _prepareFuture;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    if (_openApiToolset == null) {
      await (_prepareFuture ??= _prepareToolset());
    }

    final OpenAPIToolset? toolset = _openApiToolset;
    if (toolset == null) {
      return <BaseTool>[];
    }

    return toolset.getTools(readonlyContext: readonlyContext);
  }

  Future<void> _prepareToolset() async {
    if (_openApiToolset != null) {
      return;
    }

    final String specStr = await _apihubClient.getSpecContent(
      _apihubResourceName,
    );
    final Map<String, Object?> specDict = _parseSpec(specStr);
    if (specDict.isEmpty) {
      return;
    }

    final Map<String, Object?> info = _readMap(specDict['info']);
    if (name.isEmpty) {
      name = toSnakeCase(_readString(info['title']) ?? 'unnamed');
    }
    if (description.isEmpty) {
      description = _readString(info['description']) ?? '';
    }

    _openApiToolset = OpenAPIToolset(
      specDict: specDict,
      authCredential: _authCredential,
      authScheme: _authScheme,
      toolFilter: toolFilter,
    );
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

Map<String, Object?> _parseSpec(String specStr) {
  final String trimmed = specStr.trim();
  if (trimmed.isEmpty) {
    return <String, Object?>{};
  }

  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    final Object? decoded = jsonDecode(trimmed);
    return _readMap(decoded);
  }

  final Directory tempDir = Directory.systemTemp.createTempSync('adk_apihub_');
  try {
    final File file = File('${tempDir.path}/spec.yaml');
    file.writeAsStringSync(specStr);
    final Object? parsed = loadYamlFile(file.path);
    return _readMap(parsed);
  } finally {
    tempDir.deleteSync(recursive: true);
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
