/// Core abstractions for runtime-executable tools.
library;

import '../models/llm_request.dart';
import '../types/content.dart';
import 'tool_configs.dart';
import 'tool_context.dart';

/// Controls whether a tool is blocking or non-blocking in Live API mode.
enum ToolBehavior {
  /// The model waits for the tool response before continuing.
  blocking('BLOCKING'),

  /// The model continues the conversation while the tool executes in the background.
  nonBlocking('NON_BLOCKING');

  /// Creates a [ToolBehavior] with its [wireValue].
  const ToolBehavior(this.wireValue);

  /// Wire format string representation.
  final String wireValue;
}

/// Base contract for one callable tool exposed to the model runtime.
abstract class BaseTool {
  /// Creates a tool with a stable [name] and user-visible [description].
  BaseTool({
    required this.name,
    required this.description,
    this.title,
    this.isLongRunning = false,
    this.defersResponse = false,
    this.customMetadata,
    this.behavior,
    this.responseScheduling,
  });

  /// Unique tool name used in function-calling payloads.
  String name;

  /// Human-readable purpose text shown to the model.
  String description;

  /// Optional human-readable display title for the tool.
  String? title;

  /// Human-readable display title for this tool, if available.
  String? get displayTitle => title;

  /// Whether the tool can outlive a single response turn.
  bool isLongRunning;

  /// Whether response event creation is handled by framework code elsewhere.
  bool defersResponse;

  /// Arbitrary metadata attached to this tool declaration.
  Map<String, dynamic>? customMetadata;

  /// Controls whether the tool is blocking or non-blocking in Live mode.
  ToolBehavior? behavior;

  /// Live response scheduling policy for this tool.
  FunctionResponseScheduling? responseScheduling;

  /// Returns the function declaration exposed to the model, if any.
  FunctionDeclaration? getDeclaration() => null;

  /// Whether this tool call requires human confirmation before execution.
  ///
  /// When returning `true`, the framework confirmation gate holds the call back.
  Future<bool> checkRequireConfirmation(
    Map<String, dynamic> args,
    ToolContext toolContext,
  ) async => false;

  /// Executes the tool and returns a JSON-like response payload.
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  });

  /// Returns a telemetry error type when [response] represents a tool error.
  ///
  /// Tool implementations can return structured error payloads instead of
  /// throwing. This hook lets telemetry record those failures consistently.
  String? detectErrorInResponse(Object? response) => null;

  /// Mutates outgoing [llmRequest] before model generation.
  ///
  /// The default behavior appends this tool to the request tool list.
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    llmRequest.appendTools(<BaseTool>[this]);
  }

  /// Unwraps a 2-branch optional union type annotation (`T | None`,
  /// `Optional[T]`, `Union[T, None]`, or `T?`) to its underlying type `T`.
  ///
  /// Returns `null` when [typeAnnotation] is a multi-type non-optional union
  /// (`X | Y`), a 3+ branch union (`X | Y | None`), or an untyped `Any` /
  /// `Object` / `dynamic` annotation that cannot be safely coerced from config.
  static String? unwrapOptionalParameterType(String typeAnnotation) {
    String trimmed = typeAnnotation.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    // Handle PEP 604 `A | B` union syntax at top level.
    final List<String> pipeBranches = _splitTopLevel(trimmed, '|');
    if (pipeBranches.length > 1) {
      if (pipeBranches.length != 2) {
        return null;
      }
      final List<String> nonNull = pipeBranches
          .map((String s) => s.trim())
          .where((String s) => !_isNullTypeName(s))
          .toList(growable: false);
      if (nonNull.length != 1) {
        return null;
      }
      trimmed = nonNull.first;
    } else if (_startsWithGeneric(trimmed, 'Optional')) {
      final String inner = _extractGenericInner(trimmed, 'Optional');
      final List<String> args = _splitTopLevel(inner, ',');
      if (args.length != 1) {
        return null;
      }
      trimmed = args.first.trim();
    } else if (_startsWithGeneric(trimmed, 'Union')) {
      final String inner = _extractGenericInner(trimmed, 'Union');
      final List<String> args = _splitTopLevel(inner, ',');
      if (args.length != 2) {
        return null;
      }
      final List<String> nonNull = args
          .map((String s) => s.trim())
          .where((String s) => !_isNullTypeName(s))
          .toList(growable: false);
      if (nonNull.length != 1) {
        return null;
      }
      trimmed = nonNull.first;
    } else if (trimmed.endsWith('?')) {
      trimmed = trimmed.substring(0, trimmed.length - 1).trim();
    }

    // Check if the unwrapped type itself is still a union.
    if (_splitTopLevel(trimmed, '|').length > 1 ||
        _startsWithGeneric(trimmed, 'Union')) {
      return null;
    }
    if (_isUntypedAnnotation(trimmed)) {
      return null;
    }
    return trimmed;
  }

  /// Resolves and validates tool constructor keyword arguments from [config]
  /// according to [parameterTypes] (mapping parameter name to type annotation).
  ///
  /// Optional 2-branch unions (`T | None`, `Optional[T]`, `T?`) are unwrapped
  /// to `T`, while multi-type unions (`int | str`, `int | str | None`) and
  /// untyped (`Any`, `list[Any]`) parameters are skipped.
  static Map<String, Object?> resolveConfigKwargs(
    ToolArgsConfig config,
    Map<String, String> parameterTypes, {
    Map<String, Object? Function(Map<String, Object?>)>? modelFactories,
  }) {
    final Map<String, Object?> kwargs = <String, Object?>{};
    final Map<String, Object?> configDict = config.toJson();

    for (final MapEntry<String, String> entry in parameterTypes.entries) {
      final String paramName = entry.key;
      if (!configDict.containsKey(paramName)) {
        continue;
      }
      final Object? value = configDict[paramName];
      final String? paramType = unwrapOptionalParameterType(entry.value);
      if (paramType == null) {
        continue;
      }

      if (_isPrimitiveTypeName(paramType)) {
        kwargs[paramName] = value;
        continue;
      }

      if (_isListType(paramType)) {
        final String? itemType = unwrapOptionalParameterType(
          _extractListInnerType(paramType),
        );
        if (itemType == null) {
          continue;
        }
        if (_isPrimitiveTypeName(itemType)) {
          kwargs[paramName] = value;
          continue;
        }
        final Object? Function(Map<String, Object?>)? factory =
            modelFactories?[itemType];
        if (factory != null && value is List) {
          kwargs[paramName] = <Object?>[
            for (final Object? element in value)
              element is Map
                  ? factory(
                      element.map(
                        (Object? k, Object? v) => MapEntry('$k', v),
                      ),
                    )
                  : element,
          ];
        }
        continue;
      }

      final Object? Function(Map<String, Object?>)? factory =
          modelFactories?[paramType];
      if (factory != null) {
        if (value is Map) {
          kwargs[paramName] = factory(
            value.map((Object? k, Object? v) => MapEntry('$k', v)),
          );
        } else {
          kwargs[paramName] = value;
        }
      }
    }
    return kwargs;
  }

  /// Instantiates a tool of type [T] from [config] using [parameterTypes] and
  /// [builder].
  static T fromConfig<T extends BaseTool>(
    ToolArgsConfig config, {
    String configAbsPath = '',
    required Map<String, String> parameterTypes,
    required T Function(Map<String, Object?> kwargs) builder,
    Map<String, Object? Function(Map<String, Object?>)>? modelFactories,
  }) {
    final Map<String, Object?> kwargs = resolveConfigKwargs(
      config,
      parameterTypes,
      modelFactories: modelFactories,
    );
    return builder(kwargs);
  }
}

