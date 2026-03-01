import '../flows/llm_flows/audio_transcriber.dart';
import 'bigquery/client.dart';
import 'bigtable/client.dart';
import 'spanner/client.dart';
import 'spanner/utils.dart';
import 'toolbox_toolset.dart';

/// Registers commonly injected runtime adapters in one place.
///
/// This is a convenience bootstrap API that wires the existing low-level
/// registration hooks used by ADK tool integrations.
void configureToolRuntimeBootstrap({
  BigQueryClientFactory? bigQueryClientFactory,
  BigtableAdminClientFactory? bigtableAdminClientFactory,
  BigtableDataClientFactory? bigtableDataClientFactory,
  SpannerClientFactory? spannerClientFactory,
  SpannerEmbedder? spannerEmbedder,
  SpannerEmbedderAsync? spannerEmbedderAsync,
  ToolboxToolsetDelegateFactory? toolboxDelegateFactory,
  AudioRecognizer? defaultAudioRecognizer,
}) {
  if (bigQueryClientFactory != null) {
    setBigQueryClientFactory(bigQueryClientFactory);
  }
  if (bigtableAdminClientFactory != null || bigtableDataClientFactory != null) {
    setBigtableClientFactories(
      adminClientFactory: bigtableAdminClientFactory,
      dataClientFactory: bigtableDataClientFactory,
    );
  }
  if (spannerClientFactory != null) {
    setSpannerClientFactory(spannerClientFactory);
  }
  if (spannerEmbedder != null || spannerEmbedderAsync != null) {
    setSpannerEmbedders(
      embedder: spannerEmbedder,
      embedderAsync: spannerEmbedderAsync,
    );
  }
  if (toolboxDelegateFactory != null) {
    ToolboxToolset.registerDefaultDelegateFactory(toolboxDelegateFactory);
  }
  if (defaultAudioRecognizer != null) {
    AudioTranscriber.registerDefaultRecognizer(defaultAudioRecognizer);
  }
}

/// Resets bootstrap registrations back to package defaults.
void resetToolRuntimeBootstrap({
  bool resetBigQuery = true,
  bool resetBigtable = true,
  bool resetSpannerClient = true,
  bool resetSpannerEmbeddersRuntime = true,
  bool clearToolboxDelegate = true,
  bool clearDefaultAudioRecognizer = true,
}) {
  if (resetBigQuery) {
    resetBigQueryClientFactory();
  }
  if (resetBigtable) {
    resetBigtableClientFactories();
  }
  if (resetSpannerClient) {
    resetSpannerClientFactory();
  }
  if (resetSpannerEmbeddersRuntime) {
    resetSpannerEmbedders();
  }
  if (clearToolboxDelegate) {
    ToolboxToolset.clearDefaultDelegateFactory();
  }
  if (clearDefaultAudioRecognizer) {
    AudioTranscriber.clearDefaultRecognizer();
  }
}
