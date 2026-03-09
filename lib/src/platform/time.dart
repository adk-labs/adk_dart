/// Platform helpers for abstracting system time generation.
library;

typedef TimeProvider = double Function();

double _defaultTimeProvider() {
  return DateTime.now().millisecondsSinceEpoch / 1000;
}

TimeProvider _timeProvider = _defaultTimeProvider;

/// Sets the provider used by [getTime].
void setTimeProvider(TimeProvider provider) {
  _timeProvider = provider;
}

/// Restores the default system time provider.
void resetTimeProvider() {
  _timeProvider = _defaultTimeProvider;
}

/// Returns the current time in seconds since the Unix epoch.
double getTime() => _timeProvider();

/// Returns the current UTC time derived from [getTime].
DateTime getUtcNow() {
  return DateTime.fromMicrosecondsSinceEpoch(
    (getTime() * Duration.microsecondsPerSecond).round(),
    isUtc: true,
  );
}
