enum StreamingMode { none, sse, bidi }

final BigInt _pythonSysMaxSize = BigInt.parse('9223372036854775807');

class ToolThreadPoolConfig {
  ToolThreadPoolConfig({this.maxWorkers = 4}) {
    if (maxWorkers < 1) {
      throw ArgumentError.value(maxWorkers, 'maxWorkers', 'Must be >= 1');
    }
  }

  int maxWorkers;
}

class RunConfig {
  RunConfig({
    this.supportCfc = false,
    this.streamingMode = StreamingMode.none,
    this.maxLlmCalls = 500,
    this.speechConfig,
    this.saveLiveBlob = false,
    this.toolThreadPoolConfig,
    this.responseModalities,
    this.outputAudioTranscription,
    this.inputAudioTranscription,
    this.realtimeInputConfig,
    this.enableAffectiveDialog,
    this.proactivity,
    this.sessionResumption,
    this.contextWindowCompression,
    this.customMetadata,
  }) {
    maxLlmCalls = validateMaxLlmCalls(maxLlmCalls);
  }

  bool supportCfc;
  StreamingMode streamingMode;
  int maxLlmCalls;
  Object? speechConfig;
  bool saveLiveBlob;
  ToolThreadPoolConfig? toolThreadPoolConfig;
  List<String>? responseModalities;
  Object? outputAudioTranscription;
  Object? inputAudioTranscription;
  Object? realtimeInputConfig;
  bool? enableAffectiveDialog;
  Object? proactivity;
  Object? sessionResumption;
  Object? contextWindowCompression;
  Map<String, dynamic>? customMetadata;

  static int validateMaxLlmCalls(int value) {
    if (BigInt.from(value) == _pythonSysMaxSize) {
      throw ArgumentError.value(
        value,
        'maxLlmCalls',
        'maxLlmCalls should be less than $_pythonSysMaxSize.',
      );
    }
    if (value <= 0) {
      print(
        'maxLlmCalls is less than or equal to 0. This will result in no '
        'enforcement on total number of llm calls that will be made for a '
        'run. This may not be ideal, as this could result in a never ending '
        'communication between the model and the agent in certain cases.',
      );
    }
    return value;
  }

  RunConfig copyWith({
    bool? supportCfc,
    StreamingMode? streamingMode,
    int? maxLlmCalls,
    Object? speechConfig = _sentinel,
    bool? saveLiveBlob,
    Object? toolThreadPoolConfig = _sentinel,
    List<String>? responseModalities,
    Object? outputAudioTranscription = _sentinel,
    Object? inputAudioTranscription = _sentinel,
    Object? realtimeInputConfig = _sentinel,
    Object? enableAffectiveDialog = _sentinel,
    Object? proactivity = _sentinel,
    Object? sessionResumption = _sentinel,
    Object? contextWindowCompression = _sentinel,
    Map<String, dynamic>? customMetadata,
  }) {
    return RunConfig(
      supportCfc: supportCfc ?? this.supportCfc,
      streamingMode: streamingMode ?? this.streamingMode,
      maxLlmCalls: maxLlmCalls ?? this.maxLlmCalls,
      speechConfig: identical(speechConfig, _sentinel)
          ? this.speechConfig
          : speechConfig,
      saveLiveBlob: saveLiveBlob ?? this.saveLiveBlob,
      toolThreadPoolConfig: identical(toolThreadPoolConfig, _sentinel)
          ? this.toolThreadPoolConfig == null
                ? null
                : ToolThreadPoolConfig(
                    maxWorkers: this.toolThreadPoolConfig!.maxWorkers,
                  )
          : toolThreadPoolConfig as ToolThreadPoolConfig?,
      responseModalities:
          responseModalities ??
          (this.responseModalities == null
              ? null
              : List<String>.from(this.responseModalities!)),
      outputAudioTranscription: identical(outputAudioTranscription, _sentinel)
          ? this.outputAudioTranscription
          : outputAudioTranscription,
      inputAudioTranscription: identical(inputAudioTranscription, _sentinel)
          ? this.inputAudioTranscription
          : inputAudioTranscription,
      realtimeInputConfig: identical(realtimeInputConfig, _sentinel)
          ? this.realtimeInputConfig
          : realtimeInputConfig,
      enableAffectiveDialog: identical(enableAffectiveDialog, _sentinel)
          ? this.enableAffectiveDialog
          : enableAffectiveDialog as bool?,
      proactivity: identical(proactivity, _sentinel)
          ? this.proactivity
          : proactivity,
      sessionResumption: identical(sessionResumption, _sentinel)
          ? this.sessionResumption
          : sessionResumption,
      contextWindowCompression: identical(contextWindowCompression, _sentinel)
          ? this.contextWindowCompression
          : contextWindowCompression,
      customMetadata:
          customMetadata ??
          (this.customMetadata == null
              ? null
              : Map<String, dynamic>.from(this.customMetadata!)),
    );
  }
}

const Object _sentinel = Object();
