part of 'web_server.dart';

/// Optional testing override for evaluating whether an HTTP request originates
/// from a local loopback client on Visual Agent Builder and Dev Test routes.
@visibleForTesting
bool Function(HttpRequest request)? isLocalAgentBuilderClientTestingOverride;

const Set<String> _yamlBuilderExtensions = <String>{'.yaml', '.yml'};
final RegExp _devValidIdentifierPattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

String _decodeRawSegmentOrThrow(String rawSegment) {
  try {
    return Uri.decodeComponent(rawSegment);
  } on ArgumentError {
    throw const FormatException('Malformed percent-encoding in URL path.');
  }
}

List<String> _rawNonEmptyPathSegments(String routedPath) {
  return routedPath
      .split('/')
      .where((String segment) => segment.isNotEmpty)
      .toList(growable: false);
}

bool _isDirectLoopbackClient(HttpRequest request, _AdkDevWebContext context) {
  if (isLocalAgentBuilderClientTestingOverride != null) {
    return isLocalAgentBuilderClientTestingOverride!(request);
  }
  for (final String header in const <String>[
    'forwarded',
    'x-forwarded-for',
    'x-forwarded-host',
  ]) {
    if (_firstHeaderValue(request, header) != null) {
      return false;
    }
  }
  if (context.serverHost != null && !_isLoopbackAddress(context.serverHost!)) {
    return false;
  }
  final HttpConnectionInfo? connInfo = request.connectionInfo;
  if (connInfo != null && !_isLoopbackAddress(connInfo.remoteAddress.address)) {
    return false;
  }
  return true;
}

Future<bool> _ensureLocalAgentBuilderClient(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final String? origin = _firstHeaderValue(request, 'origin');
  if (origin != null) {
    if (!_isRequestOriginAllowed(
      origin: origin,
      request: request,
      allowOrigins: context.allowOrigins,
      serverHost: context.serverHost,
    )) {
      await _writeText(
        request,
        context,
        statusCode: HttpStatus.forbidden,
        text: 'Forbidden: origin not allowed',
        includeCorsHeaders: false,
      );
      return false;
    }
    if (_requestHasForeignBrowserOrigin(request, context)) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.forbidden,
        message:
            "This endpoint writes agent files or starts runs, so it accepts "
            "browser requests only from this server's own origin or an origin "
            "listed literally in allow_origins.",
      );
      return false;
    }
  }

  final Map<String, String> effectiveEnv = <String, String>{
    ...Platform.environment,
    ...context.environment,
  };
  try {
    requireLocalAgentBuilderClient(
      isLocal: _isDirectLoopbackClient(request, context),
      environment: effectiveEnv,
    );
    return true;
  } on StateError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.forbidden,
      message: error.message,
    );
    return false;
  }
}

bool _isPathInsideRoot(String candidatePath, String rootPath) {
  final String normalizedRoot = Uri.directory(
    rootPath,
  ).toFilePath(windows: Platform.isWindows);
  final String normalizedCandidate = File(
    candidatePath,
  ).absolute.uri.toFilePath(windows: Platform.isWindows);
  final String rootNoTrailing = normalizedRoot.endsWith(Platform.pathSeparator)
      ? normalizedRoot.substring(
          0,
          normalizedRoot.length - Platform.pathSeparator.length,
        )
      : normalizedRoot;
  return normalizedCandidate == rootNoTrailing ||
      normalizedCandidate.startsWith(
        '$rootNoTrailing${Platform.pathSeparator}',
      );
}

Directory _resolveBuilderAppRoot(String agentsDir, String appName) {
  if (appName.isEmpty ||
      appName == '.' ||
      appName == '..' ||
      appName.contains('/') ||
      appName.contains('\\') ||
      appName.contains('\x00') ||
      appName.runes.any((int r) => r < 0x20 || r == 0x7f)) {
    throw ArgumentError('Invalid app name: $appName');
  }
  final Directory baseDir = Directory(agentsDir).absolute;
  final String resolvedBasePath = baseDir.existsSync()
      ? baseDir.resolveSymbolicLinksSync()
      : baseDir.path;
  final Directory candidate = Directory(
    '${baseDir.path}${Platform.pathSeparator}$appName',
  ).absolute;
  if (!_isPathInsideRoot(candidate.path, baseDir.path)) {
    throw ArgumentError('App path escapes base directory: $appName');
  }
  final FileSystemEntityType entityType = FileSystemEntity.typeSync(
    candidate.path,
    followLinks: false,
  );
  if (entityType == FileSystemEntityType.link) {
    final String resolvedTarget = candidate.resolveSymbolicLinksSync();
    if (!_isPathInsideRoot(resolvedTarget, resolvedBasePath)) {
      throw ArgumentError('App symlink escapes base directory: $appName');
    }
  }
  return candidate;
}

bool _hasBuilderYamlExtension(String path) {
  final int dotIndex = path.lastIndexOf('.');
  if (dotIndex <= 0) {
    return false;
  }
  final String ext = path.substring(dotIndex).toLowerCase();
  return _yamlBuilderExtensions.contains(ext);
}

String _parseBuilderQueryFilePath(String rawFilePath) {
  if (rawFilePath.contains('\x00') ||
      rawFilePath.runes.any((int r) => r < 0x20 || r == 0x7f)) {
    throw ArgumentError('Invalid characters in file path.');
  }
  String normalized = rawFilePath.replaceAll('\\', '/');
  while (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  if (normalized.isEmpty) {
    throw ArgumentError('Empty file path.');
  }
  final List<String> segments = normalized.split('/');
  for (final String seg in segments) {
    if (seg.isEmpty || seg == '.' || seg == '..') {
      throw ArgumentError('Invalid file path segment in "$rawFilePath".');
    }
  }
  if (!_hasBuilderYamlExtension(normalized)) {
    throw ArgumentError('Only .yaml and .yml files are supported.');
  }
  return segments.join(Platform.pathSeparator);
}

String _parseBuilderUploadRelPath(String appName, String rawFilename) {
  if (rawFilename.isEmpty ||
      rawFilename.contains('\x00') ||
      rawFilename.runes.any((int r) => r < 0x20 || r == 0x7f)) {
    throw ArgumentError('Invalid upload filename.');
  }
  final String unixPath = rawFilename.replaceAll('\\', '/');
  if (unixPath.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:').hasMatch(unixPath)) {
    throw ArgumentError('Absolute upload filenames are not allowed.');
  }
  final List<String> rawParts = unixPath.split('/');
  for (final String part in rawParts) {
    if (part.isEmpty || part == '.' || part == '..') {
      throw ArgumentError('Path traversal is not allowed in "$rawFilename".');
    }
  }
  final List<String> relParts =
      (rawParts.length >= 2 && rawParts.first == appName)
      ? rawParts.sublist(1)
      : rawParts;
  if (relParts.isEmpty || relParts.first == 'tmp') {
    throw ArgumentError('Invalid target path "$rawFilename".');
  }
  final String normalized = relParts.join('/');
  if (!_hasBuilderYamlExtension(normalized)) {
    throw ArgumentError(
      'Unsupported file extension for "$rawFilename"; only .yaml and .yml are allowed.',
    );
  }
  return relParts.join(Platform.pathSeparator);
}

File _resolveSafeFileUnderRoot(
  Directory rootDir,
  String relativeOSPath, {
  required bool forWrite,
}) {
  final Directory absRoot = rootDir.absolute;
  final String canonicalRoot = absRoot.existsSync()
      ? absRoot.resolveSymbolicLinksSync()
      : absRoot.path;
  final List<String> parts = relativeOSPath.split(Platform.pathSeparator);
  String currentPath = absRoot.path;
  for (int i = 0; i < parts.length; i++) {
    final String part = parts[i];
    if (part.isEmpty || part == '.' || part == '..') {
      throw ArgumentError('Invalid path segment "$part".');
    }
    currentPath = '$currentPath${Platform.pathSeparator}$part';
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      currentPath,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link) {
      if (forWrite) {
        throw ArgumentError('Refusing to write through symlink: $relativeOSPath');
      }
      final String resolvedTarget = (i == parts.length - 1)
          ? File(currentPath).resolveSymbolicLinksSync()
          : Directory(currentPath).resolveSymbolicLinksSync();
      if (!_isPathInsideRoot(resolvedTarget, canonicalRoot)) {
        throw ArgumentError('Symlink escapes root directory: $relativeOSPath');
      }
    } else if (type != FileSystemEntityType.notFound && i < parts.length - 1) {
      final String resolvedDir = Directory(
        currentPath,
      ).resolveSymbolicLinksSync();
      if (!_isPathInsideRoot(resolvedDir, canonicalRoot)) {
        throw ArgumentError('Directory escapes root: $relativeOSPath');
      }
    }
  }
  final File candidate = File(currentPath).absolute;
  if (!_isPathInsideRoot(candidate.path, absRoot.path)) {
    throw ArgumentError('Target path escapes root: $relativeOSPath');
  }
  return candidate;
}

