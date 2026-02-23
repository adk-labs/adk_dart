import 'dart:convert';
import 'dart:io';

class ApiHubHttpResponse {
  ApiHubHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

typedef ApiHubRequestExecutor =
    Future<ApiHubHttpResponse> Function({
      required Uri uri,
      required String method,
      required Map<String, String> headers,
    });

typedef ApiHubAccessTokenProvider =
    Future<String?> Function({String? serviceAccountJson});

class APIHubResourceNames {
  APIHubResourceNames({
    required this.apiResourceName,
    this.apiVersionResourceName,
    this.apiSpecResourceName,
  });

  final String apiResourceName;
  final String? apiVersionResourceName;
  final String? apiSpecResourceName;
}

abstract class BaseAPIHubClient {
  Future<String> getSpecContent(String resourceName);
}

class APIHubClient implements BaseAPIHubClient {
  APIHubClient({
    this.accessToken,
    this.serviceAccountJson,
    ApiHubRequestExecutor? requestExecutor,
    ApiHubAccessTokenProvider? accessTokenProvider,
  }) : _requestExecutor = requestExecutor ?? _defaultApiHubRequestExecutor,
       _accessTokenProvider =
           accessTokenProvider ?? _defaultApiHubAccessTokenProvider;

  final String rootUrl = 'https://apihub.googleapis.com/v1';
  final String? accessToken;
  final String? serviceAccountJson;

  final ApiHubRequestExecutor _requestExecutor;
  final ApiHubAccessTokenProvider _accessTokenProvider;

  String? _cachedAccessToken;

  @override
  Future<String> getSpecContent(String path) async {
    final APIHubResourceNames resourceNames = extractResourceName(path);

    String? apiVersionResourceName = resourceNames.apiVersionResourceName;
    String? apiSpecResourceName = resourceNames.apiSpecResourceName;

    if (resourceNames.apiResourceName.isNotEmpty &&
        apiVersionResourceName == null) {
      final Map<String, Object?> api = await getApi(
        resourceNames.apiResourceName,
      );
      final List<Object?> versions = _readList(api['versions']);
      if (versions.isEmpty) {
        throw ArgumentError(
          'No versions found in API Hub resource: '
          '${resourceNames.apiResourceName}',
        );
      }
      apiVersionResourceName = _readString(versions.first);
    }

    if (apiVersionResourceName != null && apiSpecResourceName == null) {
      final Map<String, Object?> apiVersion = await getApiVersion(
        apiVersionResourceName,
      );
      final List<Object?> specResourceNames = _readList(apiVersion['specs']);
      if (specResourceNames.isEmpty) {
        throw ArgumentError(
          'No specs found in API Hub version: $apiVersionResourceName',
        );
      }
      apiSpecResourceName = _readString(specResourceNames.first);
    }

    if (apiSpecResourceName != null && apiSpecResourceName.isNotEmpty) {
      return _fetchSpec(apiSpecResourceName);
    }

    throw ArgumentError('No API Hub resource found in path: {path}');
  }

  Future<List<Map<String, Object?>>> listApis(
    String project,
    String location,
  ) async {
    final Uri url = Uri.parse(
      '$rootUrl/projects/$project/locations/$location/apis',
    );
    final Map<String, Object?> json = await _getJson(url);
    return _readList(
      json['apis'],
    ).map((Object? value) => _readMap(value)).toList(growable: false);
  }

  Future<Map<String, Object?>> getApi(String apiResourceName) async {
    final Uri url = Uri.parse('$rootUrl/$apiResourceName');
    return _getJson(url);
  }

  Future<Map<String, Object?>> getApiVersion(String apiVersionName) async {
    final Uri url = Uri.parse('$rootUrl/$apiVersionName');
    return _getJson(url);
  }

