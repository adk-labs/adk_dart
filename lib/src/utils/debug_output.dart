import '../events/event.dart';
import '../types/content.dart';

const int _argsMaxLen = 50;
const int _responseMaxLen = 100;
const int _codeOutputMaxLen = 100;

String _truncate(String text, int maxLen) {
  if (text.length <= maxLen) {
    return text;
  }
  return '${text.substring(0, maxLen)}...';
}

String _codeLanguage(Object? executableCode) {
  if (executableCode is Map) {
    final Object? language = executableCode['language'];
    if (language != null) {
      return '$language';
    }
  }
  return 'code';
}

String _codeOutput(Object? codeExecutionResult) {
  if (codeExecutionResult is Map) {
    final Object? output =
        codeExecutionResult['output'] ?? codeExecutionResult['result'];
    if (output != null) {
      return '$output';
    }
  }
  if (codeExecutionResult != null) {
    return '$codeExecutionResult';
  }
  return 'result';
}

void printEvent(
  Event event, {
  bool verbose = false,
  void Function(String line)? sink,
}) {
  final Content? content = event.content;
  if (content == null || content.parts.isEmpty) {
    return;
  }

  final void Function(String line) output = sink ?? print;
  final List<String> textBuffer = <String>[];

  void flushText() {
    if (textBuffer.isEmpty) {
      return;
    }
    output('${event.author} > ${textBuffer.join()}');
    textBuffer.clear();
  }

  for (final Part part in content.parts) {
    if (part.text != null) {
      textBuffer.add(part.text!);
      continue;
    }

    flushText();

    if (!verbose) {
      continue;
    }

    if (part.functionCall != null) {
      output(
        '${event.author} > [Calling tool: ${part.functionCall!.name}'
        '(${_truncate('${part.functionCall!.args}', _argsMaxLen)})]',
      );
      continue;
    }

    if (part.functionResponse != null) {
      output(
        '${event.author} > [Tool result: '
        '${_truncate('${part.functionResponse!.response}', _responseMaxLen)}]',
      );
      continue;
    }

    if (part.executableCode != null) {
      output(
        '${event.author} > [Executing ${_codeLanguage(part.executableCode)} code...]',
      );
      continue;
    }

    if (part.codeExecutionResult != null) {
      output(
        '${event.author} > [Code output: '
        '${_truncate(_codeOutput(part.codeExecutionResult), _codeOutputMaxLen)}]',
      );
      continue;
    }

    if (part.inlineData != null) {
      final String mimeType = part.inlineData!.mimeType;
      output('${event.author} > [Inline data: $mimeType]');
      continue;
    }

    if (part.fileData != null) {
      output('${event.author} > [File: ${part.fileData!.fileUri}]');
    }
  }

  flushText();
}
