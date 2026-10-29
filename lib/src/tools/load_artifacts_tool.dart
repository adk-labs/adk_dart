/// Tool that loads stored artifacts into model-visible context.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:archive/archive.dart';

import '../models/llm_request.dart';
import '../types/content.dart';
import 'base_tool.dart';
import 'tool_context.dart';

const List<String> _geminiSupportedInlineMimePrefixes = <String>[
  'image/',
  'audio/',
  'video/',
];
const Set<String> _geminiSupportedInlineMimeTypes = <String>{'application/pdf'};
const Set<String> _geminiUnsupportedInlineSubtypes = <String>{
  'image/svg',
  'image/svg+xml',
  'image/xml',
};
const Set<String> _textLikeMimeTypes = <String>{
  'application/csv',
  'application/json',
  'application/xml',
  'application/svg+xml',
  'image/svg',
  'image/svg+xml',
  'image/xml',
};
const Set<String> _spreadsheetMimeTypes = <String>{
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-excel',
};

/// Signature for custom artifact preprocessing callback.
typedef ProcessArtifactCallback =
    FutureOr<Part?> Function(Part artifact, String artifactName);

/// Signature for filtering or transforming available artifact names.
typedef ProcessArtifactNamesCallback =
    FutureOr<List<String>> Function(
      List<String> artifactNames,
      ToolContext toolContext,
    );

/// Tool that loads saved artifacts into the current turn.
class LoadArtifactsTool extends BaseTool {
  /// Creates a tool that loads saved artifacts into the current request.
  LoadArtifactsTool({
    this.processArtifact,
    this.processArtifactNames,
    this.enableSpreadsheetParsing = false,
  }) : super(
         name: 'load_artifacts',
         description: '''Loads artifacts into the session for this request.

NOTE: Call when you need access to artifacts (for example, uploads saved by the
web UI).''',
       );

  /// Optional callback to customize or filter artifact parts before adding them
  /// to the LLM request.
  final ProcessArtifactCallback? processArtifact;

  /// Optional callback to filter the list of available artifact names.
  final ProcessArtifactNamesCallback? processArtifactNames;

  /// Whether to parse spreadsheet artifacts (.xlsx, .xls) into textual representations.
  final bool enableSpreadsheetParsing;

