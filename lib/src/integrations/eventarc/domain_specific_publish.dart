/// Domain-specific publish tool factory for Google Cloud Eventarc.
library;

import 'dart:async';

import '../../agents/context.dart';
import '../../agents/readonly_context.dart';
import '../../models/llm_request.dart';
import '../../tools/_google_credentials.dart';
import '../../tools/eventarc/config.dart';
import '../../tools/eventarc/message_tool.dart' as message_tool;
import '../../tools/google_tool.dart';
import '../../tools/tool_context.dart';

/// Sentinel class indicating that a CloudEvent binding or default was not set.
class MissingSentinel {
  /// Creates a missing-value sentinel.
  const MissingSentinel();
}

/// Sentinel constant indicating that a CloudEvent binding or default was not set.
// ignore: constant_identifier_names
const MissingSentinel MISSING = MissingSentinel();

/// Sentinel class indicating that an optional CloudEvent attribute should be omitted.
class OmitSentinel {
  /// Creates an omit-attribute sentinel.
  const OmitSentinel();
}

/// Sentinel constant indicating that an optional CloudEvent attribute should be omitted.
// ignore: constant_identifier_names
const OmitSentinel OMIT = OmitSentinel();

/// Indicates that a CloudEvent attribute should be provided by the LLM agent.
class AgentProvided {
  /// Creates an agent-provided attribute descriptor with [description] and optional [defaultValue].
  const AgentProvided(
    this.description, {
    this.defaultValue = MISSING,
  });

  /// Prompt-facing description of the CloudEvent attribute.
  final String description;

  /// Fallback static value, callback, [OMIT], or [MISSING] when required.
  final Object? defaultValue;
}

/// Configuration binding CloudEvent attributes to static values, callbacks, or [AgentProvided] fields.
///
/// Callback bindings may accept:
/// - `()` (zero parameters)
/// - `(payload)` (1 parameter for `event_data`)
/// - `(Context ctx)` / `(ToolContext ctx)` (1 parameter for runtime context)
/// - `(payload, ctx)` or `(ctx, payload)` (2 parameters for both)
///
/// Setting optional attributes (`time`, `datacontenttype`, `subject`,
/// `customAttributes`) to [OMIT] omits them from the published CloudEvent.
/// Mandatory attributes (`type`, `source`, `id`, `specversion`) cannot be [OMIT].
class CloudEventAttributesBinding {
  /// Creates a CloudEvent attribute binding specification.
  const CloudEventAttributesBinding({
    required this.type,
    required this.source,
    this.datacontenttype = MISSING,
    this.subject = MISSING,
    this.time = MISSING,
    this.specversion = MISSING,
    this.id = MISSING,
    this.customAttributes,
  });

  /// Binding for the CloudEvents `type` attribute.
  final Object? type;

  /// Binding for the CloudEvents `source` attribute.
  final Object? source;

  /// Optional binding for the CloudEvents `datacontenttype` attribute.
  final Object? datacontenttype;

  /// Optional binding for the CloudEvents `subject` attribute.
  final Object? subject;

  /// Optional binding for the CloudEvents `time` attribute.
  final Object? time;

  /// Optional binding for the CloudEvents `specversion` attribute.
  final Object? specversion;

  /// Optional binding for the CloudEvents `id` attribute.
  final Object? id;

  /// Optional bindings for custom CloudEvents extension attributes.
  final Map<String, Object?>? customAttributes;
}

/// Invoker callback receiving resolved `publish_message` keyword arguments.
typedef EventarcPublishInvoker =
    FutureOr<Map<String, dynamic>> Function(Map<String, dynamic> kwargs);

