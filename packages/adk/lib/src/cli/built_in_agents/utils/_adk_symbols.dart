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

/// Checks whether a `google.adk.*` name exists in the installed ADK package.
///
/// Shared by the config writer and the file writer, which both need to refuse a
/// reference to something this version does not have. It lives in `utils`
/// because those two already import each other; a copy in either would be a
/// cycle.
library;

import 'dart:io';

import 'adk_source_utils.dart';

/// Symbols that existed in 1.x but were removed in 2.x.
const Set<String> _removedAdkSymbols = <String>{
  'google.adk.agents.common_configs.ArgumentConfig',
  'google.adk.agents.ArgumentConfig',
};

/// Known built-in tool and symbol aliases re-exported at package level in ADK.
const Map<String, Set<String>> _packageReExports = <String, Set<String>>{
  'google.adk': <String>{
    'Agent',
    'LlmAgent',
    'BaseAgent',
    'LoopAgent',
    'ParallelAgent',
    'SequentialAgent',
    'Runner',
    'InMemoryRunner',
  },
  'google.adk.agents': <String>{
    'Agent',
    'BaseAgent',
    'BaseAgentConfig',
    'LlmAgent',
    'LlmAgentConfig',
    'LoopAgent',
    'LoopAgentConfig',
    'ParallelAgent',
    'ParallelAgentConfig',
    'SequentialAgent',
    'SequentialAgentConfig',
    'InvocationContext',
    'ReadonlyContext',
    'CallbackContext',
    'Context',
    'RunConfig',
    'LiveRequestQueue',
    'LanggraphAgent',
    'RemoteA2aAgent',
  },
  'google.adk.tools': <String>{
    'BaseTool',
    'BaseToolset',
    'FunctionTool',
    'LongRunningFunctionTool',
    'ToolContext',
    'AgentTool',
    'google_search',
    'enterprise_web_search',
    'google_maps_grounding',
    'url_context',
    'VertexAiSearchTool',
    'DiscoveryEngineSearchTool',
    'exit_loop',
    'get_user_choice',
    'load_artifacts',
    'load_memory',
    'preload_memory',
    'transfer_to_agent',
    'load_web_page',
    'ExampleTool',
    'AuthToolArguments',
  },
  'google.adk.models': <String>{
    'BaseLlm',
    'BaseLlmConnection',
    'Gemini',
    'Gemma',
    'LiteLlm',
    'LLMRegistry',
    'LlmRequest',
    'LlmResponse',
  },
};

/// Returns whether a `google.adk.*` [name] resolves in the installed package.
///
/// Resolves module prefixes and exported/declared attributes against the
/// installed ADK source tree so that module paths, classes, functions, and
/// package re-exports resolve accurately.
bool adkSymbolExists(String name) {
  final String trimmed = name.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (_removedAdkSymbols.contains(trimmed)) {
    return false;
  }
  if (trimmed == 'google' || trimmed == 'google.adk') {
    return true;
  }
  if (!trimmed.startsWith('google.adk.')) {
    return false;
  }

  // Check explicit package re-exports first.
  final int lastDot = trimmed.lastIndexOf('.');
  if (lastDot > 0) {
    final String modulePrefix = trimmed.substring(0, lastDot);
    final String symbolName = trimmed.substring(lastDot + 1);
    final Set<String>? exports = _packageReExports[modulePrefix];
    if (exports != null && exports.contains(symbolName)) {
      return true;
    }
  }

  final String? sourceRoot = findAdkSourceFolder();
  if (sourceRoot == null) {
    return false;
  }

  final List<String> parts = trimmed.substring('google.adk.'.length).split('.');
  if (parts.isEmpty || parts.any((String p) => p.isEmpty)) {
    return false;
  }

  // Walk from longest module prefix down to 1, matching Python's importlib walk.
  for (int split = parts.length; split >= 1; split--) {
    final List<String> moduleParts = parts.sublist(0, split);
    final List<String> attrParts = parts.sublist(split);

    final _ResolvedModule? resolvedModule = _resolveAdkModule(
      sourceRoot,
      moduleParts,
    );
    if (resolvedModule == null) {
      continue;
    }

    if (attrParts.isEmpty) {
      return true;
    }

    // Check whether the remaining attribute chain exists in the resolved module.
    final String firstAttr = attrParts.first;
    if (_moduleDefinesOrExportsSymbol(resolvedModule, firstAttr)) {
      return true;
    }
    return false;
  }

  return false;
}

