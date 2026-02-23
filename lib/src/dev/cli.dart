import 'dart:async';
import 'dart:io';

import '../events/event.dart';
import '../sessions/session.dart';
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
  -m, --message         Single message mode (no interactive prompt)

Web options:
  -p, --port            Port to bind (default: 8000)
      --host            Host to bind (default: 127.0.0.1)
      --user-id         User id used by default web session
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
      sessionId = null,
      message = null;

  ParsedAdkCommand.run({
    required this.projectDir,
    this.userId,
    this.sessionId,
    this.message,
  }) : type = AdkCommandType.run,
       appName = null,
       port = null,
       host = null;

  ParsedAdkCommand.web({
    required this.projectDir,
    required this.port,
    required this.host,
    this.userId,
  }) : type = AdkCommandType.web,
       appName = null,
       sessionId = null,
       message = null;

  final AdkCommandType type;
  final String projectDir;
  final String? appName;
  final int? port;
  final InternetAddress? host;
  final String? userId;
  final String? sessionId;
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
    case 'api_server':
      return _parseWebCommand(commandArgs);
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
  String? message;
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

    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for run: $arg');
    }

    if (seenProjectDir) {
      throw CliUsageError('run accepts only one project directory.');
    }
    projectDir = arg;
    seenProjectDir = true;
  }

  return ParsedAdkCommand.run(
    projectDir: projectDir,
    userId: _emptyToNull(userId),
    sessionId: _emptyToNull(sessionId),
    message: _emptyToNull(message),
  );
}

ParsedAdkCommand _parseWebCommand(List<String> args) {
  int port = 8000;
  InternetAddress host = InternetAddress.loopbackIPv4;
  String projectDir = '.';
  String? userId;
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
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for web: $arg');
    }
    if (seenProjectDir) {
      throw CliUsageError('web accepts only one project directory.');
    }
    projectDir = arg;
    seenProjectDir = true;
  }

  return ParsedAdkCommand.web(
    projectDir: projectDir,
    port: port,
    host: host,
    userId: _emptyToNull(userId),
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
  final Session session = await runtime.createSession(
    userId: userId,
    sessionId: command.sessionId,
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

  await runtime.runner.close();
  return 0;
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
      port: command.port!,
      host: command.host!,
    );
  } on SocketException catch (error) {
    err.writeln(
      'Failed to bind web server on ${command.host!.address}:${command.port}: $error',
    );
    await runtime.runner.close();
    return 1;
  }

  out.writeln(
    'ADK web server is running on http://${_displayHost(server.address)}:${server.port}',
  );
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
