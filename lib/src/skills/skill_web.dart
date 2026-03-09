/// Web-safe skill parsing and registry runtime.
library;

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

/// Metadata value allowed in skill frontmatter.
typedef SkillMetadataValue = Object?;

/// Resource payload allowed in skill references/assets.
typedef SkillResourceData = Object;

/// Minimal shape shared by all skill descriptors.
abstract class SkillDescriptor {
  /// Creates a skill descriptor.
  SkillDescriptor();

  /// Stable skill name in lowercase kebab-case.
  String get name;

  /// Human-readable summary used in skill catalogs.
  String get description;
}

/// L1 skill metadata parsed from SKILL.md frontmatter.
class Frontmatter implements SkillDescriptor {
  /// Creates validated skill frontmatter metadata.
  Frontmatter({
    required String name,
    required String description,
    this.license,
    String? compatibility,
    this.allowedTools,
    Map<String, SkillMetadataValue>? metadata,
    Map<String, Object?>? extraFields,
  }) : name = _validateName(name),
       description = _validateDescription(description),
       compatibility = _validateCompatibility(compatibility),
       metadata = Map<String, SkillMetadataValue>.unmodifiable(
         _cloneMetadataMap(metadata ?? <String, SkillMetadataValue>{}),
       ),
       extraFields = Map<String, Object?>.unmodifiable(
         extraFields ?? <String, Object?>{},
       );

  /// Parses frontmatter from a decoded map.
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

  /// Canonical skill name.
  @override
  final String name;

  /// Short skill description.
  @override
  final String description;

  /// Optional license identifier.
  final String? license;

  /// Optional compatibility note shown to agents/users.
  final String? compatibility;

  /// Optional allowed-tools selector expression.
  final String? allowedTools;

  /// Free-form metadata map.
  final Map<String, SkillMetadataValue> metadata;

  /// Unknown frontmatter fields preserved when allowed.
  final Map<String, Object?> extraFields;

  /// Converts this frontmatter object back into a plain map.
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
      result['metadata'] = _cloneMetadataMap(metadata);
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

  static Map<String, SkillMetadataValue> _readMetadata(Object? value) {
    if (value == null) {
      return <String, SkillMetadataValue>{};
    }
    if (value is! Map) {
      throw ArgumentError('metadata must be a mapping');
    }
    final Map<String, SkillMetadataValue> metadata =
        <String, SkillMetadataValue>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final Object? key = entry.key;
      if (key is! String) {
        throw ArgumentError('metadata keys must be strings');
      }
      metadata[key] = _normalizeMetadataValue(entry.value);
    }
    return metadata;
  }
}

/// Wrapper for script content.
class Script {
  /// Creates a script wrapper from source text.
  Script({required this.src});

  /// Raw script source code.
  final String src;

  @override
  String toString() => src;
}

/// L3 skill resources loaded from references/assets/scripts directories.
class Resources {
  /// Creates grouped skill resources.
  Resources({
    Map<String, SkillResourceData>? references,
    Map<String, SkillResourceData>? assets,
    Map<String, Script>? scripts,
  }) : references = Map<String, SkillResourceData>.unmodifiable(
         _normalizeResourceMap(references ?? <String, SkillResourceData>{}),
       ),
       assets = Map<String, SkillResourceData>.unmodifiable(
         _normalizeResourceMap(assets ?? <String, SkillResourceData>{}),
       ),
       scripts = Map<String, Script>.unmodifiable(
         scripts ?? <String, Script>{},
       );

  /// Text or binary references bundled with the skill.
  final Map<String, SkillResourceData> references;

  /// Static text or binary assets bundled with the skill.
  final Map<String, SkillResourceData> assets;

  /// Executable scripts bundled with the skill.
  final Map<String, Script> scripts;

  /// Returns one reference by [referenceId], if present.
  String? getReference(String referenceId) =>
      _readTextResource(references[referenceId]);

  /// Returns one binary reference by [referenceId], if present.
  List<int>? getReferenceBytes(String referenceId) =>
      _readBinaryResource(references[referenceId]);

  /// Returns one asset by [assetId], if present.
  String? getAsset(String assetId) => _readTextResource(assets[assetId]);

  /// Returns one binary asset by [assetId], if present.
  List<int>? getAssetBytes(String assetId) =>
      _readBinaryResource(assets[assetId]);

  /// Returns one raw reference payload by [referenceId], if present.
  SkillResourceData? getReferenceData(String referenceId) =>
      references[referenceId];

  /// Returns one raw asset payload by [assetId], if present.
  SkillResourceData? getAssetData(String assetId) => assets[assetId];

