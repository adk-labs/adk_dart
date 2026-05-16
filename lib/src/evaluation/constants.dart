/// Shared constants used by evaluation module integrations.
library;

/// The guidance message shown when evaluation dependencies are unavailable.
const String missingEvalDependenciesMessage =
    'Eval module is not installed, please install via '
    '`pip install "google-adk[eval]"`.';

/// Timeout for waiting for live model turn completion during eval inference.
const int defaultLiveTimeoutSeconds = 300;
