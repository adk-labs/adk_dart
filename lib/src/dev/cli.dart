import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../events/event.dart';
import '../sessions/session.dart';
import '../sessions/schemas/v0.dart';
import '../types/content.dart';
import 'project.dart';
import 'runtime.dart';
import 'web_server.dart';

const String adkUsage = '''
Usage: adk <command> [options]

Commands:
  create <project_dir>  Create a new ADK Dart project scaffold.
  run [project_dir]     Run an interactive CLI chat session.
  web [project_dir]     Start the ADK dev web server.
  api_server [project_dir]
                       Start the ADK API server (alias of `web`).

Create options:
      --app-name        Logical app name (default: directory name)

Run options:
      --user-id         User id (default: from adk.json or "user")
      --session-id      Reuse a session id (default: auto-generated)
      --save_session    Save session snapshot on exit
      --resume          Resume from a saved session snapshot json file
      --replay          Replay session input file json (state + queries)
  -m, --message         Single message mode (no interactive prompt)

Web options:
  -p, --port            Port to bind (default: 8000)
      --host            Host to bind (default: 127.0.0.1)
      --user-id         User id used by default web session
      --allow_origins   CORS origins (repeatable, supports regex: prefix)
      --url_prefix      URL prefix (example: /adk)
      --session_service_uri
      --artifact_service_uri
      --memory_service_uri
      --use_local_storage / --no-use_local_storage
      --auto_create_session
      --trace_to_cloud
      --otel_to_cloud
      --reload / --no-reload
      --reload_agents
      --a2a
      --extra_plugins
      --logo_text
      --logo_image_url
  -h, --help            Show this help message.
''';

class CliUsageError implements Exception {
  CliUsageError(this.message);

  final String message;

  @override
  String toString() => message;
}

enum AdkCommandType { create, run, web }

class ParsedAdkCommand {
  ParsedAdkCommand.create({required this.projectDir, this.appName})
    : type = AdkCommandType.create,
      port = null,
      host = null,
      userId = null,
      allowOrigins = const <String>[],
      sessionServiceUri = null,
      artifactServiceUri = null,
      memoryServiceUri = null,
      useLocalStorage = true,
      urlPrefix = null,
      traceToCloud = false,
      otelToCloud = false,
      reload = true,
      a2a = false,
      reloadAgents = false,
      extraPlugins = const <String>[],
      logoText = null,
      logoImageUrl = null,
      autoCreateSession = false,
      enableWebUi = true,
      sessionId = null,
      saveSession = false,
      resumeFilePath = null,
      replayFilePath = null,
      message = null;

  ParsedAdkCommand.run({
    required this.projectDir,
    this.userId,
    this.sessionId,
    required this.saveSession,
    this.resumeFilePath,
    this.replayFilePath,
    this.message,
  }) : type = AdkCommandType.run,
       appName = null,
       port = null,
       host = null,
       allowOrigins = const <String>[],
       sessionServiceUri = null,
       artifactServiceUri = null,
       memoryServiceUri = null,
       useLocalStorage = true,
       urlPrefix = null,
       traceToCloud = false,
       otelToCloud = false,
       reload = true,
       a2a = false,
       reloadAgents = false,
       extraPlugins = const <String>[],
       logoText = null,
       logoImageUrl = null,
       autoCreateSession = false,
       enableWebUi = true;

  ParsedAdkCommand.web({
    required this.projectDir,
    required this.port,
    required this.host,
    this.userId,
    required this.allowOrigins,
    this.sessionServiceUri,
    this.artifactServiceUri,
    this.memoryServiceUri,
    required this.useLocalStorage,
    this.urlPrefix,
    required this.traceToCloud,
    required this.otelToCloud,
    required this.reload,
    required this.a2a,
    required this.reloadAgents,
    required this.extraPlugins,
    this.logoText,
    this.logoImageUrl,
    required this.autoCreateSession,
    required this.enableWebUi,
  }) : type = AdkCommandType.web,
       appName = null,
       sessionId = null,
       saveSession = false,
       resumeFilePath = null,
       replayFilePath = null,
       message = null;

