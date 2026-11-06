/// Microsoft Teams integration runner for ADK agents.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../../errors/already_exists_error.dart';
import '../../events/event.dart';
import '../../runners/runner.dart';
import '../../sessions/session.dart';
import '../../types/content.dart';

const String _errorReply =
    'Sorry, something went wrong while handling your message.';
const int _maxSessionLocks = 1024;

/// Derives a deterministic, URL/path-safe ADK session ID from a Teams
/// [conversationId].
///
/// Returns `'teams-<32 hex chars of SHA-256>'`.
String sessionIdForConversation(String conversationId) {
  final String digest = crypto.sha256
      .convert(utf8.encode(conversationId))
      .toString()
      .substring(0, 32);
  return 'teams-$digest';
}

/// Handler invoked by a [TeamsAgentApplication] for an incoming Teams activity.
typedef TeamsActivityHandler =
    Future<void> Function(TeamsTurnContext context, [Object? state]);

/// Minimal representation of an incoming or outgoing Microsoft Teams activity.
class TeamsActivity {
  /// Creates a [TeamsActivity].
  const TeamsActivity({
    this.type = 'message',
    this.text,
    this.fromId,
    this.conversationId,
  });

  /// Deserializes a [TeamsActivity] from a JSON map.
  factory TeamsActivity.fromJson(Map<String, Object?> json) {
    final Object? fromObj = json['from'] ?? json['from_property'];
    final Object? convObj = json['conversation'];
    return TeamsActivity(
      type: (json['type'] as String?) ?? 'message',
      text: json['text'] as String?,
      fromId: fromObj is Map
          ? (fromObj['id'] as String?)
          : (json['fromId'] as String?),
      conversationId: convObj is Map
          ? (convObj['id'] as String?)
          : (json['conversationId'] as String?),
    );
  }

  /// Activity type (for example `'message'` or `'typing'`).
  final String type;

  /// Message text payload, if any.
  final String? text;

  /// Sender user identifier (`from.id`).
  final String? fromId;

  /// Conversation identifier (`conversation.id`).
  final String? conversationId;

  /// Serializes this activity to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    if (text != null) 'text': text,
    if (fromId != null) 'from': <String, Object?>{'id': fromId},
    if (conversationId != null)
      'conversation': <String, Object?>{'id': conversationId},
  };
}

/// Turn context passed to [TeamsActivityHandler] callbacks.
abstract class TeamsTurnContext {
  /// Incoming activity for the current turn.
  TeamsActivity get activity;

  /// Sends a reply [activityOrText] (`String` or [TeamsActivity]) to the
  /// conversation.
  Future<Object?> sendActivity(Object activityOrText);
}

/// Default in-memory [TeamsTurnContext] implementation.
class SimpleTeamsTurnContext implements TeamsTurnContext {
  /// Creates a [SimpleTeamsTurnContext] for [activity].
  SimpleTeamsTurnContext({
    required this.activity,
    Future<Object?> Function(Object activityOrText)? onSendActivity,
  }) : _onSendActivity = onSendActivity;

  @override
  final TeamsActivity activity;

  final Future<Object?> Function(Object activityOrText)? _onSendActivity;

  /// Activities sent during this turn (`String` or [TeamsActivity]).
  final List<Object> sentActivities = <Object>[];

  @override
  Future<Object?> sendActivity(Object activityOrText) async {
    sentActivities.add(activityOrText);
    if (_onSendActivity != null) {
      return _onSendActivity(activityOrText);
    }
    return null;
  }
}

/// Minimal contract for a Microsoft Agents SDK `AgentApplication`.
abstract class TeamsAgentApplication {
  /// Adapter used to process incoming HTTP requests, if available.
  Object? get adapter => null;

  /// Registers [handler] for activities of [activityType] (e.g. `'message'`).
  void registerActivityHandler(
    String activityType,
    TeamsActivityHandler handler,
  );
}

/// In-memory [TeamsAgentApplication] implementation for local servers and tests.
class SimpleTeamsAgentApplication extends TeamsAgentApplication {
  final Map<String, List<TeamsActivityHandler>> _handlers =
      <String, List<TeamsActivityHandler>>{};

  /// Registered handlers keyed by activity type.
  Map<String, List<TeamsActivityHandler>> get handlers =>
      Map<String, List<TeamsActivityHandler>>.unmodifiable(_handlers);

