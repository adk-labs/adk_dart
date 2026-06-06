/// Web-safe skill parsing runtime.
library;

import 'dart:convert';

import '../features/_feature_registry.dart';
import 'package:archive/archive.dart' as archive;
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:yaml/yaml.dart';

final RegExp _skillNamePattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final RegExp _skillNameSnakeOrKebabPattern = RegExp(
  r'^([a-z0-9]+(-[a-z0-9]+)*|[a-z0-9]+(_[a-z0-9]+)*)$',
);

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
    final bool allowSnakeCase = isFeatureEnabled(
      FeatureName.snakeCaseSkillName,
    );
    final RegExp pattern = allowSnakeCase
        ? _skillNameSnakeOrKebabPattern
        : _skillNamePattern;
    if (!pattern.hasMatch(normalized)) {
      throw ArgumentError(
        allowSnakeCase
            ? 'name must be lowercase kebab-case (a-z, 0-9, hyphens) or '
                  'snake_case (a-z, 0-9, underscores), with no leading, '
                  'trailing, or consecutive delimiters. Mixing hyphens and '
                  'underscores is not allowed.'
            : 'name must be lowercase kebab-case (a-z, 0-9, hyphens), '
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
      throw ArgumentError(
        'description must be at most 1024 characters. '
        'Description length: ${value.length}',
      );
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

  /// Fetches a skill by [name] and optional [version].
  ///
  /// Subclasses can override this to fetch skills from a remote registry.
  Future<Skill?> getSkill({required String name, String? version}) async {
    final Skill? skill = get(name);
    if (skill == null) {
      return null;
    }
    if (version != null && skill.version != version) {
      return null;
    }
    return skill;
  }

  /// Searches the registry for skill frontmatter matching [query].
  ///
  /// The default in-memory implementation performs a simple case-insensitive
  /// match over name, description, and instructions. Subclasses can override
  /// this for semantic search or implementation-specific filters.
  Future<List<Frontmatter>> searchSkills({
    required String query,
    Map<String, Object?>? filters,
  }) async {
    final String normalizedQuery = query.trim().toLowerCase();
    final Iterable<Skill> candidates = normalizedQuery.isEmpty
        ? _skills.values
        : _skills.values.where((Skill skill) {
            return skill.name.toLowerCase().contains(normalizedQuery) ||
                skill.description.toLowerCase().contains(normalizedQuery) ||
                skill.instructions.toLowerCase().contains(normalizedQuery);
          });

    return candidates
        .where((Skill skill) => _matchesFilters(skill, filters))
        .map((Skill skill) => skill.frontmatter)
        .toList(growable: false);
  }

  /// JSON schema for filters accepted by [searchSkills], if any.
  Map<String, Object?>? getFilterSchema() => null;

  /// Model-facing description for the registry search tool.
  String getSearchDescription() {
    return 'Searches for relevant skills in the registry based on a semantic or keyword query.';
  }

  bool _matchesFilters(Skill skill, Map<String, Object?>? filters) {
    if (filters == null || filters.isEmpty) {
      return true;
    }
    final Object? version = filters['version'];
    if (version is String && version.isNotEmpty && skill.version != version) {
      return false;
    }
    final Object? license = filters['license'];
    if (license is String &&
        license.isNotEmpty &&
        skill.frontmatter.license != license) {
      return false;
    }
    final Object? compatibility = filters['compatibility'];
    if (compatibility is String &&
        compatibility.isNotEmpty &&
        skill.frontmatter.compatibility != compatibility) {
      return false;
    }
    return true;
  }
}

/// Exception used by [SkillSource] implementations.
class SkillSourceException implements Exception {
  /// Creates a skill-source exception.
  SkillSourceException(this.message, [this.cause]);

  /// Human-readable failure reason.
  final String message;

  /// Optional underlying failure.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'SkillSourceException: $message'
      : 'SkillSourceException: $message ($cause)';
}

/// Asynchronous source interface for skill metadata, instructions, resources.
abstract class SkillSource {
  /// Lists all available skill frontmatter keyed by skill name.
  Future<Map<String, Frontmatter>> listFrontmatters();

  /// Lists resource paths under [resourceDirectory], relative to the skill.
  Future<List<String>> listResources(
    String skillName,
    String resourceDirectory,
  );

  /// Loads frontmatter for [skillName].
  Future<Frontmatter> loadFrontmatter(String skillName);

  /// Loads the instruction body from `SKILL.md` for [skillName].
  Future<String> loadInstructions(String skillName);

  /// Loads one resource as raw bytes, relative to the skill directory.
  Future<List<int>> loadResource(String skillName, String resourcePath);
}

/// In-memory [SkillSource] implementation.
class InMemorySkillSource implements SkillSource {
  /// Creates a source from pre-built skill data.
  InMemorySkillSource(Map<String, InMemorySkillData> skills)
    : _skills = Map<String, InMemorySkillData>.unmodifiable(skills);

  /// Creates a source from complete [Skill] objects.
  factory InMemorySkillSource.fromSkills(Iterable<Skill> skills) {
    return InMemorySkillSource(<String, InMemorySkillData>{
      for (final Skill skill in skills)
        skill.name: InMemorySkillData.fromSkill(skill),
    });
  }

  /// Creates a Java-parity builder for in-memory skills.
  static InMemorySkillSourceBuilder builder() {
    return InMemorySkillSourceBuilder();
  }

  final Map<String, InMemorySkillData> _skills;

  @override
  Future<Map<String, Frontmatter>> listFrontmatters() async {
    return <String, Frontmatter>{
      for (final MapEntry<String, InMemorySkillData> entry in _skills.entries)
        entry.key: entry.value.frontmatter,
    };
  }

  @override
  Future<List<String>> listResources(
    String skillName,
    String resourceDirectory,
  ) async {
    final InMemorySkillData data = _readSkill(skillName);
    final String prefix = resourceDirectory.trim().isEmpty
        ? ''
        : resourceDirectory.endsWith('/')
        ? resourceDirectory
        : '$resourceDirectory/';
    if (prefix.isNotEmpty &&
        !data.resources.keys.any((String path) => path.startsWith(prefix))) {
      throw SkillSourceException(
        "Resource directory not found: $resourceDirectory for skill: $skillName",
      );
    }
    final List<String> paths =
        data.resources.keys
            .where((String path) => path.startsWith(prefix))
            .toList(growable: false)
          ..sort();
    return paths;
  }

  @override
  Future<Frontmatter> loadFrontmatter(String skillName) async {
    return _readSkill(skillName).frontmatter;
  }

  @override
  Future<String> loadInstructions(String skillName) async {
    return _readSkill(skillName).instructions;
  }

  @override
  Future<List<int>> loadResource(String skillName, String resourcePath) async {
    final List<int>? bytes = _readSkill(skillName).resources[resourcePath];
    if (bytes == null) {
      throw SkillSourceException('Resource not found: $resourcePath');
    }
    return List<int>.from(bytes);
  }

  InMemorySkillData _readSkill(String skillName) {
    final InMemorySkillData? data = _skills[skillName];
    if (data == null) {
      throw SkillSourceException('Skill not found: $skillName');
    }
    return data;
  }
}

/// Complete in-memory payload for one skill source entry.
class InMemorySkillData {
  /// Creates in-memory skill data.
  InMemorySkillData({
    required this.frontmatter,
    required this.instructions,
    Map<String, List<int>>? resources,
  }) : resources = Map<String, List<int>>.unmodifiable(
         (resources ?? <String, List<int>>{}).map(
           (String key, List<int> value) =>
               MapEntry(key, List<int>.from(value)),
         ),
       );

  /// Builds skill data from a complete [Skill].
  factory InMemorySkillData.fromSkill(Skill skill) {
    final Map<String, List<int>> resources = <String, List<int>>{};
    void addResource(String directory, String name, SkillResourceData data) {
      resources['$directory/$name'] = _resourceToBytes(data);
    }

    skill.resources.references.forEach(
      (String name, SkillResourceData data) =>
          addResource('references', name, data),
    );
    skill.resources.assets.forEach(
      (String name, SkillResourceData data) =>
          addResource('assets', name, data),
    );
    skill.resources.scripts.forEach((String name, Script script) {
      resources['scripts/$name'] = utf8.encode(script.src);
    });
    return InMemorySkillData(
      frontmatter: skill.frontmatter,
      instructions: skill.instructions,
      resources: resources,
    );
  }

  /// Frontmatter for this skill.
  final Frontmatter frontmatter;

  /// Instruction body for this skill.
  final String instructions;

  /// Resource bytes keyed by path relative to skill root.
  final Map<String, List<int>> resources;
}

/// Builder for [InMemorySkillSource].
class InMemorySkillSourceBuilder {
  final Map<String, InMemorySkillBuilder> _skillBuilders =
      <String, InMemorySkillBuilder>{};

  /// Returns a builder for [name], creating it if needed.
  InMemorySkillBuilder skill(String name) {
    return _skillBuilders.putIfAbsent(
      name,
      () => InMemorySkillBuilder._(this, name),
    );
  }

  /// Builds the source.
  InMemorySkillSource build() {
    return InMemorySkillSource(<String, InMemorySkillData>{
      for (final MapEntry<String, InMemorySkillBuilder> entry
          in _skillBuilders.entries)
        entry.key: entry.value._build(),
    });
  }
}

/// Builder for one in-memory skill.
class InMemorySkillBuilder {
  InMemorySkillBuilder._(this._owner, this.name);

  final InMemorySkillSourceBuilder _owner;

  /// Skill name this builder configures.
  final String name;
  Frontmatter? _frontmatter;
  String? _instructions;
  final Map<String, List<int>> _resources = <String, List<int>>{};

  /// Sets frontmatter.
  InMemorySkillBuilder frontmatter(Frontmatter value) {
    _frontmatter = value;
    return this;
  }

  /// Sets instruction body.
  InMemorySkillBuilder instructions(String value) {
    _instructions = value;
    return this;
  }

  /// Adds a resource from raw bytes.
  InMemorySkillBuilder addResource(String path, Object content) {
    _resources[path] = _resourceToBytes(content);
    return this;
  }

  /// Switches to another skill builder.
  InMemorySkillBuilder skill(String name) {
    return _owner.skill(name);
  }

  /// Builds the containing source.
  InMemorySkillSource build() {
    return _owner.build();
  }

  InMemorySkillData _build() {
    final Frontmatter? frontmatter = _frontmatter;
    if (frontmatter == null) {
      throw StateError('Frontmatter is required for skill $name.');
    }
    final String? instructions = _instructions;
    if (instructions == null) {
      throw StateError('Instructions are required for skill $name.');
    }
    return InMemorySkillData(
      frontmatter: frontmatter,
      instructions: instructions,
      resources: _resources,
    );
  }
}

/// Filesystem-backed [SkillSource], unsupported on Web.
class LocalSkillSource implements SkillSource {
  /// Creates an unsupported local source on Web.
  LocalSkillSource(this.skillsBasePath);

  /// Directory containing skill subdirectories.
  final String skillsBasePath;

  @override
  Future<Map<String, Frontmatter>> listFrontmatters() {
    throw UnsupportedError(
      'LocalSkillSource is not supported on this platform.',
    );
  }

  @override
  Future<List<String>> listResources(
    String skillName,
    String resourceDirectory,
  ) {
    throw UnsupportedError(
      'LocalSkillSource is not supported on this platform.',
    );
  }

  @override
  Future<Frontmatter> loadFrontmatter(String skillName) {
    throw UnsupportedError(
      'LocalSkillSource is not supported on this platform.',
    );
  }

  @override
  Future<String> loadInstructions(String skillName) {
    throw UnsupportedError(
      'LocalSkillSource is not supported on this platform.',
    );
  }

  @override
  Future<List<int>> loadResource(String skillName, String resourcePath) {
    throw UnsupportedError(
      'LocalSkillSource is not supported on this platform.',
    );
  }
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

/// Loads a [Skill] from ZIP bytes containing a root-level `SKILL.md`.
Skill loadSkillFromZipBytes(List<int> zipBytes) {
  final archive.Archive skillArchive = archive.ZipDecoder().decodeBytes(
    zipBytes,
  );
  final Map<String, archive.ArchiveFile> files =
      <String, archive.ArchiveFile>{};
  for (final archive.ArchiveFile entry in skillArchive) {
    final String name = _normalizeArchiveEntryName(entry.name);
    _assertSafeArchiveEntry(entry.name, name);
    if (!entry.isFile) {
      continue;
    }
    if (entry.isSymbolicLink) {
      throw ArgumentError('Dangerous zip entry ignored: ${entry.name}');
    }
    files[name] = entry;
  }

  final archive.ArchiveFile? skillMd = files['SKILL.md'] ?? files['skill.md'];
  if (skillMd == null) {
    throw StateError('SKILL.md not found in zipped filesystem.');
  }
  final List<int>? skillMdBytes = skillMd.readBytes();
  if (skillMdBytes == null) {
    throw const FormatException(
      'SKILL.md could not be read from zipped filesystem.',
    );
  }

  final _ParsedSkillMd parsed = _parseSkillMdContent(
    _decodeSkillText(skillMdBytes),
  );
  final Object? skillName = parsed.frontmatter['name'];
  if (skillName == null) {
    throw ArgumentError("SKILL.md frontmatter must contain 'name'");
  }
  if (skillName is! String || _isInvalidArchiveSkillName(skillName)) {
    throw ArgumentError('Invalid skill name in SKILL.md: $skillName');
  }
  final Frontmatter frontmatter = Frontmatter.fromMap(parsed.frontmatter);

  final Map<String, SkillResourceData> references =
      <String, SkillResourceData>{};
  final Map<String, SkillResourceData> assets = <String, SkillResourceData>{};
  final Map<String, Script> scripts = <String, Script>{};
  for (final MapEntry<String, archive.ArchiveFile> entry in files.entries) {
    if (entry.key == 'SKILL.md' || entry.key == 'skill.md') {
      continue;
    }
    if (_containsIgnoredArchiveSegment(entry.key)) {
      continue;
    }
    final List<int>? bytes = entry.value.readBytes();
    if (bytes == null) {
      continue;
    }
    if (entry.key.startsWith('references/')) {
      final String resourceId = entry.key.substring('references/'.length);
      if (resourceId.isNotEmpty) {
        references[resourceId] = _decodeSkillResource(resourceId, bytes);
      }
      continue;
    }
    if (entry.key.startsWith('assets/')) {
      final String resourceId = entry.key.substring('assets/'.length);
      if (resourceId.isNotEmpty) {
        assets[resourceId] = _decodeSkillResource(resourceId, bytes);
      }
      continue;
    }
    if (entry.key.startsWith('scripts/')) {
      final String scriptId = entry.key.substring('scripts/'.length);
      if (scriptId.isEmpty) {
        continue;
      }
      try {
        scripts[scriptId] = Script(src: _decodeSkillText(bytes));
      } on FormatException {
        continue;
      }
    }
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

/// Web stub for GCS-backed skill storage.
abstract class SkillGcsStore {
  /// Lists blob names in [bucketName], optionally filtered by [prefix].
  Future<List<String>> listBlobNames(String bucketName, {String? prefix});

  /// Downloads raw blob bytes, or `null` when the blob is missing.
  Future<List<int>?> downloadBlob(String bucketName, String blobName);
}

/// Web stub for live GCS-backed skill storage.
class LiveSkillGcsStore implements SkillGcsStore {
  /// Creates an unsupported live store on Web.
  LiveSkillGcsStore({
    Uri? apiBaseUri,
    Future<String> Function()? accessTokenProvider,
  });

  @override
  Future<List<String>> listBlobNames(String bucketName, {String? prefix}) {
    throw UnsupportedError(
      'LiveSkillGcsStore is not supported on this platform.',
    );
  }

  @override
  Future<List<int>?> downloadBlob(String bucketName, String blobName) {
    throw UnsupportedError(
      'LiveSkillGcsStore is not supported on this platform.',
    );
  }
}

/// Throws because GCS-backed skill loading is unsupported on Web.
Future<Map<String, Frontmatter>> listSkillsInGcsDir(
  String bucketName, {
  String skillsBasePath = '',
  Object? storageStore,
}) {
  throw UnsupportedError(
    'listSkillsInGcsDir is not supported on this platform. '
    'Use inline Skill definitions instead.',
  );
}

/// Throws because GCS-backed skill loading is unsupported on Web.
Future<Skill> loadSkillFromGcsDir(
  String bucketName,
  String skillId, {
  String skillsBasePath = '',
  Object? storageStore,
}) {
  throw UnsupportedError(
    'loadSkillFromGcsDir is not supported on this platform. '
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

List<int> _resourceToBytes(Object value) {
  if (value is String) {
    return utf8.encode(value);
  }
  if (value is List<int>) {
    return List<int>.from(value);
  }
  if (value is List) {
    return value
        .map<int>((Object? item) => item as int)
        .toList(growable: false);
  }
  throw ArgumentError('resource values must be String or List<int>');
}

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

class _ParsedSkillMd {
  _ParsedSkillMd({required this.frontmatter, required this.body});

  final Map<String, Object?> frontmatter;
  final String body;
}

_ParsedSkillMd _parseSkillMdContent(String content) {
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

Map<String, Object?> _parseYamlMapping(String source) {
  final Object? loaded = loadYaml(source);
  if (loaded is! YamlMap) {
    throw FormatException('SKILL.md frontmatter must be a YAML mapping');
  }
  return _yamlMapToPlainMap(loaded);
}

Map<String, Object?> _yamlMapToPlainMap(YamlMap map) {
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<dynamic, dynamic> entry in map.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      throw FormatException('SKILL.md frontmatter keys must be strings');
    }
    result[key] = _yamlToPlainValue(entry.value);
  }
  return result;
}

Object? _yamlToPlainValue(Object? value) {
  if (value is YamlMap) {
    return _yamlMapToPlainMap(value);
  }
  if (value is YamlList) {
    return value.nodes
        .map<Object?>((YamlNode node) => _yamlToPlainValue(node.value))
        .toList(growable: false);
  }
  return value;
}

String _decodeSkillText(List<int> bytes) {
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw FormatException('Skill content is not valid UTF-8 text.');
  }
}

SkillResourceData _decodeSkillResource(String relativePath, List<int> bytes) {
  if (_shouldTreatAsBinaryResource(relativePath)) {
    return List<int>.from(bytes);
  }
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    return List<int>.from(bytes);
  }
}

String _normalizeArchiveEntryName(String name) => name.replaceAll('\\', '/');

void _assertSafeArchiveEntry(String originalName, String normalizedName) {
  final List<String> segments = normalizedName.split('/');
  if (normalizedName.isEmpty ||
      normalizedName.startsWith('/') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(normalizedName) ||
      segments.contains('..')) {
    throw ArgumentError('Dangerous zip entry ignored: $originalName');
  }
}

bool _isInvalidArchiveSkillName(String skillName) {
  final String normalized = skillName.replaceAll('\\', '/');
  return normalized.isEmpty ||
      normalized.startsWith('/') ||
      normalized.contains('/') ||
      normalized == '.' ||
      normalized == '..';
}

bool _containsIgnoredArchiveSegment(String path) {
  return path.split('/').contains('__pycache__');
}

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

bool _shouldTreatAsBinaryResource(String relativePath) {
  final String lower = relativePath.toLowerCase();
  for (final String extension in _textSkillResourceExtensions) {
    if (lower.endsWith(extension)) {
      return false;
    }
  }
  return true;
}
