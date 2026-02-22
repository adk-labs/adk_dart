import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../events/event.dart';
import '../sessions/session.dart';
import '../types/content.dart';
import 'project.dart';
import 'runtime.dart';

Future<HttpServer> startAdkDevWebServer({
  required DevAgentRuntime runtime,
  required DevProjectConfig project,
  int port = 8000,
  InternetAddress? host,
}) async {
  if (port < 0 || port > 65535) {
    throw ArgumentError.value(port, 'port', 'Port must be between 0 and 65535');
  }

  final InternetAddress resolvedHost = host ?? InternetAddress.loopbackIPv4;
  final HttpServer server = await HttpServer.bind(resolvedHost, port);
  unawaited(_handleRequests(server, runtime, project));
  return server;
}

Future<void> _handleRequests(
  HttpServer server,
  DevAgentRuntime runtime,
  DevProjectConfig project,
) async {
  await for (final HttpRequest request in server) {
    try {
      await _handleRequest(request, runtime, project);
    } catch (_) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.internalServerError,
        payload: <String, Object>{'error': 'Internal server error.'},
      );
    }
  }
}

Future<void> _handleRequest(
  HttpRequest request,
  DevAgentRuntime runtime,
  DevProjectConfig project,
) async {
  final String path = request.uri.path;
  switch (path) {
    case '/':
      await _writeHtml(request.response, _buildIndexHtml(project: project));
      return;
    case '/health':
      await _writeJson(
        request.response,
        payload: <String, Object>{
          'status': 'ok',
          'service': 'adk_dart_web',
          'appName': project.appName,
        },
      );
      return;
    case '/api/info':
      await _writeJson(
        request.response,
        payload: <String, Object>{
          'name': 'adk_dart',
          'ui': 'development',
          'appName': project.appName,
          'agentName': project.agentName,
          'description': project.description,
        },
      );
      return;
  }

  if (path == '/api/sessions' && request.method == 'POST') {
    await _handleCreateSession(request, runtime, project);
    return;
  }

  if (path == '/api/sessions' && request.method == 'GET') {
    await _handleListSessions(request, runtime, project);
    return;
  }

  final List<String> segments = request.uri.pathSegments;
  if (segments.length == 4 &&
      segments[0] == 'api' &&
      segments[1] == 'sessions' &&
      segments[3] == 'messages' &&
      request.method == 'POST') {
    await _handlePostMessage(request, runtime, project, sessionId: segments[2]);
    return;
  }

  if (segments.length == 4 &&
      segments[0] == 'api' &&
      segments[1] == 'sessions' &&
      segments[3] == 'events' &&
      request.method == 'GET') {
    await _handleGetEvents(request, runtime, project, sessionId: segments[2]);
    return;
  }

  if (request.method != 'GET' &&
      request.method != 'POST' &&
      request.method != 'OPTIONS') {
    await _writeJson(
      request.response,
      statusCode: HttpStatus.methodNotAllowed,
      payload: <String, Object>{'error': 'Method not allowed.'},
    );
    return;
  }

  if (request.method == 'OPTIONS') {
    await _writeJson(request.response, payload: <String, Object>{});
    return;
  }

  await _writeJson(
    request.response,
    statusCode: HttpStatus.notFound,
    payload: <String, Object>{'error': 'Not found.'},
  );
}

Future<void> _handleCreateSession(
  HttpRequest request,
  DevAgentRuntime runtime,
  DevProjectConfig project,
) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String userId =
      (payload['userId'] as String?)?.trim().isNotEmpty == true
      ? (payload['userId'] as String).trim()
      : project.userId;
  final Session session = await runtime.createSession(userId: userId);

  await _writeJson(
    request.response,
    payload: <String, Object>{
      'session': _sessionToJson(session),
      'events': <Object>[],
    },
  );
}

Future<void> _handleListSessions(
  HttpRequest request,
  DevAgentRuntime runtime,
  DevProjectConfig project,
) async {
  final String userId = request.uri.queryParameters['userId'] ?? project.userId;
  final List<Session> sessions = await runtime.listSessions(userId: userId);

  await _writeJson(
    request.response,
    payload: <String, Object>{
      'sessions': sessions.map<Map<String, Object>>(_sessionToJson).toList(),
    },
  );
}

