/// Container-based code execution implementations.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/invocation_context.dart';
import 'base_code_executor.dart';
import 'code_execution_utils.dart';

/// Default image tag used by [ContainerCodeExecutor].
const String defaultContainerImageTag = 'adk-code-executor:latest';

/// Result of executing a command inside a container runtime.
class DockerExecResult {
  /// Creates a container exec result.
  DockerExecResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  /// Command exit code.
  final int exitCode;

  /// Captured stdout.
  final String stdout;

  /// Captured stderr.
  final String stderr;
}

/// Runtime abstraction for container lifecycle and exec operations.
abstract class ContainerRuntimeClient {
  /// Builds an image from [dockerPath] tagged as [imageTag].
  Future<void> buildImage({
    required String dockerPath,
    required String imageTag,
  });

  /// Starts a container and returns its container ID.
  Future<String> startContainer({required String imageTag});

  /// Executes [command] inside [containerId].
  Future<DockerExecResult> exec({
    required String containerId,
    required List<String> command,
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  });

  /// Stops [containerId].
  Future<void> stopContainer({required String containerId});

  /// Returns whether runtime tooling is available.
  Future<bool> isAvailable();
}

/// Process runner signature used by [ProcessContainerRuntimeClient].
typedef DockerProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Docker CLI-backed container runtime client.
class ProcessContainerRuntimeClient implements ContainerRuntimeClient {
  /// Creates a process-based container runtime client.
  ProcessContainerRuntimeClient({
    this.dockerBinary = 'docker',
    this.host,
    DockerProcessRunner? processRunner,
  }) : _processRunner =
           processRunner ??
           ((String executable, List<String> arguments) {
             return Process.run(executable, arguments);
           });

  /// Docker CLI binary used for runtime commands.
  final String dockerBinary;

  /// Optional Docker host passed as `-H`.
  final String? host;
  final DockerProcessRunner _processRunner;

  List<String> _withHost(List<String> args) {
    final String? hostValue = host;
    if (hostValue == null || hostValue.trim().isEmpty) {
      return List<String>.from(args);
    }
    return <String>['-H', hostValue, ...args];
  }