void _copyDirContentsExcludingTmp(Directory source, Directory destination) {
  if (!source.existsSync()) {
    return;
  }
  final String canonicalSource = source.resolveSymbolicLinksSync();
  destination.createSync(recursive: true);
  final String canonicalDest = destination.resolveSymbolicLinksSync();

  void copyRecursive(Directory srcDir, Directory dstDir) {
    dstDir.createSync(recursive: true);
    for (final FileSystemEntity entity in srcDir.listSync(followLinks: false)) {
      final String name = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.lastWhere(
              (String s) => s.isNotEmpty,
              orElse: () => '',
            )
          : entity.path.split(Platform.pathSeparator).last;
      if (name.isEmpty) {
        continue;
      }
      if (identical(srcDir.path, source.path) && name == 'tmp') {
        continue;
      }
      if (srcDir.absolute.path == source.absolute.path && name == 'tmp') {
        continue;
      }
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        entity.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.link) {
        // Never copy symlinks that escape the source directory.
        try {
          final String resolved = entity.resolveSymbolicLinksSync();
          if (!_isPathInsideRoot(resolved, canonicalSource)) {
            continue;
          }
        } on FileSystemException {
          continue;
        }
        continue;
      }
      final String dstChildPath = '${dstDir.path}${Platform.pathSeparator}$name';
      if (FileSystemEntity.typeSync(dstChildPath, followLinks: false) ==
          FileSystemEntityType.link) {
        throw ArgumentError('Refusing to overwrite symlink at $dstChildPath');
      }
      if (entity is Directory) {
        final Directory dstSub = Directory(dstChildPath);
        copyRecursive(entity, dstSub);
      } else if (entity is File) {
        final File dstFile = File(dstChildPath);
        if (!_isPathInsideRoot(dstFile.absolute.path, canonicalDest) &&
            !_isPathInsideRoot(dstFile.absolute.path, destination.absolute.path)) {
          throw ArgumentError('Destination file escapes target directory.');
        }
        dstFile.parent.createSync(recursive: true);
        entity.copySync(dstFile.path);
      }
    }
  }

  copyRecursive(source, destination);
}

bool _ensureBuilderTmpExists(Directory appRoot, String appName) {
  if (!appRoot.existsSync()) {
    return false;
  }
  final Directory tmpAgentRoot = Directory(
    '${appRoot.path}${Platform.pathSeparator}tmp${Platform.pathSeparator}$appName',
  );
  if (tmpAgentRoot.existsSync()) {
    return true;
  }
  _copyDirContentsExcludingTmp(appRoot, tmpAgentRoot);
  return true;
}

bool _cleanupBuilderTmp(Directory appRoot, String appName) {
  final Directory baseTmp = Directory(
    '${appRoot.path}${Platform.pathSeparator}tmp',
  );
  final Directory tmpAgentRoot = Directory(
    '${baseTmp.path}${Platform.pathSeparator}$appName',
  );
  if (tmpAgentRoot.existsSync()) {
    tmpAgentRoot.deleteSync(recursive: true);
  }
  if (baseTmp.existsSync()) {
    try {
      if (baseTmp.listSync(followLinks: false).isEmpty) {
        baseTmp.deleteSync();
      }
    } on FileSystemException {
      // Ignore concurrent cleanup race.
    }
  }
  return true;
}

class _UploadedBuilderFile {
  const _UploadedBuilderFile({required this.filename, required this.bytes});

  final String filename;
  final List<int> bytes;
}

int _indexOfBytes(List<int> haystack, List<int> needle, [int start = 0]) {
  if (needle.isEmpty) {
    return start;
  }
  final int limit = haystack.length - needle.length;
  for (int i = start; i <= limit; i++) {
    bool match = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return i;
    }
  }
  return -1;
}

