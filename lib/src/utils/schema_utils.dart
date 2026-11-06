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