  @override
  Future<void> buildImage({
    required String dockerPath,
    required String imageTag,
  }) async {
    final List<String> args = _withHost(<String>[
      'build',
      '-t',
      imageTag,
      dockerPath,
    ]);
    final ProcessResult result = await _processRunner(dockerBinary, args);
    if (result.exitCode != 0) {
      throw ProcessException(
        dockerBinary,
        args,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  @override
  Future<String> startContainer({required String imageTag}) async {
    final List<String> args = _withHost(<String>[
      'run',
      '-d',
      '--rm',
      '-t',
      imageTag,
      'tail',
      '-f',
      '/dev/null',
    ]);
    final ProcessResult result = await _processRunner(dockerBinary, args);
    if (result.exitCode != 0) {
      throw ProcessException(
        dockerBinary,
        args,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }

    final String containerId = '${result.stdout}'.trim();
    if (containerId.isEmpty) {
      throw StateError('Container started but no container ID was returned.');
    }
    return containerId;
  }

  @override
  Future<DockerExecResult> exec({
    required String containerId,
    required List<String> command,
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final List<String> args = _withHost(<String>['exec']);
    if (workingDirectory != null && workingDirectory.isNotEmpty) {
      args
        ..add('-w')
        ..add(workingDirectory);
    }
    if (environment != null) {
      environment.forEach((String key, String value) {
        args
          ..add('-e')
          ..add('$key=$value');
      });
    }
    args
      ..add(containerId)
      ..addAll(command);

    final Future<ProcessResult> runFuture = _processRunner(dockerBinary, args);
    final ProcessResult result = timeout == null
        ? await runFuture
        : await runFuture.timeout(timeout);

    return DockerExecResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  @override
  Future<void> stopContainer({required String containerId}) async {
    await _processRunner(
      dockerBinary,
      _withHost(<String>['stop', containerId]),
    );
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final ProcessResult probe = await _processRunner(
        dockerBinary,
        _withHost(<String>['--version']),
      );
      return probe.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

/// Default input directory inside the container for staged input files.
const String defaultContainerInputDir = '/tmp/inputs';

/// Default output directory inside the container for execution working directory.
const String defaultContainerOutputDir = '/tmp/outputs';

/// Maximum total byte size (100 MiB) of collected output files.
const int maxContainerOutputTotalBytes = 100 * 1024 * 1024;

/// Container-backed code executor that runs snippets in Docker.
class ContainerCodeExecutor extends BaseCodeExecutor {
  /// Creates a container-backed code executor.
  ContainerCodeExecutor({
    this.baseUrl,
    String? image,
    this.dockerPath,
    this.inputDir = defaultContainerInputDir,
    this.outputDir = defaultContainerOutputDir,
    bool stateful = false,
    bool optimizeDataFile = false,
    super.errorRetryAttempts = 2,
    ContainerRuntimeClient? runtimeClient,
  }) : image = image ?? defaultContainerImageTag,
       _runtimeClient =
           runtimeClient ?? ProcessContainerRuntimeClient(host: baseUrl),
       super(stateful: stateful, optimizeDataFile: optimizeDataFile) {
    if ((image == null || image.trim().isEmpty) &&
        (dockerPath == null || dockerPath!.trim().isEmpty)) {
      throw ArgumentError(
        'Either image or dockerPath must be set for ContainerCodeExecutor.',
      );
    }
    if (stateful) {
      throw ArgumentError(
        'Cannot set `stateful=true` in ContainerCodeExecutor.',
      );
    }
    if (optimizeDataFile) {
      throw ArgumentError(
        'Cannot set `optimizeDataFile=true` in ContainerCodeExecutor.',
      );
    }
    final String normInput = _normalizePosixPath(inputDir);
    final String normOutput = _normalizePosixPath(outputDir);
    if (_pathsOverlapOrNested(normInput, normOutput)) {
      throw ArgumentError(
        'inputDir and outputDir must not be the same or nested in each other.',
      );
    }
  }

  /// Optional Docker host URL passed to the runtime client.
  final String? baseUrl;

  /// Docker image tag used for code execution.
  final String image;

  /// Optional Docker build context path for custom images.
  final String? dockerPath;

  /// Container directory where input files are staged before execution.
  final String inputDir;

  /// Container working directory where code executes and output files are collected.
  final String outputDir;
  final ContainerRuntimeClient _runtimeClient;

  String? _containerId;
  bool _imageBuilt = false;

  Future<void> _ensureContainerReady() async {
    if (_containerId != null && _containerId!.isNotEmpty) {
      return;
    }

    final bool dockerAvailable = await _runtimeClient.isAvailable();
    if (!dockerAvailable) {
      throw ProcessException(
        'docker',
        const <String>['--version'],
        'Docker is not available in this runtime.',
        127,
      );
    }

    if (!_imageBuilt && dockerPath != null && dockerPath!.trim().isNotEmpty) {
      final Directory dockerDirectory = Directory(dockerPath!);
      if (!await dockerDirectory.exists()) {
        throw FileSystemException(
          'Invalid Docker path: $dockerPath',
          dockerPath,
        );
      }
      await _runtimeClient.buildImage(dockerPath: dockerPath!, imageTag: image);
      _imageBuilt = true;
    }

    _containerId = await _runtimeClient.startContainer(imageTag: image);
    final DockerExecResult verify = await _runtimeClient.exec(
      containerId: _containerId!,
      command: const <String>['which', 'python3'],
      timeout: const Duration(seconds: 10),
    );
    if (verify.exitCode != 0) {
      await closeContainer();
      throw StateError('python3 is not installed in the container.');
    }
  }

  /// Stops and clears the currently running container, if present.
  Future<void> closeContainer() async {
    final String? containerId = _containerId;
    _containerId = null;
    if (containerId == null || containerId.isEmpty) {
      return;
    }
    await _runtimeClient.stopContainer(containerId: containerId);
  }

  /// Executes a raw command inside the container runtime.
  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    try {
      await _ensureContainerReady();
      final DockerExecResult result = await _runtimeClient.exec(
        containerId: _containerId!,
        command: <String>['python3', '-c', request.command],
        workingDirectory: request.workingDirectory,
        environment: request.environment,
        timeout: request.timeout ?? const Duration(minutes: 2),
      );

      return CodeExecutionResult(
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      );
    } on TimeoutException {
      return CodeExecutionResult(
        exitCode: -1,
        stderr: 'Docker code execution timed out.',
        timedOut: true,
      );
    } on ProcessException catch (error) {
      return CodeExecutionResult(
        exitCode: -1,
        stderr: 'Docker invocation failed: ${error.message}',
      );
    } on FileSystemException catch (error) {
      return CodeExecutionResult(exitCode: -1, stderr: error.message);
    } on StateError catch (error) {
      return CodeExecutionResult(exitCode: -1, stderr: '$error');
    }
  }

  /// Executes code with container input file staging and output file collection.
  @override
  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) async {
    final List<({String name, List<int> bytes})> stagedFiles;
    try {
      stagedFiles = _validateAndDecodeInputFiles(codeExecutionInput.inputFiles);
    } on ArgumentError catch (error) {
      return CodeExecutionResult(exitCode: -1, stderr: '$error');
    }

    await _ensureContainerReady();
    final String containerId = _containerId!;
    final String normInputDir = _normalizePosixPath(inputDir);
    final String normOutputDir = _normalizePosixPath(outputDir);

    await _prepareDirectories(containerId, normInputDir, normOutputDir);
    await _stageInputFiles(containerId, normInputDir, stagedFiles);

    final CodeExecutionResult execResult = await execute(
      CodeExecutionRequest(
        command: codeExecutionInput.code,
        workingDirectory: normOutputDir,
      ),
    );
    final List<CodeExecutionFile> collectedOutputs = await _collectOutputFiles(
      containerId,
      normOutputDir,
    );
    return CodeExecutionResult(
      exitCode: execResult.exitCode,
      stdout: execResult.stdout,
      stderr: execResult.stderr,
      timedOut: execResult.timedOut,
      outputFiles: collectedOutputs,
    );
  }

  Future<void> _prepareDirectories(
    String containerId,
    String normInputDir,
    String normOutputDir,
  ) async {
    final String qInput = _shellQuote(normInputDir);
    final String qOutput = _shellQuote(normOutputDir);
    final DockerExecResult result = await _runtimeClient.exec(
      containerId: containerId,
      command: <String>[
        'sh',
        '-c',
        'rm -rf $qInput $qOutput && mkdir -p $qInput $qOutput',
      ],
    );
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to prepare container directories $normInputDir and $normOutputDir: ${result.stderr}',
      );
    }
  }

  Future<void> _stageInputFiles(
    String containerId,
    String normInputDir,
    List<({String name, List<int> bytes})> stagedFiles,
  ) async {
    if (stagedFiles.isEmpty) {
      return;
    }
    for (final ({String name, List<int> bytes}) file in stagedFiles) {
      final String encoded = base64Encode(file.bytes);
      final String targetPath = _shellQuote('$normInputDir/${file.name}');
      final DockerExecResult result = await _runtimeClient.exec(
        containerId: containerId,
        command: <String>[
          'sh',
          '-c',
          "printf '%s' '$encoded' | base64 -d > $targetPath",
        ],
      );
      if (result.exitCode != 0) {
        throw StateError(
          'Failed to stage input file "${file.name}" into $normInputDir: ${result.stderr}',
        );
      }
    }
  }

  Future<List<CodeExecutionFile>> _collectOutputFiles(
    String containerId,
    String normOutputDir,
  ) async {
    final String qOutput = _shellQuote(normOutputDir);
    final String script =
        'import base64, json, os, sys; '
        'root = $qOutput; '
        'items = []; total = 0; limit = $maxContainerOutputTotalBytes; '
        'for dirpath, dirnames, filenames in os.walk(root, followlinks=False): '
        '  dirnames[:] = [d for d in sorted(dirnames) if not os.path.islink(os.path.join(dirpath, d))]; '
        '  for fn in sorted(filenames): '
        '    full = os.path.join(dirpath, fn); '
        '    if os.path.islink(full) or not os.path.isfile(full): continue; '
        '    sz = os.path.getsize(full); '
        '    total += sz; '
        '    if total > limit: sys.stderr.write("Total output files size exceeds limit"); sys.exit(67); '
        '    rel = os.path.relpath(full, root).replace("\\\\", "/"); '
        '    with open(full, "rb") as f: data = base64.b64encode(f.read()).decode("ascii"); '
        '    items.append({"name": rel, "size": sz, "content": data}); '
        'print(json.dumps(items))';
    final DockerExecResult result = await _runtimeClient.exec(
      containerId: containerId,
      command: <String>['sh', '-c', 'python3 -c ${_shellQuote(script)}'],
    );
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to collect output files from $normOutputDir: ${result.stderr}',
      );
    }

    final String trimmed = result.stdout.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('[')) {
      return <CodeExecutionFile>[];
    }

    final Object? decoded = jsonDecode(trimmed);
    if (decoded is! List) {
      return <CodeExecutionFile>[];
    }

    int totalBytes = 0;
    final List<CodeExecutionFile> files = <CodeExecutionFile>[];
    for (final Object? entry in decoded) {
      if (entry is! Map) {
        continue;
      }
      final String rawRel = '${entry['name'] ?? ''}'.replaceAll('\\', '/');
      final String relPath = rawRel
          .replaceFirst(RegExp(r'^(?:\./|/)+'), '')
          .trim();
      if (relPath.isEmpty || relPath == '.' || relPath == '..') {
        continue;
      }
      if (relPath.startsWith('user:')) {
        throw StateError(
          "Output file path '$relPath' starts with reserved prefix 'user:'.",
        );
      }

      final Object? rawContent = entry['content'];
      final List<int> fileBytes = rawContent == null
          ? const <int>[]
          : _toBytes(rawContent);
      final int declaredSize = entry['size'] is num
          ? (entry['size'] as num).toInt()
          : fileBytes.length;
      final int effectiveSize = declaredSize > fileBytes.length
          ? declaredSize
          : fileBytes.length;
      totalBytes += effectiveSize;
      if (totalBytes > maxContainerOutputTotalBytes) {
        throw StateError(
          'Total output files size ($totalBytes bytes) exceeds the '
          '${maxContainerOutputTotalBytes ~/ (1024 * 1024)} MiB limit.',
        );
      }

      final String? explicitMime = entry['mime_type'] as String?;
      files.add(
        CodeExecutionFile(
          name: relPath,
          content: base64Encode(fileBytes),
          mimeType: (explicitMime != null && explicitMime.isNotEmpty)
              ? explicitMime
              : _guessMimeType(relPath),
        ),
      );
    }
    return files;
  }
}

List<({String name, List<int> bytes})> _validateAndDecodeInputFiles(
  List<CodeExecutionFile> inputFiles,
) {
  final List<({String name, List<int> bytes})> staged =
      <({String name, List<int> bytes})>[];
  final Set<String> seenNames = <String>{};
  for (final CodeExecutionFile file in inputFiles) {
    final String fileName = _extractInputFileBasename(file.name);
    if (!seenNames.add(fileName)) {
      throw ArgumentError(
        'Duplicate input file name after path normalization: "$fileName".',
      );
    }
    staged.add((name: fileName, bytes: _toBytes(file.content)));
  }
  return staged;
}

List<int> _toBytes(Object value) {
  if (value is List<int>) {
    return value;
  }
  if (value is String) {
    final String normalized = value.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) {
      return const <int>[];
    }
    try {
      return base64Decode(normalized);
    } on FormatException {
      return utf8.encode(value);
    }
  }
  return utf8.encode('$value');
}

