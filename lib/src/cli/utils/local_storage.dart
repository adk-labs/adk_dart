import 'dart:async';
import 'dart:io';

import '../../artifacts/base_artifact_service.dart';
import '../../artifacts/file_artifact_service.dart';
import '../../events/event.dart';
import '../../sessions/base_session_service.dart';
import '../../sessions/session.dart';
import '../../sessions/sqlite_session_service.dart';
import 'dot_adk_folder.dart';

const String builtInSessionServiceKey = '__adk_built_in_session_service__';

BaseSessionService createLocalDatabaseSessionService({
  required Object baseDir,
}) {
  final DotAdkFolder manager = DotAdkFolder(baseDir);
  manager.dotAdkDir.createSync(recursive: true);
  return SqliteSessionService(manager.sessionDbPath.path);
}

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

BaseArtifactService createLocalArtifactService({required Object baseDir}) {
  final DotAdkFolder manager = DotAdkFolder(baseDir);
  manager.artifactsDir.createSync(recursive: true);
  return FileArtifactService(manager.artifactsDir.path);
}

class PerAgentDatabaseSessionService extends BaseSessionService {
  PerAgentDatabaseSessionService({
    required Object agentsRoot,
    Map<String, String>? appNameToDir,
  }) : _agentsRoot = Directory('$agentsRoot').absolute,
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
  Future<Event> appendEvent({
    required Session session,
    required Event event,
  }) async {
    final BaseSessionService service = await _getService(session.appName);
    return service.appendEvent(session: session, event: event);
  }
}
