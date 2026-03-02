/// JSON-compatible map type used across model and tool payloads.
typedef JsonMap = Map<String, dynamic>;

/// Inline binary payload attached to a [Part].
class InlineData {
  /// Creates inline binary data.
  InlineData({required this.mimeType, required this.data, this.displayName});

  /// MIME type for [data].
  String mimeType;

  /// Raw binary bytes.
  List<int> data;

  /// Optional display label.
  String? displayName;

  /// Returns a copy of this inline payload with optional overrides.
  InlineData copyWith({
    String? mimeType,
    List<int>? data,
    Object? displayName = _sentinel,
  }) {
    return InlineData(
      mimeType: mimeType ?? this.mimeType,
      data: data ?? List<int>.from(this.data),
      displayName: identical(displayName, _sentinel)
          ? this.displayName
          : displayName as String?,
    );
  }
}

/// File reference payload attached to a [Part].
class FileData {
  /// Creates file reference data.
  FileData({required this.fileUri, this.mimeType, this.displayName});

  /// URI for the remote or local file resource.
  String fileUri;

  /// Optional MIME type for the file.
  String? mimeType;

  /// Optional display label.
  String? displayName;

  /// Returns a copy of this file payload with optional overrides.
  FileData copyWith({
    String? fileUri,
    Object? mimeType = _sentinel,
    Object? displayName = _sentinel,
  }) {
    return FileData(
      fileUri: fileUri ?? this.fileUri,
      mimeType: identical(mimeType, _sentinel)
          ? this.mimeType
          : mimeType as String?,
      displayName: identical(displayName, _sentinel)
          ? this.displayName
          : displayName as String?,
    );
  }
}

/// Function-call payload emitted by model responses.
class FunctionCall {
  /// Creates a function-call payload.
  FunctionCall({
    required this.name,
    JsonMap? args,
    this.id,
    List<Map<String, Object?>>? partialArgs,
    this.willContinue,
  }) : args = args ?? <String, dynamic>{},
       partialArgs = partialArgs
           ?.map((Map<String, Object?> item) => Map<String, Object?>.from(item))
           .toList(growable: false);

  /// Function name requested by the model.
  String name;

  /// Function arguments payload.
  JsonMap args;

  /// Optional tool-call identifier.
  String? id;

  /// Optional partial argument deltas from streaming calls.
  List<Map<String, Object?>>? partialArgs;

  /// Whether additional streaming call chunks are expected.
  bool? willContinue;

  /// Returns a copy of this function-call payload.
  FunctionCall copyWith({
    String? name,
    JsonMap? args,
    Object? id = _sentinel,
    Object? partialArgs = _sentinel,
    Object? willContinue = _sentinel,
  }) {
    return FunctionCall(
      name: name ?? this.name,
      args: args ?? Map<String, dynamic>.from(this.args),
      id: identical(id, _sentinel) ? this.id : id as String?,
      partialArgs: identical(partialArgs, _sentinel)
          ? this.partialArgs
                ?.map(
                  (Map<String, Object?> item) =>
                      Map<String, Object?>.from(item),
                )
                .toList(growable: false)
          : partialArgs as List<Map<String, Object?>>?,
      willContinue: identical(willContinue, _sentinel)
          ? this.willContinue
          : willContinue as bool?,
    );
  }
}

/// Function-response payload sent back to the model.
class FunctionResponse {
  /// Creates a function-response payload.
  FunctionResponse({required this.name, JsonMap? response, this.id})
    : response = response ?? <String, dynamic>{};

  /// Function name this response corresponds to.
  String name;

  /// Function response body.
  JsonMap response;

  /// Optional tool-call identifier.
  String? id;

  /// Returns a copy of this function-response payload.
  FunctionResponse copyWith({
    String? name,
    JsonMap? response,
    Object? id = _sentinel,
  }) {
    return FunctionResponse(
      name: name ?? this.name,
      response: response ?? Map<String, dynamic>.from(this.response),
      id: identical(id, _sentinel) ? this.id : id as String?,
    );
  }
}

/// One multimodal content part within a [Content] turn.
class Part {
  /// Creates a content part.
  Part({
    this.text,
    this.thought = false,
    this.thoughtSignature,
    this.functionCall,
    this.functionResponse,
    this.inlineData,
    this.fileData,
    this.executableCode,
    this.codeExecutionResult,
  });

  /// Creates a text [Part].
  factory Part.text(
    String text, {
    bool thought = false,
    List<int>? thoughtSignature,
  }) {
    return Part(
      text: text,
      thought: thought,
      thoughtSignature: thoughtSignature == null
          ? null
          : List<int>.from(thoughtSignature),
    );
  }

