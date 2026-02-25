typedef JsonMap = Map<String, dynamic>;

class InlineData {
  InlineData({required this.mimeType, required this.data, this.displayName});

  String mimeType;
  List<int> data;
  String? displayName;

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

class FileData {
  FileData({required this.fileUri, this.mimeType, this.displayName});

  String fileUri;
  String? mimeType;
  String? displayName;

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

class FunctionCall {
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

  String name;
  JsonMap args;
  String? id;
  List<Map<String, Object?>>? partialArgs;
  bool? willContinue;

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

class FunctionResponse {
  FunctionResponse({required this.name, JsonMap? response, this.id})
    : response = response ?? <String, dynamic>{};

  String name;
  JsonMap response;
  String? id;

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

class Part {
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

  String? text;
  bool thought;
  List<int>? thoughtSignature;
  FunctionCall? functionCall;
  FunctionResponse? functionResponse;
  InlineData? inlineData;
  FileData? fileData;
  Object? executableCode;
  Object? codeExecutionResult;

  bool get hasText => text != null && text!.isNotEmpty;

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

class Content {
  Content({this.role, List<Part>? parts}) : parts = parts ?? <Part>[];

  factory Content.userText(String text) {
    return Content(role: 'user', parts: [Part.text(text)]);
  }

  factory Content.modelText(String text) {
    return Content(role: 'model', parts: [Part.text(text)]);
  }

  String? role;
  List<Part> parts;

  bool get isEmpty => parts.isEmpty;

  Content copyWith({Object? role = _sentinel, List<Part>? parts}) {
    return Content(
      role: identical(role, _sentinel) ? this.role : role as String?,
      parts: parts ?? this.parts.map((part) => part.copyWith()).toList(),
    );
  }
}

const Object _sentinel = Object();