  final AdkCommandType type;
  final String projectDir;
  final String? appName;
  final int? port;
  final InternetAddress? host;
  final String? userId;
  final List<String> allowOrigins;
  final String? sessionServiceUri;
  final String? artifactServiceUri;
  final String? memoryServiceUri;
  final bool useLocalStorage;
  final String? urlPrefix;
  final bool traceToCloud;
  final bool otelToCloud;
  final bool reload;
  final bool a2a;
  final bool reloadAgents;
  final List<String> extraPlugins;
  final String? logoText;
  final String? logoImageUrl;
  final bool autoCreateSession;
  final bool enableWebUi;
  final String? sessionId;
  final bool saveSession;
  final String? resumeFilePath;
  final String? replayFilePath;
  final String? message;
}

ParsedAdkCommand parseAdkCliArgs(List<String> args) {
  if (args.isEmpty) {
    throw CliUsageError('Missing command.');
  }

  final String command = args.first;
  final List<String> commandArgs = args.skip(1).toList(growable: false);

  switch (command) {
    case 'create':
      return _parseCreateCommand(commandArgs);
    case 'run':
      return _parseRunCommand(commandArgs);
    case 'web':
      return _parseWebCommand(commandArgs, enableWebUi: true);
    case 'api_server':
      return _parseWebCommand(commandArgs, enableWebUi: false);
    default:
      throw CliUsageError('Unknown command: $command');
  }
}

Future<int> runAdkCli(
  List<String> args, {
  IOSink? outSink,
  IOSink? errSink,
}) async {
  final IOSink out = outSink ?? stdout;
  final IOSink err = errSink ?? stderr;

  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    out.writeln(adkUsage);
    return 0;
  }

  if (args.length > 1 && (args[1] == '-h' || args[1] == '--help')) {
    out.writeln(adkUsage);
    return 0;
  }

  final ParsedAdkCommand parsed;
  try {
    parsed = parseAdkCliArgs(args);
  } on CliUsageError catch (error) {
    err.writeln(error.message);
    err.writeln('');
    err.writeln(adkUsage);
    return 64;
  }

  try {
    switch (parsed.type) {
      case AdkCommandType.create:
        return _runCreateCommand(parsed, out);
      case AdkCommandType.run:
        return _runRunCommand(parsed, out);
      case AdkCommandType.web:
        return _runWebCommand(parsed, out, err);
    }
  } on FileSystemException catch (error) {
    err.writeln('Filesystem error: $error');
    return 1;
  } on SocketException catch (error) {
    err.writeln('Network error: $error');
    return 1;
  } on FormatException catch (error) {
    err.writeln('Config parse error: $error');
    return 1;
  }
}

ParsedAdkCommand _parseCreateCommand(List<String> args) {
  String? projectDir;
  String? appName;

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--app-name') {
      appName = _nextArg(args, i, '--app-name');
      i += 1;
      continue;
    }
    if (arg.startsWith('--app-name=')) {
      appName = arg.substring('--app-name='.length).trim();
      continue;
    }

    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for create: $arg');
    }

    if (projectDir != null) {
      throw CliUsageError('create accepts only one project directory.');
    }
    projectDir = arg;
  }

  if (projectDir == null || projectDir.trim().isEmpty) {
    throw CliUsageError('Missing project directory for create.');
  }

  return ParsedAdkCommand.create(
    projectDir: projectDir,
    appName: appName?.trim().isEmpty == true ? null : appName?.trim(),
  );
}

