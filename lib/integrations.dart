/// External cloud, platform, and third-party service integrations.
///
/// Exports connectors and toolsets for Google Cloud (BigQuery, Firestore,
/// GCS, Secret Manager, Parameter Manager, Model Armor), OpenAI, LiveKit,
/// ElevenLabs, MongoDB, Redis, E2B, OpenSandbox, and Slack.
///
/// ```dart
/// import 'package:adk_dart/integrations.dart';
/// ```
library;

export 'src/integrations/_iam_connectors/gcp_auth_provider.dart';
export 'src/integrations/_iam_connectors/gcp_iam_connector_auth.dart';
export 'src/integrations/agent_identity/agent_identity.dart'
    hide GcpAuthProvider, GcpAuthProviderScheme;
export 'src/integrations/agent_registry/agent_registry.dart';
export 'src/integrations/bigquery/bigquery.dart';
export 'src/integrations/e2b/e2b_environment.dart';
export 'src/integrations/eleven_labs/eleven_labs.dart';
export 'src/integrations/eventarc/eventarc.dart';
export 'src/integrations/firestore/firestore.dart';
export 'src/integrations/fsspec/fsspec.dart';
export 'src/integrations/gcs/gcs.dart';
export 'src/integrations/livekit/livekit.dart';
export 'src/integrations/model_armor/model_armor.dart';
export 'src/integrations/mongodb/mongodb.dart';
export 'src/integrations/oci/oci.dart';
export 'src/integrations/openai/openai.dart';
export 'src/integrations/openai/openai_decisions_classifier.dart';
export 'src/integrations/opensandbox/opensandbox_environment.dart';
export 'src/integrations/parameter_manager/parameter_manager.dart';
export 'src/integrations/redis/redis.dart';
export 'src/integrations/secret_manager/secret_manager.dart'
    hide resolveDefaultGoogleAccessToken;
export 'src/integrations/skill_registry/gcp_skill_registry.dart';
export 'src/integrations/slack/slack_runner.dart';
export 'src/integrations/teams/teams.dart';
export 'src/integrations/typesafe/typesafe_classifier.dart';
export 'src/integrations/vmaas/agent_engine_client.dart';
export 'src/integrations/vmaas/agent_engine_environment.dart';
