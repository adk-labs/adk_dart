/// MCP tool wrappers and normalized descriptor models.
library;

import 'dart:convert';

import '../../agents/readonly_context.dart';
import '../../auth/auth_credential.dart';
import '../../events/ui_widget.dart';
import '../../models/llm_request.dart';
import '../base_authenticated_tool.dart';
import '../tool_context.dart';
import 'mcp_session_manager.dart';

/// Header-builder callback used before making MCP tool HTTP calls.
typedef McpToolHeaderProvider =
    Map<String, String> Function(ReadonlyContext readonlyContext);

/// Lightweight MCP tool descriptor used by [McpTool].
class McpBaseTool {
  /// Creates a normalized MCP tool descriptor.
  McpBaseTool({
    required this.name,
    this.description = '',
    Map<String, dynamic>? inputSchema,
    Map<String, dynamic>? outputSchema,
    Map<String, Object?>? meta,
  }) : inputSchema = inputSchema ?? <String, dynamic>{},
       outputSchema = outputSchema ?? <String, dynamic>{},
       meta = meta ?? <String, Object?>{};

  /// Tool name returned by MCP tool discovery.
  final String name;

  /// Human-readable tool description.
  final String description;

  /// Input JSON schema accepted by this tool.
  final Map<String, dynamic> inputSchema;

  /// Output JSON schema emitted by this tool.
  final Map<String, dynamic> outputSchema;

  /// Optional MCP metadata attached to the tool descriptor.
  final Map<String, Object?> meta;

  /// Serializes this descriptor to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'inputSchema': Map<String, dynamic>.from(inputSchema),
      'outputSchema': Map<String, dynamic>.from(outputSchema),
      if (meta.isNotEmpty) 'meta': Map<String, Object?>.from(meta),
    };
  }
}

/// Auth-aware MCP tool wrapper that delegates calls through [McpSessionManager].
class McpTool extends BaseAuthenticatedTool {
  /// Creates an MCP-backed tool.
  McpTool({
    required McpBaseTool mcpTool,
    required McpConnectionParams connectionParams,
    required McpSessionManager sessionManager,
    super.authConfig,
    Object requireConfirmation = false,
    this.headerProvider,
  }) : _mcpTool = mcpTool,
       _connectionParams = connectionParams,
       _sessionManager = sessionManager,
       _requireConfirmation = requireConfirmation,
       super(
         name: mcpTool.name,
         description: mcpTool.description,
       );

  final McpBaseTool _mcpTool;
  final McpConnectionParams _connectionParams;
  final McpSessionManager _sessionManager;
  final Object _requireConfirmation;

  /// Optional provider for dynamic per-request headers.
  final McpToolHeaderProvider? headerProvider;

  /// Raw MCP tool descriptor used by this wrapper.
  McpBaseTool get rawMcpTool => _mcpTool;

  /// Visibility hints declared on the MCP tool metadata.
  List<String> get visibility {
    final Object? ui = _mcpTool.meta['ui'];
    if (ui is Map) {
      final Object? value = ui['visibility'];
      if (value is List) {
        return value.map((Object? item) => '$item').toList(growable: false);
      }
    }
    return const <String>[];
  }

  /// MCP App UI resource URI, when declared by the tool metadata.
  String? get mcpAppResourceUri {
    final Object? ui = _mcpTool.meta['ui'];
    if (ui is Map) {
      final Object? value = ui['resourceUri'];
      if (value is String && value.startsWith('ui://')) {
        return value;
      }
    }
    final Object? flat = _mcpTool.meta['ui/resourceUri'];
    if (flat is String && flat.startsWith('ui://')) {
      return flat;
    }
    return null;
  }

  @override
  /// Returns a function declaration using MCP input schema as parameters.
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: Map<String, dynamic>.from(_mcpTool.inputSchema),
    );
  }

  @override
  /// Executes an authenticated MCP tool call.
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
    final String? resourceUri = mcpAppResourceUri;
    if (resourceUri != null) {
      toolContext.renderUiWidget(
        UiWidget(
          id: toolContext.functionCallId!,
          provider: 'mcp',
          payload: <String, Object?>{
            'resource_uri': resourceUri,
            'tool': _mcpTool.toJson(),
            'tool_args': Map<String, Object?>.from(args),
          },
        ),
      );
    }
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
