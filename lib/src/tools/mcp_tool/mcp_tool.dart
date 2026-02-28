import 'dart:convert';

import '../../agents/readonly_context.dart';
import '../../auth/auth_credential.dart';
import '../../auth/auth_tool.dart';
import '../../models/llm_request.dart';
import '../base_authenticated_tool.dart';
import '../tool_context.dart';
import 'mcp_session_manager.dart';

typedef McpToolHeaderProvider =
    Map<String, String> Function(ReadonlyContext readonlyContext);

class McpBaseTool {
  McpBaseTool({
    required this.name,
    this.description = '',
    Map<String, dynamic>? inputSchema,
    Map<String, dynamic>? outputSchema,
  }) : inputSchema = inputSchema ?? <String, dynamic>{},
       outputSchema = outputSchema ?? <String, dynamic>{};

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Map<String, dynamic> outputSchema;
}

class McpTool extends BaseAuthenticatedTool {
  McpTool({
    required McpBaseTool mcpTool,
    required McpConnectionParams connectionParams,
    required McpSessionManager sessionManager,
    AuthConfig? authConfig,
    Object requireConfirmation = false,
    this.headerProvider,
  }) : _mcpTool = mcpTool,
       _connectionParams = connectionParams,
       _sessionManager = sessionManager,
       _requireConfirmation = requireConfirmation,
       super(
         name: mcpTool.name,
         description: mcpTool.description,
         authConfig: authConfig,
       );

  final McpBaseTool _mcpTool;
  final McpConnectionParams _connectionParams;
  final McpSessionManager _sessionManager;
  final Object _requireConfirmation;
  final McpToolHeaderProvider? headerProvider;

  McpBaseTool get rawMcpTool => _mcpTool;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: Map<String, dynamic>.from(_mcpTool.inputSchema),
    );
  }

  @override
  Future<Object?> runAuthenticated({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
    required AuthCredential? credential,
  }) async {
    final bool needsConfirmation = await _evaluateRequireConfirmation(
      args: args,
      toolContext: toolContext,
    );
    if (needsConfirmation) {
      if (toolContext.toolConfirmation == null) {
        toolContext.requestConfirmation(
          hint:
              'Please approve or reject the tool call $name() with a tool confirmation payload.',
        );
        return <String, Object>{
          'error':
              'This tool call requires confirmation, please approve or reject.',
        };
      }
      if (toolContext.toolConfirmation?.confirmed != true) {
        return <String, Object>{'error': 'This tool call is rejected.'};
      }
    }

    final Map<String, String> headers = <String, String>{};
    headers.addAll(_headersFromCredential(credential));
    if (headerProvider != null) {
      headers.addAll(
        headerProvider!(ReadonlyContext(toolContext.invocationContext)),
      );
    }

    final Object? response = await _sessionManager.callTool(
      connectionParams: _connectionParams,
      toolName: _mcpTool.name,
      args: args,
      headers: headers.isEmpty ? null : headers,
    );
    return response;
  }

  Future<bool> _evaluateRequireConfirmation({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    if (_requireConfirmation is bool) {
      return _requireConfirmation;
    }
    if (_requireConfirmation is! Function) {
      return false;
    }

    final Function predicate = _requireConfirmation as Function;
    final List<_InvocationPlan> plans = <_InvocationPlan>[
      _InvocationPlan(
        positional: const <Object?>[],
        named: <Symbol, Object?>{
          ..._toNamedArgs(args),
          #toolContext: toolContext,
        },
      ),
      _InvocationPlan(positional: const <Object?>[], named: _toNamedArgs(args)),
      _InvocationPlan(positional: <Object?>[args, toolContext]),
      _InvocationPlan(positional: <Object?>[args]),
      _InvocationPlan(positional: const <Object?>[]),
    ];

    for (final _InvocationPlan plan in plans) {
      try {
        final Object? value = Function.apply(
          predicate,
          plan.positional,
          plan.named,
        );
        if (value is Future<bool>) {
          return value;
        }
        if (value is Future) {
          final Object? resolved = await value;
          return resolved == true;
        }
        return value == true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  Map<Symbol, Object?> _toNamedArgs(Map<String, dynamic> args) {
    return <Symbol, Object?>{
      for (final MapEntry<String, dynamic> entry in args.entries)
        Symbol(entry.key): entry.value,
    };
  }

  Map<String, String> _headersFromCredential(AuthCredential? credential) {
    if (credential == null) {
      return <String, String>{};
    }
    switch (credential.authType) {
      case AuthCredentialType.apiKey:
        if (credential.apiKey == null || credential.apiKey!.isEmpty) {
          return <String, String>{};
        }
        return <String, String>{'x-api-key': credential.apiKey!};
      case AuthCredentialType.http:
        return _headersFromHttp(credential.http);
      case AuthCredentialType.oauth2:
      case AuthCredentialType.openIdConnect:
        final String? accessToken = credential.oauth2?.accessToken;
        if (accessToken == null || accessToken.isEmpty) {
          return <String, String>{};
        }
        return <String, String>{'Authorization': 'Bearer $accessToken'};
      case AuthCredentialType.serviceAccount:
        return <String, String>{};
    }
  }

  Map<String, String> _headersFromHttp(HttpAuth? http) {
    if (http == null) {
      return <String, String>{};
    }
    final Map<String, String> headers = <String, String>{
      ...http.additionalHeaders,
    };
    final String scheme = http.scheme.trim().toLowerCase();
    final HttpCredentials credentials = http.credentials;
    if (scheme == 'bearer' && credentials.token != null) {
      headers['Authorization'] = 'Bearer ${credentials.token}';
    } else if (scheme == 'basic' &&
        credentials.username != null &&
        credentials.password != null) {
      final String encoded = base64Encode(
        utf8.encode('${credentials.username}:${credentials.password}'),
      );
      headers['Authorization'] = 'Basic $encoded';
    } else if (credentials.token != null && credentials.token!.isNotEmpty) {
      headers['Authorization'] = '${http.scheme} ${credentials.token}';
    }
    return headers;
  }
}

class _InvocationPlan {
  _InvocationPlan({required this.positional, Map<Symbol, Object?>? named})
    : named = named ?? const <Symbol, Object?>{};

  final List<Object?> positional;
  final Map<Symbol, Object?> named;
}
