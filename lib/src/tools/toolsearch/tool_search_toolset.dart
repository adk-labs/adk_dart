/// Dynamic BM25 and keyword tool search toolset for large tool catalogs.
library;

import 'dart:math' as math;

import '../../agents/readonly_context.dart';
import '../../models/llm_request.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../tool_context.dart';

/// Canonical tool name for [SearchToolsTool].
const String searchToolsToolName = 'search_tools';

/// State key prefix used to store revealed deferred tool names per agent.
const String revealedToolsStatePrefix = '_adk_revealed_tools_';

/// Configuration options for [ToolSearchToolset].
class ToolSearchConfig {
  /// Creates a configuration for [ToolSearchToolset].
  const ToolSearchConfig({
    this.maxResults = 5,
    this.alwaysLoadedTools = const <String>{},
    this.bm25K1 = 1.5,
    this.bm25B = 0.75,
    this.injectSystemInstruction = true,
  });

  /// Maximum number of matching tools revealed by a single search query.
  final int maxResults;

  /// Tool names that should always be exposed without requiring search.
  final Set<String> alwaysLoadedTools;

  /// BM25 term-frequency saturation parameter `k1`.
  final double bm25K1;

  /// BM25 document-length normalization parameter `b`.
  final double bm25B;

  /// Whether to append guidance for using `search_tools` to the LLM request.
  final bool injectSystemInstruction;
}

/// Tool that searches deferred tools in a [ToolSearchToolset] and reveals matches.
class SearchToolsTool extends BaseTool {
  /// Creates a search tool bound to [toolset].
  SearchToolsTool(
    this._toolset, {
    super.name = searchToolsToolName,
    String? description,
  }) : super(
         description:
             description ??
             'Searches for deferred tools by keyword, required terms (+term), '
                 'or exact name selection (select:tool_a,tool_b) and loads '
                 'matching tools so they can be called.',
       );

  final ToolSearchToolset _toolset;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'description':
                'Search query string. Supports BM25 keywords, required terms '
                'prefixed with "+" (e.g. "+calendar create"), regex patterns, '
                'or exact selection via "select:tool1,tool2".',
          },
          'max_results': <String, Object?>{
            'type': 'integer',
            'description':
                'Optional maximum number of tools to return and reveal.',
          },
        },
        'required': <String>['query'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? rawQuery = args['query'];
    if (rawQuery is! String || rawQuery.trim().isEmpty) {
      return <String, Object?>{
        'error': "Argument 'query' is required and must be a non-empty string.",
        'tools': const <Map<String, Object?>>[],
      };
    }
    final int limit = args['max_results'] is num
        ? (args['max_results'] as num).toInt()
        : _toolset.config.maxResults;
    return _toolset.searchAndReveal(
      query: rawQuery.trim(),
      toolContext: toolContext,
      maxResults: limit,
    );
  }
}

/// Toolset that defers loading a large catalog of tools until discovered via `search_tools`.
///
/// ```dart
/// final searchToolset = ToolSearchToolset(
///   tools: [weatherTool, calendarTool, billingTool],
///   config: const ToolSearchConfig(
///     maxResults: 3,
///     alwaysLoadedTools: {'weather_lookup'},
///   ),
/// );
/// ```
class ToolSearchToolset extends BaseToolset {
  /// Creates a tool search toolset wrapping [tools].
  ToolSearchToolset({
    required List<Object> tools,
    this.config = const ToolSearchConfig(),
    String searchToolName = searchToolsToolName,
    String? searchToolDescription,
    super.toolFilter,
    super.toolNamePrefix,
  }) {
    _searchTool = SearchToolsTool(
      this,
      name: searchToolName,
      description: searchToolDescription,
    );
    for (final Object entry in tools) {
      if (entry is BaseTool) {
        _directTools.add(entry);
      } else if (entry is BaseToolset) {
        _nestedToolsets.add(entry);
      } else {
        throw ArgumentError(
          'ToolSearchToolset.tools only accepts BaseTool or BaseToolset instances, '
          'got ${entry.runtimeType}.',
        );
      }
    }
  }

