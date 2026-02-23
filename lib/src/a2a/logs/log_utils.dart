import 'dart:convert';

import '../protocol.dart';

const String _newLine = '\n';

String buildMessagePartLog(A2aPart part) {
  final A2aPartRoot root = part.root;
  String content;

  if (root is A2aTextPart) {
    final String text = root.text;
    content =
        'TextPart: ${text.length > 100 ? '${text.substring(0, 100)}...' : text}';
  } else if (root is A2aDataPart) {
    final Map<String, Object?> summary = <String, Object?>{};
    root.data.forEach((String key, Object? value) {
      if ((value is Map || value is List) && '$value'.length > 100) {
        summary[key] = '<${value.runtimeType}>';
      } else {
        summary[key] = value;
      }
    });
    content = 'DataPart: ${jsonEncode(summary)}';
  } else if (root is A2aFilePart) {
    if (root.file is A2aFileWithUri) {
      final A2aFileWithUri file = root.file as A2aFileWithUri;
      content = 'FilePart(uri=${file.uri}, mime=${file.mimeType ?? ''})';
    } else if (root.file is A2aFileWithBytes) {
      final A2aFileWithBytes file = root.file as A2aFileWithBytes;
      content =
          'FilePart(bytes=${file.bytes.length}, mime=${file.mimeType ?? ''})';
    } else {
      content = 'FilePart(${root.file.runtimeType})';
    }
  } else {
    content = '${root.runtimeType}';
  }

  if (root.metadata.isNotEmpty) {
    content = '$content\n    Part Metadata: ${jsonEncode(root.metadata)}';
  }

  return content;
}

String buildA2aRequestLog(A2aMessage request) {
  final List<String> messagePartsLogs = <String>[];
  for (int i = 0; i < request.parts.length; i += 1) {
    final String partLog = buildMessagePartLog(
      request.parts[i],
    ).replaceAll('\n', '\n  ');
    messagePartsLogs.add('Part $i: $partLog');
  }

  final String metadataSection = request.metadata.isEmpty
      ? ''
      : '''
  Metadata:
  ${jsonEncode(request.metadata)}''';

  return '''
A2A Send Message Request:
-----------------------------------------------------------
Message:
  ID: ${request.messageId}
  Role: ${request.role}
  Task ID: ${request.taskId}
  Context ID: ${request.contextId}$metadataSection
-----------------------------------------------------------
Message Parts:
${messagePartsLogs.isEmpty ? 'No parts' : messagePartsLogs.join(_newLine)}
-----------------------------------------------------------
''';
}

String buildA2aResponseLog(Object response) {
  final List<String> resultDetails = <String>[];
  String statusMessageSection = 'None';
  String historySection = 'No history';

  if (response is A2aTask) {
    resultDetails.addAll(<String>[
      'Task ID: ${response.id}',
      'Context ID: ${response.contextId}',
      'Status State: ${response.status.state}',
      'Status Timestamp: ${response.status.timestamp}',
      'History Length: ${response.history.length}',
      'Artifacts Count: ${response.artifacts.length}',
    ]);

    if (response.metadata.isNotEmpty) {
      resultDetails.add('Task Metadata: ${jsonEncode(response.metadata)}');
    }

    final A2aMessage? statusMessage = response.status.message;
    if (statusMessage != null) {
      final List<String> partLogs = <String>[];
      for (int i = 0; i < statusMessage.parts.length; i += 1) {
        partLogs.add(
          'Part $i: ${buildMessagePartLog(statusMessage.parts[i]).replaceAll('\n', '\n  ')}',
        );
      }
      statusMessageSection =
          '''ID: ${statusMessage.messageId}
Role: ${statusMessage.role}
Task ID: ${statusMessage.taskId}
Context ID: ${statusMessage.contextId}
Message Parts:
${partLogs.isEmpty ? 'No parts' : partLogs.join(_newLine)}''';
      if (statusMessage.metadata.isNotEmpty) {
        statusMessageSection =
            '$statusMessageSection\nMetadata:\n${jsonEncode(statusMessage.metadata)}';
      }
    }

    if (response.history.isNotEmpty) {
      final List<String> entries = <String>[];
      for (int i = 0; i < response.history.length; i += 1) {
        final A2aMessage message = response.history[i];
        final List<String> partLogs = <String>[];
        for (int j = 0; j < message.parts.length; j += 1) {
          partLogs.add(
            '  Part $j: ${buildMessagePartLog(message.parts[j]).replaceAll('\n', '\n    ')}',
          );
        }
        entries.add('''Message ${i + 1}:
  ID: ${message.messageId}
  Role: ${message.role}
  Task ID: ${message.taskId}
  Context ID: ${message.contextId}
  Message Parts:
${partLogs.isEmpty ? '  No parts' : partLogs.join(_newLine)}''');
      }
      historySection = entries.join(_newLine);
    }
  } else if (response is A2aMessage) {
    resultDetails.addAll(<String>[
      'Message ID: ${response.messageId}',
      'Role: ${response.role}',
      'Task ID: ${response.taskId}',
      'Context ID: ${response.contextId}',
    ]);

    if (response.parts.isNotEmpty) {
      resultDetails.add('Message Parts:');
      for (int i = 0; i < response.parts.length; i += 1) {
        resultDetails.add(
          '  Part $i: ${buildMessagePartLog(response.parts[i]).replaceAll('\n', '\n    ')}',
        );
      }
    }

    if (response.metadata.isNotEmpty) {
      resultDetails.add('Metadata: ${jsonEncode(response.metadata)}');
    }
  } else {
    resultDetails.add('Data: $response');
  }

  return '''
A2A Response:
-----------------------------------------------------------
Type: SUCCESS
Result Type: ${response.runtimeType}
-----------------------------------------------------------
Result Details:
${resultDetails.join(_newLine)}
-----------------------------------------------------------
Status Message:
$statusMessageSection
-----------------------------------------------------------
History:
$historySection
-----------------------------------------------------------
''';
}