  Future<(List<String>, Set<String>)> _getArtifactNames(
    ToolContext toolContext,
  ) async {
    final List<String> artifactNames = List<String>.from(
      await toolContext.listArtifacts(),
    );
    final Set<String> allNames = artifactNames.toSet();
    if (processArtifactNames != null) {
      final List<String> filteredNames = await processArtifactNames!(
        artifactNames,
        toolContext,
      );
      return (filteredNames, allNames.difference(filteredNames.toSet()));
    }
    return (artifactNames, <String>{});
  }

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'artifact_names': <String, dynamic>{
            'type': 'array',
            'items': <String, dynamic>{'type': 'string'},
          },
        },
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final List<String> requestedNames = _coerceArtifactNames(
      args['artifact_names'],
    );
    final (List<String> availableNames, _) = await _getArtifactNames(
      toolContext,
    );
    final Set<String> availableSet = availableNames.toSet();
    final List<String> artifactNames = <String>[
      for (final String name in requestedNames)
        if (availableSet.contains(name) ||
            availableSet.contains('$_userNamespacePrefix$name'))
          name,
    ];
    return <String, Object?>{
      'artifact_names': artifactNames,
      'status':
          'artifact contents temporarily inserted and removed. to access these artifacts, call load_artifacts tool again.',
    };
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    await super.processLlmRequest(
      toolContext: toolContext,
      llmRequest: llmRequest,
    );

    final (List<String> artifactNames, Set<String> filteredOutNames) =
        await _getArtifactNames(toolContext);
    if (artifactNames.isEmpty && filteredOutNames.isEmpty) {
      return;
    }

    if (artifactNames.isNotEmpty) {
      llmRequest.appendInstructions(<String>[
        'You have a list of artifacts:\n'
            '  ${_jsonDumpsStringList(artifactNames)}\n\n'
            '  When the user asks questions about any of the artifacts, you should call the\n'
            '  `load_artifacts` function to load the artifact. Always call load_artifacts\n'
            '  before answering questions related to the artifacts, regardless of whether the\n'
            '  artifacts have been loaded before. Do not depend on prior answers about the\n'
            '  artifacts.\n',
      ]);
    }

    if (llmRequest.contents.isEmpty) {
      return;
    }
    final Content tail = llmRequest.contents.last;
    if (tail.parts.isEmpty) {
      return;
    }
    final FunctionResponse? response = tail.parts.first.functionResponse;
    if (response == null || response.name != name) {
      return;
    }

    final Object? payloadNames = response.response['artifact_names'];
    if (payloadNames is! List ||
        !payloadNames.every((dynamic item) => item is String)) {
      return;
    }
    final List<String> rawArtifactNames = payloadNames.cast<String>();
    final Set<String> availableNames = artifactNames.toSet();
    for (final String requestedName in rawArtifactNames) {
      final String? resolvedName = _resolveRequestedArtifactName(
        requestedName,
        availableNames,
      );
      if (resolvedName == null) {
        final String? filteredOutName = _resolveRequestedArtifactName(
          requestedName,
          filteredOutNames,
        );
        if (filteredOutName != null) {
          developer.log(
            'Artifact "$requestedName" was filtered out by '
            'process_artifact_names and cannot be loaded.',
            name: 'adk_dart.tools.load_artifacts_tool',
          );
        } else {
          developer.log(
            'Artifact "$requestedName" is not in the list of available '
            'artifacts.',
            name: 'adk_dart.tools.load_artifacts_tool',
          );
        }
        continue;
      }

      String artifactName = resolvedName;
      Part? artifact = await toolContext.loadArtifact(artifactName);
      if (artifact == null && !artifactName.startsWith(_userNamespacePrefix)) {
        artifactName = '$_userNamespacePrefix$artifactName';
        artifact = await toolContext.loadArtifact(artifactName);
      }
      if (artifact == null) {
        continue;
      }

      Part? processed;
      if (processArtifact != null) {
        processed = await processArtifact!(artifact, artifactName);
      } else {
        processed = _asSafePart(
          artifact,
          requestedName,
          enableSpreadsheetParsing: enableSpreadsheetParsing,
        );
      }

      if (processed != null) {
        llmRequest.contents.add(
          Content(
            role: 'user',
            parts: <Part>[Part.text('Artifact $requestedName is:'), processed],
          ),
        );
      }
    }
  }
}

const String _userNamespacePrefix = 'user:';

String? _resolveRequestedArtifactName(
  String requestedName,
  Set<String> availableNames,
) {
  if (availableNames.contains(requestedName)) {
    return requestedName;
  }
  if (requestedName.startsWith(_userNamespacePrefix)) {
    final String bareName = requestedName.substring(
      _userNamespacePrefix.length,
    );
    if (availableNames.contains(bareName)) {
      return requestedName;
    }
  } else {
    final String prefixedName = '$_userNamespacePrefix$requestedName';
    if (availableNames.contains(prefixedName)) {
      return prefixedName;
    }
  }
  return null;
}

List<String> _coerceArtifactNames(Object? value) {
  if (value is List) {
    final List<String> artifactNames = <String>[];
    for (final dynamic item in value) {
      final String name = '$item'.trim();
      if (name.isEmpty || name == 'null') {
        continue;
      }
      artifactNames.add(name);
    }
    return artifactNames;
  }
  return const <String>[];
}

String _jsonDumpsStringList(List<String> values) {
  return '[${values.map(jsonEncode).join(', ')}]';
}

/// Converts an [artifact] into a safe [Part] representation for LLM consumption.
Part asSafePartForLlm(
  Part artifact,
  String artifactName, {
  bool enableSpreadsheetParsing = false,
}) => _asSafePart(
  artifact,
  artifactName,
  enableSpreadsheetParsing: enableSpreadsheetParsing,
);

