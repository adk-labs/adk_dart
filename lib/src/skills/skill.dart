/// Skill discovery, parsing, and registry runtime for Dart and Flutter.
library;

import 'dart:convert';
import 'dart:io';

import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:yaml/yaml.dart';

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
    if (!allowUnknownFields) {
      if (unknown.isNotEmpty) {
        throw ArgumentError(
          'Unknown frontmatter fields: ${unknown.toList()..sort()}',
        );
      }
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

/// Loads a [Skill] from a directory containing `SKILL.md`.
Skill loadSkillFromDir(String skillDirPath) {
  final Directory skillDir = _resolveSkillDir(skillDirPath);
  final _ParsedSkillMd parsed = _parseSkillMd(skillDir);
  final Frontmatter frontmatter = Frontmatter.fromMap(parsed.frontmatter);

  final String directoryName = _basename(skillDir.path);
  if (directoryName != frontmatter.name) {
    throw ArgumentError(
      "Skill name '${frontmatter.name}' does not match directory "
      "name '$directoryName'.",
    );
  }

  final Map<String, SkillResourceData> references = _loadResourceDir(
    Directory(_join(skillDir.path, 'references')),
  );
  final Map<String, SkillResourceData> assets = _loadResourceDir(
    Directory(_join(skillDir.path, 'assets')),
  );
  final Map<String, String> rawScripts = _loadScriptDir(
    Directory(_join(skillDir.path, 'scripts')),
  );
  final Map<String, Script> scripts = <String, Script>{};
  for (final MapEntry<String, String> entry in rawScripts.entries) {
    scripts[entry.key] = Script(src: entry.value);
  }

  return Skill(
    frontmatter: frontmatter,
    instructions: parsed.body,
    resources: Resources(
      references: references,
      assets: assets,
      scripts: scripts,
    ),
  );
}

/// Validates skill directory structure and returns human-readable problems.
List<String> validateSkillDir(String skillDirPath) {
  final Directory skillDir = _resolveSkillDir(skillDirPath);

  if (!skillDir.existsSync()) {
    return <String>["Directory '${skillDir.path}' does not exist."];
  }
  if (skillDir.statSync().type != FileSystemEntityType.directory) {
    return <String>["'${skillDir.path}' is not a directory."];
  }

  if (_findSkillMd(skillDir) == null) {
    return <String>["SKILL.md not found in '${skillDir.path}'."];
  }

  Map<String, Object?> parsed;
  try {
    parsed = _parseSkillMd(skillDir).frontmatter;
  } catch (error) {
    return <String>[_formatSkillError(error)];
  }

  final List<String> problems = <String>[];
  final Set<String> unknown = parsed.keys
      .where((String key) => !_allowedFrontmatterKeys.contains(key))
      .toSet();
  if (unknown.isNotEmpty) {
    final List<String> sorted = unknown.toList()..sort();
    problems.add('Unknown frontmatter fields: $sorted');
  }

  Frontmatter frontmatter;
  try {
    frontmatter = Frontmatter.fromMap(parsed);
  } catch (error) {
    problems.add('Frontmatter validation error: ${_formatSkillError(error)}');
    return problems;
  }

  final String directoryName = _basename(skillDir.path);
  if (directoryName != frontmatter.name) {
    problems.add(
      "Skill name '${frontmatter.name}' does not match directory "
      "name '$directoryName'.",
    );
  }

  return problems;
}

/// Reads only frontmatter properties from a skill directory.
Frontmatter readSkillProperties(String skillDirPath) {
  final Directory skillDir = _resolveSkillDir(skillDirPath);
  final _ParsedSkillMd parsed = _parseSkillMd(skillDir);
  return Frontmatter.fromMap(parsed.frontmatter);
}

/// Lists valid skills in a base directory keyed by directory name.
Map<String, Frontmatter> listSkillsInDir(String skillsBasePath) {
  final Directory baseDir = Directory(skillsBasePath);
  if (!baseDir.existsSync() ||
      baseDir.statSync().type != FileSystemEntityType.directory) {
    return <String, Frontmatter>{};
  }

  final List<FileSystemEntity> entries = baseDir.listSync(followLinks: false)
    ..sort((FileSystemEntity a, FileSystemEntity b) {
      return a.path.compareTo(b.path);
    });

  final Map<String, Frontmatter> skills = <String, Frontmatter>{};
  for (final FileSystemEntity entry in entries) {
    if (FileSystemEntity.typeSync(entry.path, followLinks: true) !=
        FileSystemEntityType.directory) {
      continue;
    }

    final String skillId = _basename(entry.path);
    try {
      final Frontmatter frontmatter = readSkillProperties(entry.path);
      if (skillId != frontmatter.name) {
        throw ArgumentError(
          "Skill name '${frontmatter.name}' does not match directory "
          "name '$skillId'.",
        );
      }
      skills[skillId] = frontmatter;
    } catch (error) {
      stderr.writeln(
        "Skipping invalid skill '$skillId' in directory "
        "'${baseDir.path}': ${_formatSkillError(error)}",
      );
    }
  }

  return skills;
}

class _ParsedSkillMd {
  _ParsedSkillMd({required this.frontmatter, required this.body});

  final Map<String, Object?> frontmatter;
  final String body;
}

_ParsedSkillMd _parseSkillMd(Directory skillDir) {
  if (!skillDir.existsSync()) {
    throw FileSystemException(
      "Skill directory '${skillDir.path}' not found.",
      skillDir.path,
    );
  }
  if (skillDir.statSync().type != FileSystemEntityType.directory) {
    throw FileSystemException(
      "Skill directory '${skillDir.path}' not found.",
      skillDir.path,
    );
  }

  final File? skillMd = _findSkillMd(skillDir);
  if (skillMd == null) {
    throw FileSystemException(
      "SKILL.md not found in '${skillDir.path}'.",
      skillDir.path,
    );
  }

  final String content = skillMd.readAsStringSync();
  if (!content.startsWith('---')) {
    throw FormatException('SKILL.md must start with YAML frontmatter (---)');
  }

  final int closingIndex = content.indexOf('---', 3);
  if (closingIndex < 0) {
    throw FormatException('SKILL.md frontmatter not properly closed with ---');
  }

  final String frontmatterText = content.substring(3, closingIndex);
  final String body = content.substring(closingIndex + 3).trim();

  final Map<String, Object?> parsed = _parseYamlMapping(frontmatterText);
  return _ParsedSkillMd(frontmatter: parsed, body: body);
}

Map<String, SkillResourceData> _loadResourceDir(Directory directory) {
  final Map<String, SkillResourceData> files = <String, SkillResourceData>{};
  if (!directory.existsSync()) {
    return files;
  }
  if (directory.statSync().type != FileSystemEntityType.directory) {
    return files;
  }

  final String basePath = _normalizePath(directory.path);
  for (final FileSystemEntity entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) {
      continue;
    }
    final String normalizedPath = _normalizePath(entity.path);
    if (normalizedPath.split('/').contains('__pycache__')) {
      continue;
    }
    final String relativePath = normalizedPath.substring(basePath.length + 1);
    final List<int> bytes = entity.readAsBytesSync();
    if (_shouldTreatAsBinaryResource(relativePath, bytes)) {
      files[relativePath] = List<int>.from(bytes);
      continue;
    }
    try {
      files[relativePath] = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      files[relativePath] = List<int>.from(bytes);
    }
  }
  return files;
}

