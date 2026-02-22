import 'dart:collection';

import '../sessions/session.dart';
import '../types/content.dart';
import 'invocation_context.dart';
import 'run_config.dart';

class ReadonlyContext {
  ReadonlyContext(this._invocationContext);

  final InvocationContext _invocationContext;

  InvocationContext get invocationContext => _invocationContext;

  Content? get userContent => _invocationContext.userContent;

  String get invocationId => _invocationContext.invocationId;

  String get agentName => _invocationContext.agent.name;

  Map<String, Object?> get state {
    return UnmodifiableMapView<String, Object?>(
      _invocationContext.session.state,
    );
  }

  Session get session => _invocationContext.session;

  String get userId => _invocationContext.userId;

  RunConfig? get runConfig => _invocationContext.runConfig;
}