  /// Configuration for BM25 ranking and always-loaded tools.
  final ToolSearchConfig config;

  late final SearchToolsTool _searchTool;
  final List<BaseTool> _directTools = <BaseTool>[];
  final List<BaseToolset> _nestedToolsets = <BaseToolset>[];

  /// The `search_tools` [BaseTool] exposed by this toolset.
  BaseTool get searchTool => _searchTool;

  /// Resolves all underlying candidate tools from direct tools and nested toolsets.
  Future<List<BaseTool>> resolveCatalogTools({
    ReadonlyContext? readonlyContext,
  }) async {
    final List<BaseTool> catalog = <BaseTool>[..._directTools];
    for (final BaseToolset toolset in _nestedToolsets) {
      final List<BaseTool> nested = await toolset.getToolsWithPrefix(
        readonlyContext: readonlyContext,
      );
      catalog.addAll(nested);
    }
    return catalog
        .where((BaseTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  /// Returns the names of tools currently revealed in [context].
  List<String> getRevealedToolNames(ReadonlyContext context) {
    final String key = '$revealedToolsStatePrefix${context.agentName}';
    final Object? raw = context.state[key];
    if (raw is List) {
      return raw.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }

  /// Marks [toolNames] as revealed in [toolContext] state so they are included in subsequent turns.
  List<String> revealTools(ToolContext toolContext, Iterable<String> toolNames) {
    final String key = '$revealedToolsStatePrefix${toolContext.agentName}';
    final List<String> current = <String>[];
    final Object? existing = toolContext.state[key];
    if (existing is List) {
      for (final Object? item in existing) {
        if (item is String && !current.contains(item)) {
          current.add(item);
        }
      }
    }
    for (final String name in toolNames) {
      final String trimmed = name.trim();
      if (trimmed.isNotEmpty && !current.contains(trimmed)) {
        current.add(trimmed);
      }
    }
    toolContext.state[key] = current;
    return List<String>.unmodifiable(current);
  }

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final List<BaseTool> catalog = await resolveCatalogTools(
      readonlyContext: readonlyContext,
    );
    final Set<String> activeNames = <String>{...config.alwaysLoadedTools};
    if (readonlyContext != null) {
      activeNames.addAll(getRevealedToolNames(readonlyContext));
    }

    final List<BaseTool> visible = <BaseTool>[_searchTool];
    final Set<String> seen = <String>{_searchTool.name};
    for (final BaseTool tool in catalog) {
      if (activeNames.contains(tool.name) && seen.add(tool.name)) {
        visible.add(tool);
      }
    }
    return visible;
  }

  /// Searches the deferred tool catalog with [query], reveals matching tools in [toolContext], and returns a summary map.
  Future<Map<String, Object?>> searchAndReveal({
    required String query,
    required ToolContext toolContext,
    int? maxResults,
  }) async {
    final List<BaseTool> catalog = await resolveCatalogTools(
      readonlyContext: toolContext,
    );
    final int limit = math.max(1, maxResults ?? config.maxResults);
    final List<BaseTool> matches = searchCatalog(
      query: query,
      catalog: catalog,
      maxResults: limit,
    );

    final List<String> matchedNames = matches
        .map((BaseTool tool) => tool.name)
        .toList(growable: false);
    if (matchedNames.isNotEmpty) {
      revealTools(toolContext, matchedNames);
    }

    final List<Map<String, Object?>> summaries = matches
        .map((BaseTool tool) {
          final FunctionDeclaration? decl = tool.getDeclaration();
          return <String, Object?>{
            'name': tool.name,
            'description': tool.description,
            if (decl != null && decl.parameters.isNotEmpty)
              'parameters': decl.parameters,
          };
        })
        .toList(growable: false);

    return <String, Object?>{
      'query': query,
      'matched_count': summaries.length,
      'revealed_tools': matchedNames,
      'tools': summaries,
    };
  }

  /// Ranks and filters [catalog] tools against [query] using `select:`, `+term`, BM25, and regex fallback.
  List<BaseTool> searchCatalog({
    required String query,
    required List<BaseTool> catalog,
    int? maxResults,
  }) {
    final String trimmed = query.trim();
    if (trimmed.isEmpty || catalog.isEmpty) {
      return const <BaseTool>[];
    }
    final int limit = math.max(1, maxResults ?? config.maxResults);

    // 1. Direct selection syntax: `select:tool_a,tool_b`
    if (trimmed.toLowerCase().startsWith('select:')) {
      final Set<String> requested = trimmed
          .substring('select:'.length)
          .split(',')
          .map((String s) => s.trim().toLowerCase())
          .where((String s) => s.isNotEmpty)
          .toSet();
      return catalog
          .where((BaseTool tool) => requested.contains(tool.name.toLowerCase()))
          .take(limit)
          .toList(growable: false);
    }

    // 2. Parse required terms (`+term`) and query tokens.
    final List<String> requiredTerms = <String>[];
    final List<String> optionalTerms = <String>[];
    for (final String rawToken in trimmed.split(RegExp(r'\s+'))) {
      if (rawToken.startsWith('+') && rawToken.length > 1) {
        requiredTerms.addAll(_tokenize(rawToken.substring(1)));
      } else {
        optionalTerms.addAll(_tokenize(rawToken));
      }
    }
    final List<String> allQueryTerms = <String>[
      ...requiredTerms,
      ...optionalTerms,
    ];

    final List<_ToolDocument> docs = catalog
        .map(_ToolDocument.fromTool)
        .toList(growable: false);

    final double avgDocLength = docs.isEmpty
        ? 1.0
        : docs.fold<int>(0, (int sum, _ToolDocument d) => sum + d.length) /
              docs.length;

    final Map<String, int> docFreq = <String, int>{};
    for (final _ToolDocument doc in docs) {
      for (final String token in doc.termFreq.keys) {
        docFreq[token] = (docFreq[token] ?? 0) + 1;
      }
    }

    final List<({BaseTool tool, double score})> scored =
        <({BaseTool tool, double score})>[];
    final int totalDocs = docs.length;

    for (final _ToolDocument doc in docs) {
      bool satisfiesRequired = true;
      for (final String req in requiredTerms) {
        if (!doc.containsTermOrSubstring(req)) {
          satisfiesRequired = false;
          break;
        }
      }
      if (!satisfiesRequired) {
        continue;
      }

      double score = 0.0;
      for (final String term in allQueryTerms) {
        final int tf = doc.termFreq[term] ?? 0;
        if (tf > 0) {
          final int df = docFreq[term] ?? 0;
          final double idf = math.log(
            1.0 + (totalDocs - df + 0.5) / (df + 0.5),
          );
          final double numerator = tf * (config.bm25K1 + 1.0);
          final double denominator =
              tf +
              config.bm25K1 *
                  (1.0 -
                      config.bm25B +
                      config.bm25B *
                          (doc.length / math.max(1.0, avgDocLength)));
          score += idf * (numerator / denominator);
        } else if (doc.rawTextLower.contains(term)) {
          score += 0.25;
        }
      }

      if (doc.tool.name.toLowerCase() == trimmed.toLowerCase()) {
        score += 10.0;
      } else if (doc.tool.name.toLowerCase().contains(trimmed.toLowerCase())) {
        score += 2.0;
      }

      if (score > 0 || (allQueryTerms.isEmpty && requiredTerms.isNotEmpty)) {
        scored.add((tool: doc.tool, score: score));
      }
    }

    // 3. Fallback to regex matching if BM25 produced no hits.
    if (scored.isEmpty && requiredTerms.isEmpty) {
      try {
        final RegExp pattern = RegExp(trimmed, caseSensitive: false);
        for (final _ToolDocument doc in docs) {
          if (pattern.hasMatch(doc.rawText)) {
            scored.add((tool: doc.tool, score: 1.0));
          }
        }
      } catch (_) {
        // Ignore invalid regular expression syntax.
      }
    }

    scored.sort(
      (({BaseTool tool, double score}) a, ({BaseTool tool, double score}) b) {
        final int cmp = b.score.compareTo(a.score);
        if (cmp != 0) {
          return cmp;
        }
        return a.tool.name.compareTo(b.tool.name);
      },
    );

    return scored
        .take(limit)
        .map((({BaseTool tool, double score}) item) => item.tool)
        .toList(growable: false);
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    if (!config.injectSystemInstruction) {
      return;
    }
    final List<BaseTool> catalog = await resolveCatalogTools(
      readonlyContext: toolContext,
    );
    final Set<String> activeNames = <String>{
      ...config.alwaysLoadedTools,
      ...getRevealedToolNames(toolContext),
    };
    final int deferredCount = catalog
        .where((BaseTool t) => !activeNames.contains(t.name))
        .length;
    if (deferredCount <= 0) {
      return;
    }
    final String effectiveSearchName =
        toolNamePrefix != null && toolNamePrefix!.isNotEmpty
        ? '${toolNamePrefix}_${_searchTool.name}'
        : _searchTool.name;
    llmRequest.appendInstructions(<String>[
      'There are $deferredCount additional deferred tools available in the catalog. '
          'Use `$effectiveSearchName` with keywords, `+required` terms, or '
          '`select:tool_name` to discover and load tools before calling them.',
    ]);
  }

  @override
  Future<void> close() async {
    for (final BaseToolset toolset in _nestedToolsets) {
      await toolset.close();
    }
    await super.close();
  }
}

class _ToolDocument {
  _ToolDocument({
    required this.tool,
    required this.rawText,
    required this.rawTextLower,
    required this.termFreq,
    required this.length,
  });

  factory _ToolDocument.fromTool(BaseTool tool) {
    final StringBuffer buffer = StringBuffer()
      ..write(tool.name)
      ..write(' ')
      ..write(tool.name.replaceAll('_', ' '))
      ..write(' ')
      ..write(tool.description);
    final FunctionDeclaration? decl = tool.getDeclaration();
    if (decl != null && decl.parameters.isNotEmpty) {
      buffer.write(' ');
      _appendSchemaText(decl.parameters, buffer);
    }
    final String rawText = buffer.toString();
    final List<String> tokens = _tokenize(rawText);
    final Map<String, int> freq = <String, int>{};
    for (final String token in tokens) {
      freq[token] = (freq[token] ?? 0) + 1;
    }
    return _ToolDocument(
      tool: tool,
      rawText: rawText,
      rawTextLower: rawText.toLowerCase(),
      termFreq: freq,
      length: math.max(1, tokens.length),
    );
  }

  final BaseTool tool;
  final String rawText;
  final String rawTextLower;
  final Map<String, int> termFreq;
  final int length;

  bool containsTermOrSubstring(String term) {
    final String lower = term.toLowerCase();
    return termFreq.containsKey(lower) || rawTextLower.contains(lower);
  }
}

void _appendSchemaText(Object? value, StringBuffer buffer) {
  if (value is Map) {
    value.forEach((Object? k, Object? v) {
      if (k is String && k != 'type' && k != 'properties' && k != 'required') {
        buffer.write('$k ');
      }
      _appendSchemaText(v, buffer);
    });
  } else if (value is Iterable) {
    for (final Object? item in value) {
      _appendSchemaText(item, buffer);
    }
  } else if (value is String) {
    buffer.write('$value ');
  }
}

List<String> _tokenize(String input) {
  final String normalized = input.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (Match m) => '${m.group(1)} ${m.group(2)}',
  );
  return RegExp(r'[a-zA-Z0-9]+')
      .allMatches(normalized.toLowerCase())
      .map((RegExpMatch m) => m.group(0)!)
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
}
