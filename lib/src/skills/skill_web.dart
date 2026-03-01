import 'package:unorm_dart/unorm_dart.dart' as unorm;

final RegExp _skillNamePattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

const Set<String> _allowedFrontmatterKeys = <String>{
  'name',
  'description',
  'license',
  'allowed-tools',
  'allowed_tools',
  'metadata',
  'compatibility',
};

abstract class SkillDescriptor {
  String get name;
  String get description;
}

/// L1 skill metadata parsed from SKILL.md frontmatter.
class Frontmatter implements SkillDescriptor {
  Frontmatter({
    required String name,
    required String description,
    this.license,
    String? compatibility,
    this.allowedTools,
    Map<String, String>? metadata,
    Map<String, Object?>? extraFields,
  }) : name = _validateName(name),
       description = _validateDescription(description),
       compatibility = _validateCompatibility(compatibility),
       metadata = Map<String, String>.unmodifiable(
         metadata ?? <String, String>{},
       ),
       extraFields = Map<String, Object?>.unmodifiable(
         extraFields ?? <String, Object?>{},
       );

  factory Frontmatter.fromMap(
    Map<String, Object?> value, {
    bool allowUnknownFields = true,
  }) {
    final Set<String> unknown = value.keys
        .where((String key) => !_allowedFrontmatterKeys.contains(key))
        .toSet();
    if (!allowUnknownFields && unknown.isNotEmpty) {
      throw ArgumentError(
        'Unknown frontmatter fields: ${unknown.toList()..sort()}',
      );
    }

    final Object? nameValue = value['name'];
    final Object? descriptionValue = value['description'];
    if (nameValue is! String) {
      throw ArgumentError('name is required and must be a string');
    }
    if (descriptionValue is! String) {
      throw ArgumentError('description is required and must be a string');
    }

    final String? allowedTools =
        _readOptionalString(value['allowed_tools']) ??
        _readOptionalString(value['allowed-tools']);

    return Frontmatter(
      name: nameValue,
      description: descriptionValue,
      license: _readOptionalString(value['license']),
      compatibility: _readOptionalString(value['compatibility']),
      allowedTools: allowedTools,
      metadata: _readMetadata(value['metadata']),
      extraFields: allowUnknownFields
          ? <String, Object?>{for (final String key in unknown) key: value[key]}
          : <String, Object?>{},
    );
  }

  @override
  final String name;

  @override
  final String description;

  final String? license;
  final String? compatibility;
  final String? allowedTools;
  final Map<String, String> metadata;
  final Map<String, Object?> extraFields;

  Map<String, Object?> toMap({bool byAlias = false}) {
    final Map<String, Object?> result = <String, Object?>{
      'name': name,
      'description': description,
    };
    if (license != null) {
      result['license'] = license;
    }
    if (compatibility != null) {
      result['compatibility'] = compatibility;
    }
    if (allowedTools != null) {
      result[byAlias ? 'allowed-tools' : 'allowed_tools'] = allowedTools;
    }
    if (metadata.isNotEmpty) {
      result['metadata'] = Map<String, String>.from(metadata);
    }
    if (extraFields.isNotEmpty) {
      for (final MapEntry<String, Object?> entry in extraFields.entries) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  static String _validateName(String value) {
    final String normalized = _normalizeNfkc(value);
    if (normalized.length > 64) {
      throw ArgumentError('name must be at most 64 characters');
    }
    if (!_skillNamePattern.hasMatch(normalized)) {
      throw ArgumentError(
        'name must be lowercase kebab-case (a-z, 0-9, hyphens), '
        'with no leading, trailing, or consecutive hyphens',
      );
    }
    return normalized;
  }

  static String _validateDescription(String value) {
    if (value.isEmpty) {
      throw ArgumentError('description must not be empty');
    }
    if (value.length > 1024) {
      throw ArgumentError('description must be at most 1024 characters');
    }
    return value;
  }

  static String? _validateCompatibility(String? value) {
    if (value != null && value.length > 500) {
      throw ArgumentError('compatibility must be at most 500 characters');
    }
    return value;
  }

  static String? _readOptionalString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw ArgumentError('expected string value, got ${value.runtimeType}');
    }
    return value;
  }

