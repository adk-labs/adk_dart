/// JSON schema transformation helpers.
library;

/// Recursively lowercases `type` values in a JSON schema [value].
void lowercaseSchemaTypes(Object? value) {
  if (value is Map) {
    final Object? schemaType = value['type'];
    if (schemaType is String) {
      value['type'] = schemaType.toLowerCase();
    } else if (schemaType is List) {
      for (int i = 0; i < schemaType.length; i++) {
        final Object? item = schemaType[i];
        if (item is String) {
          schemaType[i] = item.toLowerCase();
        }
      }
    }
    for (final Object? child in value.values) {
      lowercaseSchemaTypes(child);
    }
  } else if (value is List) {
    for (final Object? item in value) {
      lowercaseSchemaTypes(item);
    }
  }
}

Object? _deepCopyJsonValue(Object? value) {
  if (value is Map) {
    return value.map<String, dynamic>(
      (Object? k, Object? v) =>
          MapEntry<String, dynamic>(k.toString(), _deepCopyJsonValue(v)),
    );
  }
  if (value is List) {
    return value.map<Object?>(_deepCopyJsonValue).toList();
  }
  return value;
}

/// Recursively transforms a JSON [schema] for OpenAI strict structured outputs.
///
/// OpenAI strict mode requires:
/// 1. `additionalProperties: false` on all object schemas (including nested/`$defs`).
/// 2. All properties listed in `required` (no optional omissions).
/// 3. `$ref` nodes must have no sibling keywords (e.g., no `description` next to
///    `$ref`), except a root `$ref` beside `$defs` which is inlined first so
///    the `$defs` it points to are preserved.
///
/// Mutates [schema] in place.
void enforceStrictOpenAiSchema(Map<String, Object?> schema) {
  // A root $ref beside $defs (Pydantic's form for a recursive model) is
  // inlined, so the root is an object and the $defs it points to are kept.
  // Root keys win over the definition's; `seen` stops a cyclic $ref chain.
  final Object? defs = schema[r'$defs'];
  final Set<String> seen = <String>{};
  while (defs is Map) {
    final Object? ref = schema[r'$ref'];
    if (ref is! String || !ref.startsWith(r'#/$defs/')) {
      break;
    }
    final String name = ref.substring(r'#/$defs/'.length);
    final Object? target = defs[name];
    if (seen.contains(name) || target is! Map) {
      break;
    }
    seen.add(name);
    schema.remove(r'$ref');
    for (final MapEntry<Object?, Object?> entry in target.entries) {
      final String key = entry.key.toString();
      schema.putIfAbsent(key, () => _deepCopyJsonValue(entry.value));
    }
  }

  // Strip sibling keywords from $ref nodes (OpenAI rejects them).
  if (schema.containsKey(r'$ref')) {
    for (final String key in schema.keys.toList()) {
      if (key != r'$ref') {
        schema.remove(key);
      }
    }
    return;
  }

  // Ensure all object schemas have additionalProperties: false and list every
  // property as required.
  if (schema['type'] == 'object' && schema['properties'] is Map) {
    final Map<dynamic, dynamic> props =
        schema['properties'] as Map<dynamic, dynamic>;
    schema['additionalProperties'] = false;
    final List<String> requiredKeys =
        props.keys.map((Object? k) => k.toString()).toList()..sort();
    schema['required'] = requiredKeys;
  }

  // Recurse into $defs.
  final Object? rawDefs = schema[r'$defs'];
  if (rawDefs is Map) {
    for (final Object? key in rawDefs.keys.toList()) {
      final Object? defn = rawDefs[key];
      if (defn is Map<String, Object?>) {
        enforceStrictOpenAiSchema(defn);
      } else if (defn is Map) {
        final Map<String, Object?> converted = defn.map(
          (Object? k, Object? v) => MapEntry<String, Object?>(k.toString(), v),
        );
        enforceStrictOpenAiSchema(converted);
        rawDefs[key] = converted;
      }
    }
  }

  // Recurse into property schemas.
  final Object? rawProps = schema['properties'];
  if (rawProps is Map) {
    for (final Object? key in rawProps.keys.toList()) {
      final Object? prop = rawProps[key];
      if (prop is Map<String, Object?>) {
        enforceStrictOpenAiSchema(prop);
      } else if (prop is Map) {
        final Map<String, Object?> converted = prop.map(
          (Object? k, Object? v) => MapEntry<String, Object?>(k.toString(), v),
        );
        enforceStrictOpenAiSchema(converted);
        rawProps[key] = converted;
      }
    }
  }

  // Recurse into combinators.
  for (final String key in const <String>['anyOf', 'oneOf', 'allOf']) {
    final Object? rawCombinator = schema[key];
    if (rawCombinator is List) {
      for (int i = 0; i < rawCombinator.length; i++) {
        final Object? item = rawCombinator[i];
        if (item is Map<String, Object?>) {
          enforceStrictOpenAiSchema(item);
        } else if (item is Map) {
          final Map<String, Object?> converted = item.map(
            (Object? k, Object? v) =>
                MapEntry<String, Object?>(k.toString(), v),
          );
          enforceStrictOpenAiSchema(converted);
          rawCombinator[i] = converted;
        }
      }
    }
  }

  // Recurse into array item schemas.
  final Object? rawItems = schema['items'];
  if (rawItems is Map<String, Object?>) {
    enforceStrictOpenAiSchema(rawItems);
  } else if (rawItems is Map) {
    final Map<String, Object?> converted = rawItems.map(
      (Object? k, Object? v) => MapEntry<String, Object?>(k.toString(), v),
    );
    enforceStrictOpenAiSchema(converted);
    schema['items'] = converted;
  }
}

