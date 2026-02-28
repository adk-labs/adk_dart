import '../agents/context.dart';
import '../agents/invocation_context.dart';
import '../agents/readonly_context.dart';
import '../events/event.dart';
import '../flows/llm_flows/base_llm_flow.dart';
import '../flows/llm_flows/functions.dart' as flow_functions;
import '../models/llm_request.dart';
import '../tools/base_tool.dart';
import '../types/content.dart';
import 'auth_handler.dart';
import 'auth_credential.dart';
import 'auth_tool.dart';

/// Handles auth responses and resumes paused tool calls after credential input.
class AuthLlmRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(InvocationContext context, LlmRequest request) async* {
    final List<Event> events = context.session.events;
    if (events.isEmpty) {
      return;
    }

    final Event? lastWithContent = _findLastEventWithContent(events);
    if (lastWithContent == null || lastWithContent.author != 'user') {
      return;
    }

    final List<FunctionResponse> authResponses = lastWithContent
        .getFunctionResponses()
        .where(
          (FunctionResponse response) =>
              response.name == flow_functions.requestEucFunctionCallName,
        )
        .toList(growable: false);
    if (authResponses.isEmpty) {
      return;
    }

    final Set<String> requestFunctionCallIds = authResponses
        .map((FunctionResponse response) => response.id)
        .whereType<String>()
        .toSet();
    if (requestFunctionCallIds.isEmpty) {
      return;
    }

    final Map<String, AuthConfig> requestedAuthConfigByRequestId =
        _collectRequestedAuthConfigs(events, requestFunctionCallIds);

    for (final FunctionResponse response in authResponses) {
      final AuthConfig authConfig = _parseAuthConfig(response.response);
      final String? requestId = response.id;
      final AuthConfig? requestedAuthConfig = requestId == null
          ? null
          : requestedAuthConfigByRequestId[requestId];
      if (requestedAuthConfig?.credentialKey.isNotEmpty == true) {
        authConfig.credentialKey = requestedAuthConfig!.credentialKey;
      }
      await AuthHandler(
        authConfig: authConfig,
      ).parseAndStoreAuthResponse(Context(context).state);
    }

    final Set<String> toolsToResume = _collectToolsToResume(
      events,
      requestFunctionCallIds,
    );
    if (toolsToResume.isEmpty) {
      return;
    }

    final Map<String, BaseTool> toolsDict = await _buildToolsDict(context);
    if (toolsDict.isEmpty) {
      return;
    }