ParsedAdkCommand _parseRunCommand(List<String> args) {
  String projectDir = '.';
  String? userId;
  String? sessionId;
  String? resumeFilePath;
  String? replayFilePath;
  String? message;
  bool saveSession = false;
  bool seenProjectDir = false;

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--user-id') {
      userId = _nextArg(args, i, '--user-id');
      i += 1;
      continue;
    }
    if (arg.startsWith('--user-id=')) {
      userId = arg.substring('--user-id='.length);
      continue;
    }
    if (arg == '--session-id') {
      sessionId = _nextArg(args, i, '--session-id');
      i += 1;
      continue;
    }
    if (arg.startsWith('--session-id=')) {
      sessionId = arg.substring('--session-id='.length);
      continue;
    }
    if (arg == '-m' || arg == '--message') {
      message = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--message=')) {
      message = arg.substring('--message='.length);
      continue;
    }
    if (arg == '--save_session') {
      saveSession = true;
      continue;
    }
    if (arg == '--resume') {
      resumeFilePath = _nextArg(args, i, '--resume');
      i += 1;
      continue;
    }
    if (arg.startsWith('--resume=')) {
      resumeFilePath = arg.substring('--resume='.length);
      continue;
    }
    if (arg == '--replay') {
      replayFilePath = _nextArg(args, i, '--replay');
      i += 1;
      continue;
    }
    if (arg.startsWith('--replay=')) {
      replayFilePath = arg.substring('--replay='.length);
      continue;
    }

    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for run: $arg');
    }

    if (seenProjectDir) {
      throw CliUsageError('run accepts only one project directory.');
    }
    projectDir = arg;
    seenProjectDir = true;
  }

  if (_emptyToNull(resumeFilePath) != null &&
      _emptyToNull(replayFilePath) != null) {
    throw CliUsageError('--resume and --replay cannot be used together.');
  }
  if (_emptyToNull(message) != null && _emptyToNull(replayFilePath) != null) {
    throw CliUsageError('--message and --replay cannot be used together.');
  }

  return ParsedAdkCommand.run(
    projectDir: projectDir,
    userId: _emptyToNull(userId),
    sessionId: _emptyToNull(sessionId),
    saveSession: saveSession,
    resumeFilePath: _emptyToNull(resumeFilePath),
    replayFilePath: _emptyToNull(replayFilePath),
    message: _emptyToNull(message),
  );
}