String? _extractMultipartBoundary(String contentTypeHeader) {
  final List<String> params = contentTypeHeader.split(';').skip(1).toList();
  for (final String rawParam in params) {
    final String trimmed = rawParam.trim();
    final int eq = trimmed.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    final String key = trimmed.substring(0, eq).trim().toLowerCase();
    if (key == 'boundary') {
      String value = trimmed.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

List<_UploadedBuilderFile> _parseMultipartBuilderFiles(
  List<int> bodyBytes,
  String boundary,
) {
  final List<int> dashBoundary = ascii.encode('--$boundary');
  final List<int> crlfCrlf = const <int>[13, 10, 13, 10];
  final List<int> lfLf = const <int>[10, 10];
  final List<_UploadedBuilderFile> uploads = <_UploadedBuilderFile>[];

  int pos = _indexOfBytes(bodyBytes, dashBoundary, 0);
  if (pos < 0) {
    throw const FormatException('Missing multipart boundary in request body.');
  }

  while (pos >= 0) {
    int partStart = pos + dashBoundary.length;
    if (partStart + 1 < bodyBytes.length &&
        bodyBytes[partStart] == 45 &&
        bodyBytes[partStart + 1] == 45) {
      // Closing `--boundary--`.
      break;
    }
    if (partStart + 1 < bodyBytes.length &&
        bodyBytes[partStart] == 13 &&
        bodyBytes[partStart + 1] == 10) {
      partStart += 2;
    } else if (partStart < bodyBytes.length && bodyBytes[partStart] == 10) {
      partStart += 1;
    }

    final int nextBoundary = _indexOfBytes(bodyBytes, dashBoundary, partStart);
    if (nextBoundary < 0) {
      break;
    }

    int partEnd = nextBoundary;
    if (partEnd >= 2 &&
        bodyBytes[partEnd - 2] == 13 &&
        bodyBytes[partEnd - 1] == 10) {
      partEnd -= 2;
    } else if (partEnd >= 1 && bodyBytes[partEnd - 1] == 10) {
      partEnd -= 1;
    }

    final List<int> partBytes = bodyBytes.sublist(partStart, partEnd);
    int headerEnd = _indexOfBytes(partBytes, crlfCrlf, 0);
    int contentStart = headerEnd + 4;
    if (headerEnd < 0) {
      headerEnd = _indexOfBytes(partBytes, lfLf, 0);
      contentStart = headerEnd + 2;
    }
    if (headerEnd >= 0) {
      final String headerBlock = utf8.decode(
        partBytes.sublist(0, headerEnd),
        allowMalformed: true,
      );
      final List<int> contentBytes = partBytes.sublist(contentStart);
      String? fieldName;
      String? filename;
      for (final String rawLine in const LineSplitter().convert(headerBlock)) {
        final int colon = rawLine.indexOf(':');
        if (colon <= 0) {
          continue;
        }
        final String hName = rawLine.substring(0, colon).trim().toLowerCase();
        final String hVal = rawLine.substring(colon + 1).trim();
        if (hName == 'content-disposition') {
          final RegExp paramRegex = RegExp(
            r'([a-zA-Z0-9_-]+)\s*=\s*(?:"([^"]*)"|([^;\s]+))',
          );
          for (final RegExpMatch match in paramRegex.allMatches(hVal)) {
            final String pKey = match.group(1)!.toLowerCase();
            final String pVal = match.group(2) ?? match.group(3) ?? '';
            if (pKey == 'name') {
              fieldName = pVal;
            } else if (pKey == 'filename') {
              filename = pVal;
            }
          }
        }
      }
      if ((fieldName == 'files' || fieldName == 'file' || filename != null) &&
          filename != null) {
        uploads.add(
          _UploadedBuilderFile(filename: filename, bytes: contentBytes),
        );
      }
    }

    pos = nextBoundary;
  }

  return uploads;
}

Future<List<_UploadedBuilderFile>> _readUploadedBuilderFiles(
  HttpRequest request,
) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in request) {
    builder.add(chunk);
  }
  final List<int> bodyBytes = builder.takeBytes();
  final String contentTypeHeader =
      request.headers.value(HttpHeaders.contentTypeHeader) ?? '';
  final String mediaType = contentTypeHeader
      .split(';')
      .first
      .trim()
      .toLowerCase();

  if (mediaType == 'multipart/form-data') {
    final String? boundary = _extractMultipartBoundary(contentTypeHeader);
    if (boundary == null) {
      throw const FormatException(
        'Missing boundary parameter in multipart/form-data Content-Type.',
      );
    }
    return _parseMultipartBuilderFiles(bodyBytes, boundary);
  }

  final String rawText = utf8.decode(bodyBytes);
  if (mediaType == 'application/json' ||
      (mediaType.isEmpty && rawText.trimLeft().startsWith('{'))) {
    final Object? decoded = jsonDecode(rawText);
    if (decoded is! Map) {
      throw const FormatException('Expected JSON object body.');
    }
    final Map<String, Object?> map = Map<String, Object?>.from(decoded);
    final Object? rawFiles = map['files'];
    if (rawFiles is List) {
      final List<_UploadedBuilderFile> result = <_UploadedBuilderFile>[];
      for (final Object? entry in rawFiles) {
        if (entry is! Map) {
          throw const FormatException('Each entry in "files" must be an object.');
        }
        final String? name =
            (entry['filename'] ?? entry['file_path'] ?? entry['path'])
                as String?;
        final Object? content = entry['content'] ?? entry['yaml'];
        if (name == null || content is! String) {
          throw const FormatException(
            'Each file object must include string "filename" and "content".',
          );
        }
        result.add(
          _UploadedBuilderFile(filename: name, bytes: utf8.encode(content)),
        );
      }
      return result;
    }
    if (rawFiles is Map) {
      final List<_UploadedBuilderFile> result = <_UploadedBuilderFile>[];
      for (final MapEntry<Object?, Object?> entry in rawFiles.entries) {
        if (entry.value is! String) {
          throw const FormatException('File map values must be YAML strings.');
        }
        result.add(
          _UploadedBuilderFile(
            filename: '${entry.key}',
            bytes: utf8.encode(entry.value as String),
          ),
        );
      }
      return result;
    }
    final Object? directContent = map['content'] ?? map['yaml'];
    if (directContent is String) {
      final String targetName =
          (map['file_path'] ??
                  map['filename'] ??
                  request.uri.queryParameters['file_path'] ??
                  'root_agent.yaml')
              .toString();
      return <_UploadedBuilderFile>[
        _UploadedBuilderFile(
          filename: targetName,
          bytes: utf8.encode(directContent),
        ),
      ];
    }
    throw const FormatException('No files found in JSON builder save payload.');
  }

  if (mediaType == 'application/x-yaml' ||
      mediaType == 'text/yaml' ||
      mediaType == 'application/yaml' ||
      mediaType == 'text/plain') {
    final String targetName =
        request.uri.queryParameters['file_path'] ?? 'root_agent.yaml';
    return <_UploadedBuilderFile>[
      _UploadedBuilderFile(filename: targetName, bytes: bodyBytes),
    ];
  }

  throw FormatException(
    'Unsupported Content-Type for builder save: "$contentTypeHeader".',
  );
}

void _validateUploadedBuilderYaml({
  required String appName,
  required String filename,
  required List<int> bytes,
}) {
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw ArgumentError('Invalid UTF-8 in uploaded YAML file $filename.');
  }

  final List<YamlDocument> docs;
  try {
    docs = loadYamlDocuments(text);
  } on YamlException catch (error) {
    throw ArgumentError('Invalid YAML in $filename: ${error.message}');
  }

  for (final YamlDocument doc in docs) {
    checkCodeReference(
      doc.contents.value,
      appName: appName,
      filename: filename,
    );
  }
}

Future<void> _writeYamlBuilderResponse(
  HttpRequest request,
  _AdkDevWebContext context, {
  required List<int> bytes,
  required bool isYamlContent,
}) async {
  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);
  response.statusCode = HttpStatus.ok;
  response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  response.headers.contentType = isYamlContent
      ? ContentType('application', 'x-yaml', charset: 'utf-8')
      : ContentType('text', 'plain', charset: 'utf-8');
  response.add(bytes);
  await response.close();
}