  APIHubResourceNames extractResourceName(String urlOrPath) {
    String path;
    Map<String, List<String>>? queryParams;

    try {
      final Uri parsedUrl = Uri.parse(urlOrPath);
      path = parsedUrl.path;
      queryParams = parsedUrl.queryParametersAll;

      if (path.contains('api-hub/')) {
        path = path.split('api-hub')[1];
      }
    } catch (_) {
      path = urlOrPath;
    }

    final List<String> pathSegments = path
        .split('/')
        .where((String segment) => segment.isNotEmpty)
        .toList(growable: false);

    String? project;
    String? location;
    String? apiId;
    String? versionId;
    String? specId;

    final int projectIndex = pathSegments.indexOf('projects');
    if (projectIndex >= 0 && projectIndex + 1 < pathSegments.length) {
      project = pathSegments[projectIndex + 1];
    } else if (queryParams != null &&
        queryParams['project']?.isNotEmpty == true) {
      project = queryParams['project']!.first;
    }

    if (project == null || project.isEmpty) {
      throw ArgumentError(
        'Project ID not found in URL or path in APIHubClient. Input path is '
        "'$urlOrPath'. Please make sure there is either "
        "'/projects/PROJECT_ID' in the path or 'project=PROJECT_ID' query "
        'param in the input.',
      );
    }

    final int locationIndex = pathSegments.indexOf('locations');
    if (locationIndex >= 0 && locationIndex + 1 < pathSegments.length) {
      location = pathSegments[locationIndex + 1];
    }
    if (location == null || location.isEmpty) {
      throw ArgumentError(
        'Location not found in URL or path in APIHubClient. Input path is '
        "'$urlOrPath'. Please make sure there is either "
        "'/location/LOCATION_ID' in the path.",
      );
    }

    final int apiIndex = pathSegments.indexOf('apis');
    if (apiIndex >= 0 && apiIndex + 1 < pathSegments.length) {
      apiId = pathSegments[apiIndex + 1];
    }
    if (apiId == null || apiId.isEmpty) {
      throw ArgumentError(
        'API id not found in URL or path in APIHubClient. Input path is '
        "'$urlOrPath'. Please make sure there is either '/apis/API_ID' in "
        'the path.',
      );
    }

    final int versionIndex = pathSegments.indexOf('versions');
    if (versionIndex >= 0 && versionIndex + 1 < pathSegments.length) {
      versionId = pathSegments[versionIndex + 1];
    }

    final int specIndex = pathSegments.indexOf('specs');
    if (specIndex >= 0 && specIndex + 1 < pathSegments.length) {
      specId = pathSegments[specIndex + 1];
    }

    final String apiResourceName =
        'projects/$project/locations/$location/apis/$apiId';
    final String? apiVersionResourceName = versionId == null
        ? null
        : '$apiResourceName/versions/$versionId';
    final String? apiSpecResourceName =
        versionId != null && specId != null && apiVersionResourceName != null
        ? '$apiVersionResourceName/specs/$specId'
        : null;

    return APIHubResourceNames(
      apiResourceName: apiResourceName,
      apiVersionResourceName: apiVersionResourceName,
      apiSpecResourceName: apiSpecResourceName,
    );
  }

  Future<Map<String, Object?>> _getJson(Uri url) async {
    final ApiHubHttpResponse response = await _requestExecutor(
      uri: url,
      method: 'GET',
      headers: <String, String>{
        'accept': 'application/json, text/plain, */*',
        HttpHeaders.authorizationHeader: 'Bearer ${await _getAccessToken()}',
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
  }

  Future<String> _fetchSpec(String apiSpecResourceName) async {
    final Uri url = Uri.parse('$rootUrl/$apiSpecResourceName:contents');
    final Map<String, Object?> json = await _getJson(url);
    final String contentBase64 = _readString(json['contents']) ?? '';
    if (contentBase64.isEmpty) {
      return '';
    }
    return utf8.decode(base64Decode(contentBase64));
  }

  Future<String> _getAccessToken() async {
    if (accessToken != null && accessToken!.isNotEmpty) {
      return accessToken!;
    }

    if (_cachedAccessToken != null && _cachedAccessToken!.isNotEmpty) {
      return _cachedAccessToken!;
    }

    final String? resolved = await _accessTokenProvider(
      serviceAccountJson: serviceAccountJson,
    );
    if (resolved == null || resolved.isEmpty) {
      throw ArgumentError(
        'Please provide a service account or an access token to API Hub client.',
      );
    }

    _cachedAccessToken = resolved;
    return resolved;
  }
}

Future<ApiHubHttpResponse> _defaultApiHubRequestExecutor({
  required Uri uri,
  required String method,
  required Map<String, String> headers,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decodeStream(response);
    return ApiHubHttpResponse(statusCode: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

Future<String?> _defaultApiHubAccessTokenProvider({
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