/// Snake-case alias for [adkSymbolExists].
// ignore: non_constant_identifier_names
bool adk_symbol_exists(String name) => adkSymbolExists(name);

final class _ResolvedModule {
  const _ResolvedModule({this.file, this.directory});

  final File? file;
  final Directory? directory;
}

_ResolvedModule? _resolveAdkModule(
  String sourceRoot,
  List<String> moduleParts,
) {
  final String sep = Platform.pathSeparator;
  final String relPath = moduleParts.join(sep);
  final String baseCandidate = '$sourceRoot$sep$relPath';

  final File dartFile = File('$baseCandidate.dart');
  if (dartFile.existsSync()) {
    return _ResolvedModule(file: dartFile);
  }

  final File pyFile = File('$baseCandidate.py');
  if (pyFile.existsSync()) {
    return _ResolvedModule(file: pyFile);
  }

  final Directory dir = Directory(baseCandidate);
  if (dir.existsSync()) {
    return _ResolvedModule(directory: dir);
  }

  return null;
}

bool _moduleDefinesOrExportsSymbol(_ResolvedModule module, String symbolName) {
  if (module.file != null) {
    return _fileDefinesSymbol(module.file!, symbolName);
  }
  if (module.directory != null) {
    try {
      for (final FileSystemEntity entity in module.directory!.listSync(
        recursive: false,
        followLinks: true,
      )) {
        if (entity is File &&
            (entity.path.endsWith('.dart') || entity.path.endsWith('.py'))) {
          if (_fileDefinesSymbol(entity, symbolName)) {
            return true;
          }
        }
      }
    } on FileSystemException {
      return false;
    }
  }
  return false;
}

bool _fileDefinesSymbol(File file, String symbolName) {
  final String content;
  try {
    content = file.readAsStringSync();
  } on FileSystemException {
    return false;
  }

  final String escaped = RegExp.escape(symbolName);
  final String snakeEquivalent = _camelToSnake(symbolName);
  final String camelEquivalent = _snakeToCamel(symbolName);
  final Set<String> candidateNames = <String>{
    escaped,
    if (snakeEquivalent != symbolName) RegExp.escape(snakeEquivalent),
    if (camelEquivalent != symbolName) RegExp.escape(camelEquivalent),
  };

  for (final String candidate in candidateNames) {
    final List<RegExp> patterns = <RegExp>[
      // Dart declarations: class, mixin, enum, typedef, extension, const, final, var, functions
      RegExp(
        r'\b(?:class|mixin|enum|typedef|extension)\s+' + candidate + r'\b',
      ),
      RegExp(
        r'\b(?:const|final|var|late)\s+(?:[A-Za-z0-9_<>,?\s]+\s+)?' +
            candidate +
            r'\b',
      ),
      RegExp(
        r'(?:^|\n)\s*(?:[A-Za-z0-9_<>,?]+\s+)+' + candidate + r'\s*[(<]',
      ),
      // Python declarations: class, def, assignment, __all__
      RegExp(r'\b(?:class|def)\s+' + candidate + r'\b'),
      RegExp(r'(?:^|\n)\s*' + candidate + r'\s*(?::[^=\n]+)?='),
      RegExp('[\'"]$candidate[\'"]'),
    ];
    for (final RegExp pattern in patterns) {
      if (pattern.hasMatch(content)) {
        return true;
      }
    }
  }
  return false;
}

String _camelToSnake(String input) {
  return input
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (Match m) => '${m[1]}_${m[2]!.toLowerCase()}',
      )
      .toLowerCase();
}

String _snakeToCamel(String input) {
  final List<String> parts = input.split('_');
  if (parts.length <= 1) {
    return input;
  }
  return parts.first +
      parts
          .skip(1)
          .map(
            (String p) =>
                p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}',
          )
          .join();
}
