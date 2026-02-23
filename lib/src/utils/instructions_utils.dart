import '../agents/invocation_context.dart';
import '../agents/readonly_context.dart';
import '../sessions/state.dart';
import '../types/content.dart';

final RegExp _templatePattern = RegExp(r'{+[^{}]*}+');
final RegExp _identifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

Future<String> injectSessionState(
  String template,
  ReadonlyContext readonlyContext,
) async {
  final InvocationContext invocationContext = readonlyContext.invocationContext;
  final List<RegExpMatch> matches = _templatePattern
      .allMatches(template)
      .toList(growable: false);
  if (matches.isEmpty) {
    return template;
  }

  final StringBuffer result = StringBuffer();
  int lastEnd = 0;
  for (final RegExpMatch match in matches) {
    result.write(template.substring(lastEnd, match.start));
    result.write(
      await _replaceTemplateMatch(match.group(0) ?? '', invocationContext),
    );
    lastEnd = match.end;
  }
  result.write(template.substring(lastEnd));
  return result.toString();
}

Future<String> _replaceTemplateMatch(
  String rawToken,
  InvocationContext invocationContext,
) async {
  String varName = rawToken.substring(1, rawToken.length - 1).trim();
  bool optional = false;
  if (varName.endsWith('?')) {
    optional = true;
    varName = varName.substring(0, varName.length - 1);
  }

  if (varName.startsWith('artifact.')) {
    final String filename = varName.substring('artifact.'.length);
    if (invocationContext.artifactService == null) {
      throw StateError('Artifact service is not initialized.');
    }

    final Part? artifact = await invocationContext.loadArtifact(
      filename: filename,
    );
    if (artifact == null) {
      if (optional) {
        return '';
      }
      throw StateError('Artifact $filename not found.');
    }
    return _artifactToString(artifact);
  }

  if (!isValidStateName(varName)) {
    return rawToken;
  }

  if (invocationContext.session.state.containsKey(varName)) {
    final Object? value = invocationContext.session.state[varName];
    return value?.toString() ?? '';
  }

  if (optional) {
    return '';
  }
  throw StateError('Context variable not found: `$varName`.');
}

String _artifactToString(Part artifact) {
  if (artifact.text != null) {
    return artifact.text!;
  }
  if (artifact.fileData != null) {
    return artifact.fileData!.fileUri;
  }
  if (artifact.inlineData != null) {
    return 'inline_data:${artifact.inlineData!.mimeType}';
  }
  if (artifact.functionResponse != null) {
    return '${artifact.functionResponse!.response}';
  }
  if (artifact.functionCall != null) {
    return '${artifact.functionCall!.args}';
  }
  if (artifact.codeExecutionResult != null) {
    return '${artifact.codeExecutionResult}';
  }
  if (artifact.executableCode != null) {
    return '${artifact.executableCode}';
  }
  return '';
}

bool isValidStateName(String varName) {
  final List<String> parts = varName.split(':');
  if (parts.length == 1) {
    return _identifierPattern.hasMatch(varName);
  }

  if (parts.length == 2) {
    final String prefix = '${parts[0]}:';
    final bool validPrefix =
        prefix == State.appPrefix ||
        prefix == State.userPrefix ||
        prefix == State.tempPrefix;
    if (!validPrefix) {
      return false;
    }
    return _identifierPattern.hasMatch(parts[1]);
  }

  return false;
}
