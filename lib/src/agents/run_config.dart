enum StreamingMode { none, sse, bidi }

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
    this.maxLlmCalls = 0,
    this.saveLiveBlob = false,
    this.toolThreadPoolConfig,
    this.responseModalities,
    this.customMetadata,
  });

  bool supportCfc;
  StreamingMode streamingMode;
  int maxLlmCalls;
  bool saveLiveBlob;
  ToolThreadPoolConfig? toolThreadPoolConfig;
  List<String>? responseModalities;
  Map<String, dynamic>? customMetadata;

  RunConfig copyWith({
    bool? supportCfc,
    StreamingMode? streamingMode,
    int? maxLlmCalls,
    bool? saveLiveBlob,
    Object? toolThreadPoolConfig = _sentinel,
    List<String>? responseModalities,
    Map<String, dynamic>? customMetadata,
  }) {
    return RunConfig(
      supportCfc: supportCfc ?? this.supportCfc,
      streamingMode: streamingMode ?? this.streamingMode,
      maxLlmCalls: maxLlmCalls ?? this.maxLlmCalls,
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
      customMetadata:
          customMetadata ??
          (this.customMetadata == null
              ? null
              : Map<String, dynamic>.from(this.customMetadata!)),
    );
  }
}

const Object _sentinel = Object();
