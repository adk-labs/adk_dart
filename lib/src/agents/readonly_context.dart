/// Read-only invocation context exposed to agents and tools.
library;

import 'dart:collection';

import '../sessions/session.dart';
import '../types/content.dart';
import 'invocation_context.dart';
import 'run_config.dart';

/// Immutable view over [InvocationContext] data.
class ReadonlyContext {
  /// Creates a read-only view backed by [_invocationContext].
  ReadonlyContext(this._invocationContext);

  final InvocationContext _invocationContext;

  /// Underlying invocation context.
  InvocationContext get invocationContext => _invocationContext;

  /// Latest user-authored content for this turn.
  Content? get userContent => _invocationContext.userContent;

  /// Invocation identifier for this run.
  String get invocationId => _invocationContext.invocationId;

  /// Active agent name.
  String get agentName => _invocationContext.agent.name;

  /// Read-only session state snapshot.
  Map<String, Object?> get state {
    return UnmodifiableMapView<String, Object?>(
      _invocationContext.session.state,
    );
  }

  /// Current session object.
  Session get session => _invocationContext.session;

  /// Active end-user identifier.
  String get userId => _invocationContext.userId;

  /// Optional run configuration for this invocation.
  RunConfig? get runConfig => _invocationContext.runConfig;
}