  /// Creates a function-call [Part].
  factory Part.fromFunctionCall({
    required String name,
    JsonMap? args,
    String? id,
    List<Map<String, Object?>>? partialArgs,
    bool? willContinue,
    List<int>? thoughtSignature,
  }) {
    return Part(
      functionCall: FunctionCall(
        name: name,
        args: args,
        id: id,
        partialArgs: partialArgs,
        willContinue: willContinue,
      ),
      thoughtSignature: thoughtSignature == null
          ? null
          : List<int>.from(thoughtSignature),
    );
  }

  /// Creates a function-response [Part].
  factory Part.fromFunctionResponse({
    required String name,
    JsonMap? response,
    String? id,
  }) {
    return Part(
      functionResponse: FunctionResponse(
        name: name,
        response: response,
        id: id,
      ),
    );
  }

  /// Creates an inline-data [Part].
  factory Part.fromInlineData({
    required String mimeType,
    required List<int> data,
    String? displayName,
  }) {
    return Part(
      inlineData: InlineData(
        mimeType: mimeType,
        data: List<int>.from(data),
        displayName: displayName,
      ),
    );
  }

  /// Creates a file-data [Part].
  factory Part.fromFileData({
    required String fileUri,
    String? mimeType,
    String? displayName,
  }) {
    return Part(
      fileData: FileData(
        fileUri: fileUri,
        mimeType: mimeType,
        displayName: displayName,
      ),
    );
  }

  /// Optional plain text payload.
  String? text;

  /// Whether this part is model thought text.
  bool thought;

  /// Optional thought signature bytes for traceability.
  List<int>? thoughtSignature;

  /// Optional function-call payload.
  FunctionCall? functionCall;

  /// Optional function-response payload.
  FunctionResponse? functionResponse;

  /// Optional inline binary payload.
  InlineData? inlineData;

  /// Optional file reference payload.
  FileData? fileData;

  /// Optional executable code payload.
  Object? executableCode;

  /// Optional code execution result payload.
  Object? codeExecutionResult;

  /// Whether this part contains non-empty text.
  bool get hasText => text != null && text!.isNotEmpty;

  /// Returns a copy of this part with optional overrides.
  Part copyWith({
    Object? text = _sentinel,
    bool? thought,
    Object? thoughtSignature = _sentinel,
    Object? functionCall = _sentinel,
    Object? functionResponse = _sentinel,
    Object? inlineData = _sentinel,
    Object? fileData = _sentinel,
    Object? executableCode = _sentinel,
    Object? codeExecutionResult = _sentinel,
  }) {
    return Part(
      text: identical(text, _sentinel) ? this.text : text as String?,
      thought: thought ?? this.thought,
      thoughtSignature: identical(thoughtSignature, _sentinel)
          ? (this.thoughtSignature == null
                ? null
                : List<int>.from(this.thoughtSignature!))
          : thoughtSignature as List<int>?,
      functionCall: identical(functionCall, _sentinel)
          ? this.functionCall?.copyWith()
          : functionCall as FunctionCall?,
      functionResponse: identical(functionResponse, _sentinel)
          ? this.functionResponse?.copyWith()
          : functionResponse as FunctionResponse?,
      inlineData: identical(inlineData, _sentinel)
          ? this.inlineData?.copyWith()
          : inlineData as InlineData?,
      fileData: identical(fileData, _sentinel)
          ? this.fileData?.copyWith()
          : fileData as FileData?,
      executableCode: identical(executableCode, _sentinel)
          ? this.executableCode
          : executableCode,
      codeExecutionResult: identical(codeExecutionResult, _sentinel)
          ? this.codeExecutionResult
          : codeExecutionResult,
    );
  }
}

/// One conversation turn consisting of a role and [Part] list.
class Content {
  /// Creates conversation content.
  Content({this.role, List<Part>? parts}) : parts = parts ?? <Part>[];

  /// Creates a user-text content turn.
  factory Content.userText(String text) {
    return Content(role: 'user', parts: [Part.text(text)]);
  }

  /// Creates a model-text content turn.
  factory Content.modelText(String text) {
    return Content(role: 'model', parts: [Part.text(text)]);
  }

  /// Role for this turn, for example `user` or `model`.
  String? role;

  /// Parts included in this turn.
  List<Part> parts;

  /// Whether this content has no parts.
  bool get isEmpty => parts.isEmpty;

  /// Returns a copy of this content with optional overrides.
  Content copyWith({Object? role = _sentinel, List<Part>? parts}) {
    return Content(
      role: identical(role, _sentinel) ? this.role : role as String?,
      parts: parts ?? this.parts.map((part) => part.copyWith()).toList(),
    );
  }
}

const Object _sentinel = Object();