Part _asSafePart(
  Part artifact,
  String artifactName, {
  bool enableSpreadsheetParsing = false,
}) {
  if (artifact.inlineData != null) {
    return _asSafeInlineDataPart(
      artifact,
      artifactName,
      enableSpreadsheetParsing: enableSpreadsheetParsing,
    );
  }
  if (artifact.text != null && artifact.text!.isNotEmpty) {
    return artifact.copyWith();
  }
  if (artifact.fileData != null) {
    return artifact.copyWith();
  }
  if (artifact.functionCall != null || artifact.functionResponse != null) {
    return Part.text(
      '[Artifact $artifactName contains structured tool data and was loaded.]',
    );
  }
  if (artifact.codeExecutionResult != null || artifact.executableCode != null) {
    return Part.text(
      '[Artifact $artifactName contains code execution output and was loaded.]',
    );
  }
  return Part.text('[Artifact $artifactName was loaded.]');
}

Part _asSafeInlineDataPart(
  Part artifact,
  String artifactName, {
  bool enableSpreadsheetParsing = false,
}) {
  final InlineData inlineData = artifact.inlineData!;
  if (_isInlineMimeTypeSupported(inlineData.mimeType)) {
    final int delimiterIndex = inlineData.mimeType.indexOf(';');
    final String canonicalMimeType = delimiterIndex == -1
        ? inlineData.mimeType.trim().toLowerCase()
        : '${inlineData.mimeType.substring(0, delimiterIndex).trim().toLowerCase()}${inlineData.mimeType.substring(delimiterIndex)}';
    return artifact.copyWith(
      inlineData: inlineData.copyWith(mimeType: canonicalMimeType),
    );
  }

  final String mimeType =
      _normalizeMimeType(inlineData.mimeType) ?? 'application/octet-stream';
  final List<int> data = inlineData.data;
  if (data.isEmpty) {
    return Part.text(
      '[Artifact: $artifactName, type: $mimeType. No inline data was provided.]',
    );
  }

  // Attempt DOCX extraction
  final bool isDocx =
      mimeType ==
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
      mimeType == 'application/octet-stream' ||
      artifactName.toLowerCase().endsWith('.docx');
  if (isDocx) {
    final String? extractedText = _tryExtractDocxText(data);
    if (extractedText != null) {
      return Part.text(extractedText);
    }
  }

  // Attempt Spreadsheet extraction if enabled
  if (enableSpreadsheetParsing &&
      (_spreadsheetMimeTypes.contains(mimeType) ||
          artifactName.toLowerCase().endsWith('.xlsx') ||
          artifactName.toLowerCase().endsWith('.xls'))) {
    final String? extractedSpreadsheet = _tryExtractXlsxText(data);
    if (extractedSpreadsheet != null) {
      return Part.text(extractedSpreadsheet);
    }
  }

  final bool isTextLike =
      mimeType.startsWith('text/') ||
      _textLikeMimeTypes.contains(mimeType) ||
      artifactName.toLowerCase().endsWith('.csv') ||
      artifactName.toLowerCase().endsWith('.txt') ||
      artifactName.toLowerCase().endsWith('.json') ||
      artifactName.toLowerCase().endsWith('.xml');

  if (isTextLike) {
    return Part.text(utf8.decode(data, allowMalformed: true));
  }

  final double sizeKb = data.length / 1024;
  return Part.text(
    '[Binary artifact: $artifactName, type: $mimeType, size: ${sizeKb.toStringAsFixed(1)} KB. Content cannot be displayed inline.]',
  );
}