/// Path-based validation alias specification for nested map/list lookups.
class AliasPath {
  /// Creates a validation alias path from [first] and optional path segments.
  AliasPath(Object first, [Object? second, Object? third, Object? fourth])
    : path = <Object>[first, ?second, ?third, ?fourth];

  /// Creates a validation alias path from an explicit list of [path] segments.
  const AliasPath.fromList(this.path);

  /// Ordered lookup path segments (strings for map keys, ints for list indices).
  final List<Object> path;

  /// Resolves this path against [data], returning `(found, value)`.
  (bool, Object?) resolve(Map<String, Object?> data) {
    if (path.isEmpty) {
      return (false, null);
    }
    Object? current = data;
    for (final Object segment in path) {
      if (current is Map && segment is String) {
        if (!current.containsKey(segment)) {
          return (false, null);
        }
        current = current[segment];
      } else if (current is List && segment is int) {
        if (segment < 0 || segment >= current.length) {
          return (false, null);
        }
        current = current[segment];
      } else {
        return (false, null);
      }
    }
    return (true, current);
  }
}

/// Ordered set of candidate validation aliases (`String` or [AliasPath]).
class AliasChoices {
  /// Creates alias choices from candidate aliases.
  AliasChoices(
    Object first, [
    Object? second,
    Object? third,
    Object? fourth,
    Object? fifth,
  ]) : choices = <Object>[first, ?second, ?third, ?fourth, ?fifth];

  /// Creates alias choices from an explicit list of [choices].
  const AliasChoices.fromList(this.choices);

  /// Candidate aliases (`String` or [AliasPath]) evaluated in order.
  final List<Object> choices;
}

/// Field metadata declaration mirroring Pydantic's `FieldInfo`.
class FieldInfo {
  /// Creates field metadata with optional [alias], [validationAlias], and [defaultValue].
  const FieldInfo({this.alias, this.validationAlias, this.defaultValue});

  /// String alias for the field.
  final String? alias;

  /// Validation alias (`String`, [AliasPath], or [AliasChoices]).
  final Object? validationAlias;

  /// Default value when no input key matches.
  final Object? defaultValue;
}

/// Returns top-level dict keys that [fields] consume during validation.
///
/// Mirrors `top_level_input_keys` in Python ADK `_schema_utils.py`.
Set<String> topLevelInputKeys(Map<String, Object?> fields) {
  final Set<String> keys = fields.keys.toSet();
  for (final Object? rawField in fields.values) {
    String? alias;
    Object? validationAlias;
    if (rawField is FieldInfo) {
      alias = rawField.alias;
      validationAlias = rawField.validationAlias;
    } else if (rawField is Map) {
      final Object? rawAlias = rawField['alias'];
      if (rawAlias is String) {
        alias = rawAlias;
      }
      validationAlias =
          rawField['validation_alias'] ?? rawField['validationAlias'];
    } else if (rawField != null) {
      final dynamic dyn = rawField;
      try {
        final Object? a = dyn.alias;
        if (a is String) {
          alias = a;
        }
      } catch (_) {}
      try {
        validationAlias = dyn.validationAlias;
      } catch (_) {
        try {
          validationAlias = dyn.validation_alias;
        } catch (_) {}
      }
    }

    if (alias != null) {
      keys.add(alias);
    }
    if (validationAlias is String) {
      keys.add(validationAlias);
    } else if (validationAlias is AliasPath) {
      if (validationAlias.path.isNotEmpty &&
          validationAlias.path.first is String) {
        keys.add(validationAlias.path.first as String);
      }
    } else if (validationAlias is AliasChoices) {
      for (final Object choice in validationAlias.choices) {
        if (choice is String) {
          keys.add(choice);
        } else if (choice is AliasPath &&
            choice.path.isNotEmpty &&
            choice.path.first is String) {
          keys.add(choice.path.first as String);
        }
      }
    }
  }
  return keys;
}

/// Resolves the input value for [fieldName] and [fieldInfo] from [data].
///
/// Returns `(matched, value)` according to alias/validationAlias precedence.
(bool, Object?) resolveFieldInputValue(
  String fieldName,
  Object? fieldInfo,
  Map<String, Object?> data,
) {
  String? alias;
  Object? validationAlias;
  Object? defaultValue;
  if (fieldInfo is FieldInfo) {
    alias = fieldInfo.alias;
    validationAlias = fieldInfo.validationAlias;
    defaultValue = fieldInfo.defaultValue;
  } else if (fieldInfo is Map) {
    if (fieldInfo['alias'] is String) {
      alias = fieldInfo['alias'] as String;
    }
    validationAlias =
        fieldInfo['validation_alias'] ?? fieldInfo['validationAlias'];
    defaultValue = fieldInfo['default'] ?? fieldInfo['defaultValue'];
  }

  if (validationAlias != null) {
    if (validationAlias is String) {
      if (data.containsKey(validationAlias)) {
        return (true, data[validationAlias]);
      }
    } else if (validationAlias is AliasPath) {
      final (bool ok, Object? val) = validationAlias.resolve(data);
      if (ok) {
        return (true, val);
      }
    } else if (validationAlias is AliasChoices) {
      for (final Object choice in validationAlias.choices) {
        if (choice is String && data.containsKey(choice)) {
          return (true, data[choice]);
        } else if (choice is AliasPath) {
          final (bool ok, Object? val) = choice.resolve(data);
          if (ok) {
            return (true, val);
          }
        }
      }
    }
  }

  if (alias != null && data.containsKey(alias)) {
    return (true, data[alias]);
  }
  if (data.containsKey(fieldName)) {
    return (true, data[fieldName]);
  }
  if (defaultValue != null) {
    return (true, defaultValue);
  }
  return (false, null);
}
