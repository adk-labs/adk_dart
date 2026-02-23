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
  FunctionCall({required this.name, JsonMap? args, this.id})
    : args = args ?? <String, dynamic>{};

  String name;
  JsonMap args;
  String? id;

  FunctionCall copyWith({String? name, JsonMap? args, Object? id = _sentinel}) {
    return FunctionCall(
      name: name ?? this.name,
      args: args ?? Map<String, dynamic>.from(this.args),
      id: identical(id, _sentinel) ? this.id : id as String?,
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
    this.functionCall,
    this.functionResponse,
    this.inlineData,
    this.fileData,
    this.executableCode,
    this.codeExecutionResult,
  });

  factory Part.text(String text, {bool thought = false}) {
    return Part(text: text, thought: thought);
  }

  factory Part.fromFunctionCall({
    required String name,
    JsonMap? args,
    String? id,
  }) {
    return Part(
      functionCall: FunctionCall(name: name, args: args, id: id),
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
