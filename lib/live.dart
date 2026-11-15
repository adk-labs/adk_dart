/// Live streaming and multimodal bidirectional execution primitives.
///
/// Provides [CascadeLive], [GeminiSTT], [GeminiTTS], [LiveIngress],
/// [LiveEgress], [LiveRequestQueue], and typed [IngressEvent] / [EgressEvent]
/// streams for low-latency voice and multimodal agent pipelines.
///
/// ```dart
/// import 'package:adk_dart/live.dart';
///
/// final model = CascadeLive(
///   model: 'gemini-2.5-flash',
///   stt: GeminiSTT(),
///   tts: GeminiTTS(),
/// );
/// ```
///
/// @docImport 'src/agents/live_request_queue.dart';
/// @docImport 'src/live/cascade_live.dart';
/// @docImport 'src/live/cascade_live_events.dart';
/// @docImport 'src/live/gemini_stt.dart';
/// @docImport 'src/live/gemini_tts.dart';
/// @docImport 'src/live/transforms.dart';
library;

export 'src/live/live.dart';