ParsedAdkCommand _parseWebCommand(
  List<String> args, {
  required bool enableWebUi,
}) {
  int port = 8000;
  InternetAddress host = InternetAddress.loopbackIPv4;
  String projectDir = '.';
  String? userId;
  final List<String> allowOrigins = <String>[];
  String? sessionServiceUri;
  String? artifactServiceUri;
  String? memoryServiceUri;
  String? deprecatedSessionDbUrl;
  String? deprecatedArtifactStorageUri;
  bool useLocalStorage = true;
  String? urlPrefix;
  bool traceToCloud = false;
  bool otelToCloud = false;
  bool reload = true;
  bool a2a = false;
  bool reloadAgents = false;
  final List<String> extraPlugins = <String>[];
  String? logoText;
  String? logoImageUrl;
  bool autoCreateSession = false;
  bool seenProjectDir = false;

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--port' || arg == '-p') {
      port = _parsePort(_nextArg(args, i, arg));
      i += 1;
      continue;
    }
    if (arg.startsWith('--port=')) {
      port = _parsePort(arg.substring('--port='.length));
      continue;
    }
    if (arg == '--host') {
      host = _parseHost(_nextArg(args, i, '--host'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--host=')) {
      host = _parseHost(arg.substring('--host='.length));
      continue;
    }
    if (arg == '--user-id') {
      userId = _nextArg(args, i, '--user-id');
      i += 1;
      continue;
    }
    if (arg.startsWith('--user-id=')) {
      userId = arg.substring('--user-id='.length);
      continue;
    }
    if (arg == '--allow_origins') {
      allowOrigins.add(_nextArg(args, i, '--allow_origins').trim());
      i += 1;
      continue;
    }
    if (arg.startsWith('--allow_origins=')) {
      allowOrigins.add(arg.substring('--allow_origins='.length).trim());
      continue;
    }
    if (arg == '--session_service_uri') {
      sessionServiceUri = _nextArg(args, i, '--session_service_uri').trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--session_service_uri=')) {
      sessionServiceUri = arg.substring('--session_service_uri='.length).trim();
      continue;
    }
    if (arg == '--artifact_service_uri') {
      artifactServiceUri = _nextArg(args, i, '--artifact_service_uri').trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--artifact_service_uri=')) {
      artifactServiceUri = arg
          .substring('--artifact_service_uri='.length)
          .trim();
      continue;
    }
    if (arg == '--memory_service_uri') {
      memoryServiceUri = _nextArg(args, i, '--memory_service_uri').trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--memory_service_uri=')) {
      memoryServiceUri = arg.substring('--memory_service_uri='.length).trim();
      continue;
    }
    if (arg == '--session_db_url') {
      deprecatedSessionDbUrl = _nextArg(args, i, '--session_db_url').trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--session_db_url=')) {
      deprecatedSessionDbUrl = arg.substring('--session_db_url='.length).trim();
      continue;
    }
    if (arg == '--artifact_storage_uri') {
      deprecatedArtifactStorageUri = _nextArg(
        args,
        i,
        '--artifact_storage_uri',
      ).trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--artifact_storage_uri=')) {
      deprecatedArtifactStorageUri = arg
          .substring('--artifact_storage_uri='.length)
          .trim();
      continue;
    }
    if (arg == '--url_prefix') {
      urlPrefix = _normalizeUrlPrefix(_nextArg(args, i, '--url_prefix'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--url_prefix=')) {
      urlPrefix = _normalizeUrlPrefix(arg.substring('--url_prefix='.length));
      continue;
    }
    if (arg == '--extra_plugins') {
      extraPlugins.add(_nextArg(args, i, '--extra_plugins').trim());
      i += 1;
      continue;
    }
    if (arg.startsWith('--extra_plugins=')) {
      extraPlugins.add(arg.substring('--extra_plugins='.length).trim());
      continue;
    }
    if (arg == '--logo_text') {
      logoText = _nextArg(args, i, '--logo_text').trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--logo_text=')) {
      logoText = arg.substring('--logo_text='.length).trim();
      continue;
    }
    if (arg == '--logo_image_url') {
      logoImageUrl = _nextArg(args, i, '--logo_image_url').trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--logo_image_url=')) {
      logoImageUrl = arg.substring('--logo_image_url='.length).trim();
      continue;
    }
    if (arg == '--use_local_storage') {
      useLocalStorage = true;
      continue;
    }
    if (arg == '--no-use_local_storage') {
      useLocalStorage = false;
      continue;
    }
    if (arg == '--trace_to_cloud') {
      traceToCloud = true;
      continue;
    }
    if (arg == '--otel_to_cloud') {
      otelToCloud = true;
      continue;
    }
    if (arg == '--reload') {
      reload = true;
      continue;
    }
    if (arg == '--no-reload') {
      reload = false;
      continue;
    }
    if (arg == '--a2a') {
      a2a = true;
      continue;
    }
    if (arg == '--reload_agents') {
      reloadAgents = true;
      continue;
    }
    if (arg == '--auto_create_session') {
      autoCreateSession = true;
      continue;
    }
    if (arg == '--eval_storage_uri') {
      _nextArg(args, i, '--eval_storage_uri');
      i += 1;
      continue;
    }
    if (arg.startsWith('--eval_storage_uri=')) {
      continue;
    }
    if (arg == '--log_level' || arg == '--verbosity') {
      _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=') || arg.startsWith('--verbosity=')) {
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for web: $arg');
    }
    if (seenProjectDir) {
      throw CliUsageError('web accepts only one project directory.');
    }
    projectDir = arg;
    seenProjectDir = true;
  }

  sessionServiceUri ??= deprecatedSessionDbUrl;
  artifactServiceUri ??= deprecatedArtifactStorageUri;

  return ParsedAdkCommand.web(
    projectDir: projectDir,
    port: port,
    host: host,
    userId: _emptyToNull(userId),
    allowOrigins: _normalizeCsvValues(allowOrigins),
    sessionServiceUri: _emptyToNull(sessionServiceUri),
    artifactServiceUri: _emptyToNull(artifactServiceUri),
    memoryServiceUri: _emptyToNull(memoryServiceUri),
    useLocalStorage: useLocalStorage,
    urlPrefix: _emptyToNull(urlPrefix),
    traceToCloud: traceToCloud,
    otelToCloud: otelToCloud,
    reload: reload,
    a2a: a2a,
    reloadAgents: reloadAgents,
    extraPlugins: _normalizeCsvValues(extraPlugins),
    logoText: _emptyToNull(logoText),
    logoImageUrl: _emptyToNull(logoImageUrl),
    autoCreateSession: autoCreateSession,
    enableWebUi: enableWebUi,
  );
}

String _nextArg(List<String> args, int index, String option) {
  if (index + 1 >= args.length) {
    throw CliUsageError('Missing value for $option.');
  }
  return args[index + 1];
}

String? _emptyToNull(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

int _parsePort(String rawPort) {
  final int? port = int.tryParse(rawPort);
  if (port == null || port < 0 || port > 65535) {
    throw CliUsageError('Invalid port: $rawPort');
  }
  return port;
}

InternetAddress _parseHost(String rawHost) {
  if (rawHost == 'localhost') {
    return InternetAddress.loopbackIPv4;
  }

  final InternetAddress? host = InternetAddress.tryParse(rawHost);
  if (host == null) {
    throw CliUsageError('Invalid host: $rawHost');
  }
  return host;
}

List<String> _normalizeCsvValues(List<String> values) {
  final List<String> expanded = <String>[];
  for (final String value in values) {
    final List<String> parts = value
        .split(',')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
    if (parts.isNotEmpty) {
      expanded.addAll(parts);
    }
  }
  return expanded;
}

String _normalizeUrlPrefix(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (!trimmed.startsWith('/')) {
    throw CliUsageError('url_prefix must start with "/": $trimmed');
  }
  if (trimmed.length > 1 && trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

Future<int> _runCreateCommand(ParsedAdkCommand command, IOSink out) async {
  await createDevProject(
    projectDirPath: command.projectDir,
    appName: command.appName,
  );
  out.writeln('Created ADK project at ${command.projectDir}');
  out.writeln('Next steps:');
  out.writeln('  cd ${command.projectDir}');
  out.writeln('  adk run .');
  out.writeln('  adk web --port 8000 .');
  return 0;
}

Future<int> _runRunCommand(ParsedAdkCommand command, IOSink out) async {
  final DevProjectConfig loadedConfig = await loadDevProjectConfig(
    command.projectDir,
  );
  final DevProjectConfig config = command.userId == null
      ? loadedConfig
      : loadedConfig.copyWith(userId: command.userId);
  final DevAgentRuntime runtime = DevAgentRuntime(config: config);

  final String userId = config.userId;

  if (command.replayFilePath != null) {
    final Session replaySession = await _runReplayFile(
      runtime: runtime,
      userId: userId,
      replayFilePath: command.replayFilePath!,
      out: out,
    );
    if (command.saveSession) {
      await _saveSessionSnapshot(
        runtime: runtime,
        session: replaySession,
        projectDir: command.projectDir,
        requestedSessionIdForSave: command.sessionId,
        out: out,
      );
    }
    await runtime.runner.close();
    return 0;
  }

  final Session session = await _prepareRunSession(
    runtime: runtime,
    userId: userId,
    requestedSessionId: command.sessionId,
    resumeFilePath: command.resumeFilePath,
  );

  if (command.message != null) {
    final List<Event> events = await runtime.sendMessage(
      userId: userId,
      sessionId: session.id,
      message: command.message!,
    );
    final List<String> replies = _agentTextReplies(
      events,
      agentName: runtime.config.agentName,
    );
    out.writeln(replies.isEmpty ? '(no response)' : replies.join('\n'));
    if (command.saveSession) {
      await _saveSessionSnapshot(
        runtime: runtime,
        session: session,
        projectDir: command.projectDir,
        requestedSessionIdForSave: command.sessionId,
        out: out,
      );
    }
    await runtime.runner.close();
    return 0;
  }

  out.writeln('ADK CLI chat started for app `${runtime.config.appName}`');
  out.writeln('Session: ${session.id}');
  out.writeln("Type 'exit' or 'quit' to stop.");

  while (true) {
    out.write('\nYou > ');
    await out.flush();

    final String? line = stdin.readLineSync();
    if (line == null) {
      break;
    }
    final String input = line.trim();
    if (input.isEmpty) {
      continue;
    }
    if (input == 'exit' || input == 'quit') {
      break;
    }

    final List<Event> events = await runtime.sendMessage(
      userId: userId,
      sessionId: session.id,
      message: input,
    );
    final List<String> replies = _agentTextReplies(
      events,
      agentName: runtime.config.agentName,
    );
    if (replies.isEmpty) {
      out.writeln('Agent > (no text response)');
      continue;
    }
    for (final String reply in replies) {
      out.writeln('Agent > $reply');
    }
  }

  if (command.saveSession) {
    await _saveSessionSnapshot(
      runtime: runtime,
      session: session,
      projectDir: command.projectDir,
      requestedSessionIdForSave: command.sessionId,
      out: out,
    );
  }

  await runtime.runner.close();
  return 0;
}

class _ReplayInput {
  _ReplayInput({required this.state, required this.queries});

  final Map<String, Object?> state;
  final List<String> queries;

  factory _ReplayInput.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> state = <String, Object?>{};
    final Object? rawState = json['state'];
    if (rawState is Map) {
      state.addAll(
        rawState.map((Object? key, Object? value) => MapEntry('$key', value)),
      );
    }

    final List<String> queries = <String>[];
    final Object? rawQueries = json['queries'];
    if (rawQueries is List) {
      for (final Object? query in rawQueries) {
        if (query == null) {
          continue;
        }
        final String text = '$query';
        if (text.trim().isEmpty) {
          continue;
        }
        queries.add(text);
      }
    }

    return _ReplayInput(state: state, queries: queries);
  }
}

Future<Session> _runReplayFile({
  required DevAgentRuntime runtime,
  required String userId,
  required String replayFilePath,
  required IOSink out,
}) async {
  final File replayFile = File(replayFilePath);
  if (!await replayFile.exists()) {
    throw FileSystemException('Replay file not found.', replayFile.path);
  }
  final Object? decoded = jsonDecode(await replayFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Invalid replay file: expected object.');
  }
  final Map<String, Object?> replayJson = decoded.map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );
  final _ReplayInput replayInput = _ReplayInput.fromJson(replayJson);
  replayInput.state['_time'] = DateTime.now().toIso8601String();

  final Session session = await runtime.createSessionWithState(
    userId: userId,
    state: replayInput.state,
  );

  for (final String query in replayInput.queries) {
    out.writeln('[user]: $query');
    final List<Event> events = await runtime.sendMessage(
      userId: userId,
      sessionId: session.id,
      message: query,
    );
    for (final Event event in events) {
      final Content? content = event.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }
      final String text = content.parts
          .where((Part part) => part.text != null && part.text!.isNotEmpty)
          .map((Part part) => part.text!)
          .join();
      if (text.isEmpty) {
        continue;
      }
      out.writeln('[${event.author}]: $text');
    }
  }

  return session;
}

Future<Session> _prepareRunSession({
  required DevAgentRuntime runtime,
  required String userId,
  required String? requestedSessionId,
  required String? resumeFilePath,
}) async {
  if (resumeFilePath == null) {
    return runtime.createSession(userId: userId, sessionId: requestedSessionId);
  }

  final Session loaded = await _loadSessionSnapshot(resumeFilePath);
  final Session session = await runtime.createSessionWithState(
    userId: userId,
    sessionId: requestedSessionId,
    state: loaded.events.isEmpty
        ? Map<String, Object?>.from(loaded.state)
        : null,
  );

  for (final Event event in loaded.events) {
    await runtime.runner.sessionService.appendEvent(
      session: session,
      event: event.copyWith(),
    );
  }

  return session;
}

Future<Session> _loadSessionSnapshot(String filePath) async {
  final File file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException('Resume file not found.', file.path);
  }

  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Invalid session snapshot: expected object.');
  }
  final Map<String, Object?> json = decoded.map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );

  final StorageSessionV0 storage = StorageSessionV0.fromJson(json);
  final List<Event> events = storage.storageEvents
      .map((StorageEventV0 item) => item.toEvent())
      .toList(growable: false);

  return storage.toSession(
    stateOverride: Map<String, Object?>.from(storage.state),
    events: events,
  );
}

