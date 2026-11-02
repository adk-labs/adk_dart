/// Local `.adk` storage-backed service factories for CLI runtime.
library;

import 'dart:async';
import 'dart:io';

import 'package:adk_dart/src/artifacts/base_artifact_service.dart';
import 'package:adk_dart/src/artifacts/file_artifact_service.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/sessions/base_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/sessions/sqlite_session_service.dart';
import 'package:adk_dart/src/types/content.dart';
import 'dot_adk_folder.dart';

/// Internal app key used for CLI built-in session services.
const String builtInSessionServiceKey = '__adk_built_in_session_service__';

/// Internal app key used for CLI built-in artifact services.
const String builtInArtifactServiceKey = '__adk_built_in_artifact_service__';

bool _isAbsolutePath(String path) {
  final String normalized = path.trim();
  if (normalized.isEmpty) {
    return false;
  }
  if (normalized.startsWith('/') || normalized.startsWith(r'\')) {
    return true;
  }
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(normalized);
}

/// Creates a SQLite-backed session service rooted at [baseDir].
BaseSessionService createLocalDatabaseSessionService({
  required Object baseDir,
}) {
  final DotAdkFolder manager = DotAdkFolder(baseDir);
  manager.dotAdkDir.createSync(recursive: true);
  return SqliteSessionService(manager.sessionDbPath.path);
}

/// Creates a local session service for CLI usage.
///
/// When [perAgent] is `true`, each app uses its own underlying database.
BaseSessionService createLocalSessionService({
  required Object baseDir,
  bool perAgent = false,
  Map<String, String>? appNameToDir,
}) {
  if (perAgent) {
    return PerAgentDatabaseSessionService(
      agentsRoot: baseDir,
      appNameToDir: appNameToDir,
    );
  }
  return createLocalDatabaseSessionService(baseDir: baseDir);
}

/// Creates a file-backed artifact service rooted at [baseDir].
///
/// When [perAgent] is `true`, creates a [PerAgentFileArtifactService] that
/// stores artifacts in each agent's `.adk/artifacts` folder.
BaseArtifactService createLocalArtifactService({
  required Object baseDir,
  bool perAgent = false,
  Map<String, String>? appNameToDir,
}) {
  if (perAgent) {
    return PerAgentFileArtifactService(
      agentsRoot: baseDir,
      appNameToDir: appNameToDir,
    );
  }
  final DotAdkFolder manager = DotAdkFolder(baseDir);
  manager.artifactsDir.createSync(recursive: true);
  return FileArtifactService(manager.artifactsDir.path);
}

/// Routes session operations to per-agent local database services.
class PerAgentDatabaseSessionService extends BaseSessionService {
  /// Creates a per-agent database session service.
  PerAgentDatabaseSessionService({
    required Object agentsRoot,
    Map<String, String>? appNameToDir,
  }) : _agentsRoot = directoryFromArg(agentsRoot, parameterName: 'agentsRoot'),
       _appNameToDir = appNameToDir ?? <String, String>{};

  final Directory _agentsRoot;
  final Map<String, String> _appNameToDir;
  final Map<String, BaseSessionService> _services =
      <String, BaseSessionService>{};
  Future<void> _lock = Future<void>.value();

  Future<T> _withLock<T>(Future<T> Function() action) async {
    final Completer<void> next = Completer<void>();
    final Future<void> previous = _lock;
    _lock = next.future;
    await previous;
    try {
      return await action();
    } finally {
      next.complete();
    }
  }

  Future<BaseSessionService> _getService(String appName) async {
    return _withLock<BaseSessionService>(() async {
      final String key = appName.startsWith('__')
          ? builtInSessionServiceKey
          : (_appNameToDir[appName] ?? appName);
      final BaseSessionService? existing = _services[key];
      if (existing != null) {
        return existing;
      }

      final BaseSessionService created;
      if (key == builtInSessionServiceKey) {
        created = createLocalDatabaseSessionService(baseDir: _agentsRoot.path);
      } else if (_isAbsolutePath(key)) {
        // appNameToDir entries may already be absolute paths (for example from
        // web server directory discovery); avoid prefixing agentsRoot again.
        created = createLocalDatabaseSessionService(baseDir: key);
      } else {
        final DotAdkFolder folder = dotAdkFolderForAgent(
          agentsRoot: _agentsRoot.path,
          appName: key,
        );
        created = createLocalDatabaseSessionService(
          baseDir: folder.agentDir.path,
        );
      }
      _services[key] = created;
      return created;
    });
  }

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    final BaseSessionService service = await _getService(appName);
    return service.createSession(
      appName: appName,
      userId: userId,
      state: state,
      sessionId: sessionId,
    );
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    final BaseSessionService service = await _getService(appName);
    return service.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      config: config,
    );
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    final BaseSessionService service = await _getService(appName);
    return service.listSessions(appName: appName, userId: userId);
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    final BaseSessionService service = await _getService(appName);
    await service.deleteSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  @override
  Future<Map<String, Object?>> getUserState({
    required String appName,
    required String userId,
  }) async {
    final BaseSessionService service = await _getService(appName);
    return service.getUserState(appName: appName, userId: userId);
  }

  @override
  Future<Event> appendEvent({
    required Session session,
    required Event event,
  }) async {
    final BaseSessionService service = await _getService(session.appName);
    return service.appendEvent(session: session, event: event);
  }

  /// Closes all underlying session services and clears the cache.
  Future<void> close() async {
    for (final BaseSessionService service in _services.values) {
      try {
        final Object? maybeFuture = (service as dynamic).close();
        if (maybeFuture is Future<Object?>) {
          await maybeFuture;
        }
      } on NoSuchMethodError {
        // Ignore session services that do not expose a close() method.
      }
    }
    _services.clear();
  }
}