String _extractInputFileBasename(String rawName) {
  final String normalized = rawName.replaceAll('\\', '/').trim();
  if (normalized.isEmpty ||
      normalized.contains('\u0000') ||
      normalized.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:([/\\]|$)').hasMatch(normalized)) {
    throw ArgumentError('Invalid input file name: "$rawName".');
  }
  final List<String> segments = normalized.split('/');
  for (final String segment in segments) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      throw ArgumentError('Invalid input file name: "$rawName".');
    }
  }
  return segments.last;
}

String _normalizePosixPath(String rawPath) {
  final String trimmed = rawPath.trim().replaceAll('\\', '/');
  if (trimmed.isEmpty) {
    return '.';
  }
  final bool isAbsolute = trimmed.startsWith('/');
  final List<String> stack = <String>[];
  for (final String part in trimmed.split('/')) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (stack.isNotEmpty && stack.last != '..') {
        stack.removeLast();
      } else if (!isAbsolute) {
        stack.add('..');
      }
      continue;
    }
    stack.add(part);
  }
  final String joined = stack.join('/');
  if (isAbsolute) {
    return '/$joined';
  }
  return joined.isEmpty ? '.' : joined;
}

bool _pathsOverlapOrNested(String first, String second) {
  if (first == second) {
    return true;
  }
  if (first == '/' || second == '/') {
    return first.startsWith('/') && second.startsWith('/');
  }
  return first.startsWith('$second/') || second.startsWith('$first/');
}

String _shellQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

String _guessMimeType(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) {
    return 'application/octet-stream';
  }
  final String ext = fileName.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'txt':
    case 'log':
      return 'text/plain';
    case 'csv':
      return 'text/csv';
    case 'tsv':
      return 'text/tab-separated-values';
    case 'json':
      return 'application/json';
    case 'html':
    case 'htm':
      return 'text/html';
    case 'md':
    case 'markdown':
      return 'text/markdown';
    case 'xml':
      return 'application/xml';
    case 'yaml':
    case 'yml':
      return 'application/x-yaml';
    case 'py':
      return 'text/x-python';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'svg':
      return 'image/svg+xml';
    case 'webp':
      return 'image/webp';
    case 'pdf':
      return 'application/pdf';
    case 'zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}