String? _tryExtractDocxText(List<int> bytes) {
  try {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final ArchiveFile? documentFile = archive.findFile('word/document.xml');
    if (documentFile == null) {
      return null;
    }
    final Object rawContent = documentFile.content;
    final List<int> contentBytes = rawContent is List<int>
        ? rawContent
        : (rawContent is String ? utf8.encode(rawContent) : <int>[]);
    if (contentBytes.isEmpty) {
      return null;
    }
    final String xmlContent = utf8.decode(contentBytes, allowMalformed: true);

    final RegExp nsRegex = RegExp(
      r'xmlns:([a-zA-Z0-9]+)="[^"]*wordprocessingml',
    );
    final RegExpMatch? nsMatch = nsRegex.firstMatch(xmlContent);
    final String prefix = nsMatch != null ? nsMatch.group(1)! : 'w';

    final String pTag = '$prefix:p';
    final String tTag = '$prefix:t';

    final List<String> paragraphs = <String>[];
    final RegExp pSplitRegex = RegExp('<$pTag(?:[^>]*)>');
    final List<String> pSegments = xmlContent.split(pSplitRegex);

    final RegExp tFindRegex = RegExp('<$tTag(?:[^>]*)>([^<]*)</$tTag>');

    for (final String p in pSegments) {
      final List<String> texts = <String>[];
      for (final RegExpMatch m in tFindRegex.allMatches(p)) {
        texts.add(m.group(1) ?? '');
      }
      if (texts.isNotEmpty) {
        paragraphs.add(texts.join(''));
      }
    }

    return paragraphs.join('\n');
  } catch (_) {
    return null;
  }
}

