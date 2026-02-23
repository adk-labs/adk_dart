import 'dart:async';

import 'function_tool.dart';
import 'tool_context.dart';
import '_google_credentials.dart';

class GoogleTool extends FunctionTool {
  GoogleTool({
    required Function func,
    BaseGoogleCredentialsConfig? credentialsConfig,
    this.toolSettings,
    String? name,
    String? description,
    super.requireConfirmation,
  }) : _credentialsManager = credentialsConfig == null
           ? null
           : GoogleCredentialsManager(credentialsConfig),
       super(func: func, name: name, description: description);

  final GoogleCredentialsManager? _credentialsManager;
  final Object? toolSettings;

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    try {
      final Object? credentials = await _credentialsManager
          ?.getValidCredentials(toolContext);
      if (credentials == null && _credentialsManager != null) {
        return 'User authorization is required to access Google services for $name. Please complete the authorization flow.';
      }

      final Map<String, dynamic> enrichedArgs = Map<String, dynamic>.from(args);
      if (credentials != null) {
        enrichedArgs['credentials'] = credentials;
      }
      if (toolSettings != null) {
        enrichedArgs['settings'] = toolSettings;
      }

      try {
        return await _invokeWithFallbacks(
          target: func,
          args: enrichedArgs,
          toolContext: toolContext,
        );
      } catch (_) {
        return super.run(args: args, toolContext: toolContext);
      }
    } catch (error) {
      return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
    }
  }

  Future<Object?> _invokeWithFallbacks({
    required Function target,
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final List<InvocationPlan> plans = <InvocationPlan>[
      InvocationPlan(
        positional: const <Object?>[],
        named: <Symbol, Object?>{
          ..._namedArgs(args),
          #toolContext: toolContext,
        },
      ),
      InvocationPlan(positional: const <Object?>[], named: _namedArgs(args)),
      InvocationPlan(
        positional: args.values.toList(),
        named: <Symbol, Object?>{#toolContext: toolContext},
      ),
      InvocationPlan(positional: args.values.toList()),
      InvocationPlan(positional: <Object?>[args, toolContext]),
      InvocationPlan(positional: <Object?>[args]),
      InvocationPlan(positional: <Object?>[toolContext]),
      InvocationPlan(positional: const <Object?>[]),
    ];

    Object? lastError;
    for (final InvocationPlan plan in plans) {
      try {
        final Object? result = Function.apply(
          target,
          plan.positional,
          plan.named,
        );
        if (result is Future<Object?>) {
          return result;
        }
        if (result is Future) {
          return await result;
        }
        return result;
      } catch (error) {
        lastError = error;
      }
    }

    throw StateError(
      'Failed to invoke google tool `$name` with args `$args`: $lastError',
    );
  }

  Map<Symbol, Object?> _namedArgs(Map<String, dynamic> args) {
    return <Symbol, Object?>{
      for (final MapEntry<String, dynamic> entry in args.entries)
        Symbol(entry.key): entry.value,
    };
  }
}