Future<bool> _handleBuilderRoutes(
  HttpRequest request,
  _AdkDevWebContext context,
  String routedPath,
) async {
  if (!context.enableWebUi) {
    return false;
  }

  final List<String> rawSegments = _rawNonEmptyPathSegments(routedPath);
  String? appName;
  List<String>? extraRawSegments;

  // Match `/dev/apps/{app_name}/builder[/...]`
  if (rawSegments.length >= 4 &&
      rawSegments[0] == 'dev' &&
      rawSegments[1] == 'apps' &&
      rawSegments[3] == 'builder') {
    appName = _decodeRawSegmentOrThrow(rawSegments[2]);
    extraRawSegments = rawSegments.sublist(4);
  }
  // Match legacy alias `/builder/app/{app_name}[/...]`
  else if (rawSegments.length >= 3 &&
      rawSegments[0] == 'builder' &&
      rawSegments[1] == 'app') {
    appName = _decodeRawSegmentOrThrow(rawSegments[2]);
    extraRawSegments = rawSegments.sublist(3);
  } else {
    return false;
  }

  final String method = request.method.toUpperCase();

  // POST .../builder/save
  if (method == 'POST' &&
      extraRawSegments.length == 1 &&
      extraRawSegments[0] == 'save') {
    if (!await _ensureLocalAgentBuilderClient(request, context)) {
      return true;
    }
    final bool tmp = _isTruthy(request.uri.queryParameters['tmp']);
    final Directory appRoot;
    try {
      appRoot = _resolveBuilderAppRoot(context.agentsDir, appName);
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    final List<_UploadedBuilderFile> uploads;
    try {
      uploads = await _readUploadedBuilderFiles(request);
    } on FormatException catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: error.message,
      );
      return true;
    }

    if (uploads.isEmpty) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: 'No files provided in builder save request.',
      );
      return true;
    }

    final List<(String relOSPath, List<int> bytes)> validatedFiles =
        <(String, List<int>)>[];
    try {
      for (final _UploadedBuilderFile upload in uploads) {
        final String relOSPath = _parseBuilderUploadRelPath(
          appName,
          upload.filename,
        );
        _validateUploadedBuilderYaml(
          appName: appName,
          filename: upload.filename,
          bytes: upload.bytes,
        );
        validatedFiles.add((relOSPath, upload.bytes));
      }
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    try {
      if (tmp) {
        final Directory tmpAgentRoot = Directory(
          '${appRoot.path}${Platform.pathSeparator}tmp${Platform.pathSeparator}$appName',
        );
        if (FileSystemEntity.typeSync(tmpAgentRoot.path, followLinks: false) ==
            FileSystemEntityType.link) {
          throw ArgumentError('Refusing to write into symlinked tmp directory.');
        }
        // Validate all target paths before writing any file.
        final List<(File target, List<int> bytes)> planned =
            <(File, List<int>)>[];
        for (final (String relOSPath, List<int> bytes) in validatedFiles) {
          final File dest = _resolveSafeFileUnderRoot(
            tmpAgentRoot,
            relOSPath,
            forWrite: true,
          );
          planned.add((dest, bytes));
        }
        tmpAgentRoot.createSync(recursive: true);
        for (final (File dest, List<int> bytes) in planned) {
          dest.parent.createSync(recursive: true);
          dest.writeAsBytesSync(bytes);
        }
      } else {
        appRoot.createSync(recursive: true);
        final List<(File target, List<int> bytes)> planned =
            <(File, List<int>)>[];
        for (final (String relOSPath, List<int> bytes) in validatedFiles) {
          final File dest = _resolveSafeFileUnderRoot(
            appRoot,
            relOSPath,
            forWrite: true,
          );
          planned.add((dest, bytes));
        }
        final Directory tmpAgentRoot = Directory(
          '${appRoot.path}${Platform.pathSeparator}tmp${Platform.pathSeparator}$appName',
        );
        if (tmpAgentRoot.existsSync()) {
          _copyDirContentsExcludingTmp(tmpAgentRoot, appRoot);
        }
        for (final (File dest, List<int> bytes) in planned) {
          dest.parent.createSync(recursive: true);
          dest.writeAsBytesSync(bytes);
        }
        _cleanupBuilderTmp(appRoot, appName);
        if (context.agentLoader is AgentLoader) {
          (context.agentLoader as AgentLoader).removeAgentFromCache(appName);
        }
        final Runner? staleRunner = context._runners.remove(appName);
        if (staleRunner != null) {
          await staleRunner.close();
        }
      }
      await _writeJson(request, context, payload: true);
      return true;
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    } on FileSystemException catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.internalServerError,
        message: 'Failed to save agent files: ${error.message}',
      );
      return true;
    }
  }

  // POST .../builder/cancel
  if (method == 'POST' &&
      extraRawSegments.length == 1 &&
      extraRawSegments[0] == 'cancel') {
    if (!await _ensureLocalAgentBuilderClient(request, context)) {
      return true;
    }
    try {
      final Directory appRoot = _resolveBuilderAppRoot(
        context.agentsDir,
        appName,
      );
      final bool cleaned = _cleanupBuilderTmp(appRoot, appName);
      await _writeJson(request, context, payload: cleaned);
    } on ArgumentError {
      await _writeJson(request, context, payload: false);
    }
    return true;
  }

  // GET .../builder or GET .../builder/{file_path:path}
  if (method == 'GET') {
    if (!await _ensureLocalAgentBuilderClient(request, context)) {
      return true;
    }
    final bool tmp = _isTruthy(request.uri.queryParameters['tmp']);
    final String? queryFilePath = request.uri.queryParameters['file_path'];
    String rawTargetPath;
    if (extraRawSegments.isNotEmpty) {
      final List<String> decodedParts = <String>[];
      try {
        for (final String seg in extraRawSegments) {
          final String decoded = _decodeRawSegmentOrThrow(seg);
          if (decoded.contains('/') ||
              decoded.contains('\\') ||
              decoded == '.' ||
              decoded == '..') {
            await _writeYamlBuilderResponse(
              request,
              context,
              bytes: const <int>[],
              isYamlContent: false,
            );
            return true;
          }
          decodedParts.add(decoded);
        }
      } on FormatException {
        await _writeYamlBuilderResponse(
          request,
          context,
          bytes: const <int>[],
          isYamlContent: false,
        );
        return true;
      }
      rawTargetPath = decodedParts.join('/');
    } else if (queryFilePath != null && queryFilePath.isNotEmpty) {
      rawTargetPath = queryFilePath;
    } else {
      rawTargetPath = 'root_agent.yaml';
    }

    try {
      final Directory appRoot = _resolveBuilderAppRoot(
        context.agentsDir,
        appName,
      );
      final String relOSPath = _parseBuilderQueryFilePath(rawTargetPath);
      final Directory targetRoot;
      if (tmp) {
        if (!_ensureBuilderTmpExists(appRoot, appName)) {
          await _writeYamlBuilderResponse(
            request,
            context,
            bytes: const <int>[],
            isYamlContent: false,
          );
          return true;
        }
        targetRoot = Directory(
          '${appRoot.path}${Platform.pathSeparator}tmp${Platform.pathSeparator}$appName',
        );
      } else {
        if (!appRoot.existsSync()) {
          await _writeYamlBuilderResponse(
            request,
            context,
            bytes: const <int>[],
            isYamlContent: false,
          );
          return true;
        }
        targetRoot = appRoot;
      }
      final File targetFile = _resolveSafeFileUnderRoot(
        targetRoot,
        relOSPath,
        forWrite: false,
      );
      if (!targetFile.existsSync()) {
        await _writeYamlBuilderResponse(
          request,
          context,
          bytes: const <int>[],
          isYamlContent: false,
        );
        return true;
      }
      await _writeYamlBuilderResponse(
        request,
        context,
        bytes: targetFile.readAsBytesSync(),
        isYamlContent: true,
      );
      return true;
    } on ArgumentError {
      await _writeYamlBuilderResponse(
        request,
        context,
        bytes: const <int>[],
        isYamlContent: false,
      );
      return true;
    }
  }

  return false;
}