  /// Returns one script by [scriptId], if present.
  Script? getScript(String scriptId) => scripts[scriptId];

  /// Lists available reference IDs.
  List<String> listReferences() => references.keys.toList(growable: false);

  /// Lists available asset IDs.
  List<String> listAssets() => assets.keys.toList(growable: false);

  /// Lists available script IDs.
  List<String> listScripts() => scripts.keys.toList(growable: false);
}

/// Complete skill representation with metadata, instructions, and resources.
class Skill implements SkillDescriptor {
  /// Creates a complete skill object.
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
    Map<String, SkillMetadataValue>? metadata,
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

  /// Parsed SKILL.md frontmatter metadata.
  final Frontmatter frontmatter;

  /// Markdown body instructions from SKILL.md.
  final String instructions;

  /// Associated references/assets/scripts.
  final Resources resources;

  /// Optional skill version string.
  final String version;

  /// Skill name from [frontmatter].
  @override
  String get name => frontmatter.name;

  /// Skill description from [frontmatter].
  @override
  String get description => frontmatter.description;
}

/// In-memory registry for named [Skill] objects.
class SkillRegistry {
  /// Creates an empty [SkillRegistry].
  SkillRegistry();

  final Map<String, Skill> _skills = <String, Skill>{};

  /// Adds or replaces one [skill] by its name.
  void register(Skill skill) {
    _skills[skill.name] = skill;
  }

  /// Returns a skill by [name], if registered.
  Skill? get(String name) => _skills[name];

  /// Whether a skill exists for [name].
  bool contains(String name) => _skills.containsKey(name);

  /// Removes a skill by [name].
  void remove(String name) {
    _skills.remove(name);
  }

  /// Removes every registered skill.
  void clear() {
    _skills.clear();
  }

  /// Returns all registered skills.
  List<Skill> list() => _skills.values.toList(growable: false);
}

/// Renders a skill summary list as XML text for model prompts.
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

/// Throws because directory-based skill loading is unsupported on Web.
Skill loadSkillFromDir(String skillDirPath) {
  throw UnsupportedError(
    'loadSkillFromDir is not supported on this platform. '
    'Use inline Skill definitions instead.',
  );
}

/// Reports unsupported validation mode on Web.
List<String> validateSkillDir(String skillDirPath) {
  return <String>[
    'validateSkillDir is not supported on this platform. '
        'Use inline Skill definitions instead.',
  ];
}

/// Throws because skill-property file loading is unsupported on Web.
Frontmatter readSkillProperties(String skillDirPath) {
  throw UnsupportedError(
    'readSkillProperties is not supported on this platform. '
    'Use inline Skill definitions instead.',
  );
}

/// Returns no directory-backed skills on Web.
Map<String, Frontmatter> listSkillsInDir(String skillsBasePath) {
  return <String, Frontmatter>{};
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

Map<String, SkillMetadataValue> _cloneMetadataMap(
  Map<String, SkillMetadataValue> metadata,
) {
  return metadata.map(
    (String key, SkillMetadataValue value) =>
        MapEntry<String, SkillMetadataValue>(
          key,
          _normalizeMetadataValue(value),
        ),
  );
}

Object? _normalizeMetadataValue(Object? value) {
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry<String, Object?>(
        key.toString(),
        _normalizeMetadataValue(item),
      ),
    );
  }
  if (value is List) {
    return value
        .map<Object?>((Object? item) => _normalizeMetadataValue(item))
        .toList(growable: false);
  }
  return value;
}

Map<String, SkillResourceData> _normalizeResourceMap(
  Map<String, SkillResourceData> resources,
) {
  return resources.map(
    (String key, SkillResourceData value) =>
        MapEntry<String, SkillResourceData>(
          key,
          _normalizeResourceValue(value),
        ),
  );
}

SkillResourceData _normalizeResourceValue(Object? value) {
  if (value is String) {
    return value;
  }
  if (value is List<int>) {
    return List<int>.from(value);
  }
  if (value is List) {
    final List<int> bytes = value
        .map<int>((Object? item) {
          if (item is! int) {
            throw ArgumentError('resource values must be String or List<int>');
          }
          return item;
        })
        .toList(growable: false);
    return bytes;
  }
  throw ArgumentError('resource values must be String or List<int>');
}

String? _readTextResource(Object? value) => value is String ? value : null;

List<int>? _readBinaryResource(Object? value) {
  if (value is List<int>) {
    return List<int>.from(value);
  }
  if (value is List) {
    return value
        .map<int>((Object? item) => item as int)
        .toList(growable: false);
  }
  return null;
}