    for (int i = events.length - 1; i >= 0; i -= 1) {
      final Event event = events[i];
      final bool hasMatchingCall = event.getFunctionCalls().any(
        (FunctionCall call) =>
            call.id != null && toolsToResume.contains(call.id!),
      );
      if (!hasMatchingCall) {
        continue;
      }

      final Event? resumed = await flow_functions.handleFunctionCallsAsync(
        context,
        event,
        toolsDict,
        filters: toolsToResume,
      );
      if (resumed != null) {
        yield resumed;
      }
      return;
    }
  }

  Event? _findLastEventWithContent(List<Event> events) {
    for (int i = events.length - 1; i >= 0; i -= 1) {
      final Event event = events[i];
      if (event.content != null) {
        return event;
      }
    }
    return null;
  }

  Map<String, AuthConfig> _collectRequestedAuthConfigs(
    List<Event> events,
    Set<String> requestFunctionCallIds,
  ) {
    final Map<String, AuthConfig> configs = <String, AuthConfig>{};
    for (final Event event in events) {
      for (final FunctionCall call in event.getFunctionCalls()) {
        final String? requestId = call.id;
        if (requestId == null ||
            !requestFunctionCallIds.contains(requestId) ||
            call.name != flow_functions.requestEucFunctionCallName) {
          continue;
        }

        final Object? rawAuthConfig = call.args['auth_config'];
        if (rawAuthConfig == null) {
          continue;
        }
        configs[requestId] = _parseAuthConfig(rawAuthConfig);
      }
    }
    return configs;
  }

  Set<String> _collectToolsToResume(
    List<Event> events,
    Set<String> requestFunctionCallIds,
  ) {
    final Set<String> toolIds = <String>{};
    for (final Event event in events) {
      for (final FunctionCall call in event.getFunctionCalls()) {
        final String? requestId = call.id;
        if (requestId == null ||
            !requestFunctionCallIds.contains(requestId) ||
            call.name != flow_functions.requestEucFunctionCallName) {
          continue;
        }

        final String? functionCallId = _readFunctionCallId(call.args);
        if (functionCallId == null ||
            functionCallId.startsWith(toolsetAuthCredentialIdPrefix)) {
          continue;
        }
        toolIds.add(functionCallId);
      }
    }
    return toolIds;
  }

  String? _readFunctionCallId(Map<String, dynamic> args) {
    final Object? raw =
        args['function_call_id'] ??
        args['functionCallId'] ??
        args['function_call'];
    if (raw is String && raw.isNotEmpty) {
      return raw;
    }
    return null;
  }

  Future<Map<String, BaseTool>> _buildToolsDict(
    InvocationContext context,
  ) async {
    final dynamic agent = context.agent;
    try {
      final Object? toolsRaw = await agent.canonicalTools(
        ReadonlyContext(context),
      );
      if (toolsRaw is! List) {
        return <String, BaseTool>{};
      }

      final Map<String, BaseTool> dict = <String, BaseTool>{};
      for (final Object? item in toolsRaw) {
        if (item is BaseTool) {
          dict[item.name] = item;
        }
      }
      return dict;
    } catch (_) {
      return <String, BaseTool>{};
    }
  }

  AuthConfig _parseAuthConfig(Object? raw) {
    if (raw is AuthConfig) {
      return raw;
    }
    if (raw is! Map) {
      throw ArgumentError('Invalid auth config response: $raw');
    }

    final Map<Object?, Object?> map = raw;
    final String authScheme =
        _readString(map['authScheme']) ??
        _readString(map['auth_scheme']) ??
        _readString(map['scheme']) ??
        'unknown';

    final AuthConfig config = AuthConfig(
      authScheme: authScheme,
      credentialKey:
          _readString(map['credentialKey']) ??
          _readString(map['credential_key']),
      rawAuthCredential: _parseAuthCredential(
        map['rawAuthCredential'] ?? map['raw_auth_credential'],
      ),
      exchangedAuthCredential: _parseAuthCredential(
        map['exchangedAuthCredential'] ?? map['exchanged_auth_credential'],
      ),
    );
    return config;
  }

  AuthCredential? _parseAuthCredential(Object? raw) {
    if (raw is AuthCredential) {
      return raw.copyWith();
    }
    if (raw is! Map) {
      return null;
    }

    final Map<Object?, Object?> map = raw;
    final AuthCredentialType? authType = _parseAuthCredentialType(
      _readString(map['authType']) ?? _readString(map['auth_type']),
    );
    if (authType == null) {
      return null;
    }

    return AuthCredential(
      authType: authType,
      resourceRef:
          _readString(map['resourceRef']) ?? _readString(map['resource_ref']),
      apiKey: _readString(map['apiKey']) ?? _readString(map['api_key']),
      http: _parseHttpAuth(map['http']),
      oauth2: _parseOAuth2Auth(map['oauth2']),
      serviceAccount: _parseServiceAccountAuth(
        map['serviceAccount'] ?? map['service_account'],
      ),
    );
  }

  HttpAuth? _parseHttpAuth(Object? raw) {
    if (raw is HttpAuth) {
      return raw;
    }
    if (raw is! Map) {
      return null;
    }
    final Map<Object?, Object?> map = raw;

    final HttpCredentials credentials = HttpCredentials(
      username: _readString(map['username']),
      password: _readString(map['password']),
      token: _readString(map['token']),
    );

    final Map<String, String> headers = <String, String>{};
    final Object? additionalHeaders =
        map['additionalHeaders'] ?? map['additional_headers'];
    if (additionalHeaders is Map) {
      for (final MapEntry<Object?, Object?> entry
          in additionalHeaders.entries) {
        final Object? key = entry.key;
        if (key is! String) {
          continue;
        }
        headers[key] = '${entry.value ?? ''}';
      }
    }

    return HttpAuth(
      scheme: _readString(map['scheme']) ?? 'bearer',
      credentials: credentials,
      additionalHeaders: headers,
    );
  }

  OAuth2Auth? _parseOAuth2Auth(Object? raw) {
    if (raw is OAuth2Auth) {
      return raw;
    }
    if (raw is! Map) {
      return null;
    }
    final Map<Object?, Object?> map = raw;
    return OAuth2Auth(
      clientId: _readString(map['clientId']) ?? _readString(map['client_id']),
      clientSecret:
          _readString(map['clientSecret']) ?? _readString(map['client_secret']),
      authUri: _readString(map['authUri']) ?? _readString(map['auth_uri']),
      state: _readString(map['state']),
      redirectUri:
          _readString(map['redirectUri']) ?? _readString(map['redirect_uri']),
      authResponseUri:
          _readString(map['authResponseUri']) ??
          _readString(map['auth_response_uri']),
      authCode: _readString(map['authCode']) ?? _readString(map['auth_code']),
      accessToken:
          _readString(map['accessToken']) ?? _readString(map['access_token']),
      refreshToken:
          _readString(map['refreshToken']) ?? _readString(map['refresh_token']),
      idToken: _readString(map['idToken']) ?? _readString(map['id_token']),
      expiresAt: _readInt(map['expiresAt']) ?? _readInt(map['expires_at']),
      expiresIn: _readInt(map['expiresIn']) ?? _readInt(map['expires_in']),
      audience: _readString(map['audience']),
      tokenEndpointAuthMethod:
          _readString(
            map['tokenEndpointAuthMethod'] ?? map['token_endpoint_auth_method'],
          ) ??
          'client_secret_basic',
    );
  }

  ServiceAccountAuth? _parseServiceAccountAuth(Object? raw) {
    if (raw is ServiceAccountAuth) {
      return raw;
    }
    if (raw is! Map) {
      return null;
    }
    final Map<Object?, Object?> map = raw;

    ServiceAccountCredential? credential;
    final Object? rawCredential =
        map['serviceAccountCredential'] ?? map['service_account_credential'];
    if (rawCredential is ServiceAccountCredential) {
      credential = rawCredential;
    } else if (rawCredential is Map) {
      final Map<Object?, Object?> c = rawCredential;
      final String? projectId =
          _readString(c['projectId']) ?? _readString(c['project_id']);
      final String? privateKeyId =
          _readString(c['privateKeyId']) ?? _readString(c['private_key_id']);
      final String? privateKey =
          _readString(c['privateKey']) ?? _readString(c['private_key']);
      final String? clientEmail =
          _readString(c['clientEmail']) ?? _readString(c['client_email']);
      final String? clientId =
          _readString(c['clientId']) ?? _readString(c['client_id']);
      final String? authUri =
          _readString(c['authUri']) ?? _readString(c['auth_uri']);
      final String? tokenUri =
          _readString(c['tokenUri']) ?? _readString(c['token_uri']);
      if (projectId != null &&
          privateKeyId != null &&
          privateKey != null &&
          clientEmail != null &&
          clientId != null &&
          authUri != null &&
          tokenUri != null) {
        credential = ServiceAccountCredential(
          projectId: projectId,
          privateKeyId: privateKeyId,
          privateKey: privateKey,
          clientEmail: clientEmail,
          clientId: clientId,
          authUri: authUri,
          tokenUri: tokenUri,
        );
      }
    }

    final List<String> scopes = <String>[];
    final Object? rawScopes = map['scopes'];
    if (rawScopes is List) {
      for (final Object? scope in rawScopes) {
        if (scope is String) {
          scopes.add(scope);
        }
      }
    }

    return ServiceAccountAuth(
      serviceAccountCredential: credential,
      scopes: scopes,
      useDefaultCredential:
          _readBool(map['useDefaultCredential']) ??
          _readBool(map['use_default_credential']) ??
          false,
    );
  }

  AuthCredentialType? _parseAuthCredentialType(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    for (final AuthCredentialType type in AuthCredentialType.values) {
      if (type.name.toLowerCase() == value.toLowerCase()) {
        return type;
      }
    }

    switch (value.toLowerCase()) {
      case 'open_id_connect':
      case 'openidconnect':
      case 'openid_connect':
        return AuthCredentialType.openIdConnect;
      default:
        return null;
    }
  }

  String? _readString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    return '$value';
  }

  int? _readInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  bool? _readBool(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    if (value is String) {
      if (value.toLowerCase() == 'true') {
        return true;
      }
      if (value.toLowerCase() == 'false') {
        return false;
      }
    }
    return null;
  }
}