  static Map<String, String> _readMetadata(Object? value) {
    if (value == null) {
      return <String, String>{};
    }
    if (value is! Map) {
      throw ArgumentError('metadata must be a mapping');
    }
    final Map<String, String> metadata = <String, String>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final Object? key = entry.key;
      if (key is! String) {
        throw ArgumentError('metadata keys must be strings');
      }
      metadata[key] = '${entry.value ?? ''}';
    }
    return metadata;
  }
}

/// Wrapper for script content.
class Script {
  Script({required this.src});

  final String src;

  @override
  String toString() => src;
}

/// L3 skill resources loaded from references/assets/scripts directories.
class Resources {
  Resources({
    Map<String, String>? references,
    Map<String, String>? assets,
    Map<String, Script>? scripts,
  }) : references = Map<String, String>.unmodifiable(
         references ?? <String, String>{},
       ),
       assets = Map<String, String>.unmodifiable(assets ?? <String, String>{}),
       scripts = Map<String, Script>.unmodifiable(
         scripts ?? <String, Script>{},
       );

  final Map<String, String> references;
  final Map<String, String> assets;
  final Map<String, Script> scripts;

  String? getReference(String referenceId) => references[referenceId];

  String? getAsset(String assetId) => assets[assetId];

  Script? getScript(String scriptId) => scripts[scriptId];

  List<String> listReferences() => references.keys.toList(growable: false);

  List<String> listAssets() => assets.keys.toList(growable: false);

  List<String> listScripts() => scripts.keys.toList(growable: false);
}

/// Complete skill representation with metadata, instructions, and resources.
class Skill implements SkillDescriptor {
  Skill({
    Frontmatter? frontmatter,
    String? name,
    String? description,
    this.instructions = '',
    Resources? resources,
    this.version = '0.1.0',
    String? license,
    String? compatibility,
    String? allowedTools,
    Map<String, String>? metadata,
  }) : frontmatter =
           frontmatter ??
           Frontmatter(
             name: name ?? '',
             description: description ?? '',
             license: license,
             compatibility: compatibility,
             allowedTools: allowedTools,
             metadata: metadata,
           ),
       resources = resources ?? Resources();

  final Frontmatter frontmatter;
  final String instructions;
  final Resources resources;
  final String version;

  @override
  String get name => frontmatter.name;

  @override
  String get description => frontmatter.description;
}

class SkillRegistry {
  final Map<String, Skill> _skills = <String, Skill>{};

  void register(Skill skill) {
    _skills[skill.name] = skill;
  }

  Skill? get(String name) => _skills[name];

  bool contains(String name) => _skills.containsKey(name);

  void remove(String name) {
    _skills.remove(name);
  }

  void clear() {
    _skills.clear();
  }

  List<Skill> list() => _skills.values.toList(growable: false);
}

String formatSkillsAsXml(List<SkillDescriptor> skills) {
  if (skills.isEmpty) {
    return '<available_skills>\n</available_skills>';
  }

  final List<String> lines = <String>['<available_skills>'];
  for (final SkillDescriptor skill in skills) {
    lines.add('<skill>');
    lines.add('<name>');
    lines.add(_escapeXml(skill.name));
    lines.add('</name>');
    lines.add('<description>');
    lines.add(_escapeXml(skill.description));
    lines.add('</description>');
    lines.add('</skill>');
  }
  lines.add('</available_skills>');
  return lines.join('\n');
}

Skill loadSkillFromDir(String skillDirPath) {
  throw UnsupportedError(
    'loadSkillFromDir is not supported on this platform. '
    'Use inline Skill definitions instead.',
  );
}

List<String> validateSkillDir(String skillDirPath) {
  return <String>[
    'validateSkillDir is not supported on this platform. '
        'Use inline Skill definitions instead.',
  ];
}

Frontmatter readSkillProperties(String skillDirPath) {
  throw UnsupportedError(
    'readSkillProperties is not supported on this platform. '
    'Use inline Skill definitions instead.',
  );
}

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}

String _normalizeNfkc(String input) {
  return unorm.nfkc(input);
}
