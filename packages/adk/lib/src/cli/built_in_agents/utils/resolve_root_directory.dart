// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Working directory helper tool to resolve path context issues.
library;

import 'dart:io';

import 'path_normalizer.dart';

/// Resolves a [filePath] using the root directory from [sessionState].
///
/// This is a helper function that other tools can use to resolve file paths
/// without needing to be async or return detailed resolution information.
///
/// Returns a resolved absolute [File] whose path is guaranteed to be within
/// the root directory (equivalent to `candidate.relative_to(resolved_root)`).
///
/// Throws an [ArgumentError] if [filePath] resolves outside the root directory,
/// for example via `..` traversal or an absolute path pointing outside the
/// root.
File resolveFilePath(
  String filePath, [
  Map<String, Object?>? sessionState,
  String? workingDirectory,
]) {
  final String normalizedPath = sanitizeGeneratedFilePath(filePath);

  String rootDirectory = './';
  if (sessionState != null && sessionState.containsKey('root_directory')) {
    final Object? rawRoot = sessionState['root_directory'];
    if (rawRoot is String && rawRoot.isNotEmpty) {
      rootDirectory = rawRoot;
    }
  }

  final String rawRootPath;
  if (_isAbsolutePath(rootDirectory)) {
    rawRootPath = rootDirectory;
  } else if (workingDirectory != null && workingDirectory.isNotEmpty) {
    rawRootPath = _joinPaths(workingDirectory, rootDirectory);
  } else {
    rawRootPath = _joinPaths(Directory.current.path, rootDirectory);
  }
  final String resolvedRoot = canonicalizePath(rawRootPath);

  final String rawCandidatePath = _isAbsolutePath(normalizedPath)
      ? normalizedPath
      : _joinPaths(resolvedRoot, normalizedPath);
  final String candidate = canonicalizePath(rawCandidatePath);

  // Keep the resolved path within the root to block path-traversal escapes
  // (equivalent to `candidate.relative_to(resolved_root)`).
  if (!isPathRelativeTo(candidate, resolvedRoot)) {
    throw ArgumentError(
      "File path '$filePath' resolves outside the root directory "
      '$resolvedRoot.',
    );
  }
  return File(candidate);
}

/// Snake-case alias for [resolveFilePath].
// ignore: non_constant_identifier_names
File resolve_file_path(
  String filePath, [
  Map<String, Object?>? sessionState,
  String? workingDirectory,
]) => resolveFilePath(filePath, sessionState, workingDirectory);

/// Resolves multiple [filePaths] using the root directory from [sessionState].
List<File> resolveFilePaths(
  List<String> filePaths, [
  Map<String, Object?>? sessionState,
  String? workingDirectory,
]) {
  return <File>[
    for (final String path in filePaths)
      resolveFilePath(path, sessionState, workingDirectory),
  ];
}

/// Snake-case alias for [resolveFilePaths].
// ignore: non_constant_identifier_names
List<File> resolve_file_paths(
  List<String> filePaths, [
  Map<String, Object?>? sessionState,
  String? workingDirectory,
]) => resolveFilePaths(filePaths, sessionState, workingDirectory);

/// Extracts the session state map from a tool or readonly [context] object.
Map<String, Object?>? extractSessionState(Object? context) {
  if (context == null) {
    return null;
  }
  if (context is Map<String, Object?>) {
    return context;
  }
  if (context is Map) {
    return context.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
  }
  final dynamic dyn = context;
  try {
    final Object? state = dyn.state;
    if (state is Map<String, Object?>) {
      return state;
    }
    if (state is Map) {
      return state.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    }
  } catch (_) {}
  try {
    final Object? state = dyn.session?.state;
    if (state is Map<String, Object?>) {
      return state;
    }
    if (state is Map) {
      return state.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    }
  } catch (_) {}
  try {
    final Object? state = dyn.invocationContext?.session?.state;
    if (state is Map<String, Object?>) {
      return state;
    }
    if (state is Map) {
      return state.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    }
  } catch (_) {}
  return null;
}