Directory _getDevTestAgentDir(_AdkDevWebContext context, String appName) {
  if (appName.isEmpty ||
      appName.contains('/') ||
      appName.contains('\\') ||
      appName.contains('\x00')) {
    throw ArgumentError('Invalid app name.');
  }
  final List<String> parts = appName.split('.');
  if (parts.any((String p) => !_devValidIdentifierPattern.hasMatch(p))) {
    throw ArgumentError('Invalid app name.');
  }
  final Directory baseDir = Directory(context.agentsDir).absolute;
  final String resolvedBase = baseDir.existsSync()
      ? baseDir.resolveSymbolicLinksSync()
      : baseDir.path;
  final Directory agentDir = Directory(
    '${baseDir.path}${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}',
  ).absolute;
  if (!_isPathInsideRoot(agentDir.path, baseDir.path)) {
    throw ArgumentError('Invalid app path.');
  }
  if (agentDir.existsSync()) {
    final String resolvedAgent = agentDir.resolveSymbolicLinksSync();
    if (!_isPathInsideRoot(resolvedAgent, resolvedBase)) {
      throw ArgumentError('Invalid app path.');
    }
  }
  return agentDir;
}

File _getDevTestFilePath({
  required Directory agentDir,
  required String testName,
  bool forWrite = false,
}) {
  if (testName.isEmpty ||
      testName == '.' ||
      testName == '..' ||
      testName.contains('/') ||
      testName.contains('\\') ||
      testName.contains('\x00')) {
    throw ArgumentError('Invalid test name.');
  }
  final String normalizedName = testName.endsWith('.json')
      ? testName
      : '$testName.json';
  if (normalizedName == '.json' ||
      normalizedName == '..json' ||
      normalizedName == '...json') {
    throw ArgumentError('Invalid test name.');
  }

  final Directory testsDir = Directory(
    '${agentDir.path}${Platform.pathSeparator}tests',
  ).absolute;
  if (FileSystemEntity.typeSync(testsDir.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw ArgumentError('Tests directory must not be a symlink.');
  }
  final String canonicalTestsDir = testsDir.existsSync()
      ? testsDir.resolveSymbolicLinksSync()
      : testsDir.path;

  final File candidate = File(
    '${testsDir.path}${Platform.pathSeparator}$normalizedName',
  ).absolute;
  if (!_isPathInsideRoot(candidate.path, testsDir.path)) {
    throw ArgumentError('Invalid test path.');
  }
  final FileSystemEntityType candidateType = FileSystemEntity.typeSync(
    candidate.path,
    followLinks: false,
  );
  if (candidateType == FileSystemEntityType.link) {
    throw ArgumentError('Invalid test path.');
  }
  if (!forWrite && candidate.existsSync()) {
    final String resolvedCandidate = candidate.resolveSymbolicLinksSync();
    if (!_isPathInsideRoot(resolvedCandidate, canonicalTestsDir)) {
      throw ArgumentError('Invalid test path.');
    }
  }
  return candidate;
}

Object? _sortJsonKeysRecursively(Object? value) {
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? k) => '$k').toList()
      ..sort();
    final Map<String, Object?> sorted = <String, Object?>{};
    for (final String key in keys) {
      sorted[key] = _sortJsonKeysRecursively(value[key]);
    }
    return sorted;
  }
  if (value is List) {
    return value.map(_sortJsonKeysRecursively).toList(growable: false);
  }
  return value;
}

Object _loadAgentOrAppForTests(_AdkDevWebContext context, String appName) {
  try {
    return context.agentLoader.loadAgent(appName);
  } on Object {
    if (appName == context.defaultAppName) {
      return context.runtime.runner.agent;
    }
    rethrow;
  }
}