Future<void> _handlePostMessage(
  HttpRequest request,
  DevAgentRuntime runtime,
  DevProjectConfig project, {
  required String sessionId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String userId =
      (payload['userId'] as String?)?.trim().isNotEmpty == true
      ? (payload['userId'] as String).trim()
      : project.userId;
  final String text = (payload['text'] as String?)?.trim() ?? '';
  if (text.isEmpty) {
    await _writeJson(
      request.response,
      statusCode: HttpStatus.badRequest,
      payload: <String, Object>{'error': 'Message text is required.'},
    );
    return;
  }

  final List<Event> events = await runtime.sendMessage(
    userId: userId,
    sessionId: sessionId,
    message: text,
  );

  String? replyText;
  for (int i = events.length - 1; i >= 0; i -= 1) {
    if (events[i].author != runtime.config.agentName) {
      continue;
    }
    final String textValue = _textFromContent(events[i].content);
    if (textValue.isNotEmpty) {
      replyText = textValue;
      break;
    }
  }

  await _writeJson(
    request.response,
    payload: <String, Object>{
      'sessionId': sessionId,
      'userId': userId,
      'events': events.map<Map<String, Object?>>(_eventToJson).toList(),
      if (replyText != null) 'reply': replyText,
    },
  );
}

Future<void> _handleGetEvents(
  HttpRequest request,
  DevAgentRuntime runtime,
  DevProjectConfig project, {
  required String sessionId,
}) async {
  final String userId = request.uri.queryParameters['userId'] ?? project.userId;
  final Session? session = await runtime.getSession(
    userId: userId,
    sessionId: sessionId,
  );
  if (session == null) {
    await _writeJson(
      request.response,
      statusCode: HttpStatus.notFound,
      payload: <String, Object>{'error': 'Session not found.'},
    );
    return;
  }

  await _writeJson(
    request.response,
    payload: <String, Object>{
      'session': _sessionToJson(session),
      'events': session.events.map<Map<String, Object?>>(_eventToJson).toList(),
    },
  );
}

Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
  if (request.method == 'GET') {
    return <String, dynamic>{};
  }
  final String body = await utf8.decoder.bind(request).join();
  if (body.trim().isEmpty) {
    return <String, dynamic>{};
  }

  final Object? decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }

  throw const FormatException('Request JSON body must be an object.');
}

Map<String, Object> _sessionToJson(Session session) {
  return <String, Object>{
    'id': session.id,
    'appName': session.appName,
    'userId': session.userId,
    'lastUpdateTime': session.lastUpdateTime,
  };
}

Map<String, Object?> _eventToJson(Event event) {
  return <String, Object?>{
    'id': event.id,
    'invocationId': event.invocationId,
    'author': event.author,
    'timestamp': event.timestamp,
    'partial': event.partial,
    'content': _contentToJson(event.content),
    'actions': <String, Object?>{
      'transferToAgent': event.actions.transferToAgent,
      'escalate': event.actions.escalate,
      'skipSummarization': event.actions.skipSummarization,
      'endOfAgent': event.actions.endOfAgent,
      'rewindBeforeInvocationId': event.actions.rewindBeforeInvocationId,
      'stateDelta': event.actions.stateDelta,
      'artifactDelta': event.actions.artifactDelta,
    },
  };
}

Map<String, Object?>? _contentToJson(Content? content) {
  if (content == null) {
    return null;
  }
  return <String, Object?>{
    'role': content.role,
    'parts': content.parts.map<Map<String, Object?>>((Part part) {
      return <String, Object?>{
        'text': part.text,
        'thought': part.thought,
        'functionCall': part.functionCall == null
            ? null
            : <String, Object?>{
                'name': part.functionCall!.name,
                'args': part.functionCall!.args,
                'id': part.functionCall!.id,
              },
        'functionResponse': part.functionResponse == null
            ? null
            : <String, Object?>{
                'name': part.functionResponse!.name,
                'response': part.functionResponse!.response,
                'id': part.functionResponse!.id,
              },
      };
    }).toList(),
  };
}

String _textFromContent(Content? content) {
  if (content == null) {
    return '';
  }
  final List<String> lines = <String>[];
  for (final Part part in content.parts) {
    if (part.text != null && part.text!.trim().isNotEmpty) {
      lines.add(part.text!.trim());
    }
  }
  return lines.join('\n');
}

Future<void> _writeHtml(HttpResponse response, String html) async {
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = ContentType.html;
  response.write(html);
  await response.close();
}

Future<void> _writeJson(
  HttpResponse response, {
  required Map<String, Object> payload,
  int statusCode = HttpStatus.ok,
}) async {
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(payload));
  await response.close();
}

