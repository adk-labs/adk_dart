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

/// Helpers for normalizing file path strings produced by the model.
library;

import 'dart:io';

final RegExp _segmentSplitPattern = RegExp(r'[/\\]');
const String _boundaryChars = " \t\r\n'\"`";

/// Strips stray quotes and whitespace around each path segment of [filePath].
///
/// The agent occasionally emits quoted paths such as `'tools/web.yaml'` which
/// would otherwise create directories literally named `'<name>`. This helper
/// removes leading and trailing whitespace and quote-like characters from the
/// path and from each path component while preserving intentional interior
/// characters.
String sanitizeGeneratedFilePath(Object? filePath) {
  final String rawString = switch (filePath) {
    final String value => value,
    final FileSystemEntity entity => entity.path,
    final Uri uri => uri.toFilePath(),
    _ => '$filePath',
  };

  final String trimmed = rawString.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }

  final List<String> segments = _splitPreservingSeparators(trimmed);
  final List<String> sanitizedSegments = <String>[];

  for (final String segment in segments) {
    if (segment.isEmpty) {
      sanitizedSegments.add(segment);
      continue;
    }
    if (segment == '/' || segment == r'\') {
      sanitizedSegments.add(segment);
      continue;
    }
    sanitizedSegments.add(_stripBoundaryChars(segment));
  }

  final String sanitized = _stripBoundaryChars(sanitizedSegments.join());
  return sanitized.isNotEmpty ? sanitized : trimmed;
}

/// Snake-case alias for [sanitizeGeneratedFilePath].
// ignore: non_constant_identifier_names
String sanitize_generated_file_path(Object? filePath) =>
    sanitizeGeneratedFilePath(filePath);

List<String> _splitPreservingSeparators(String input) {
  final List<String> result = <String>[];
  int lastIndex = 0;
  for (final RegExpMatch match in _segmentSplitPattern.allMatches(input)) {
    result.add(input.substring(lastIndex, match.start));
    result.add(match.group(0)!);
    lastIndex = match.end;
  }
  result.add(input.substring(lastIndex));
  return result;
}

String _stripBoundaryChars(String value) {
  int start = 0;
  int end = value.length;
  while (start < end && _boundaryChars.contains(value[start])) {
    start += 1;
  }
  while (end > start && _boundaryChars.contains(value[end - 1])) {
    end -= 1;
  }
  return value.substring(start, end);
}