  @override
  void registerActivityHandler(
    String activityType,
    TeamsActivityHandler handler,
  ) {
    _handlers
        .putIfAbsent(activityType, () => <TeamsActivityHandler>[])
        .add(handler);
  }

  /// Decorator-style registration matching Python's `agent_app.activity("message")`.
  TeamsActivityHandler Function(TeamsActivityHandler handler) activity(
    String activityType,
  ) {
    return (TeamsActivityHandler handler) {
      registerActivityHandler(activityType, handler);
      return handler;
    };
  }

  /// Dispatches [context] to all handlers registered for `context.activity.type`.
  Future<void> dispatch(TeamsTurnContext context, [Object? state]) async {
    final List<TeamsActivityHandler>? list = _handlers[context.activity.type];
    if (list == null) {
      return;
    }
    for (final TeamsActivityHandler handler in list) {
      await handler(context, state);
    }
  }
}

/// HTTP application wrapper created by [TeamsRunner.createApp].
class TeamsHttpApp {
  /// Creates a [TeamsHttpApp].
  TeamsHttpApp({
    required this.agentApp,
    required this.authConfiguration,
    required Future<void> Function(TeamsTurnContext context, [Object? state])
    onMessage,
  }) : _onMessage = onMessage;

  /// Underlying Teams agent application.
  final TeamsAgentApplication agentApp;

  /// Authentication configuration bound to the `/api/messages` endpoint.
  final Object? authConfiguration;

  final Future<void> Function(TeamsTurnContext context, [Object? state])
  _onMessage;

  /// Handles a decoded JSON activity payload on `/api/messages`.
  Future<List<Object>> handleMessagesPayload(
    Map<String, Object?> payload,
  ) async {
    final TeamsActivity activity = TeamsActivity.fromJson(payload);
    final SimpleTeamsTurnContext context = SimpleTeamsTurnContext(
      activity: activity,
    );
    if (agentApp is SimpleTeamsAgentApplication) {
      await (agentApp as SimpleTeamsAgentApplication).dispatch(context);
    } else if (activity.type == 'message') {
      await _onMessage(context);
    }
    return context.sentActivities;
  }
}

class _AsyncMutex {
  Future<void>? _active;

  bool get isLocked => _active != null;

  Future<T> synchronized<T>(Future<T> Function() action) async {
    while (_active != null) {
      try {
        await _active;
      } catch (_) {}
    }
    final Completer<void> completer = Completer<void>();
    _active = completer.future;
    try {
      return await action();
    } finally {
      _active = null;
      completer.complete();
    }
  }
}

/// Connects an ADK [Runner] to a Microsoft Teams [TeamsAgentApplication].
///
/// Registers a `'message'` activity handler that forwards user messages to
/// [runner], sends a typing indicator, and streams non-partial, non-thought
/// text replies back via [TeamsTurnContext.sendActivity].
class TeamsRunner {
  /// Initializes [TeamsRunner] and registers message handlers on [agentApp].
  TeamsRunner(this.runner, this.agentApp) {
    _registerHandlers();
  }

  /// Underlying ADK [Runner] that executes the agent.
  final Runner runner;

  /// Teams [TeamsAgentApplication] receiving incoming activities.
  final TeamsAgentApplication agentApp;

  final Set<Future<void>> _backgroundTasks = <Future<void>>{};
  final LinkedHashMap<(String, String), _AsyncMutex> _sessionLocks =
      LinkedHashMap<(String, String), _AsyncMutex>();

  /// Currently running background reply futures.
  Set<Future<void>> get backgroundTasks =>
      Set<Future<void>>.unmodifiable(_backgroundTasks);

  /// Waits for all currently scheduled background reply tasks to complete.
  Future<void> waitForBackgroundTasks() async {
    while (_backgroundTasks.isNotEmpty) {
      await Future.wait(List<Future<void>>.from(_backgroundTasks));
    }
  }

  void _registerHandlers() {
    agentApp.registerActivityHandler('message', _onMessage);
  }

  _AsyncMutex _getSessionLock((String, String) key) {
    final _AsyncMutex? existing = _sessionLocks.remove(key);
    if (existing != null) {
      _sessionLocks[key] = existing;
      return existing;
    }
    final _AsyncMutex lock = _AsyncMutex();
    _sessionLocks[key] = lock;
    if (_sessionLocks.length > _maxSessionLocks) {
      final List<(String, String)> keys = _sessionLocks.keys.toList(
        growable: false,
      );
      for (final (String, String) k in keys) {
        if (k == key) {
          continue;
        }
        final _AsyncMutex? candidate = _sessionLocks[k];
        if (candidate != null && !candidate.isLocked) {
          _sessionLocks.remove(k);
          break;
        }
      }
    }
    return lock;
  }