Map<String, String> _loadScriptDir(Directory directory) {
  final Map<String, String> files = <String, String>{};
  final Map<String, SkillResourceData> raw = _loadResourceDir(directory);
  for (final MapEntry<String, SkillResourceData> entry in raw.entries) {
    if (entry.value is String) {
      files[entry.key] = entry.value as String;
      continue;
    }
    final List<int> bytes = entry.value as List<int>;
    try {
      files[entry.key] = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      continue;
    }
  }
  return files;
}

Map<String, Object?> _parseYamlMapping(String text) {
  try {
    final Object? parsed = loadYaml(text);
    if (parsed is! Map) {
      throw const FormatException(
        'SKILL.md frontmatter must be a YAML mapping',
      );
    }
    return _yamlToMap(parsed);
  } catch (error) {
    if (error is FormatException) {
      throw FormatException('Invalid YAML in frontmatter: ${error.message}');
    }
    throw FormatException('Invalid YAML in frontmatter: $error');
  }
}

Map<String, Object?> _yamlToMap(Object? value) {
  if (value is YamlMap) {
    return value.map(
      (Object? key, Object? item) => MapEntry('$key', _yamlToObject(item)),
    );
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry('$key', _yamlToObject(item)),
    );
  }
  return <String, Object?>{};
}

Object? _yamlToObject(Object? value) {
  if (value is YamlMap) {
    return value.map(
      (Object? key, Object? item) => MapEntry('$key', _yamlToObject(item)),
    );
  }
  if (value is YamlList) {
    return value.map(_yamlToObject).toList(growable: false);
  }
  return value;
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

File? _findSkillMd(Directory skillDir) {
  for (final String fileName in <String>['SKILL.md', 'skill.md']) {
    final File file = File(_join(skillDir.path, fileName));
    if (file.existsSync()) {
      return file;
    }
  }
  return null;
}

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}

String _basename(String path) {
  final List<String> segments = _normalizePath(path)
      .split('/')
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) {
    return '';
  }
  return segments.last;
}

String _join(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

Directory _resolveSkillDir(String skillDirPath) {
  final Directory candidate = Directory(skillDirPath);
  try {
    final String resolvedPath = candidate.resolveSymbolicLinksSync();
    return Directory(resolvedPath);
  } on FileSystemException {
    return candidate.absolute;
  }
}

String _normalizeNfkc(String input) {
  return unorm.nfkc(input);
}

String _formatSkillError(Object error) {
  if (error is ArgumentError) {
    return '${error.message}';
  }
  if (error is FileSystemException) {
    return error.message;
  }
  if (error is FormatException) {
    return error.message;
  }
  return '$error';
}

String _normalizePath(String path) => path.replaceAll('\\', '/');

const Set<String> _textSkillResourceExtensions = <String>{
  '.bash',
  '.csv',
  '.dart',
  '.html',
  '.htm',
  '.js',
  '.json',
  '.md',
  '.py',
  '.sh',
  '.sql',
  '.svg',
  '.toml',
  '.ts',
  '.txt',
  '.xml',
  '.yaml',
  '.yml',
};

bool _shouldTreatAsBinaryResource(String relativePath, List<int> bytes) {
  final String lower = relativePath.toLowerCase();
  for (final String extension in _textSkillResourceExtensions) {
    if (lower.endsWith(extension)) {
      return false;
    }
  }
  return true;
}
