import 'dart:convert';
import 'dart:io';

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
          ? <String, Object?>{
              for (final String key in unknown) key: value[key],
            }
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
    final String normalized = _normalizeNfkcLike(value);
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

  final Map<String, String> references = _loadDir(
    Directory(_join(skillDir.path, 'references')),
  );
  final Map<String, String> assets = _loadDir(
    Directory(_join(skillDir.path, 'assets')),
  );
  final Map<String, String> rawScripts = _loadDir(
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
    return <String>['$error'];
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
    problems.add('Frontmatter validation error: $error');
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

Frontmatter readSkillProperties(String skillDirPath) {
  final Directory skillDir = _resolveSkillDir(skillDirPath);
  final _ParsedSkillMd parsed = _parseSkillMd(skillDir);
  return Frontmatter.fromMap(parsed.frontmatter);
}

class _ParsedSkillMd {
  _ParsedSkillMd({required this.frontmatter, required this.body});

  final Map<String, Object?> frontmatter;
  final String body;
}

_ParsedSkillMd _parseSkillMd(Directory skillDir) {
  if (!skillDir.existsSync()) {
    throw ArgumentError("Skill directory '${skillDir.path}' not found.");
  }
  if (skillDir.statSync().type != FileSystemEntityType.directory) {
    throw ArgumentError("Skill directory '${skillDir.path}' not found.");
  }

  final File? skillMd = _findSkillMd(skillDir);
  if (skillMd == null) {
    throw ArgumentError("SKILL.md not found in '${skillDir.path}'.");
  }

  final String content = skillMd.readAsStringSync();
  final List<String> lines = LineSplitter.split(content).toList();
  if (lines.isEmpty || lines.first.trim() != '---') {
    throw FormatException('SKILL.md must start with YAML frontmatter (---)');
  }

  int closingIndex = -1;
  for (int i = 1; i < lines.length; i += 1) {
    if (lines[i].trim() == '---') {
      closingIndex = i;
      break;
    }
  }
  if (closingIndex < 0) {
    throw FormatException('SKILL.md frontmatter not properly closed with ---');
  }

  final String frontmatterText = lines.sublist(1, closingIndex).join('\n');
  final String body = lines.sublist(closingIndex + 1).join('\n').trim();

  final Map<String, Object?> parsed = _parseYamlMapping(frontmatterText);
  return _ParsedSkillMd(frontmatter: parsed, body: body);
}

Map<String, String> _loadDir(Directory directory) {
  final Map<String, String> files = <String, String>{};
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
    try {
      files[relativePath] = entity.readAsStringSync();
    } on FileSystemException {
      continue;
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
      throw const FormatException('SKILL.md frontmatter must be a YAML mapping');
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
      .replaceAll("'", '&apos;');
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

String _normalizeNfkcLike(String input) {
  final StringBuffer normalized = StringBuffer();
  for (final int rune in input.runes) {
    if (rune == 0x3000) {
      normalized.writeCharCode(0x20);
      continue;
    }
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      normalized.writeCharCode(rune - 0xFEE0);
      continue;
    }
    normalized.writeCharCode(rune);
  }
  return normalized.toString();
}

String _normalizePath(String path) => path.replaceAll('\\', '/');