Future<Map<String, dynamic>> _defaultPublishInvoker(
  Map<String, dynamic> kwargs,
) {
  final Object? rawCredentials = kwargs['credentials'];
  final EventarcCredentialsConfig? credentials =
      rawCredentials is EventarcCredentialsConfig
      ? rawCredentials
      : rawCredentials != null
      ? EventarcCredentialsConfig(credentials: rawCredentials)
      : null;
  final EventarcToolConfig? settings = kwargs['settings'] is EventarcToolConfig
      ? kwargs['settings'] as EventarcToolConfig
      : null;
  final Map<String, String>? customAttrs = kwargs['custom_attributes'] is Map
      ? (kwargs['custom_attributes'] as Map).map(
          (Object? k, Object? v) => MapEntry('$k', '$v'),
        )
      : null;

  return message_tool.publishEventarcMessage(
    bus: '${kwargs['bus']}',
    type: '${kwargs['type']}',
    source: '${kwargs['source']}',
    credentials: credentials,
    settings: settings,
    data: kwargs['data'],
    datacontenttype: kwargs['datacontenttype'] as String?,
    specversion: (kwargs['specversion'] as String?) ?? '1.0',
    subject: kwargs['subject'] as String?,
    id: kwargs['id'] as String?,
    time: kwargs['time'] as String?,
    customAttributes: customAttrs,
  );
}

EventarcPublishInvoker _activePublishInvoker = _defaultPublishInvoker;

/// Overrides the default publish invoker used by domain-specific Eventarc tools.
void setEventarcPublishInvoker(EventarcPublishInvoker invoker) {
  _activePublishInvoker = invoker;
}

/// Restores the default publish invoker used by domain-specific Eventarc tools.
void resetEventarcPublishInvoker() {
  _activePublishInvoker = _defaultPublishInvoker;
}

const List<String> _mandatoryFields = <String>['type', 'source'];

const List<String> _reservedAttributes = <String>[
  'type',
  'source',
  'datacontenttype',
  'subject',
  'time',
  'specversion',
  'id',
];

