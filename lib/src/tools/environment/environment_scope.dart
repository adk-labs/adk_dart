/// Scopes an environment can keep its resources in.
library;

/// Which agent runs share one resource of an environment.
///
/// A resource is whatever `initialize` sets up, such as a sandbox or a
/// working directory.
enum EnvironmentScope {
  /// All runs that use the environment instance share one resource.
  shared('shared'),

  /// Each user has their own resource, shared by all sessions of the user.
  user('user'),

  /// Each session has its own resource.
  session('session');

  /// Creates an environment scope with its string [value].
  const EnvironmentScope(this.value);

  /// String identifier matching upstream Python (`"shared"`, `"user"`, `"session"`).
  final String value;
}