String _buildIndexHtml({required DevProjectConfig project}) {
  final String title = _escapeHtml(project.appName);
  final String description = _escapeHtml(project.description);

  return '''
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>ADK Dart Web</title>
    <style>
      :root {
        --bg-1: #fef6e4;
        --bg-2: #d3f3ee;
        --ink: #202124;
        --muted: #46535f;
        --panel: #fffaf2;
        --accent: #0f766e;
        --accent-dark: #115e59;
        --edge: #d7d0c5;
      }
      * {
        box-sizing: border-box;
      }
      body {
        margin: 0;
        min-height: 100vh;
        color: var(--ink);
        font-family: "Avenir Next", "Futura", "Trebuchet MS", sans-serif;
        background:
          radial-gradient(circle at 10% -10%, var(--bg-1), transparent 40%),
          radial-gradient(circle at 90% 0%, var(--bg-2), transparent 35%),
          #f2f0ea;
      }
      .layout {
        max-width: 920px;
        margin: 0 auto;
        padding: 28px 16px 36px;
      }
      .hero {
        background: linear-gradient(140deg, #fffaf1, #f7fffd);
        border: 1px solid var(--edge);
        border-radius: 16px;
        padding: 18px 20px;
        box-shadow: 0 12px 28px rgba(17, 24, 39, 0.08);
        animation: slide-up 320ms ease-out;
      }
      .hero h1 {
        margin: 0;
        font-size: clamp(22px, 3.8vw, 34px);
        letter-spacing: 0.02em;
      }
      .hero p {
        margin: 8px 0 0;
        color: var(--muted);
      }
      .chat {
        margin-top: 16px;
        background: var(--panel);
        border: 1px solid var(--edge);
        border-radius: 16px;
        padding: 14px;
        box-shadow: 0 18px 28px rgba(17, 24, 39, 0.06);
      }
      .meta {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
        font-size: 13px;
        color: var(--muted);
        margin-bottom: 10px;
      }
      #messages {
        min-height: 320px;
        max-height: 54vh;
        overflow: auto;
        display: flex;
        flex-direction: column;
        gap: 10px;
        padding: 8px;
        background: #fff;
        border: 1px solid #eee5d8;
        border-radius: 12px;
      }
      .msg {
        padding: 9px 11px;
        border-radius: 10px;
        border: 1px solid transparent;
        line-height: 1.42;
        animation: fade-in 160ms ease-out;
      }
      .msg.user {
        background: #ebfffa;
        border-color: #b8efe3;
        align-self: flex-end;
      }
      .msg.agent {
        background: #f8f7ff;
        border-color: #ddd6fe;
        align-self: flex-start;
      }
      .msg.system {
        background: #fff9db;
        border-color: #ffe28c;
      }
      form {
        margin-top: 12px;
        display: grid;
        grid-template-columns: 1fr auto;
        gap: 10px;
      }
      input[type="text"] {
        border: 1px solid #d6cdc2;
        border-radius: 10px;
        padding: 12px;
        font-size: 15px;
        background: #fffefb;
      }
      input[type="text"]:focus {
        outline: 2px solid #8fd9cd;
        border-color: #8fd9cd;
      }
      button {
        border: 0;
        border-radius: 10px;
        padding: 0 16px;
        background: var(--accent);
        color: white;
        font-weight: 600;
        cursor: pointer;
      }
      button:hover {
        background: var(--accent-dark);
      }
      @keyframes fade-in {
        from { opacity: 0; transform: translateY(4px); }
        to { opacity: 1; transform: translateY(0); }
      }
      @keyframes slide-up {
        from { opacity: 0; transform: translateY(8px); }
        to { opacity: 1; transform: translateY(0); }
      }
      @media (max-width: 640px) {
        .layout { padding-top: 14px; }
        #messages { min-height: 280px; max-height: 52vh; }
      }
    </style>
  </head>
  <body>
    <main class="layout">
      <section class="hero">
        <h1>$title</h1>
        <p>$description</p>
      </section>
      <section class="chat">
        <div class="meta">
          <span id="session">session: (creating...)</span>
          <span>agent: ${_escapeHtml(project.agentName)}</span>
          <span>service: adk_dart_web</span>
        </div>
        <div id="messages"></div>
        <form id="form">
          <input type="text" id="prompt" placeholder="Ask a question..." autocomplete="off" />
          <button type="submit">Send</button>
        </form>
      </section>
    </main>
    <script>
      const state = { userId: ${jsonEncode(project.userId)}, sessionId: null };
      const messages = document.getElementById('messages');
      const sessionText = document.getElementById('session');
      const form = document.getElementById('form');
      const promptInput = document.getElementById('prompt');

      function addMessage(kind, text) {
        const el = document.createElement('div');
        el.className = `msg \${kind}`;
        el.textContent = text;
        messages.appendChild(el);
        messages.scrollTop = messages.scrollHeight;
      }

      async function createSession() {
        const response = await fetch('/api/sessions', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({ userId: state.userId }),
        });
        const data = await response.json();
        state.sessionId = data.session.id;
        sessionText.textContent = `session: \${state.sessionId}`;
        addMessage('system', 'Session created. Ask for time in a city.');
      }

      async function sendMessage(text) {
        if (!state.sessionId) return;
        const url = `/api/sessions/\${state.sessionId}/messages`;
        const response = await fetch(url, {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({ userId: state.userId, text }),
        });
        const data = await response.json();
        if (!response.ok) {
          addMessage('system', data.error || 'Request failed.');
          return;
        }
        const reply = data.reply || '(no text response)';
        addMessage('agent', reply);
      }

      form.addEventListener('submit', async (event) => {
        event.preventDefault();
        const text = promptInput.value.trim();
        if (!text) return;
        addMessage('user', text);
        promptInput.value = '';
        promptInput.focus();
        await sendMessage(text);
      });

      createSession().catch((error) => {
        addMessage('system', `Failed to create session: \${error}`);
      });
    </script>
  </body>
</html>
''';
}

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