String? _tryExtractXlsxText(List<int> bytes) {
  try {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final List<String> sharedStrings = <String>[];
    final ArchiveFile? ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile != null) {
      final Object content = ssFile.content;
      final List<int> ssBytes = content is List<int>
          ? content
          : (content is String ? utf8.encode(content) : <int>[]);
      final String ssXml = utf8.decode(ssBytes, allowMalformed: true);
      final RegExp tRegex = RegExp(r'<t(?:[^>]*)>([^<]*)</t>');
      for (final RegExpMatch m in tRegex.allMatches(ssXml)) {
        sharedStrings.add(m.group(1) ?? '');
      }
    }

    final Map<String, String> relIdToTarget = <String, String>{};
    final ArchiveFile? relsFile = archive.findFile(
      'xl/_rels/workbook.xml.rels',
    );
    if (relsFile != null) {
      final Object relContent = relsFile.content;
      final List<int> relBytes = relContent is List<int>
          ? relContent
          : (relContent is String ? utf8.encode(relContent) : <int>[]);
      final String relXml = utf8.decode(relBytes, allowMalformed: true);
      final RegExp relRegex = RegExp(r'<Relationship\s+([^>]*?)/?>');
      final RegExp idAttr = RegExp(r'\bId="([^"]+)"');
      final RegExp targetAttr = RegExp(r'\bTarget="([^"]+)"');
      for (final RegExpMatch match in relRegex.allMatches(relXml)) {
        final String attrs = match.group(1) ?? '';
        final String? id = idAttr.firstMatch(attrs)?.group(1);
        final String? target = targetAttr.firstMatch(attrs)?.group(1);
        if (id != null && target != null) {
          String normalizedTarget = target.startsWith('/')
              ? target.substring(1)
              : (target.startsWith('xl/') ? target : 'xl/$target');
          relIdToTarget[id] = normalizedTarget;
        }
      }
    }

    final List<({String name, ArchiveFile file})> sheets =
        <({String name, ArchiveFile file})>[];
    final ArchiveFile? workbookFile = archive.findFile('xl/workbook.xml');
    if (workbookFile != null) {
      final Object wbContent = workbookFile.content;
      final List<int> wbBytes = wbContent is List<int>
          ? wbContent
          : (wbContent is String ? utf8.encode(wbContent) : <int>[]);
      final String wbXml = utf8.decode(wbBytes, allowMalformed: true);
      final RegExp sheetTagRegex = RegExp(r'<sheet\s+([^>]*?)/?>');
      final RegExp nameAttr = RegExp(r'\bname="([^"]+)"');
      final RegExp rIdAttr = RegExp(r'\br:id="([^"]+)"');
      int index = 1;
      for (final RegExpMatch match in sheetTagRegex.allMatches(wbXml)) {
        final String attrs = match.group(1) ?? '';
        final String sheetName =
            nameAttr.firstMatch(attrs)?.group(1) ?? 'Sheet$index';
        final String? rId = rIdAttr.firstMatch(attrs)?.group(1);
        ArchiveFile? sheetFile;
        if (rId != null && relIdToTarget.containsKey(rId)) {
          sheetFile = archive.findFile(relIdToTarget[rId]!);
        }
        sheetFile ??= archive.findFile('xl/worksheets/sheet$index.xml');
        if (sheetFile != null) {
          sheets.add((name: sheetName, file: sheetFile));
        }
        index += 1;
      }
    }

    if (sheets.isEmpty) {
      final List<ArchiveFile> fallbackFiles =
          archive.files
              .where(
                (ArchiveFile f) =>
                    f.isFile &&
                    f.name.startsWith('xl/worksheets/sheet') &&
                    f.name.endsWith('.xml'),
              )
              .toList()
            ..sort((ArchiveFile a, ArchiveFile b) => a.name.compareTo(b.name));
      for (int i = 0; i < fallbackFiles.length; i += 1) {
        sheets.add((name: 'Sheet${i + 1}', file: fallbackFiles[i]));
      }
    }

    if (sheets.isEmpty) {
      return null;
    }

    final RegExp rowRegex = RegExp(r'<row(?:[^>]*)>(.*?)</row>', dotAll: true);
    final RegExp cellRegex = RegExp(
      r'<c\s+([^>]*?)>(?:<v>([^<]*)</v>|<is>.*?<t(?:[^>]*)>([^<]*)</t>.*?</is>)?',
      dotAll: true,
    );
    final RegExp tAttrRegex = RegExp(r't="([^"]*)"');

    final List<String> sheetOutputs = <String>[];
    final bool includeHeaders = sheets.length > 1 || workbookFile != null;

    for (final ({String name, ArchiveFile file}) sheet in sheets) {
      final Object sContent = sheet.file.content;
      final List<int> sheetBytes = sContent is List<int>
          ? sContent
          : (sContent is String ? utf8.encode(sContent) : <int>[]);
      final String sheetXml = utf8.decode(sheetBytes, allowMalformed: true);
      final List<String> rows = <String>[];

      for (final RegExpMatch rowMatch in rowRegex.allMatches(sheetXml)) {
        final String rowXml = rowMatch.group(1) ?? '';
        final List<String> cellValues = <String>[];
        for (final RegExpMatch cellMatch in cellRegex.allMatches(rowXml)) {
          final String attrs = cellMatch.group(1) ?? '';
          final String? val = cellMatch.group(2) ?? cellMatch.group(3);
          if (val == null) continue;
          final RegExpMatch? tMatch = tAttrRegex.firstMatch(attrs);
          final String? type = tMatch?.group(1);
          if (type == 's') {
            final int idx = int.tryParse(val) ?? -1;
            if (idx >= 0 && idx < sharedStrings.length) {
              cellValues.add(sharedStrings[idx]);
            } else {
              cellValues.add(val);
            }
          } else {
            cellValues.add(val);
          }
        }
        if (cellValues.isNotEmpty) {
          rows.add(cellValues.join('\t'));
        }
      }

      if (rows.isNotEmpty) {
        if (includeHeaders) {
          sheetOutputs.add('--- Sheet: ${sheet.name} ---\n${rows.join('\n')}');
        } else {
          sheetOutputs.add(rows.join('\n'));
        }
      }
    }

    return sheetOutputs.isNotEmpty ? sheetOutputs.join('\n\n') : null;
  } catch (_) {
    return null;
  }
}

String? _normalizeMimeType(String? mimeType) {
  if (mimeType == null) {
    return null;
  }
  final String trimmed = mimeType.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final int delimiterIndex = trimmed.indexOf(';');
  final String normalized = delimiterIndex == -1
      ? trimmed
      : trimmed.substring(0, delimiterIndex);
  return normalized.trim().toLowerCase();
}

bool _isInlineMimeTypeSupported(String? mimeType) {
  final String? normalized = _normalizeMimeType(mimeType);
  if (normalized == null) {
    return false;
  }
  if (_geminiUnsupportedInlineSubtypes.contains(normalized)) {
    return false;
  }
  if (_geminiSupportedInlineMimeTypes.contains(normalized)) {
    return true;
  }
  for (final String prefix in _geminiSupportedInlineMimePrefixes) {
    if (normalized.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}
