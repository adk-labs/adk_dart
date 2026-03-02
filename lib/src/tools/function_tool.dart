import 'dart:async';

import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// Callback signature for dynamic confirmation requirements.
typedef ConfirmationPredicate =
    FutureOr<bool> Function(Map<String, dynamic> args);

/// Wraps a Dart callable as a runtime tool.
class FunctionTool extends BaseTool {
  /// Creates a function-backed tool.
  ///
  /// [requireConfirmation] accepts either `bool`, [ConfirmationPredicate], or
  /// a plain function returning a truthy value.
  FunctionTool({
    required this.func,
    String? name,
    String? description,
    this.requireConfirmation = false,
  }) : super(name: name ?? 'function_tool', description: description ?? '');

  /// Target function invoked when the tool is called.
  final Function func;

  /// Confirmation policy for this tool call.
  final Object requireConfirmation;

  @override
  /// Returns a simple declaration derived from [name] and [description].
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(name: name, description: description);
  }

  @override
  /// Runs the wrapped function with argument-shape fallbacks.
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    if (await _requiresConfirmation(args)) {
      final confirmation = toolContext.toolConfirmation;
      if (confirmation == null) {
        toolContext.requestConfirmation(
          hint:
              'Please approve or reject this tool call with a confirmation payload.',
        );
        toolContext.actions.skipSummarization = true;
        return <String, Object>{
          'error':
              'This tool call requires confirmation, please approve or reject.',
        };
      }

      if (confirmation.confirmed != true) {
        return <String, Object>{'error': 'This tool call is rejected.'};
      }
    }

    return _invokeCallable(args, toolContext);
  }

  Future<bool> _requiresConfirmation(Map<String, dynamic> args) async {
    final Object requirement = requireConfirmation;
    if (requirement is bool) {
      return requirement;
    }

    if (requirement is ConfirmationPredicate) {
      final Object value = requirement(args);
      if (value is Future<bool>) {
        return value;
      }
      return value as bool;
    }

    if (requirement is Function) {
      final Object? result = await _invokeFunction(
        target: requirement,
        args: args,
        toolContext: null,
      );
      return result == true;
    }

    return false;
  }

  Future<Object?> _invokeCallable(
    Map<String, dynamic> args,
    ToolContext toolContext,
  ) async {
    final Object? value = await _invokeFunction(
      target: func,
      args: args,
      toolContext: toolContext,
    );
    return value;
  }

  Future<Object?> _invokeFunction({
    required Function target,
    required Map<String, dynamic> args,
    required ToolContext? toolContext,
  }) async {
    final List<InvocationPlan> plans = <InvocationPlan>[
      InvocationPlan(
        positional: const <Object?>[],
        named: <Symbol, Object?>{
          ..._namedArgs(args),
          if (toolContext != null) #toolContext: toolContext,
        },
      ),
      InvocationPlan(positional: const <Object?>[], named: _namedArgs(args)),
      InvocationPlan(
        positional: args.values.toList(),
        named: toolContext == null
            ? const <Symbol, Object?>{}
            : <Symbol, Object?>{#toolContext: toolContext},
      ),
      InvocationPlan(positional: args.values.toList()),
      InvocationPlan(
        positional: toolContext == null
            ? <Object?>[args]
            : <Object?>[args, toolContext],
      ),
      InvocationPlan(positional: <Object?>[args]),
      if (toolContext != null)
        InvocationPlan(positional: <Object?>[toolContext]),
      InvocationPlan(positional: const <Object?>[]),
    ];

    Object? lastInvocationError;
    for (final InvocationPlan plan in plans) {
      try {
        final Object? result = Function.apply(
          target,
          plan.positional,
          plan.named,
        );
        if (result is Future<Object?>) {
          return await result;
        }
        if (result is Future) {
          return await result;
        }
        return result;
      } catch (error, stackTrace) {
        if (_isInvocationShapeError(error)) {
          lastInvocationError = error;
          continue;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    throw StateError(
      'Failed to invoke function tool `$name` with args `$args`: '
      '$lastInvocationError',
    );
  }

  Map<Symbol, Object?> _namedArgs(Map<String, dynamic> args) {
    return <Symbol, Object?>{
      for (final MapEntry<String, dynamic> entry in args.entries)
        Symbol(entry.key): entry.value,
    };
  }

  bool _isInvocationShapeError(Object error) {
    return error is NoSuchMethodError ||
        error is ArgumentError ||
        error is TypeError;
  }
}

/// One invocation strategy used to call flexible user functions.
class InvocationPlan {
  /// Creates a function invocation plan with positional and named arguments.
  InvocationPlan({required this.positional, Map<Symbol, Object?>? named})
    : named = named ?? const <Symbol, Object?>{};

  /// Positional arguments supplied to [Function.apply].
  final List<Object?> positional;

  /// Named arguments supplied to [Function.apply].
  final Map<Symbol, Object?> named;
}
