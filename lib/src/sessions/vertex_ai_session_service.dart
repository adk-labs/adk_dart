import '../events/event.dart';
import 'base_session_service.dart';
import 'in_memory_session_service.dart';
import 'session.dart';

class VertexAiSessionService extends BaseSessionService {
  VertexAiSessionService({
    String? project,
    String? location,
    String? agentEngineId,
    String? expressModeApiKey,
  }) : _project = project,
       _location = location,
       _agentEngineId = agentEngineId,
       _expressModeApiKey = expressModeApiKey;

  final String? _project;
  final String? _location;
  final String? _agentEngineId;
  final String? _expressModeApiKey;
  final InMemorySessionService _delegate = InMemorySessionService();

  String? get project => _project;
  String? get location => _location;
  String? get expressModeApiKey => _expressModeApiKey;

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    if (sessionId != null && sessionId.isNotEmpty) {
      throw ArgumentError(
        'User-provided Session id is not supported for VertexAiSessionService.',
      );
    }
    _getReasoningEngineId(appName);
    return _delegate.createSession(
      appName: appName,
      userId: userId,
      state: state,
      sessionId: null,
    );
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) {
    _getReasoningEngineId(appName);
    return _delegate.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      config: config,
    );
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) {
    _getReasoningEngineId(appName);
    return _delegate.listSessions(appName: appName, userId: userId);
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) {
    _getReasoningEngineId(appName);
    return _delegate.deleteSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  @override
  Future<Event> appendEvent({required Session session, required Event event}) {
    _getReasoningEngineId(session.appName);
    return _delegate.appendEvent(session: session, event: event);
  }

  String _getReasoningEngineId(String appName) {
    if (_agentEngineId != null && _agentEngineId.isNotEmpty) {
      return _agentEngineId;
    }
    if (RegExp(r'^\d+$').hasMatch(appName)) {
      return appName;
    }
    final RegExp pattern = RegExp(
      r'^projects\/([a-zA-Z0-9-_]+)\/locations\/([a-zA-Z0-9-_]+)\/reasoningEngines\/(\d+)$',
    );
    final Match? match = pattern.firstMatch(appName);
    if (match == null) {
      throw ArgumentError(
        'App name $appName is not valid. It should either be the full '
        'ReasoningEngine resource name, or the reasoning engine id.',
      );
    }
    return match.group(3)!;
  }
}
