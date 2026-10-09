/// LiteRT-LM model integration for ADK.
///
/// ```dart
/// import 'package:adk_dart/adk_dart.dart';
/// import 'package:adk_litertlm/adk_litertlm.dart';
/// import 'package:litertlm/litertlm.dart';
///
/// final model = LiteRtLmModel.fromConfig(
///   EngineConfig(modelPath: '/path/to/model.litertlm'),
///   model: 'gemma-3-1b',
/// );
/// final agent = LlmAgent(
///   name: 'local_agent',
///   model: model,
///   instruction: 'Help the user locally.',
/// );
/// ```
library;

export 'src/litert_model.dart';