bool _isNullTypeName(String typeName) {
  final String lower = typeName.trim().toLowerCase();
  return lower == 'none' || lower == 'nonetype' || lower == 'null';
}

bool _isUntypedAnnotation(String typeName) {
  final String lower = typeName.trim().toLowerCase();
  return lower == 'any' || lower == 'object' || lower == 'dynamic';
}

bool _isPrimitiveTypeName(String typeName) {
  final String lower = typeName.trim().toLowerCase();
  return lower == 'int' ||
      lower == 'str' ||
      lower == 'string' ||
      lower == 'float' ||
      lower == 'double' ||
      lower == 'num' ||
      lower == 'bool';
}

bool _isListType(String typeName) {
  return _startsWithGeneric(typeName, 'list') ||
      _startsWithGeneric(typeName, 'List') ||
      _startsWithGeneric(typeName, 'Sequence');
}

String _extractListInnerType(String typeName) {
  for (final String prefix in const <String>['list', 'List', 'Sequence']) {
    if (_startsWithGeneric(typeName, prefix)) {
      return _extractGenericInner(typeName, prefix);
    }
  }
  return '';
}

bool _startsWithGeneric(String value, String prefix) {
  if (!value.startsWith(prefix)) {
    return false;
  }
  final String rest = value.substring(prefix.length).trim();
  return (rest.startsWith('[') && rest.endsWith(']')) ||
      (rest.startsWith('<') && rest.endsWith('>'));
}

String _extractGenericInner(String value, String prefix) {
  final String rest = value.substring(prefix.length).trim();
  return rest.substring(1, rest.length - 1).trim();
}

List<String> _splitTopLevel(String input, String delimiter) {
  final List<String> parts = <String>[];
  int depth = 0;
  int start = 0;
  for (int i = 0; i < input.length; i += 1) {
    final String ch = input[i];
    if (ch == '[' || ch == '<' || ch == '(') {
      depth += 1;
    } else if (ch == ']' || ch == '>' || ch == ')') {
      if (depth > 0) {
        depth -= 1;
      }
    } else if (depth == 0 && input.startsWith(delimiter, i)) {
      parts.add(input.substring(start, i));
      start = i + delimiter.length;
      i += delimiter.length - 1;
    }
  }
  parts.add(input.substring(start));
  return parts;
}
