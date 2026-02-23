import 'dart:convert';

import '../../types/content.dart';
import '../protocol.dart';
import 'utils.dart';

const String a2aDataPartMetadataTypeKey = 'type';
const String a2aDataPartMetadataIsLongRunningKey = 'is_long_running';
const String a2aDataPartMetadataTypeFunctionCall = 'function_call';
const String a2aDataPartMetadataTypeFunctionResponse = 'function_response';
const String a2aDataPartMetadataTypeCodeExecutionResult =
    'code_execution_result';
const String a2aDataPartMetadataTypeExecutableCode = 'executable_code';
const String a2aDataPartTextMimeType = 'text/plain';
final List<int> a2aDataPartStartTag = utf8.encode('<a2a_datapart_json>');
final List<int> a2aDataPartEndTag = utf8.encode('</a2a_datapart_json>');

typedef A2APartToGenAIPartConverter = Object? Function(A2aPart part);
typedef GenAIPartToA2APartConverter = Object? Function(Part part);

Object? convertA2aPartToGenaiPart(A2aPart a2aPart) {
  final A2aPartRoot root = a2aPart.root;

  if (root is A2aTextPart) {
    return Part.text(root.text);
  }

  if (root is A2aFilePart) {
    final A2aFile file = root.file;
    if (file is A2aFileWithUri) {
      return Part.fromFileData(fileUri: file.uri, mimeType: file.mimeType);
    }
    if (file is A2aFileWithBytes) {
      List<int> bytes;
      try {
        bytes = base64Decode(file.bytes);
      } catch (_) {
        bytes = utf8.encode(file.bytes);
      }
      return Part.fromInlineData(
        mimeType: file.mimeType ?? 'application/octet-stream',
        data: bytes,
      );
    }
    return null;
  }

  if (root is A2aDataPart) {
    final String metadataKey = getAdkMetadataKey(a2aDataPartMetadataTypeKey);
    final String? type = root.metadata[metadataKey] as String?;

    if (type == a2aDataPartMetadataTypeFunctionCall) {
      final String name = '${root.data['name'] ?? ''}';
      final Map<String, dynamic> args = _asMap(root.data['args']);
      final String? id = root.data['id'] as String?;
      if (name.isNotEmpty) {
        return Part.fromFunctionCall(name: name, args: args, id: id);
      }
    }

    if (type == a2aDataPartMetadataTypeFunctionResponse) {
      final String name = '${root.data['name'] ?? ''}';
      final Map<String, dynamic> response = _asMap(root.data['response']);
      final String? id = root.data['id'] as String?;
      if (name.isNotEmpty) {
        return Part.fromFunctionResponse(
          name: name,
          response: response,
          id: id,
        );
      }
    }

    if (type == a2aDataPartMetadataTypeCodeExecutionResult) {
      return Part(codeExecutionResult: Map<String, Object?>.from(root.data));
    }

    if (type == a2aDataPartMetadataTypeExecutableCode) {
      return Part(executableCode: Map<String, Object?>.from(root.data));
    }

    final List<int> encodedData = <int>[
      ...a2aDataPartStartTag,
      ...utf8.encode(
        jsonEncode(<String, Object?>{
          'data': root.data,
          'metadata': root.metadata,
        }),
      ),
      ...a2aDataPartEndTag,
    ];

    return Part.fromInlineData(
      mimeType: a2aDataPartTextMimeType,
      data: encodedData,
    );
  }

  return null;
}

Object? convertGenaiPartToA2aPart(Part part) {
  if (part.text != null) {
    final Map<String, Object?> metadata = <String, Object?>{};
    if (part.thought) {
      metadata[getAdkMetadataKey('thought')] = true;
    }
    return A2aPart.text(part.text!, metadata: metadata);
  }

  if (part.fileData != null) {
    final FileData file = part.fileData!;
    return A2aPart.fileUri(file.fileUri, mimeType: file.mimeType);
  }

  if (part.inlineData != null) {
    final InlineData blob = part.inlineData!;
    final List<int> data = blob.data;
    if (blob.mimeType == a2aDataPartTextMimeType &&
        _startsWith(data, a2aDataPartStartTag) &&
        _endsWith(data, a2aDataPartEndTag)) {
      final int start = a2aDataPartStartTag.length;
      final int end = data.length - a2aDataPartEndTag.length;
      final String payload = utf8.decode(data.sublist(start, end));
      final Map<String, Object?> json = _asMapObject(jsonDecode(payload));
      return A2aPart.data(
        _asMapObject(json['data']),
        metadata: _asMapObject(json['metadata']),
      );
    }

    return A2aPart.fileBytes(
      base64Encode(data),
      mimeType: blob.mimeType,
      metadata: <String, Object?>{
        if (blob.displayName != null)
          getAdkMetadataKey('display_name'): blob.displayName,
      },
    );
  }

  if (part.functionCall != null) {
    final FunctionCall call = part.functionCall!;
    return A2aPart.data(
      <String, Object?>{
        'name': call.name,
        'args': Map<String, Object?>.from(call.args),
        if (call.id != null) 'id': call.id,
      },
      metadata: <String, Object?>{
        getAdkMetadataKey(a2aDataPartMetadataTypeKey):
            a2aDataPartMetadataTypeFunctionCall,
      },
    );
  }

  if (part.functionResponse != null) {
    final FunctionResponse response = part.functionResponse!;
    return A2aPart.data(
      <String, Object?>{
        'name': response.name,
        'response': Map<String, Object?>.from(response.response),
        if (response.id != null) 'id': response.id,
      },
      metadata: <String, Object?>{
        getAdkMetadataKey(a2aDataPartMetadataTypeKey):
            a2aDataPartMetadataTypeFunctionResponse,
      },
    );
  }

  if (part.codeExecutionResult != null) {
    return A2aPart.data(
      _asMapObject(part.codeExecutionResult),
      metadata: <String, Object?>{
        getAdkMetadataKey(a2aDataPartMetadataTypeKey):
            a2aDataPartMetadataTypeCodeExecutionResult,
      },
    );
  }

  if (part.executableCode != null) {
    return A2aPart.data(
      _asMapObject(part.executableCode),
      metadata: <String, Object?>{
        getAdkMetadataKey(a2aDataPartMetadataTypeKey):
            a2aDataPartMetadataTypeExecutableCode,
      },
    );
  }

  return null;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? value) {
      return MapEntry<String, dynamic>('${key ?? ''}', value);
    });
  }
  return <String, dynamic>{};
}

Map<String, Object?> _asMapObject(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? value) {
      return MapEntry<String, Object?>('${key ?? ''}', value);
    });
  }
  return <String, Object?>{};
}

bool _startsWith(List<int> value, List<int> prefix) {
  if (value.length < prefix.length) {
    return false;
  }
  for (int i = 0; i < prefix.length; i += 1) {
    if (value[i] != prefix[i]) {
      return false;
    }
  }
  return true;
}

bool _endsWith(List<int> value, List<int> suffix) {
  if (value.length < suffix.length) {
    return false;
  }
  final int offset = value.length - suffix.length;
  for (int i = 0; i < suffix.length; i += 1) {
    if (value[offset + i] != suffix[i]) {
      return false;
    }
  }
  return true;
}