Future<bool> _handleDevReplayTestsRoutes(
  HttpRequest request,
  _AdkDevWebContext context,
  String routedPath,
) async {
  if (!context.enableWebUi) {
    return false;
  }

  final List<String> rawSegments = _rawNonEmptyPathSegments(routedPath);
  if (rawSegments.length < 4 ||
      rawSegments[0] != 'dev' ||
      rawSegments[1] != 'apps' ||
      rawSegments[3] != 'tests') {
    return false;
  }
  if (rawSegments.length > 5) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Invalid test path.',
    );
    return true;
  }

  final String appName = _decodeRawSegmentOrThrow(rawSegments[2]);
  final String method = request.method.toUpperCase();

  // GET /dev/apps/{app_name}/tests
  if (rawSegments.length == 4 && method == 'GET') {
    final Directory agentDir;
    try {
      agentDir = _getDevTestAgentDir(context, appName);
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    final Directory testsDir = Directory(
      '${agentDir.path}${Platform.pathSeparator}tests',
    );
    if (!testsDir.existsSync()) {
      await _writeJson(request, context, payload: const <String>[]);
      return true;
    }
    final List<String> names = <String>[];
    for (final FileSystemEntity entity in testsDir.listSync(
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.json')) {
        names.add(entity.uri.pathSegments.last);
      }
    }
    names.sort();
    await _writeJson(request, context, payload: names);
    return true;
  }

  if (rawSegments.length != 5) {
    return false;
  }

  final String tailSegment = _decodeRawSegmentOrThrow(rawSegments[4]);

  // POST /dev/apps/{app_name}/tests/rebuild
  if (tailSegment == 'rebuild' && method == 'POST') {
    if (!await _ensureLocalAgentBuilderClient(request, context)) {
      return true;
    }
    final Directory agentDir;
    File? targetTestFile;
    try {
      agentDir = _getDevTestAgentDir(context, appName);
      String? testName = request.uri.queryParameters['test_name'];
      if ((testName == null || testName.isEmpty) &&
          request.contentLength != 0) {
        final Map<String, dynamic> body = await _readJsonBody(request);
        final Object? bodyTestName = body['test_name'] ?? body['testName'];
        if (bodyTestName is String && bodyTestName.isNotEmpty) {
          testName = bodyTestName;
        }
      }
      if (testName != null && testName.isNotEmpty) {
        targetTestFile = _getDevTestFilePath(
          agentDir: agentDir,
          testName: testName,
        );
      }
    } on FormatException catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: error.message,
      );
      return true;
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    try {
      if (context.agentLoader is AgentLoader) {
        (context.agentLoader as AgentLoader).removeAgentFromCache(appName);
      }
      final Object loaded = _loadAgentOrAppForTests(context, appName);
      await rebuildTests(
        agentDir: agentDir.path,
        testFilePath: targetTestFile?.path,
        appName: appName,
        app: loaded is App ? loaded : null,
        rootAgent: loaded is App ? null : loaded,
      );
      await _writeJson(
        request,
        context,
        payload: const <String, Object?>{'status': 'success'},
      );
      return true;
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: '${error.message}',
      );
      return true;
    } on StateError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: error.message,
      );
      return true;
    } catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.internalServerError,
        message: 'Failed to rebuild tests: $error',
      );
      return true;
    }
  }

  // POST /dev/apps/{app_name}/tests/run
  if (tailSegment == 'run' && method == 'POST') {
    if (!await _ensureLocalAgentBuilderClient(request, context)) {
      return true;
    }
    final Directory agentDir;
    File? targetTestFile;
    try {
      agentDir = _getDevTestAgentDir(context, appName);
      final String? testName = request.uri.queryParameters['test_name'];
      if (testName != null && testName.isNotEmpty) {
        targetTestFile = _getDevTestFilePath(
          agentDir: agentDir,
          testName: testName,
        );
      }
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    final HttpResponse response = request.response;
    _setCorsHeaders(request, response, context);
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType(
      'text',
      'plain',
      charset: 'utf-8',
    );
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    response.headers.set('x-accel-buffering', 'no');
    response.bufferOutput = false;

    try {
      if (devTestRunnerProcessStarterTestingOverride != null) {
        final Process process =
            await devTestRunnerProcessStarterTestingOverride!(
              agentDir: agentDir.path,
              testFilePath: targetTestFile?.path,
            );
        await for (final String line in streamTestOutput(process)) {
          response.write(line);
          await response.flush();
        }
        await process.exitCode;
        await response.close();
        return true;
      }

      if (targetTestFile != null && !targetTestFile.existsSync()) {
        response.write(
          'ERROR: Test file not found: ${targetTestFile.uri.pathSegments.last}\n',
        );
        response.write('=== 0 passed, 1 failed ===\n');
        await response.flush();
        await response.close();
        return true;
      }

      final List<File> testFiles = targetTestFile != null
          ? <File>[targetTestFile]
          : getTestFiles(agentDir.path);
      if (testFiles.isEmpty) {
        response.write('No test files found for $appName.\n');
        response.write('=== 0 passed, 0 failed ===\n');
        await response.flush();
        await response.close();
        return true;
      }

      if (context.agentLoader is AgentLoader) {
        (context.agentLoader as AgentLoader).removeAgentFromCache(appName);
      }
      final Object loaded = _loadAgentOrAppForTests(context, appName);
      int passed = 0;
      int failed = 0;
      for (final File testFile in testFiles) {
        final String label = testFile.uri.pathSegments.last;
        response.write('Running $label...\n');
        await response.flush();
        try {
          await runAgentReplayTest(
            testFile: testFile,
            appName: appName,
            app: loaded is App ? loaded : null,
            rootAgent: loaded is App ? null : loaded,
            useMockModelWhenUnconfigured: true,
            environment: context.environment,
          );
          passed += 1;
          response.write('PASSED $label\n');
        } catch (error) {
          failed += 1;
          response.write('FAILED $label: $error\n');
        }
        await response.flush();
      }
      response.write('=== $passed passed, $failed failed ===\n');
      await response.flush();
    } catch (error) {
      response.write('\nError executing tests: $error\n');
      await response.flush();
    } finally {
      await response.close();
    }
    return true;
  }

  // GET /dev/apps/{app_name}/tests/{test_name}
  if (method == 'GET') {
    final File testFile;
    try {
      final Directory agentDir = _getDevTestAgentDir(context, appName);
      testFile = _getDevTestFilePath(agentDir: agentDir, testName: tailSegment);
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    if (!testFile.existsSync()) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: 'Test file not found',
      );
      return true;
    }

    final Object? decoded = jsonDecode(await testFile.readAsString());
    await _writeJson(
      request,
      context,
      payload: decoded ?? const <String, Object?>{},
    );
    return true;
  }

  // PUT /dev/apps/{app_name}/tests/{test_name}
  if (method == 'PUT') {
    if (!await _ensureLocalAgentBuilderClient(request, context)) {
      return true;
    }
    final File testFile;
    try {
      final Directory agentDir = _getDevTestAgentDir(context, appName);
      testFile = _getDevTestFilePath(
        agentDir: agentDir,
        testName: tailSegment,
        forWrite: true,
      );
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    final Map<String, Object?> body;
    try {
      final Map<String, dynamic> rawBody = await _readJsonBody(request);
      body = rawBody.map((String k, dynamic v) => MapEntry(k, v));
    } on FormatException catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: error.message,
      );
      return true;
    }

    final CreateTestRequest createReq = CreateTestRequest.fromJson(body);
    Map<String, Object?>? sessionPayload = createReq.sessionData;
    if (sessionPayload == null &&
        createReq.sessionId.isNotEmpty &&
        createReq.userId.isNotEmpty) {
      final Session? existingSession = await context.sessionService.getSession(
        appName: appName,
        userId: createReq.userId,
        sessionId: createReq.sessionId,
      );
      if (existingSession == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.notFound,
          message: 'Session not found: ${createReq.sessionId}',
        );
        return true;
      }
      sessionPayload = _sessionToApiJson(existingSession, includeEvents: true);
    }

    if (sessionPayload == null) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.unprocessableEntity,
        message:
            'CreateTestRequest requires "session_data" or both "session_id" and "user_id".',
      );
      return true;
    }

    try {
      testFile.parent.createSync(recursive: true);
      if (FileSystemEntity.typeSync(testFile.path, followLinks: false) ==
          FileSystemEntityType.link) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.badRequest,
          message: 'Invalid test path.',
        );
        return true;
      }
      final Object? sorted = _sortJsonKeysRecursively(sessionPayload);
      final String formatted =
          '${const JsonEncoder.withIndent('  ').convert(sorted)}\n';
      await testFile.writeAsString(formatted);
      await _writeJson(
        request,
        context,
        payload: <String, Object?>{
          'status': 'success',
          'file': testFile.uri.pathSegments.last,
        },
      );
      return true;
    } on FileSystemException catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.internalServerError,
        message: 'Failed to save test file: ${error.message}',
      );
      return true;
    }
  }

  // DELETE /dev/apps/{app_name}/tests/{test_name}
  if (method == 'DELETE') {
    if (!await _ensureLocalAgentBuilderClient(request, context)) {
      return true;
    }
    final File testFile;
    try {
      final Directory agentDir = _getDevTestAgentDir(context, appName);
      testFile = _getDevTestFilePath(agentDir: agentDir, testName: tailSegment);
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    if (!testFile.existsSync()) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: 'Test file not found',
      );
      return true;
    }

    await testFile.delete();
    await _writeJson(
      request,
      context,
      payload: const <String, Object?>{'status': 'success'},
    );
    return true;
  }

  return false;
}

class _ReasoningEngineInputError implements Exception {
  const _ReasoningEngineInputError(this.message, {this.statusCode = 422});

  final String message;
  final int statusCode;
}

String _requireReasoningEngineString(
  Map<String, Object?> input,
  List<String> keys, {
  required String fieldLabel,
}) {
  for (final String key in keys) {
    if (!input.containsKey(key)) {
      continue;
    }
    final Object? val = input[key];
    if (val is String && val.trim().isNotEmpty) {
      return val.trim();
    }
    throw _ReasoningEngineInputError(
      'Invalid or empty "$fieldLabel" parameter.',
    );
  }
  throw _ReasoningEngineInputError('Missing required "$fieldLabel" parameter.');
}