/// Routes artifact storage to per-agent `.adk/artifacts` folders.
class PerAgentFileArtifactService extends BaseArtifactService {
  /// Creates a per-agent file artifact service.
  PerAgentFileArtifactService({
    required Object agentsRoot,
    Map<String, String>? appNameToDir,
  }) : _agentsRoot = directoryFromArg(agentsRoot, parameterName: 'agentsRoot'),
       _appNameToDir = appNameToDir ?? <String, String>{};

  final Directory _agentsRoot;
  final Map<String, String> _appNameToDir;
  final Map<String, BaseArtifactService> _services =
      <String, BaseArtifactService>{};
  BaseArtifactService? _legacyService;
  Future<void> _lock = Future<void>.value();

  Future<T> _withLock<T>(Future<T> Function() action) async {
    final Completer<void> next = Completer<void>();
    final Future<void> previous = _lock;
    _lock = next.future;
    await previous;
    try {
      return await action();
    } finally {
      next.complete();
    }
  }

  Future<BaseArtifactService> _getService(String appName) async {
    return _withLock<BaseArtifactService>(() async {
      final String storageKey;
      final String baseDir;
      if (appName.startsWith('__')) {
        storageKey = builtInArtifactServiceKey;
        baseDir = _agentsRoot.path;
      } else {
        storageKey = _appNameToDir[appName] ?? appName;
        if (_isAbsolutePath(storageKey)) {
          baseDir = storageKey;
        } else {
          final DotAdkFolder folder = dotAdkFolderForAgent(
            agentsRoot: _agentsRoot.path,
            appName: storageKey,
          );
          baseDir = folder.agentDir.path;
        }
      }

      final BaseArtifactService? existing = _services[storageKey];
      if (existing != null) {
        return existing;
      }

      final BaseArtifactService created = createLocalArtifactService(
        baseDir: baseDir,
      );
      _services[storageKey] = created;
      return created;
    });
  }

  Future<BaseArtifactService?> _getLegacyService(String appName) async {
    if (appName.startsWith('__')) {
      return null;
    }
    if (_legacyService != null) {
      return _legacyService;
    }
    final Directory legacyDir = DotAdkFolder(_agentsRoot).artifactsDir;
    if (!legacyDir.existsSync()) {
      return null;
    }
    return _withLock<BaseArtifactService>(() async {
      _legacyService ??= FileArtifactService(legacyDir.path);
      return _legacyService!;
    });
  }

  @override
  Future<int> saveArtifact({
    required String appName,
    required String userId,
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    final BaseArtifactService service = await _getService(appName);
    return service.saveArtifact(
      appName: appName,
      userId: userId,
      filename: filename,
      artifact: artifact,
      sessionId: sessionId,
      customMetadata: customMetadata,
    );
  }

  @override
  Future<Part?> loadArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    final BaseArtifactService service = await _getService(appName);
    final Part? result = await service.loadArtifact(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
      version: version,
    );
    if (result != null) {
      return result;
    }
    final BaseArtifactService? legacy = await _getLegacyService(appName);
    if (legacy == null) {
      return null;
    }
    return legacy.loadArtifact(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
      version: version,
    );
  }

  @override
  Future<List<String>> listArtifactKeys({
    required String appName,
    required String userId,
    String? sessionId,
  }) async {
    final BaseArtifactService service = await _getService(appName);
    final List<String> keys = await service.listArtifactKeys(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
    final BaseArtifactService? legacy = await _getLegacyService(appName);
    if (legacy == null) {
      return keys;
    }
    final List<String> legacyKeys = await legacy.listArtifactKeys(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
    final List<String> merged = <String>{...keys, ...legacyKeys}.toList()
      ..sort();
    return merged;
  }

  @override
  Future<void> deleteArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final BaseArtifactService service = await _getService(appName);
    await service.deleteArtifact(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
    final BaseArtifactService? legacy = await _getLegacyService(appName);
    if (legacy != null) {
      await legacy.deleteArtifact(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
      );
    }
  }

  @override
  Future<List<int>> listVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final BaseArtifactService service = await _getService(appName);
    final List<int> versions = await service.listVersions(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
    if (versions.isNotEmpty) {
      return versions;
    }
    final BaseArtifactService? legacy = await _getLegacyService(appName);
    if (legacy == null) {
      return versions;
    }
    return legacy.listVersions(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
  }

  @override
  Future<List<ArtifactVersion>> listArtifactVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final BaseArtifactService service = await _getService(appName);
    final List<ArtifactVersion> versions = await service.listArtifactVersions(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
    if (versions.isNotEmpty) {
      return versions;
    }
    final BaseArtifactService? legacy = await _getLegacyService(appName);
    if (legacy == null) {
      return versions;
    }
    return legacy.listArtifactVersions(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
  }

  @override
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    final BaseArtifactService service = await _getService(appName);
    final ArtifactVersion? result = await service.getArtifactVersion(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
      version: version,
    );
    if (result != null) {
      return result;
    }
    final BaseArtifactService? legacy = await _getLegacyService(appName);
    if (legacy == null) {
      return null;
    }
    return legacy.getArtifactVersion(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
      version: version,
    );
  }
}