const Set<String> _reservedLanguageKeywords = <String>{
  'False',
  'None',
  'True',
  'abstract',
  'and',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'cls',
  'const',
  'continue',
  'covariant',
  'def',
  'default',
  'deferred',
  'del',
  'do',
  'dynamic',
  'elif',
  'else',
  'enum',
  'except',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'from',
  'global',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'lambda',
  'late',
  'library',
  'mixin',
  'new',
  'nonlocal',
  'not',
  'null',
  'operator',
  'or',
  'part',
  'pass',
  'raise',
  'required',
  'rethrow',
  'return',
  'self',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

final RegExp _validCeCustomKeyRegex = RegExp(r'^[a-z0-9]+$');
final RegExp _hasLowercaseLetterRegex = RegExp(r'[a-z]');
final RegExp _validIdentifierRegex = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

/// Domain-specific [GoogleTool] wrapper around Eventarc `publish_message`.
class DomainSpecificPublishTool extends GoogleTool {
  /// Creates a domain-specific Eventarc publish tool.
  DomainSpecificPublishTool._({
    required super.func,
    required super.name,
    required super.description,
    required FunctionDeclaration declaration,
    required Map<String, String> parameterNameToCloudEventKey,
    required Map<String, Object?> parameterDefaults,
    required Future<Map<String, dynamic>> Function({
      Map<String, dynamic> args,
      Object? eventData,
      Object? credentials,
      EventarcToolConfig? settings,
      Object? toolContext,
    })
    executor,
    super.credentialsConfig,
    super.toolSettings,
  }) : _declaration = declaration,
       parameterNameToCloudEventKey = Map<String, String>.unmodifiable(
         parameterNameToCloudEventKey,
       ),
       parameterDefaults = Map<String, Object?>.unmodifiable(parameterDefaults),
       _executor = executor,
       _localCredentialsManager = credentialsConfig == null
           ? null
           : GoogleCredentialsManager(credentialsConfig);

  final FunctionDeclaration _declaration;
  final GoogleCredentialsManager? _localCredentialsManager;
  final Future<Map<String, dynamic>> Function({
    Map<String, dynamic> args,
    Object? eventData,
    Object? credentials,
    EventarcToolConfig? settings,
    Object? toolContext,
  })
  _executor;

  /// Mapping from exposed LLM parameter name to underlying CloudEvent attribute key.
  final Map<String, String> parameterNameToCloudEventKey;

  /// Exposed schema defaults per LLM parameter (`null` for dynamic/[OMIT] defaults, [MISSING] when required).
  final Map<String, Object?> parameterDefaults;

  @override
  FunctionDeclaration? getDeclaration() => _declaration.copyWith();

  /// Directly executes the bound publish logic, throwing on invalid runtime bindings.
  Future<Map<String, dynamic>> execute({
    Map<String, dynamic> args = const <String, dynamic>{},
    Object? eventData = MISSING,
    Object? credentials,
    EventarcToolConfig? settings,
    Object? toolContext,
  }) {
    final Map<String, dynamic> mergedArgs = Map<String, dynamic>.from(args);
    if (!identical(eventData, MISSING)) {
      mergedArgs['event_data'] = eventData;
    }
    return _executor(
      args: mergedArgs,
      credentials: credentials,
      settings: settings,
      toolContext: toolContext,
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Map<String, dynamic> processedArgs = preprocessArgs(
      args,
      _declaration,
    );
    final Object? requiredRaw = _declaration.parameters['required'];
    if (requiredRaw is List) {
      final List<String> missingParams = requiredRaw
          .map((Object? p) => '$p')
          .where((String p) => p.isNotEmpty && !processedArgs.containsKey(p))
          .toList();
      if (missingParams.isNotEmpty) {
        final String missingStr = missingParams.join('\n');
        return <String, Object>{
          'error':
              'Invoking `$name()` failed as the following mandatory input parameters are not present:\n$missingStr\nYou could retry calling this tool, but it is IMPORTANT for you to provide all the mandatory parameters.',
        };
      }
    }

    try {
      final Object? resolvedCredentials = await _localCredentialsManager
          ?.getValidCredentials(toolContext);
      if (resolvedCredentials == null && _localCredentialsManager != null) {
        return 'User authorization is required to access Google services for $name. Please complete the authorization flow.';
      }
      final EventarcToolConfig? resolvedSettings =
          processedArgs['settings'] is EventarcToolConfig
          ? processedArgs['settings'] as EventarcToolConfig
          : (toolSettings is EventarcToolConfig
                ? toolSettings as EventarcToolConfig
                : null);

      return await _executor(
        args: processedArgs,
        credentials: resolvedCredentials ?? processedArgs['credentials'],
        settings: resolvedSettings,
        toolContext: toolContext,
      );
    } catch (error) {
      return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
    }
  }
}

Object? _bindingField(CloudEventAttributesBinding binding, String field) {
  switch (field) {
    case 'type':
      return binding.type;
    case 'source':
      return binding.source;
    case 'datacontenttype':
      return binding.datacontenttype;
    case 'subject':
      return binding.subject;
    case 'time':
      return binding.time;
    case 'specversion':
      return binding.specversion;
    case 'id':
      return binding.id;
    default:
      throw ArgumentError.value(field, 'field', 'Unknown CloudEvent attribute.');
  }
}

String _sanitizeParamName(String ceKey) {
  String paramName = ceKey;
  if (_reservedLanguageKeywords.contains(ceKey)) {
    paramName = '${ceKey}_';
  }
  if (!_validIdentifierRegex.hasMatch(paramName)) {
    paramName = '_$paramName';
  }
  return paramName;
}

Map<String, dynamic> _normalizePayloadSchema(Object payloadSchema) {
  if (payloadSchema is Map) {
    final Map<String, dynamic> copy = <String, dynamic>{};
    payloadSchema.forEach((Object? key, Object? value) {
      if (key == 'type' && value is String) {
        copy['$key'] = value.toUpperCase();
      } else if (value is Map) {
        copy['$key'] = _normalizePayloadSchema(value);
      } else if (value is List) {
        copy['$key'] = value
            .map((Object? item) => item is Map ? _normalizePayloadSchema(item) : item)
            .toList();
      } else {
        copy['$key'] = value;
      }
    });
    copy.putIfAbsent('type', () => 'OBJECT');
    return copy;
  }
  return <String, dynamic>{
    'type': 'OBJECT',
    'description': 'Structured event payload ($payloadSchema).',
  };
}

Object? _serializePayloadData(Object payload) {
  if (payload is Map) {
    return Map<String, dynamic>.from(payload);
  }
  if (payload is List ||
      payload is String ||
      payload is num ||
      payload is bool) {
    return payload;
  }
  try {
    final Object? dumped = (payload as dynamic).toJson();
    if (dumped is Map) {
      return Map<String, dynamic>.from(dumped);
    }
    return dumped;
  } catch (_) {
    return payload;
  }
}

List<String> _parseTopLevelParamTypes(Function fn) {
  final String sig = fn.runtimeType.toString();
  final int arrowIdx = sig.indexOf('=>');
  if (arrowIdx <= 0) {
    return const <String>[];
  }
  String paramSection = sig.substring(0, arrowIdx).trim();
  if (paramSection.startsWith('(') && paramSection.endsWith(')')) {
    paramSection = paramSection.substring(1, paramSection.length - 1).trim();
  }
  if (paramSection.isEmpty) {
    return const <String>[];
  }

  final List<String> params = <String>[];
  int depth = 0;
  int braceDepth = 0;
  int bracketDepth = 0;
  int start = 0;
  for (int i = 0; i < paramSection.length; i++) {
    final String ch = paramSection[i];
    if (ch == '<') {
      depth++;
    } else if (ch == '>') {
      if (depth > 0) depth--;
    } else if (ch == '{') {
      braceDepth++;
    } else if (ch == '}') {
      if (braceDepth > 0) braceDepth--;
    } else if (ch == '[') {
      bracketDepth++;
    } else if (ch == ']') {
      if (bracketDepth > 0) bracketDepth--;
    } else if (ch == ',' &&
        depth == 0 &&
        braceDepth == 0 &&
        bracketDepth == 0) {
      final String token = paramSection.substring(start, i).trim();
      if (token.isNotEmpty && !token.startsWith('{')) {
        params.add(token.replaceAll(RegExp(r'^\[|\]$'), '').trim());
      }
      start = i + 1;
    }
  }
  final String tail = paramSection.substring(start).trim();
  if (tail.isNotEmpty && !tail.startsWith('{')) {
    // Strip trailing named block `{...}` if mixed with positional params.
    final int namedIdx = tail.indexOf('{');
    final String cleanTail =
        (namedIdx >= 0 ? tail.substring(0, namedIdx) : tail)
            .replaceAll(RegExp(r'^\[|\]$'), '')
            .trim();
    if (cleanTail.isNotEmpty) {
      params.add(cleanTail);
    }
  }
  return params;
}

bool _isContextTypeString(String paramType) {
  final String cleaned = paramType
      .replaceAll('?', '')
      .split(' ')
      .first
      .trim();
  return cleaned == 'Context' ||
      cleaned == 'ToolContext' ||
      cleaned == 'ReadonlyContext';
}

Future<Object?> _evaluateBindingCallable(
  Function fn,
  Object? payload,
  Object? toolContext,
) async {
  final List<String> paramTypes = _parseTopLevelParamTypes(fn);

  Future<Object?> applyPositional(List<Object?> positional) async {
    final Object? result = Function.apply(fn, positional);
    if (result is Future) {
      return await result;
    }
    return result;
  }

  if (paramTypes.isEmpty) {
    return applyPositional(const <Object?>[]);
  }

  if (paramTypes.length == 1) {
    final bool expectsContext =
        _isContextTypeString(paramTypes[0]) ||
        (paramTypes[0] == 'dynamic' &&
            payload == null &&
            (toolContext is Context ||
                toolContext is ToolContext ||
                toolContext is ReadonlyContext));
    if (_isContextTypeString(paramTypes[0])) {
      return applyPositional(<Object?>[toolContext]);
    }
    if (expectsContext) {
      // Ambiguous `(dynamic)` with null payload: try payload first (matches Python),
      // falling back to toolContext on TypeError.
      try {
        return await applyPositional(<Object?>[payload]);
      } on TypeError {
        return applyPositional(<Object?>[toolContext]);
      }
    }
    try {
      return await applyPositional(<Object?>[payload]);
    } on TypeError {
      return applyPositional(<Object?>[toolContext]);
    }
  }

  if (paramTypes.length >= 2) {
    final bool firstIsContext = _isContextTypeString(paramTypes[0]);
    final List<List<Object?>> orders = firstIsContext
        ? <List<Object?>>[
            <Object?>[toolContext, payload],
            <Object?>[payload, toolContext],
          ]
        : <List<Object?>>[
            <Object?>[payload, toolContext],
            <Object?>[toolContext, payload],
          ];
    TypeError? firstTypeError;
    for (final List<Object?> args in orders) {
      try {
        return await applyPositional(args);
      } on TypeError catch (e) {
        firstTypeError ??= e;
      }
    }
    throw firstTypeError!;
  }

  return applyPositional(<Object?>[payload]);
}

/// Dynamically builds a [DomainSpecificPublishTool] ([GoogleTool]) wrapping Eventarc
/// `publish_message` with static, dynamic callback, or [AgentProvided] bindings.
DomainSpecificPublishTool buildDomainSpecificTool({
  Object? toolset,
  required String name,
  required String description,
  required Object? bus,
  required CloudEventAttributesBinding ceAttributesBinding,
  Object? payloadSchema,
  EventarcPublishInvoker? publishInvoker,
}) {
  // 1. Build-time validation matching Python `_domain_specific_publish.py`.
  for (final String field in _mandatoryFields) {
    final Object? val = _bindingField(ceAttributesBinding, field);
    if (identical(val, MISSING)) {
      throw ArgumentError(
        "CloudEventAttributesBinding requires '$field' to be provided.",
      );
    }
    if (identical(val, OMIT)) {
      throw ArgumentError(
        "CloudEvent field '$field' is mandatory and cannot be OMIT.",
      );
    }
    if (val == null) {
      throw ArgumentError(
        "CloudEvent field '$field' is mandatory and cannot be None.",
      );
    }
  }

  if (identical(bus, OMIT)) {
    throw ArgumentError("The 'bus' parameter is mandatory and cannot be OMIT.");
  }
  if (identical(bus, MISSING)) {
    throw ArgumentError(
      "The 'bus' parameter is mandatory and must be provided.",
    );
  }
  if (bus == null) {
    throw ArgumentError("The 'bus' parameter is mandatory and cannot be None.");
  }

  for (final String field in const <String>['id', 'specversion']) {
    final Object? val = _bindingField(ceAttributesBinding, field);
    if (identical(val, OMIT)) {
      throw ArgumentError(
        "CloudEvent field '$field' is mandatory and cannot be OMIT.",
      );
    }
  }

  final Map<String, Object?>? customAttributes =
      ceAttributesBinding.customAttributes;
  if (customAttributes != null) {
    for (final MapEntry<String, Object?> entry in customAttributes.entries) {
      final String k = entry.key;
      final Object? v = entry.value;
      if (_reservedAttributes.contains(k)) {
        throw ArgumentError(
          "Custom attribute '$k' shadows a standard CloudEvent attribute.",
        );
      }
      if (!_validCeCustomKeyRegex.hasMatch(k) ||
          !_hasLowercaseLetterRegex.hasMatch(k)) {
        throw ArgumentError(
          "Custom attribute '$k' is invalid. CloudEvent attributes MUST "
          "consist of lower-case letters ('a' to 'z') or digits ('0' to '9').",
        );
      }
      if (identical(v, MISSING)) {
        throw ArgumentError("Custom attribute '$k' cannot be MISSING.");
      }
    }
  }

  // 2. Collect LLM parameters & schema metadata.
  final Map<String, dynamic> schemaProperties = <String, dynamic>{};
  final List<String> requiredParams = <String>[];
  final Map<String, String> paramNameToCeKey = <String, String>{};
  final Map<String, Object?> paramDefaults = <String, Object?>{};

  void addAgentProvided(String ceKey, AgentProvided ap) {
    final String paramName = _sanitizeParamName(ceKey);
    paramNameToCeKey[paramName] = ceKey;

    final bool isOptional = !identical(ap.defaultValue, MISSING);
    final Map<String, dynamic> prop = <String, dynamic>{
      'type': 'STRING',
      'description': ap.description,
    };

    if (isOptional) {
      prop['nullable'] = true;
      final Object? exposedDefault =
          (ap.defaultValue is Function || identical(ap.defaultValue, OMIT))
          ? null
          : ap.defaultValue;
      paramDefaults[paramName] = exposedDefault;
      if (exposedDefault != null) {
        prop['default'] = exposedDefault;
      }
    } else {
      paramDefaults[paramName] = MISSING;
      requiredParams.add(paramName);
    }
    schemaProperties[paramName] = prop;
  }

  if (bus is AgentProvided) {
    addAgentProvided('bus', bus);
  }

  for (final String field in _reservedAttributes) {
    final Object? val = _bindingField(ceAttributesBinding, field);
    if (val is AgentProvided) {
      addAgentProvided(field, val);
    }
  }

  if (customAttributes != null) {
    for (final MapEntry<String, Object?> entry in customAttributes.entries) {
      if (entry.value is AgentProvided) {
        addAgentProvided(entry.key, entry.value! as AgentProvided);
      }
    }
  }

  if (payloadSchema != null) {
    schemaProperties['event_data'] = _normalizePayloadSchema(payloadSchema);
    requiredParams.add('event_data');
    paramDefaults['event_data'] = MISSING;
  }

  final Map<String, dynamic> parametersSchema = schemaProperties.isEmpty
      ? <String, dynamic>{}
      : <String, dynamic>{
          'type': 'OBJECT',
          'properties': schemaProperties,
          'required': requiredParams,
        };

  final FunctionDeclaration declaration = FunctionDeclaration(
    name: name,
    description: description,
    parameters: parametersSchema,
  );

  // Extract credentialsConfig and toolConfig from toolset if supplied.
  BaseGoogleCredentialsConfig? credentialsConfig;
  EventarcToolConfig? defaultToolSettings;
  EventarcPublishInvoker? toolsetPublishInvoker;
  if (toolset != null) {
    try {
      final Object? creds = (toolset as dynamic).credentialsConfig;
      if (creds is BaseGoogleCredentialsConfig) {
        credentialsConfig = creds;
      }
    } catch (_) {}
    try {
      final Object? cfg = (toolset as dynamic).toolConfig;
      if (cfg is EventarcToolConfig) {
        defaultToolSettings = cfg;
      }
    } catch (_) {}
    try {
      final Object? inv = (toolset as dynamic).publishInvoker;
      if (inv is EventarcPublishInvoker) {
        toolsetPublishInvoker = inv;
      }
    } catch (_) {}
  }

  // 3. Runtime executor.
  Future<Map<String, dynamic>> executeBound({
    Map<String, dynamic> args = const <String, dynamic>{},
    Object? eventData,
    Object? credentials,
    EventarcToolConfig? settings,
    Object? toolContext,
  }) async {
    final Object? payload = eventData ?? args['event_data'];
    final Object? effectiveCredentials = credentials ?? args['credentials'];
    final EventarcToolConfig effectiveSettings =
        settings ??
        (args['settings'] is EventarcToolConfig
            ? args['settings'] as EventarcToolConfig
            : (defaultToolSettings ?? const EventarcToolConfig()));
    final Object? effectiveContext = toolContext ?? args['tool_context'];

    final Map<String, dynamic> publishKwargs = <String, dynamic>{
      'credentials': effectiveCredentials,
      'settings': effectiveSettings,
    };

    if (payload != null) {
      publishKwargs['data'] = _serializePayloadData(payload);
    }

    Future<Object?> resolveAttr(
      String key,
      Object? binding, {
      required bool isMandatory,
    }) async {
      if (identical(binding, MISSING)) {
        return null;
      }

      Object? val;
      if (binding is AgentProvided) {
        String paramName = key;
        for (final MapEntry<String, String> entry
            in paramNameToCeKey.entries) {
          if (entry.value == key) {
            paramName = entry.key;
            break;
          }
        }
        final Object? llmVal = args[paramName];
        if (llmVal != null) {
          val = llmVal;
        } else {
          if (identical(binding.defaultValue, MISSING)) {
            throw ArgumentError(
              "Agent did not provide mandatory attribute '$key'",
            );
          }
          val = binding.defaultValue;
        }
      } else {
        val = binding;
      }

      if (val is Function) {
        val = await _evaluateBindingCallable(val, payload, effectiveContext);
      }

      if (identical(val, OMIT)) {
        if (isMandatory) {
          throw ArgumentError(
            "Mandatory CloudEvent attribute '$key' cannot evaluate to OMIT.",
          );
        }
        return OMIT;
      }

      return val;
    }

    final Object? busVal = await resolveAttr('bus', bus, isMandatory: true);
    if (identical(busVal, OMIT) || busVal == null) {
      throw ArgumentError(
        "Mandatory attribute 'bus' cannot evaluate to None or OMIT.",
      );
    }
    publishKwargs['bus'] = '$busVal';

    for (final String field in _reservedAttributes) {
      final bool isMandatory = _mandatoryFields.contains(field);
      final Object? val = await resolveAttr(
        field,
        _bindingField(ceAttributesBinding, field),
        isMandatory: isMandatory,
      );
      if (identical(val, OMIT)) {
        if (field == 'time' || field == 'datacontenttype') {
          publishKwargs[field] = '';
        } else if (field == 'id' || field == 'specversion') {
          throw ArgumentError(
            "CloudEvent attribute '$field' is mandatory and cannot be OMIT.",
          );
        }
      } else if (val != null) {
        publishKwargs[field] = '$val';
      }
    }

    if (customAttributes != null) {
      final Map<String, String> customAttrDict = <String, String>{};
      for (final MapEntry<String, Object?> entry in customAttributes.entries) {
        final Object? val = await resolveAttr(
          entry.key,
          entry.value,
          isMandatory: false,
        );
        if (!identical(val, OMIT) && val != null) {
          customAttrDict[entry.key] = '$val';
        }
      }
      if (customAttrDict.isNotEmpty) {
        publishKwargs['custom_attributes'] = customAttrDict;
      }
    }

    final EventarcPublishInvoker invoker =
        publishInvoker ?? toolsetPublishInvoker ?? _activePublishInvoker;
    return await invoker(publishKwargs);
  }

  return DomainSpecificPublishTool._(
    func: (Map<String, dynamic> args, [Object? toolContext]) =>
        executeBound(args: args, toolContext: toolContext),
    name: name,
    description: description,
    declaration: declaration,
    parameterNameToCloudEventKey: paramNameToCeKey,
    parameterDefaults: paramDefaults,
    executor: executeBound,
    credentialsConfig: credentialsConfig,
    toolSettings: defaultToolSettings,
  );
}