String? _optionalReasoningEngineString(
  Map<String, Object?> input,
  List<String> keys, {
  required String fieldLabel,
}) {
  for (final String key in keys) {
    if (!input.containsKey(key) || input[key] == null) {
      continue;
    }
    final Object? val = input[key];
    if (val is String) {
      final String trimmed = val.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    throw _ReasoningEngineInputError('Parameter "$fieldLabel" must be a string.');
  }
  return null;
}

Content _parseReasoningEngineMessage(Map<String, Object?> input) {
  if (!input.containsKey('message') && !input.containsKey('new_message')) {
    throw const _ReasoningEngineInputError(
      'Missing required "message" parameter.',
    );
  }
  final Object? raw = input['message'] ?? input['new_message'];
  if (raw is String) {
    if (raw.trim().isEmpty) {
      throw const _ReasoningEngineInputError(
        'Parameter "message" must not be empty.',
      );
    }
    return Content.userText(raw);
  }
  if (raw is Map) {
    return _contentFromJson(_toDynamicMap(raw));
  }
  throw const _ReasoningEngineInputError(
    'Parameter "message" must be a string or Content object.',
  );
}

String _resolveReasoningEngineAppName(
  _AdkDevWebContext context,
  Map<String, Object?> input,
) {
  final String? enterprise = context.geminiEnterpriseAppName?.trim();
  if (enterprise != null && enterprise.isNotEmpty) {
    return enterprise;
  }
  final Object? fromInput = input['app_name'] ?? input['appName'];
  if (fromInput is String && fromInput.trim().isNotEmpty) {
    return fromInput.trim();
  }
  return context.defaultAppName;
}

Future<Session> _resolveOrCreateReasoningEngineSession({
  required _AdkDevWebContext context,
  required String appName,
  required String userId,
  required String? sessionId,
  required Object? rawSessionEvents,
}) async {
  if (sessionId != null && rawSessionEvents != null) {
    throw const _ReasoningEngineInputError(
      'Cannot specify both "session_id" and "session_events".',
      statusCode: HttpStatus.badRequest,
    );
  }
  if (rawSessionEvents != null && rawSessionEvents is! List) {
    throw const _ReasoningEngineInputError(
      'Parameter "session_events" must be a list of events.',
    );
  }

  if (sessionId != null) {
    final Session? existing = await context.sessionService.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
    if (existing != null) {
      return existing;
    }
    return context.sessionService.createSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  final Session created = await context.sessionService.createSession(
    appName: appName,
    userId: userId,
  );
  if (rawSessionEvents is List && rawSessionEvents.isNotEmpty) {
    final List<Event> initialEvents = _readEventsFromPayload(
      <String, dynamic>{'events': rawSessionEvents},
      appName: appName,
      userId: userId,
      sessionId: created.id,
    );
    for (final Event event in initialEvents) {
      await context.sessionService.appendEvent(session: created, event: event);
    }
  }
  return created;
}

Future<ReasoningEngineQueryRequest?> _parseAndValidateReasoningEngineRequest(
  HttpRequest request,
  _AdkDevWebContext context, {
  required bool expectStreaming,
}) async {
  final String rawBody = await utf8.decoder.bind(request).join();
  if (rawBody.trim().isEmpty) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Request body must not be empty.',
    );
    return null;
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(rawBody);
  } on FormatException catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Invalid JSON: ${error.message}',
    );
    return null;
  }

  if (decoded is! Map) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Request body must be a JSON object.',
    );
    return null;
  }

  final ReasoningEngineQueryRequest parsed;
  try {
    parsed = ReasoningEngineQueryRequest.fromJson(
      Map<String, Object?>.from(decoded),
    );
  } on FormatException catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: error.message,
    );
    return null;
  }

  final bool? isStreamingMethod =
      allowedAgentEngineClassMethods[parsed.classMethod];
  if (isStreamingMethod == null || isStreamingMethod != expectStreaming) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'class_method ${parsed.classMethod} is not allowed',
    );
    return null;
  }

  return parsed;
}

Future<void> _handleReasoningEngine(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final ReasoningEngineQueryRequest? queryReq =
      await _parseAndValidateReasoningEngineRequest(
        request,
        context,
        expectStreaming: false,
      );
  if (queryReq == null) {
    return;
  }

  final Map<String, Object?> input = queryReq.input;
  final String targetApp = _resolveReasoningEngineAppName(context, input);

  try {
    switch (queryReq.classMethod) {
      case 'create_session':
      case 'async_create_session':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final Object? rawState = input['state'];
        if (rawState != null && rawState is! Map) {
          throw const _ReasoningEngineInputError(
            'Parameter "state" must be a JSON object.',
          );
        }
        final Session created = await context.sessionService.createSession(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          state: rawState == null
              ? null
              : Map<String, Object?>.from(rawState as Map),
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': _sessionToApiJson(created, includeEvents: true),
          },
        );
        return;

      case 'list_sessions':
      case 'async_list_sessions':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final ListSessionsResponse listed = await context.sessionService
            .listSessions(appName: targetApp, userId: userId);
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': <String, Object?>{
              'sessions': listed.sessions
                  .map(
                    (Session s) => _sessionToApiJson(s, includeEvents: false),
                  )
                  .toList(growable: false),
            },
          },
        );
        return;

      case 'get_session':
      case 'async_get_session':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String sessionId = _requireReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final Session? session = await context.sessionService.getSession(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': session == null
                ? null
                : _sessionToApiJson(session, includeEvents: true),
          },
        );
        return;

      case 'delete_session':
      case 'async_delete_session':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String sessionId = _requireReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        await context.sessionService.deleteSession(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
        );
        await _writeJson(
          request,
          context,
          payload: const <String, Object?>{'output': null},
        );
        return;

      case 'query':
      case 'async_query':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final Content newMessage = _parseReasoningEngineMessage(input);
        final Object? rawStateDelta = input['state_delta'] ?? input['stateDelta'];
        if (rawStateDelta != null && rawStateDelta is! Map) {
          throw const _ReasoningEngineInputError(
            'Parameter "state_delta" must be a JSON object.',
          );
        }
        final Runner runner = await context.getRunner(
          targetApp,
          request: request,
        );
        final Session session = await _resolveOrCreateReasoningEngineSession(
          context: context,
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          rawSessionEvents: input['session_events'] ?? input['sessionEvents'],
        );
        final List<Map<String, Object?>> serializedEvents =
            <Map<String, Object?>>[];
        await for (final Event event in runner.runAsync(
          userId: userId,
          sessionId: session.id,
          newMessage: newMessage,
          stateDelta: rawStateDelta is Map
              ? Map<String, Object?>.from(rawStateDelta)
              : null,
        )) {
          serializedEvents.add(
            _eventToApiJson(
              event,
              appName: targetApp,
              userId: userId,
              sessionId: session.id,
            ),
          );
        }
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{'output': serializedEvents},
        );
        return;

      case 'async_add_session_to_memory':
        final Object? rawSession = input['session'];
        Session? resolvedSession;
        if (rawSession is Map) {
          final Map<String, dynamic> map = _toDynamicMap(rawSession);
          final String sid = '${map['id'] ?? map['session_id'] ?? ''}';
          final String uid = '${map['user_id'] ?? map['userId'] ?? ''}';
          if (sid.isEmpty || uid.isEmpty) {
            throw const _ReasoningEngineInputError(
              'Session map must include "id" and "user_id".',
            );
          }
          resolvedSession = Session(
            id: sid,
            appName: '${map['app_name'] ?? map['appName'] ?? targetApp}',
            userId: uid,
            state: map['state'] is Map
                ? Map<String, Object?>.from(map['state'] as Map)
                : <String, Object?>{},
            events: _readEventsFromPayload(
              map,
              appName: targetApp,
              userId: uid,
              sessionId: sid,
            ),
          );
        } else {
          final String userId = _requireReasoningEngineString(
            input,
            const <String>['user_id', 'userId'],
            fieldLabel: 'user_id',
          );
          final String sessionId = _requireReasoningEngineString(
            input,
            const <String>['session_id', 'sessionId'],
            fieldLabel: 'session_id',
          );
          resolvedSession = await context.sessionService.getSession(
            appName: targetApp,
            userId: userId,
            sessionId: sessionId,
          );
        }
        if (resolvedSession == null) {
          throw const _ReasoningEngineInputError('Session not found.');
        }
        await context.memoryService.addSessionToMemory(resolvedSession);
        await _writeJson(
          request,
          context,
          payload: const <String, Object?>{'output': null},
        );
        return;

      case 'async_search_memory':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String query = _requireReasoningEngineString(
          input,
          const <String>['query'],
          fieldLabel: 'query',
        );
        final SearchMemoryResponse searchRes = await context.memoryService
            .searchMemory(appName: targetApp, userId: userId, query: query);
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': <String, Object?>{
              'memories': searchRes.memories
                  .map(
                    (MemoryEntry entry) => <String, Object?>{
                      'content': _contentToLegacyJson(entry.content),
                      if (entry.author != null) 'author': entry.author,
                      if (entry.timestamp != null) 'timestamp': entry.timestamp,
                      'custom_metadata': entry.customMetadata,
                    },
                  )
                  .toList(growable: false),
            },
          },
        );
        return;

      case 'async_save_artifact':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        final Object? rawArtifact = input['artifact'];
        if (rawArtifact is! Map) {
          throw const _ReasoningEngineInputError(
            'Parameter "artifact" must be a Part JSON object.',
          );
        }
        final Part artifactPart = _partFromJson(_toDynamicMap(rawArtifact));
        final int version = await context.artifactService.saveArtifact(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          filename: filename,
          artifact: artifactPart,
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{'output': version},
        );
        return;

      case 'async_load_artifact':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        final int? version = (input['version'] as num?)?.toInt();
        final Part? loaded = await context.artifactService.loadArtifact(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          filename: filename,
          version: version,
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': loaded == null ? null : _partToJson(loaded),
          },
        );
        return;

      case 'async_list_artifact_keys':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final List<String> keys = await context.artifactService.listArtifactKeys(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{'output': keys},
        );
        return;

      case 'async_delete_artifact':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        await context.artifactService.deleteArtifact(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          filename: filename,
        );
        await _writeJson(
          request,
          context,
          payload: const <String, Object?>{'output': null},
        );
        return;

      case 'async_list_versions':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        final List<int> versions = await context.artifactService.listVersions(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          filename: filename,
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{'output': versions},
        );
        return;

      case 'async_list_artifact_versions':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        final List<ArtifactVersion> versions = await context.artifactService
            .listArtifactVersions(
              appName: targetApp,
              userId: userId,
              sessionId: sessionId,
              filename: filename,
            );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': versions.map(_artifactVersionToJson).toList(),
          },
        );
        return;

      case 'async_get_artifact_version':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        final int? version = (input['version'] as num?)?.toInt();
        final ArtifactVersion? artifactVersion = await context.artifactService
            .getArtifactVersion(
              appName: targetApp,
              userId: userId,
              sessionId: sessionId,
              filename: filename,
              version: version,
            );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': artifactVersion == null
                ? null
                : _artifactVersionToJson(artifactVersion),
          },
        );
        return;
    }
  } on _ReasoningEngineInputError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: error.statusCode,
      message: error.message,
    );
  }
}