  Future<void> _onMessage(TeamsTurnContext context, [Object? state]) async {
    final TeamsActivity activity = context.activity;
    final String text = (activity.text ?? '').trim();
    if (text.isEmpty) {
      return;
    }
    final String? userId = activity.fromId;
    final String? conversationId = activity.conversationId;
    if (userId == null ||
        userId.isEmpty ||
        conversationId == null ||
        conversationId.isEmpty) {
      return;
    }
    final String sessionId = sessionIdForConversation(conversationId);

    late final Future<void> task;
    task = _replyInBackground(context, userId, sessionId, text).whenComplete(
      () {
        _backgroundTasks.remove(task);
      },
    );
    _backgroundTasks.add(task);
  }

  Future<void> _replyInBackground(
    TeamsTurnContext context,
    String userId,
    String sessionId,
    String text,
  ) async {
    final _AsyncMutex lock = _getSessionLock((userId, sessionId));
    await lock.synchronized(() async {
      try {
        await context.sendActivity(const TeamsActivity(type: 'typing'));

        Session? session = await runner.sessionService.getSession(
          appName: runner.appName,
          userId: userId,
          sessionId: sessionId,
        );
        if (session == null) {
          try {
            session = await runner.sessionService.createSession(
              appName: runner.appName,
              userId: userId,
              sessionId: sessionId,
            );
          } on AlreadyExistsError {
            session = await runner.sessionService.getSession(
              appName: runner.appName,
              userId: userId,
              sessionId: sessionId,
            );
          } catch (_) {
            session = await runner.sessionService.getSession(
              appName: runner.appName,
              userId: userId,
              sessionId: sessionId,
            );
          }
          if (session == null) {
            throw StateError(
              'Failed to create or load session $sessionId for user $userId',
            );
          }
        }

        final Content userContent = Content(
          role: 'user',
          parts: <Part>[Part.text(text)],
        );

        bool sentReply = false;
        String? errorCode;
        await for (final Event event in runner.runAsync(
          userId: userId,
          sessionId: session.id,
          newMessage: userContent,
        )) {
          if (event.partial == true) {
            continue;
          }
          if (event.content != null && event.content!.parts.isNotEmpty) {
            for (final Part part in event.content!.parts) {
              if (part.text != null &&
                  part.text!.isNotEmpty &&
                  !part.thought) {
                await context.sendActivity(part.text!);
                sentReply = true;
              }
            }
          }
          if (event.errorCode != null) {
            errorCode = event.errorCode;
          }
        }

        if (!sentReply && errorCode != null) {
          await context.sendActivity(_errorReply);
        }
      } catch (_) {
        try {
          await context.sendActivity(_errorReply);
        } catch (_) {}
      }
    });
  }

  /// Creates a [TeamsHttpApp] wired to `/api/messages` with [authConfiguration].
  TeamsHttpApp createApp(Object? authConfiguration) {
    return TeamsHttpApp(
      agentApp: agentApp,
      authConfiguration: authConfiguration,
      onMessage: _onMessage,
    );
  }

  /// Starts an HTTP server listening on [host]:[port] for `/api/messages`.
  Future<HttpServer> start(
    Object? authConfiguration, {
    String host = 'localhost',
    int port = 3978,
  }) async {
    final TeamsHttpApp app = createApp(authConfiguration);
    final HttpServer server = await HttpServer.bind(host, port);
    server.listen((HttpRequest request) async {
      if (request.method == 'POST' && request.uri.path == '/api/messages') {
        try {
          final String body = await utf8.decoder.bind(request).join();
          final Object? decoded = body.isEmpty ? null : jsonDecode(body);
          if (decoded is Map) {
            final Map<String, Object?> map = <String, Object?>{
              for (final MapEntry<Object?, Object?> e in decoded.entries)
                '${e.key}': e.value,
            };
            await app.handleMessagesPayload(map);
          }
          request.response.statusCode = HttpStatus.ok;
        } catch (_) {
          request.response.statusCode = HttpStatus.internalServerError;
        } finally {
          await request.response.close();
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    return server;
  }
}