Map<String, Object?> _sessionSnapshotJson(Session session) {
  final StorageSessionV0 storage = StorageSessionV0(
    appName: session.appName,
    userId: session.userId,
    id: session.id,
    state: Map<String, Object?>.from(session.state),
    storageEvents: session.events
        .map(
          (Event event) =>
              StorageEventV0.fromEvent(session: session, event: event),
        )
        .toList(growable: false),
  );
  return storage.toJson();
}

Future<void> _saveSessionSnapshot({
  required DevAgentRuntime runtime,
  required Session session,
  required String projectDir,
  required String? requestedSessionIdForSave,
  required IOSink out,
}) async {
  final Session? refreshed = await runtime.getSession(
    userId: session.userId,
    sessionId: session.id,
  );
  final Session target = refreshed ?? session;
  String? saveId = requestedSessionIdForSave?.trim();
  if (saveId == null || saveId.isEmpty) {
    out.write('Session ID to save: ');
    await out.flush();
    saveId = stdin.readLineSync()?.trim();
    if (saveId == null || saveId.isEmpty) {
      saveId = target.id;
    }
  }
  final File output = File(
    '${Directory(projectDir).absolute.path}${Platform.pathSeparator}$saveId.session.json',
  );
  final String payload = const JsonEncoder.withIndent(
    '  ',
  ).convert(_sessionSnapshotJson(target));
  await output.writeAsString(payload);
  out.writeln('Session saved to ${output.path}');
}