Future<void> _handleStreamReasoningEngine(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final ReasoningEngineQueryRequest? queryReq =
      await _parseAndValidateReasoningEngineRequest(
        request,
        context,
        expectStreaming: true,
      );
  if (queryReq == null) {
    return;
  }

  Map<String, Object?> effectiveInput = queryReq.input;
  if (queryReq.classMethod == 'streaming_agent_run_with_events') {
    final Object? requestJsonRaw = effectiveInput['request_json'];
    if (requestJsonRaw is String && requestJsonRaw.trim().isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(requestJsonRaw);
        if (decoded is Map) {
          effectiveInput = Map<String, Object?>.from(decoded);
        } else {
          await _writeError(
            request,
            context,
            statusCode: HttpStatus.badRequest,
            message: 'request_json must decode to a JSON object.',
          );
          return;
        }
      } on FormatException catch (error) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.badRequest,
          message: 'Invalid request_json: ${error.message}',
        );
        return;
      }
    } else if (requestJsonRaw != null) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.unprocessableEntity,
        message: 'request_json must be a non-empty JSON string.',
      );
      return;
    }
  }

  final String targetApp = _resolveReasoningEngineAppName(
    context,
    effectiveInput,
  );

  final String userId;
  final String? sessionId;
  final Content newMessage;
  final Map<String, Object?>? stateDelta;
  final Runner runner;
  final Session session;

  try {
    userId = _requireReasoningEngineString(
      effectiveInput,
      const <String>['user_id', 'userId'],
      fieldLabel: 'user_id',
    );
    sessionId = _optionalReasoningEngineString(
      effectiveInput,
      const <String>['session_id', 'sessionId'],
      fieldLabel: 'session_id',
    );
    newMessage = _parseReasoningEngineMessage(effectiveInput);
    final Object? rawStateDelta =
        effectiveInput['state_delta'] ?? effectiveInput['stateDelta'];
    if (rawStateDelta != null && rawStateDelta is! Map) {
      throw const _ReasoningEngineInputError(
        'Parameter "state_delta" must be a JSON object.',
      );
    }
    stateDelta = rawStateDelta is Map
        ? Map<String, Object?>.from(rawStateDelta)
        : null;
    runner = await context.getRunner(targetApp, request: request);
    session = await _resolveOrCreateReasoningEngineSession(
      context: context,
      appName: targetApp,
      userId: userId,
      sessionId: sessionId,
      rawSessionEvents:
          effectiveInput['session_events'] ?? effectiveInput['sessionEvents'],
    );
  } on _ReasoningEngineInputError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: error.statusCode,
      message: error.message,
    );
    return;
  }

  final String acceptHeader =
      (request.headers.value(HttpHeaders.acceptHeader) ?? '').toLowerCase();
  final bool emitSse = acceptHeader.contains('text/event-stream');

  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = emitSse
      ? ContentType('text', 'event-stream', charset: 'utf-8')
      : ContentType.json;
  response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  response.headers.set('x-accel-buffering', 'no');
  response.bufferOutput = false;

  try {
    await for (final Event event in runner.runAsync(
      userId: userId,
      sessionId: session.id,
      newMessage: newMessage,
      stateDelta: stateDelta,
      runConfig: RunConfig(streamingMode: StreamingMode.sse),
    )) {
      final Map<String, Object?> eventJson = _eventToApiJson(
        event,
        appName: targetApp,
        userId: userId,
        sessionId: session.id,
      );
      if (emitSse) {
        response.write('data: ${jsonEncode(eventJson)}\n\n');
      } else {
        response.write('${jsonEncode(eventJson)}\n');
      }
      await response.flush();
    }
  } finally {
    await response.close();
  }
}