/// Canonicalizes [path] by resolving `.`, `..`, and any existing symbolic links
/// along the path (even when leaf components do not yet exist on disk).
String canonicalizePath(String path) {
  final String absPath = _isAbsolutePath(path)
      ? path
      : _joinPaths(Directory.current.path, path);

  final String sep = Platform.pathSeparator;
  final String normalizedSeparators = absPath.replaceAll(r'\', '/');
  String drivePrefix = '';
  String remainder = normalizedSeparators;
  final RegExpMatch? driveMatch = RegExp(
    r'^[A-Za-z]:',
  ).firstMatch(normalizedSeparators);
  if (driveMatch != null) {
    drivePrefix = driveMatch.group(0)!;
    remainder = normalizedSeparators.substring(drivePrefix.length);
  }

  final List<String> rawParts = remainder.split('/');
  final List<String> resolvedParts = <String>[];
  for (final String part in rawParts) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (resolvedParts.isNotEmpty) {
        resolvedParts.removeLast();
      }
      continue;
    }
    resolvedParts.add(part);
  }

  // Find the deepest existing prefix and resolve symbolic links on it.
  for (int i = resolvedParts.length; i >= 0; i--) {
    final String prefixPath = i == 0
        ? (drivePrefix.isNotEmpty ? '$drivePrefix$sep' : sep)
        : '$drivePrefix$sep${resolvedParts.sublist(0, i).join(sep)}';
    final FileSystemEntityType entityType = FileSystemEntity.typeSync(
      prefixPath,
      followLinks: true,
    );
    if (entityType != FileSystemEntityType.notFound) {
      try {
        final String resolvedPrefix = entityType == FileSystemEntityType.directory
            ? Directory(prefixPath).resolveSymbolicLinksSync()
            : File(prefixPath).resolveSymbolicLinksSync();
        final String trimmedPrefix =
            resolvedPrefix.length > 1 && resolvedPrefix.endsWith(sep)
            ? resolvedPrefix.substring(0, resolvedPrefix.length - 1)
            : resolvedPrefix;
        if (i == resolvedParts.length) {
          return trimmedPrefix;
        }
        final String suffix = resolvedParts.sublist(i).join(sep);
        return trimmedPrefix == sep
            ? '$sep$suffix'
            : '$trimmedPrefix$sep$suffix';
      } on FileSystemException {
        // Fall through to lexical join if symlink resolution fails.
        break;
      }
    }
  }

  if (resolvedParts.isEmpty) {
    return drivePrefix.isNotEmpty ? '$drivePrefix$sep' : sep;
  }
  return '$drivePrefix$sep${resolvedParts.join(sep)}';
}

/// Returns whether [candidate] is inside or equal to [root] after path
/// normalization.
bool isPathRelativeTo(String candidate, String root) {
  final String sep = Platform.pathSeparator;
  final String normalizedCandidate =
      candidate.length > 1 && candidate.endsWith(sep)
      ? candidate.substring(0, candidate.length - 1)
      : candidate;
  final String normalizedRoot = root.length > 1 && root.endsWith(sep)
      ? root.substring(0, root.length - 1)
      : root;

  if (normalizedCandidate == normalizedRoot) {
    return true;
  }
  if (normalizedRoot == sep) {
    return normalizedCandidate.startsWith(sep);
  }
  return normalizedCandidate.startsWith('$normalizedRoot$sep');
}

/// Computes the relative path of [targetPath] from [rootPath], or throws an
/// [ArgumentError] if [targetPath] is not inside [rootPath].
String relativePathFromRoot(String targetPath, String rootPath) {
  final String sep = Platform.pathSeparator;
  final String normalizedTarget =
      targetPath.length > 1 && targetPath.endsWith(sep)
      ? targetPath.substring(0, targetPath.length - 1)
      : targetPath;
  final String normalizedRoot = rootPath.length > 1 && rootPath.endsWith(sep)
      ? rootPath.substring(0, rootPath.length - 1)
      : rootPath;

  if (normalizedTarget == normalizedRoot) {
    return '.';
  }
  if (normalizedRoot == sep && normalizedTarget.startsWith(sep)) {
    return normalizedTarget.substring(1);
  }
  final String prefix = '$normalizedRoot$sep';
  if (normalizedTarget.startsWith(prefix)) {
    return normalizedTarget.substring(prefix.length);
  }
  throw ArgumentError(
    "Path '$targetPath' is not relative to '$rootPath'.",
  );
}

bool _isAbsolutePath(String path) {
  if (path.startsWith('/') || path.startsWith(r'\')) {
    return true;
  }
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

String _joinPaths(String left, String right) {
  if (left.isEmpty) {
    return right;
  }
  if (right.isEmpty || right == '.' || right == './') {
    return left;
  }
  final String sep = Platform.pathSeparator;
  if (left.endsWith('/') || left.endsWith(r'\')) {
    return '$left$right';
  }
  return '$left$sep$right';
}