Future<int> _runWebCommand(
  ParsedAdkCommand command,
  IOSink out,
  IOSink err,
) async {
  final DevProjectConfig loadedConfig = await loadDevProjectConfig(
    command.projectDir,
  );
  final DevProjectConfig config = command.userId == null
      ? loadedConfig
      : loadedConfig.copyWith(userId: command.userId);
  final DevAgentRuntime runtime = DevAgentRuntime(config: config);

  final HttpServer server;
  try {
    server = await startAdkDevWebServer(
      runtime: runtime,
      project: config,
      agentsDir: command.projectDir,
      port: command.port!,
      host: command.host!,
      allowOrigins: command.allowOrigins,
      sessionServiceUri: command.sessionServiceUri,
      artifactServiceUri: command.artifactServiceUri,
      memoryServiceUri: command.memoryServiceUri,
      useLocalStorage: command.useLocalStorage,
      urlPrefix: command.urlPrefix,
      autoCreateSession: command.autoCreateSession,
      enableWebUi: command.enableWebUi,
      logoText: command.logoText,
      logoImageUrl: command.logoImageUrl,
      reload: command.reload,
      reloadAgents: command.reloadAgents,
      traceToCloud: command.traceToCloud,
      otelToCloud: command.otelToCloud,
      a2a: command.a2a,
      extraPlugins: command.extraPlugins,
      environment: Platform.environment,
    );
  } on SocketException catch (error) {
    err.writeln(
      'Failed to bind web server on ${command.host!.address}:${command.port}: $error',
    );
    await runtime.runner.close();
    return 1;
  }

  out.writeln(
    'ADK web server is running on '
    'http://${_displayHost(server.address)}:${server.port}${command.urlPrefix ?? ''}',
  );
  if (!command.enableWebUi) {
    out.writeln('UI is disabled for api_server mode.');
  }
  out.writeln('Press Ctrl+C to stop.');

  final List<StreamSubscription<ProcessSignal>> signalSubscriptions =
      <StreamSubscription<ProcessSignal>>[];
  final Completer<void> stopRequested = Completer<void>();

  final List<ProcessSignal> signals = <ProcessSignal>[
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ];

  for (final ProcessSignal signal in signals) {
    try {
      signalSubscriptions.add(
        signal.watch().listen((_) {
          if (!stopRequested.isCompleted) {
            stopRequested.complete();
          }
        }),
      );
    } on UnsupportedError {
      // Signal handling may not be available on all platforms.
    }
  }

  if (signalSubscriptions.isEmpty) {
    out.writeln('Signal handling unavailable. Press Enter to stop.');
    await stdin.first;
  } else {
    await stopRequested.future;
  }

  await server.close(force: true);
  for (final StreamSubscription<ProcessSignal> subscription
      in signalSubscriptions) {
    await subscription.cancel();
  }

  await runtime.runner.close();
  return 0;
}

List<String> _agentTextReplies(
  List<Event> events, {
  required String agentName,
}) {
  final List<String> replies = <String>[];
  for (final Event event in events) {
    if (event.author != agentName || event.content == null) {
      continue;
    }
    final String text = _textFromContent(event.content!);
    if (text.isNotEmpty) {
      replies.add(text);
    }
  }
  return replies;
}

String _textFromContent(Content content) {
  final List<String> chunks = <String>[];
  for (final Part part in content.parts) {
    if (part.text != null && part.text!.trim().isNotEmpty) {
      chunks.add(part.text!.trim());
    }
  }
  return chunks.join('\n');
}

String _displayHost(InternetAddress address) {
  if (address.type == InternetAddressType.IPv6) {
    return '[${address.address}]';
  }
  return address.address;
}
