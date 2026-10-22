/// LiveKit WebRTC & SIP telephony integration for ADK live agents.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../agents/live_request_queue.dart';
import '../../agents/readonly_context.dart';
import '../../agents/run_config.dart';
import '../../events/event.dart';
import '../../runners/runner.dart';
import '../../sessions/session.dart';
import '../../tools/base_tool.dart';
import '../../tools/base_toolset.dart';
import '../../tools/function_tool.dart';
import '../../tools/tool_context.dart';
import '../../types/content.dart';
import '../../types/id.dart';

/// LiveKit text stream topic for chat messages.
const String lkChatTopic = 'lk.chat';

/// Python-style alias for [lkChatTopic].
// ignore: constant_identifier_names
const String LK_CHAT_TOPIC = lkChatTopic;

/// LiveKit data packet and text stream topic for structured ADK parts.
const String dataTopic = 'adk';

/// Python-style alias for [dataTopic].
// ignore: constant_identifier_names
const String DATA_TOPIC = dataTopic;

/// LiveKit text stream topic for live speech transcriptions.
const String lkTranscriptionTopic = 'lk.transcription';

/// Python-style alias for [lkTranscriptionTopic].
// ignore: constant_identifier_names
const String LK_TRANSCRIPTION_TOPIC = lkTranscriptionTopic;

/// SIP participant attribute key for the caller's phone number.
const String sipPhoneNumberAttribute = 'sip.phoneNumber';

/// SIP participant attribute key for the trunk/called phone number.
const String sipTrunkPhoneNumberAttribute = 'sip.trunkPhoneNumber';

/// SIP participant attribute key for the SIP call identifier.
const String sipCallIdAttribute = 'sip.callID';

/// SIP participant attribute key for the SIP call status.
const String sipCallStatusAttribute = 'sip.callStatus';

/// Default output audio sample rate (Hz) for Gemini Live models.
const int defaultLiveKitSampleRate = 24000;

/// Default output audio channel count (mono).
const int defaultLiveKitChannels = 1;

/// Default video frame sampling rate (frames per second).
const double defaultLiveKitVideoFps = 1.0;

/// Participant attribute key used by LiveKit clients to display agent state.
const String agentStateAttribute = 'lk.agent.state';

/// DTMF code-to-digit mapping per RFC 4733.
const Map<String, int> dtmfCodes = <String, int>{
  '0': 0,
  '1': 1,
  '2': 2,
  '3': 3,
  '4': 4,
  '5': 5,
  '6': 6,
  '7': 7,
  '8': 8,
  '9': 9,
  '*': 10,
  '#': 11,
  'A': 12,
  'B': 13,
  'C': 14,
  'D': 15,
};

/// Kinds of participants in a LiveKit room.
enum LiveKitParticipantKind {
  /// Standard WebRTC browser or native client participant.
  standard,

  /// Ingress stream participant.
  ingress,

  /// Egress recorder participant.
  egress,

  /// SIP telephony bridge participant.
  sip,

  /// AI agent participant.
  agent,
}

/// Represents a participant connected to a LiveKit room.
///
/// ```dart
/// final sipCaller = LiveKitParticipant(
///   identity: 'sip_+15551234567',
///   kind: LiveKitParticipantKind.sip,
///   attributes: <String, String>{'sip.phoneNumber': '+15551234567'},
/// );
/// ```
class LiveKitParticipant {
  /// Creates a [LiveKitParticipant].
  LiveKitParticipant({
    required this.identity,
    this.kind = LiveKitParticipantKind.standard,
    Map<String, String>? attributes,
    this.audioTrackSid,
  }) : attributes = Map<String, String>.from(
         attributes ?? const <String, String>{},
       );

  /// Unique participant identity inside the room.
  final String identity;

  /// Participant kind (e.g., [LiveKitParticipantKind.sip]).
  final LiveKitParticipantKind kind;

  /// Participant metadata attributes.
  final Map<String, String> attributes;

  /// Optional SID of the participant's published microphone audio track.
  final String? audioTrackSid;
}

/// Writer handle for an open LiveKit text stream (e.g. `lk.transcription`).
abstract interface class LiveKitTextStreamWriter {
  /// Writes incremental [text] to the open text stream.
  Future<void> write(String text);

  /// Closes the text stream.
  Future<void> close();
}

/// In-memory implementation of [LiveKitTextStreamWriter].
class InMemoryLiveKitTextStreamWriter implements LiveKitTextStreamWriter {
  /// Creates an [InMemoryLiveKitTextStreamWriter].
  InMemoryLiveKitTextStreamWriter({
    required this.topic,
    Map<String, String>? attributes,
  }) : attributes = Map<String, String>.unmodifiable(
         attributes ?? const <String, String>{},
       );

  /// Topic name on which the text stream was opened.
  final String topic;

  /// Attributes attached when opening the text stream.
  final Map<String, String> attributes;

  /// Chunks written to this stream.
  final List<String> chunks = <String>[];

  /// Whether [close] has been called.
  bool isClosed = false;

  @override
  Future<void> write(String text) async {
    if (isClosed) {
      throw StateError('TextStreamWriter is already closed.');
    }
    chunks.add(text);
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }
}

/// Recorded DTMF event published by a participant.
class LiveKitDtmfEvent {
  /// Creates a [LiveKitDtmfEvent].
  const LiveKitDtmfEvent({
    required this.code,
    required this.digit,
    this.participantIdentity,
  });

  /// RFC 4733 numeric event code (`0`–`15`).
  final int code;

  /// Single DTMF character (`0`–`9`, `*`, `#`, `A`–`D`).
  final String digit;

  /// Optional sender participant identity.
  final String? participantIdentity;
}

/// Recorded data packet published to or received from a LiveKit room.
class LiveKitDataPacket {
  /// Creates a [LiveKitDataPacket].
  LiveKitDataPacket({
    required List<int> data,
    this.topic = dataTopic,
    this.reliable = true,
    this.participantIdentity,
  }) : data = Uint8List.fromList(data);

  /// Raw packet payload bytes.
  final Uint8List data;

  /// Packet topic.
  final String topic;

  /// Whether reliable WebRTC data channel delivery was requested.
  final bool reliable;

  /// Optional sender participant identity.
  final String? participantIdentity;
}

/// Inbound text message received on a LiveKit text stream topic.
class LiveKitChatMessage {
  /// Creates a [LiveKitChatMessage].
  const LiveKitChatMessage({
    required this.text,
    this.topic = lkChatTopic,
    this.participantIdentity,
  });

  /// Full text read from the text stream.
  final String text;

  /// Topic name (e.g. `lk.chat` or `adk`).
  final String topic;

  /// Sender participant identity.
  final String? participantIdentity;
}

/// Raw PCM audio frame transmitted over LiveKit.
class LiveKitAudioFrame {
  /// Creates a [LiveKitAudioFrame].
  LiveKitAudioFrame({
    required List<int> data,
    this.sampleRate = defaultLiveKitSampleRate,
    this.numChannels = defaultLiveKitChannels,
    int? samplesPerChannel,
    this.participantIdentity,
    this.trackSid,
  }) : data = Uint8List.fromList(data),
       samplesPerChannel =
           samplesPerChannel ?? (data.length ~/ (2 * defaultLiveKitChannels));

  /// Raw 16-bit signed little-endian PCM bytes.
  final Uint8List data;

  /// Audio sample rate in Hz.
  final int sampleRate;

  /// Number of audio channels.
  final int numChannels;

  /// Number of samples per channel in [data].
  final int samplesPerChannel;

  /// Optional source participant identity.
  final String? participantIdentity;

  /// Optional source audio track SID.
  final String? trackSid;
}

/// Video frame captured from a remote participant track.
class LiveKitVideoFrame {
  /// Creates a [LiveKitVideoFrame].
  LiveKitVideoFrame({
    required List<int> jpegBytes,
    this.participantIdentity,
    this.trackSid,
  }) : jpegBytes = Uint8List.fromList(jpegBytes);

  /// Encoded JPEG bytes for the video frame.
  final Uint8List jpegBytes;

  /// Optional source participant identity.
  final String? participantIdentity;

  /// Optional source video track SID.
  final String? trackSid;
}

/// Local participant interface for publishing tracks, data, DTMF, and RPCs.
abstract interface class LiveKitLocalParticipant {
  /// Local participant identity.
  String get identity;

  /// Current local participant attributes.
  Map<String, String> get attributes;

  /// Updates metadata [attributes] on the local participant.
  Future<void> setAttributes(Map<String, String> attributes);

  /// Publishes a single DTMF tone with RFC 4733 [code] and [digit].
  Future<void> publishDtmf({required int code, required String digit});

  /// Performs an RPC call on a remote participant identified by [destinationIdentity].
  Future<String> performRpc({
    required String destinationIdentity,
    required String method,
    required String payload,
    double? responseTimeout,
  });

  /// Publishes raw [payload] bytes on [topic].
  Future<void> publishData(
    List<int> payload, {
    required String topic,
    bool reliable = true,
  });

  /// Sends a single text message on [topic].
  Future<void> sendText(
    String text, {
    required String topic,
    Map<String, String>? attributes,
  });

  /// Opens a streaming text writer on [topic] with optional [attributes].
  Future<LiveKitTextStreamWriter> streamText({
    required String topic,
    Map<String, String>? attributes,
  });
}

/// In-memory implementation of [LiveKitLocalParticipant].
class InMemoryLiveKitLocalParticipant implements LiveKitLocalParticipant {
  /// Creates an [InMemoryLiveKitLocalParticipant].
  InMemoryLiveKitLocalParticipant({
    this.identity = 'adk-agent',
    Future<String> Function({
      required String destinationIdentity,
      required String method,
      required String payload,
      double? responseTimeout,
    })?
    rpcHandler,
  }) : _rpcHandler = rpcHandler;

  @override
  final String identity;

  final Map<String, String> _attributes = <String, String>{};

  /// Recorded DTMF tones published by the local participant.
  final List<LiveKitDtmfEvent> publishedDtmf = <LiveKitDtmfEvent>[];

  /// Recorded data packets published by the local participant.
  final List<LiveKitDataPacket> publishedData = <LiveKitDataPacket>[];

  /// Recorded text stream writers opened by the local participant.
  final List<InMemoryLiveKitTextStreamWriter> textStreams =
      <InMemoryLiveKitTextStreamWriter>[];

  /// Recorded one-shot texts sent via [sendText].
  final List<({String text, String topic, Map<String, String> attributes})>
  sentTexts = <({String text, String topic, Map<String, String> attributes})>[];

  /// Recorded RPC invocations issued via [performRpc].
  final List<
    ({
      String destinationIdentity,
      String method,
      String payload,
      double? responseTimeout,
    })
  >
  rpcCalls =
      <
        ({
          String destinationIdentity,
          String method,
          String payload,
          double? responseTimeout,
        })
      >[];

  final Future<String> Function({
    required String destinationIdentity,
    required String method,
    required String payload,
    double? responseTimeout,
  })?
  _rpcHandler;

  @override
  Map<String, String> get attributes =>
      Map<String, String>.unmodifiable(_attributes);

  @override
  Future<void> setAttributes(Map<String, String> attributes) async {
    _attributes.addAll(attributes);
  }

  @override
  Future<void> publishDtmf({required int code, required String digit}) async {
    publishedDtmf.add(
      LiveKitDtmfEvent(
        code: code,
        digit: digit,
        participantIdentity: identity,
      ),
    );
  }

  @override
  Future<String> performRpc({
    required String destinationIdentity,
    required String method,
    required String payload,
    double? responseTimeout,
  }) async {
    rpcCalls.add((
      destinationIdentity: destinationIdentity,
      method: method,
      payload: payload,
      responseTimeout: responseTimeout,
    ));
    if (_rpcHandler != null) {
      return _rpcHandler(
        destinationIdentity: destinationIdentity,
        method: method,
        payload: payload,
        responseTimeout: responseTimeout,
      );
    }
    return '';
  }

  @override
  Future<void> publishData(
    List<int> payload, {
    required String topic,
    bool reliable = true,
  }) async {
    publishedData.add(
      LiveKitDataPacket(
        data: payload,
        topic: topic,
        reliable: reliable,
        participantIdentity: identity,
      ),
    );
  }

  @override
  Future<void> sendText(
    String text, {
    required String topic,
    Map<String, String>? attributes,
  }) async {
    sentTexts.add((
      text: text,
      topic: topic,
      attributes: Map<String, String>.from(
        attributes ?? const <String, String>{},
      ),
    ));
  }

  @override
  Future<LiveKitTextStreamWriter> streamText({
    required String topic,
    Map<String, String>? attributes,
  }) async {
    final InMemoryLiveKitTextStreamWriter writer =
        InMemoryLiveKitTextStreamWriter(topic: topic, attributes: attributes);
    textStreams.add(writer);
    return writer;
  }
}

/// Abstract client representing a LiveKit room and its server-side SIP/Room APIs.
///
/// ```dart
/// final room = InMemoryLiveKitRoomClient(name: 'support-room');
/// ```
abstract interface class LiveKitRoomClient {
  /// Room name.
  String get name;

  /// Local agent participant.
  LiveKitLocalParticipant get localParticipant;

  /// Remote participants currently in the room, keyed by identity.
  Map<String, LiveKitParticipant> get remoteParticipants;

  /// Connects the room to [url] with [token].
  Future<void> connect(String url, String token);

  /// Disconnects from the room.
  Future<void> disconnect();

  /// Publishes a local audio output track at [sampleRate] and [channels],
  /// returning its track SID.
  Future<String> publishAudioOutputTrack({
    int sampleRate = defaultLiveKitSampleRate,
    int channels = defaultLiveKitChannels,
  });

  /// Captures an output [frame] onto the published local audio source.
  Future<void> captureAudioFrame(LiveKitAudioFrame frame);

  /// Clears buffered audio frames on interruption.
  void clearAudioBuffer();

  /// Waits for all queued audio frames to finish playing out.
  Future<void> waitForAudioPlayout();

  /// Transfers a SIP participant to [transferTo] (e.g. `tel:+15551234567`).
  Future<void> transferSipParticipant({
    required String roomName,
    required String participantIdentity,
    required String transferTo,
  });

  /// Deletes the LiveKit room on the server, disconnecting all participants.
  Future<void> deleteRoom(String roomName);

  /// Inbound audio frames from remote participants.
  Stream<LiveKitAudioFrame> get onAudioFrame;

  /// Inbound video frames from remote participants.
  Stream<LiveKitVideoFrame> get onVideoFrame;

  /// Inbound text stream messages (e.g. `lk.chat` or `adk`).
  Stream<LiveKitChatMessage> get onTextMessage;

  /// Inbound raw data packets.
  Stream<LiveKitDataPacket> get onDataReceived;

  /// Inbound SIP DTMF events.
  Stream<LiveKitDtmfEvent> get onDtmfReceived;

  /// Emits when the room disconnects.
  Stream<String?> get onDisconnected;
}

/// In-memory implementation of [LiveKitRoomClient] for testing and local runs.
///
/// ```dart
/// final room = InMemoryLiveKitRoomClient(name: 'room-1');
/// room.addRemoteParticipant(
///   LiveKitParticipant(
///     identity: 'caller-1',
///     kind: LiveKitParticipantKind.sip,
///     attributes: <String, String>{'sip.phoneNumber': '+15550001111'},
///   ),
/// );
/// ```
class InMemoryLiveKitRoomClient implements LiveKitRoomClient {
  /// Creates an [InMemoryLiveKitRoomClient].
  InMemoryLiveKitRoomClient({
    this.name = 'adk-room',
    InMemoryLiveKitLocalParticipant? localParticipant,
    Map<String, LiveKitParticipant>? remoteParticipants,
  }) : _localParticipant =
           localParticipant ?? InMemoryLiveKitLocalParticipant(),
       _remoteParticipants = Map<String, LiveKitParticipant>.from(
         remoteParticipants ?? const <String, LiveKitParticipant>{},
       );

  @override
  final String name;

  final InMemoryLiveKitLocalParticipant _localParticipant;
  final Map<String, LiveKitParticipant> _remoteParticipants;

  /// Concrete in-memory local participant.
  InMemoryLiveKitLocalParticipant get inMemoryLocalParticipant =>
      _localParticipant;

  @override
  LiveKitLocalParticipant get localParticipant => _localParticipant;

  @override
  Map<String, LiveKitParticipant> get remoteParticipants =>
      Map<String, LiveKitParticipant>.unmodifiable(_remoteParticipants);

  /// Whether the room is currently connected.
  bool isConnected = false;

  /// Whether [deleteRoom] was called on this room.
  bool isDeleted = false;

  /// Recorded SIP transfer requests.
  final List<
    ({String roomName, String participantIdentity, String transferTo})
  >
  sipTransfers =
      <({String roomName, String participantIdentity, String transferTo})>[];

  /// Recorded audio frames captured by the agent.
  final List<LiveKitAudioFrame> capturedAudioFrames = <LiveKitAudioFrame>[];

  /// Number of times [clearAudioBuffer] was invoked.
  int audioBufferClearCount = 0;

  final StreamController<LiveKitAudioFrame> _audioController =
      StreamController<LiveKitAudioFrame>.broadcast();
  final StreamController<LiveKitVideoFrame> _videoController =
      StreamController<LiveKitVideoFrame>.broadcast();
  final StreamController<LiveKitChatMessage> _textController =
      StreamController<LiveKitChatMessage>.broadcast();
  final StreamController<LiveKitDataPacket> _dataController =
      StreamController<LiveKitDataPacket>.broadcast();
  final StreamController<LiveKitDtmfEvent> _dtmfController =
      StreamController<LiveKitDtmfEvent>.broadcast();
  final StreamController<String?> _disconnectedController =
      StreamController<String?>.broadcast();

  /// Adds or updates a remote [participant] in the room.
  void addRemoteParticipant(LiveKitParticipant participant) {
    _remoteParticipants[participant.identity] = participant;
  }

  /// Removes a remote participant by [identity].
  void removeRemoteParticipant(String identity) {
    _remoteParticipants.remove(identity);
  }

  /// Emits an inbound [frame] from a remote participant.
  void emitAudioFrame(LiveKitAudioFrame frame) {
    _audioController.add(frame);
  }

  /// Emits an inbound video [frame] from a remote participant.
  void emitVideoFrame(LiveKitVideoFrame frame) {
    _videoController.add(frame);
  }

  /// Emits an inbound text stream [message].
  void emitTextMessage(LiveKitChatMessage message) {
    _textController.add(message);
  }

  /// Emits an inbound [packet].
  void emitDataPacket(LiveKitDataPacket packet) {
    _dataController.add(packet);
  }

  /// Emits an inbound [dtmf] event.
  void emitDtmf(LiveKitDtmfEvent dtmf) {
    _dtmfController.add(dtmf);
  }

  @override
  Future<void> connect(String url, String token) async {
    isConnected = true;
  }

  @override
  Future<void> disconnect([String? reason]) async {
    isConnected = false;
    if (!_disconnectedController.isClosed) {
      _disconnectedController.add(reason);
    }
  }

  @override
  Future<String> publishAudioOutputTrack({
    int sampleRate = defaultLiveKitSampleRate,
    int channels = defaultLiveKitChannels,
  }) async {
    return 'TR_agent_audio';
  }

  @override
  Future<void> captureAudioFrame(LiveKitAudioFrame frame) async {
    capturedAudioFrames.add(frame);
  }

  @override
  void clearAudioBuffer() {
    audioBufferClearCount += 1;
  }

  @override
  Future<void> waitForAudioPlayout() async {}

  @override
  Future<void> transferSipParticipant({
    required String roomName,
    required String participantIdentity,
    required String transferTo,
  }) async {
    sipTransfers.add((
      roomName: roomName,
      participantIdentity: participantIdentity,
      transferTo: transferTo,
    ));
  }

  @override
  Future<void> deleteRoom(String roomName) async {
    isDeleted = true;
    await disconnect('room_deleted');
  }

  @override
  Stream<LiveKitAudioFrame> get onAudioFrame => _audioController.stream;

  @override
  Stream<LiveKitVideoFrame> get onVideoFrame => _videoController.stream;

  @override
  Stream<LiveKitChatMessage> get onTextMessage => _textController.stream;

  @override
  Stream<LiveKitDataPacket> get onDataReceived => _dataController.stream;

  @override
  Stream<LiveKitDtmfEvent> get onDtmfReceived => _dtmfController.stream;

  @override
  Stream<String?> get onDisconnected => _disconnectedController.stream;
}

/// Manages a streaming LiveKit transcription segment (`lk.transcription`).
///
/// LiveKit clients correlate interim (`lk.transcription_final: false`) and
/// final (`lk.transcription_final: true`) streams via a shared
/// `lk.segment_id` attribute.
///
/// ```dart
/// final segment = TranscriptSegment(
///   trackSid: 'TR_audio_1',
///   identity: 'agent',
/// );
/// await segment.write(room.localParticipant, 'Hello ');
/// await segment.finish(room.localParticipant, 'Hello world!');
/// ```
class TranscriptSegment {
  /// Creates a [TranscriptSegment].
  TranscriptSegment({
    String? segmentId,
    this.trackSid = '',
    this.identity = '',
  }) : segmentId = segmentId ?? newAdkId(prefix: 'seg_');

  /// Current transcription segment identifier.
  String segmentId;

  /// Audio track SID associated with this transcription.
  String trackSid;

  /// Participant identity whose speech is being transcribed.
  String identity;

  LiveKitTextStreamWriter? _writer;

  /// Updates [trackSid] and/or [identity] when provided.
  void bind({String? trackSid, String? identity}) {
    if (trackSid != null && trackSid.isNotEmpty) {
      this.trackSid = trackSid;
    }
    if (identity != null && identity.isNotEmpty) {
      this.identity = identity;
    }
  }

  /// Builds the LiveKit transcription attributes map.
  Map<String, String> attributes({required bool finalSegment}) {
    final Map<String, String> attrs = <String, String>{
      'lk.segment_id': segmentId,
      'lk.transcription_final': finalSegment ? 'true' : 'false',
    };
    if (trackSid.isNotEmpty) {
      attrs['lk.transcribed_track_id'] = trackSid;
    }
    if (identity.isNotEmpty) {
      attrs['lk.Protobuf.sender_identity'] = identity;
    }
    return attrs;
  }

  /// Streams incremental [text] over the open interim writer.
  Future<void> write(LiveKitLocalParticipant local, String text) async {
    _writer ??= await local.streamText(
      topic: lkTranscriptionTopic,
      attributes: attributes(finalSegment: false),
    );
    await _writer!.write(text);
  }

  /// Closes the interim writer, publishes the final [text] with
  /// `lk.transcription_final = 'true'`, and rotates [segmentId].
  Future<void> finish(LiveKitLocalParticipant local, String text) async {
    await close();
    if (text.isNotEmpty) {
      final LiveKitTextStreamWriter writer = await local.streamText(
        topic: lkTranscriptionTopic,
        attributes: attributes(finalSegment: true),
      );
      await writer.write(text);
      await writer.close();
    }
    reset();
  }

  /// Closes the active interim text stream writer if one is open.
  Future<void> close() async {
    if (_writer != null) {
      final LiveKitTextStreamWriter writer = _writer!;
      _writer = null;
      await writer.close();
    }
  }

  /// Rotates [segmentId] for the next utterance.
  void reset() {
    segmentId = newAdkId(prefix: 'seg_');
  }
}

/// Active call handle registered during a [LiveKitRunner] session.
///
/// Gives agent tools access to room/telephony primitives such as hanging up,
/// transferring a SIP call, sending DTMF tones, and performing RPCs.
///
/// ```dart
/// final call = LiveKitCall(
///   room: room,
///   userId: 'user_1',
///   sessionId: 'session_1',
/// );
/// await call.sendDtmf('123#');
/// ```
class LiveKitCall {
  /// Creates a [LiveKitCall].
  LiveKitCall({
    required this.room,
    required this.userId,
    required this.sessionId,
    this.dtmfToneDuration = const Duration(milliseconds: 250),
  });

  /// Underlying LiveKit room client.
  final LiveKitRoomClient room;

  /// Active ADK user ID.
  final String userId;

  /// Active ADK session ID.
  final String sessionId;

  /// Pause duration between consecutive DTMF tones in [sendDtmf].
  final Duration dtmfToneDuration;

  /// First SIP participant in the room, or `null` if this is not a SIP call.
  LiveKitParticipant? get sipParticipant {
    for (final LiveKitParticipant participant
        in room.remoteParticipants.values) {
      if (participant.kind == LiveKitParticipantKind.sip) {
        return participant;
      }
    }
    return null;
  }

  /// Caller's phone number (`sip.phoneNumber`) for a SIP call, or `null`.
  String? get callerPhoneNumber {
    final LiveKitParticipant? sip = sipParticipant;
    if (sip == null) {
      return null;
    }
    return sip.attributes[sipPhoneNumberAttribute];
  }

  /// All `sip.*` attributes on the SIP participant, or an empty map.
  Map<String, String> sipAttributes() {
    final LiveKitParticipant? sip = sipParticipant;
    if (sip == null) {
      return <String, String>{};
    }
    final Map<String, String> result = <String, String>{};
    sip.attributes.forEach((String key, String value) {
      if (key.startsWith('sip.')) {
        result[key] = value;
      }
    });
    return result;
  }

  /// Sends a sequence of DTMF [digits] (`0-9`, `*`, `#`, `A-D`) into the room.
  ///
  /// Throws an [ArgumentError] if any character is not a valid DTMF digit.
  Future<void> sendDtmf(String digits) async {
    final List<String> normalized = <String>[];
    for (int i = 0; i < digits.length; i++) {
      final String ch = digits[i].toUpperCase();
      if (!dtmfCodes.containsKey(ch)) {
        throw ArgumentError(
          'Invalid DTMF digit "$ch" in "$digits"; allowed: 0-9, *, #, A-D',
        );
      }
      normalized.add(ch);
    }
    for (int i = 0; i < normalized.length; i++) {
      final String ch = normalized[i];
      await room.localParticipant.publishDtmf(
        code: dtmfCodes[ch]!,
        digit: ch,
      );
      if (i + 1 < normalized.length && dtmfToneDuration > Duration.zero) {
        await Future<void>.delayed(dtmfToneDuration);
      }
    }
  }

  /// Invokes an RPC [method] on a remote participant.
  ///
  /// When [destinationIdentity] is omitted, targets the single remote
  /// participant in the room or throws a [StateError].
  Future<String> performRpc({
    required String method,
    required String payload,
    String? destinationIdentity,
    double? responseTimeout,
  }) async {
    String? target = destinationIdentity;
    if (target == null || target.isEmpty) {
      final List<LiveKitParticipant> remotes = room.remoteParticipants.values
          .toList();
      if (remotes.isEmpty) {
        throw StateError('No remote participants in room');
      }
      if (remotes.length > 1) {
        final String identities = remotes
            .map((LiveKitParticipant p) => p.identity)
            .join(', ');
        throw StateError(
          'Multiple remote participants ($identities); pass destinationIdentity explicitly',
        );
      }
      target = remotes.first.identity;
    }
    return room.localParticipant.performRpc(
      destinationIdentity: target,
      method: method,
      payload: payload,
      responseTimeout: responseTimeout,
    );
  }

  /// Publishes a raw data packet to the room on [topic].
  Future<void> sendData(
    List<int> payload, {
    String topic = dataTopic,
    bool reliable = true,
  }) async {
    await room.localParticipant.publishData(
      payload,
      topic: topic,
      reliable: reliable,
    );
  }

  /// Transfers the SIP participant to [transferTo] (`tel:+1...` or `sip:...`).
  ///
  /// Throws a [StateError] if there is no SIP participant in the room.
  Future<void> transfer(String transferTo) async {
    final LiveKitParticipant? sip = sipParticipant;
    if (sip == null) {
      throw StateError('Cannot transfer: no SIP participant in room');
    }
    String destination = transferTo;
    if (!destination.startsWith('tel:') && !destination.startsWith('sip:')) {
      destination = 'tel:$destination';
    }
    await room.transferSipParticipant(
      roomName: room.name,
      participantIdentity: sip.identity,
      transferTo: destination,
    );
  }

  /// Ends the call for all participants by deleting the room on the server
  /// (falling back to disconnecting the local participant on error).
  Future<void> hangUp() async {
    try {
      await room.deleteRoom(room.name);
    } on Object {
      await room.disconnect();
    }
  }
}

final Map<(String, String), LiveKitCall> _activeCalls =
    <(String, String), LiveKitCall>{};

/// Read-only view of currently registered [LiveKitCall]s keyed by `(userId, sessionId)`.
Map<(String, String), LiveKitCall> get activeCalls =>
    Map<(String, String), LiveKitCall>.unmodifiable(_activeCalls);

/// Registers [call] in the active call registry.
void registerCall(LiveKitCall call) {
  _activeCalls[(call.userId, call.sessionId)] = call;
}

/// Removes [call] from the active call registry.
void unregisterCall(LiveKitCall call) {
  final (String, String) key = (call.userId, call.sessionId);
  if (identical(_activeCalls[key], call)) {
    _activeCalls.remove(key);
  }
}

/// Resolves the active [LiveKitCall] for [toolContext].
///
/// Throws a [StateError] if no active [LiveKitRunner] session matches.
LiveKitCall currentCall(ToolContext toolContext) {
  final LiveKitCall? call = lookupCall(toolContext);
  if (call == null) {
    throw StateError('currentCall() called outside an active LiveKitRunner');
  }
  return call;
}

/// Looks up the active [LiveKitCall] for [context], or returns `null`.
LiveKitCall? lookupCall(ReadonlyContext? context) {
  if (context == null) {
    return null;
  }
  return _activeCalls[(context.userId, context.session.id)];
}

/// Ends the phone or WebRTC call and disconnects all participants.
Future<Map<String, Object?>> endCall({
  required ToolContext toolContext,
}) async {
  final LiveKitCall call = currentCall(toolContext);
  await call.hangUp();
  return <String, Object?>{'status': 'call_ended'};
}

/// Transfers the caller to another phone number or SIP URI.
Future<Map<String, Object?>> transferCall({
  required String transferTo,
  required ToolContext toolContext,
}) async {
  final LiveKitCall call = currentCall(toolContext);
  await call.transfer(transferTo);
  return <String, Object?>{
    'status': 'transferred',
    'transfer_to': transferTo,
  };
}

/// Sends DTMF touch-tone digits (`0-9`, `*`, `#`, `A-D`) into the call.
Future<Map<String, Object?>> sendDtmf({
  required String digits,
  required ToolContext toolContext,
}) async {
  final LiveKitCall call = currentCall(toolContext);
  await call.sendDtmf(digits);
  return <String, Object?>{'status': 'sent', 'digits': digits};
}

/// Pre-configured [FunctionTool] wrapping [endCall] (`end_call`).
final FunctionTool hangUpTool = FunctionTool(
  name: 'end_call',
  description:
      'End the phone/voice call and hang up on the user. Call this when the '
      'conversation is complete or the user asks to hang up / says goodbye.',
  func: endCall,
);

/// Pre-configured [FunctionTool] wrapping [transferCall] (`transfer_call`).
final FunctionTool transferCallTool = FunctionTool(
  name: 'transfer_call',
  description:
      'Transfer the caller to another phone number or SIP endpoint (e.g. a '
      'human agent or another department). Tell the caller you are '
      'transferring them before calling this tool.',
  func: transferCall,
);

/// Pre-configured [FunctionTool] wrapping [sendDtmf] (`send_dtmf`).
final FunctionTool sendDtmfTool = FunctionTool(
  name: 'send_dtmf',
  description:
      'Send DTMF touch-tone digits (0-9, *, #, A-D) into the call — useful '
      'for navigating IVR menus or entering extensions.',
  func: sendDtmf,
);

/// Toolset that dynamically exposes LiveKit call-control tools based on the
/// active room state.
///
/// - Outside a [LiveKitRunner] session: returns no tools.
/// - Standard WebRTC session: returns `[end_call]`.
/// - SIP telephony session: returns `[end_call, transfer_call, send_dtmf]`.
///
/// ```dart
/// final agent = Agent(
///   name: 'receptionist',
///   model: 'gemini-2.5-flash-native-audio-latest',
///   tools: <Object>[LiveKitToolset()],
/// );
/// ```
class LiveKitToolset extends BaseToolset {
  /// Creates a [LiveKitToolset] with an optional [toolFilter].
  LiveKitToolset({super.toolFilter, super.toolNamePrefix});

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final LiveKitCall? call = lookupCall(readonlyContext);
    if (call == null) {
      return <BaseTool>[];
    }
    final List<BaseTool> candidates = <BaseTool>[hangUpTool];
    if (call.sipParticipant != null) {
      candidates.addAll(<BaseTool>[transferCallTool, sendDtmfTool]);
    }
    return candidates
        .where((BaseTool tool) => isToolSelected(tool, readonlyContext))
        .toList();
  }
}

/// Bridges a LiveKit WebRTC/SIP room to an ADK [Runner] via `runLive`.
///
/// ```dart
/// final lkRunner = LiveKitRunner(
///   runner: runner,
///   userId: 'caller',
/// );
/// final room = InMemoryLiveKitRoomClient(name: 'call-room');
/// await lkRunner.run(room: room);
/// ```
class LiveKitRunner {
  /// Creates a [LiveKitRunner].
  LiveKitRunner({
    required this.runner,
    this.userId = 'livekit_user',
    this.runConfig,
    this.outputSampleRate = defaultLiveKitSampleRate,
    this.outputChannels = defaultLiveKitChannels,
    this.videoFps = defaultLiveKitVideoFps,
    this.dtmfDebounce = const Duration(milliseconds: 800),
    this.hangupDrainDelay = Duration.zero,
    LiveKitRoomClient Function()? roomFactory,
  }) : _roomFactory = roomFactory ?? InMemoryLiveKitRoomClient.new;

  /// Underlying ADK [Runner].
  final Runner runner;

  /// Default user ID when none is supplied to [run].
  final String userId;

  /// Default [RunConfig] passed to [Runner.runLive].
  final RunConfig? runConfig;

  /// Sample rate (Hz) of the published agent audio track.
  final int outputSampleRate;

  /// Channel count of the published agent audio track.
  final int outputChannels;

  /// Target frame rate (fps) when forwarding remote video tracks.
  final double videoFps;

  /// Debounce window for coalescing consecutive inbound DTMF digits.
  final Duration dtmfDebounce;

  /// Delay before hanging up after a tool invokes [endCall], allowing final
  /// goodbye audio to drain.
  final Duration hangupDrainDelay;

  final LiveKitRoomClient Function() _roomFactory;

  /// Runs a bidirectional LiveKit session until the room disconnects or the
  /// live event stream completes.
  Future<LiveKitCall> run({
    LiveKitRoomClient? room,
    String? url,
    String? token,
    String? userId,
    String? sessionId,
    RunConfig? runConfig,
  }) async {
    final LiveKitRoomClient activeRoom = room ?? _roomFactory();
    final bool ownsConnection = room == null;
    if (ownsConnection) {
      if (url == null || url.isEmpty || token == null || token.isEmpty) {
        throw ArgumentError(
          'LiveKit url and token are required when room is not provided.',
        );
      }
      await activeRoom.connect(url, token);
    }

    final String effectiveUserId = userId ?? this.userId;
    final String effectiveSessionId =
        sessionId ??
        (activeRoom.name.isNotEmpty
            ? activeRoom.name
            : newAdkId(prefix: 'lk_'));
    final RunConfig effectiveRunConfig =
        runConfig ??
        this.runConfig ??
        RunConfig(
          responseModalities: const <String>['AUDIO'],
          streamingMode: StreamingMode.bidi,
        );

    LiveKitCall call = LiveKitCall(
      room: activeRoom,
      userId: effectiveUserId,
      sessionId: effectiveSessionId,
    );

    final Map<String, Object?> initialState = <String, Object?>{};
    final LiveKitParticipant? sip = call.sipParticipant;
    if (sip != null) {
      final String? callerNumber = sip.attributes[sipPhoneNumberAttribute];
      final String? calledNumber = sip.attributes[sipTrunkPhoneNumberAttribute];
      final String? sipCallId = sip.attributes[sipCallIdAttribute];
      if (callerNumber != null && callerNumber.isNotEmpty) {
        initialState['caller_phone_number'] = callerNumber;
      }
      if (calledNumber != null && calledNumber.isNotEmpty) {
        initialState['called_phone_number'] = calledNumber;
      }
      if (sipCallId != null && sipCallId.isNotEmpty) {
        initialState['sip_call_id'] = sipCallId;
      }
    }

    Session? session = await runner.sessionService.getSession(
      appName: runner.appName,
      userId: effectiveUserId,
      sessionId: effectiveSessionId,
    );
    if (session == null) {
      session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: effectiveUserId,
        sessionId: effectiveSessionId,
        state: initialState,
      );
    } else if (initialState.isNotEmpty) {
      session.state.addAll(initialState);
    }

    final String agentAudioTrackSid = await activeRoom.publishAudioOutputTrack(
      sampleRate: outputSampleRate,
      channels: outputChannels,
    );

    final LiveRequestQueue liveRequestQueue = LiveRequestQueue();
    final TranscriptSegment inputSegment = TranscriptSegment();
    final TranscriptSegment outputSegment = TranscriptSegment(
      trackSid: agentAudioTrackSid,
      identity: activeRoom.localParticipant.identity,
    );

    for (final LiveKitParticipant participant
        in activeRoom.remoteParticipants.values) {
      if (participant.kind != LiveKitParticipantKind.agent) {
        inputSegment.bind(
          trackSid: participant.audioTrackSid,
          identity: participant.identity,
        );
      }
    }

    bool callEndedByTool = false;
    final List<String> dtmfBuffer = <String>[];
    Timer? dtmfTimer;

    void flushDtmf() {
      if (dtmfBuffer.isEmpty) {
        return;
      }
      final String digits = dtmfBuffer.join();
      dtmfBuffer.clear();
      liveRequestQueue.sendContent(
        Content(
          role: 'user',
          parts: <Part>[Part.text('[DTMF: $digits]')],
        ),
      );
    }

    final List<StreamSubscription<Object?>> subscriptions =
        <StreamSubscription<Object?>>[];

    subscriptions.add(
      activeRoom.onAudioFrame.listen((LiveKitAudioFrame frame) {
        if (frame.participantIdentity != null) {
          inputSegment.bind(
            trackSid: frame.trackSid,
            identity: frame.participantIdentity,
          );
        }
        liveRequestQueue.sendRealtime(
          InlineData(
            mimeType:
                'audio/pcm;rate=${frame.sampleRate}',
            data: frame.data,
          ),
        );
      }),
    );

    subscriptions.add(
      activeRoom.onVideoFrame.listen((LiveKitVideoFrame frame) {
        liveRequestQueue.sendRealtime(
          InlineData(mimeType: 'image/jpeg', data: frame.jpegBytes),
        );
      }),
    );

    subscriptions.add(
      activeRoom.onTextMessage.listen((LiveKitChatMessage message) {
        if (message.text.isEmpty) {
          return;
        }
        if (message.topic == lkChatTopic) {
          liveRequestQueue.sendContent(
            Content(role: 'user', parts: <Part>[Part.text(message.text)]),
          );
        } else if (message.topic == dataTopic) {
          final Part? part = deserializeLiveKitPart(
            utf8.encode(message.text),
          );
          if (part != null) {
            liveRequestQueue.sendContent(
              Content(role: 'user', parts: <Part>[part]),
            );
          }
        }
      }),
    );

    subscriptions.add(
      activeRoom.onDataReceived.listen((LiveKitDataPacket packet) {
        if (packet.topic != dataTopic) {
          return;
        }
        final Part? part = deserializeLiveKitPart(packet.data);
        if (part != null) {
          liveRequestQueue.sendContent(
            Content(role: 'user', parts: <Part>[part]),
          );
        }
      }),
    );

    subscriptions.add(
      activeRoom.onDtmfReceived.listen((LiveKitDtmfEvent dtmf) {
        dtmfBuffer.add(dtmf.digit);
        dtmfTimer?.cancel();
        if (dtmfDebounce <= Duration.zero) {
          flushDtmf();
        } else {
          dtmfTimer = Timer(dtmfDebounce, flushDtmf);
        }
      }),
    );

    subscriptions.add(
      activeRoom.onDisconnected.listen((_) {
        liveRequestQueue.close();
      }),
    );

    Future<void> setAgentState(String state) async {
      try {
        await activeRoom.localParticipant.setAttributes(<String, String>{
          agentStateAttribute: state,
        });
      } on Object {
        // Ignore attribute update errors after disconnect.
      }
    }

    call = _InterceptedLiveKitCall(
      delegate: call,
      onHangUpRequested: () {
        callEndedByTool = true;
      },
    );

    registerCall(call);
    try {
      await setAgentState('listening');
      String currentState = 'listening';

      final Stream<Event> events = runner.runLive(
        userId: effectiveUserId,
        sessionId: effectiveSessionId,
        liveRequestQueue: liveRequestQueue,
        runConfig: effectiveRunConfig,
      );

      await for (final Event event in events) {
        if (event.interrupted == true) {
          activeRoom.clearAudioBuffer();
          await outputSegment.close();
          outputSegment.reset();
          if (currentState != 'listening') {
            currentState = 'listening';
            await setAgentState(currentState);
          }
        }

        final Content? content = event.content;
        if (content != null) {
          for (final Part part in content.parts) {
            final InlineData? blob = part.inlineData;
            if (blob != null &&
                blob.data.isNotEmpty &&
                blob.mimeType.startsWith('audio/pcm')) {
              if (currentState != 'speaking') {
                currentState = 'speaking';
                await setAgentState(currentState);
              }
              final int bytesPerSample = 2 * outputChannels;
              final int usableLen =
                  blob.data.length - (blob.data.length % bytesPerSample);
              if (usableLen > 0) {
                await activeRoom.captureAudioFrame(
                  LiveKitAudioFrame(
                    data: blob.data.sublist(0, usableLen),
                    sampleRate: outputSampleRate,
                    numChannels: outputChannels,
                    samplesPerChannel: usableLen ~/ bytesPerSample,
                    participantIdentity:
                        activeRoom.localParticipant.identity,
                    trackSid: agentAudioTrackSid,
                  ),
                );
              }
            } else if (part.text != null && part.text!.isNotEmpty) {
              if (!part.thought && event.outputTranscription == null) {
                if (event.partial == true) {
                  await outputSegment.write(
                    activeRoom.localParticipant,
                    part.text!,
                  );
                } else {
                  await outputSegment.finish(
                    activeRoom.localParticipant,
                    part.text!,
                  );
                }
              }
            } else {
              if (part.functionCall != null && currentState != 'thinking') {
                currentState = 'thinking';
                await setAgentState(currentState);
              }
              await activeRoom.localParticipant.publishData(
                serializeLiveKitPart(part),
                topic: dataTopic,
                reliable: true,
              );
            }
          }
        }

        final Object? inTrans = event.inputTranscription;
        if (inTrans != null) {
          final ({String? text, bool finished}) parsed =
              _parseTranscriptionObject(inTrans);
          if (parsed.text != null && parsed.text!.isNotEmpty) {
            if (parsed.finished) {
              await inputSegment.finish(
                activeRoom.localParticipant,
                parsed.text!,
              );
            } else {
              await inputSegment.write(
                activeRoom.localParticipant,
                parsed.text!,
              );
            }
          }
        }

        final Object? outTrans = event.outputTranscription;
        if (outTrans != null) {
          final ({String? text, bool finished}) parsed =
              _parseTranscriptionObject(outTrans);
          if (parsed.text != null && parsed.text!.isNotEmpty) {
            if (parsed.finished) {
              await outputSegment.finish(
                activeRoom.localParticipant,
                parsed.text!,
              );
            } else {
              await outputSegment.write(
                activeRoom.localParticipant,
                parsed.text!,
              );
            }
          }
        }

        if (event.turnComplete == true) {
          await outputSegment.close();
          outputSegment.reset();
          if (callEndedByTool) {
            if (hangupDrainDelay > Duration.zero) {
              await Future<void>.delayed(hangupDrainDelay);
            }
            await activeRoom.waitForAudioPlayout();
            await (call as _InterceptedLiveKitCall).performActualHangUp();
            break;
          }
          if (currentState != 'listening') {
            currentState = 'listening';
            await setAgentState(currentState);
          }
        }
      }
    } finally {
      dtmfTimer?.cancel();
      for (final StreamSubscription<Object?> sub in subscriptions) {
        await sub.cancel();
      }
      liveRequestQueue.close();
      unregisterCall(call);
      if (ownsConnection && !callEndedByTool) {
        await activeRoom.disconnect();
      }
    }

    return call;
  }
}

class _InterceptedLiveKitCall extends LiveKitCall {
  _InterceptedLiveKitCall({
    required this.delegate,
    required this.onHangUpRequested,
  }) : super(
         room: delegate.room,
         userId: delegate.userId,
         sessionId: delegate.sessionId,
         dtmfToneDuration: delegate.dtmfToneDuration,
       );

  final LiveKitCall delegate;
  final void Function() onHangUpRequested;

  @override
  Future<void> hangUp() async {
    onHangUpRequested();
  }

  Future<void> performActualHangUp() => delegate.hangUp();
}

({String? text, bool finished}) _parseTranscriptionObject(Object transcription) {
  if (transcription is Map) {
    return (
      text: transcription['text'] as String?,
      finished: (transcription['finished'] as bool?) ?? false,
    );
  }
  try {
    final dynamic dyn = transcription;
    final Object? text = dyn.text;
    final Object? finished = dyn.finished;
    return (
      text: text is String ? text : null,
      finished: finished is bool ? finished : false,
    );
  } on Object {
    return (text: '$transcription', finished: false);
  }
}

/// Serializes an ADK [Part] to UTF-8 JSON bytes for the LiveKit `adk` data topic.
Uint8List serializeLiveKitPart(Part part) {
  final Map<String, Object?> payload = <String, Object?>{
    if (part.text != null) 'text': part.text,
    if (part.thought) 'thought': true,
    if (part.functionCall != null)
      'function_call': <String, Object?>{
        'name': part.functionCall!.name,
        'args': part.functionCall!.args,
        if (part.functionCall!.id != null) 'id': part.functionCall!.id,
      },
    if (part.functionResponse != null)
      'function_response': <String, Object?>{
        'name': part.functionResponse!.name,
        'response': part.functionResponse!.response,
        if (part.functionResponse!.id != null) 'id': part.functionResponse!.id,
      },
    if (part.inlineData != null)
      'inline_data': <String, Object?>{
        'mime_type': part.inlineData!.mimeType,
        'data': base64Encode(part.inlineData!.data),
      },
    if (part.fileData != null)
      'file_data': <String, Object?>{
        'file_uri': part.fileData!.fileUri,
        if (part.fileData!.mimeType != null)
          'mime_type': part.fileData!.mimeType,
      },
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
}

/// Deserializes UTF-8 JSON [bytes] from the LiveKit `adk` data topic into a [Part].
Part? deserializeLiveKitPart(List<int> bytes) {
  try {
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      return null;
    }
    final Map<String, Object?> map = decoded.map(
      (Object? k, Object? v) => MapEntry('$k', v),
    );
    if (map['function_call'] is Map) {
      final Map<String, Object?> fc = (map['function_call'] as Map).map(
        (Object? k, Object? v) => MapEntry('$k', v),
      );
      final Map<String, Object?> args = (fc['args'] is Map)
          ? (fc['args'] as Map).map((Object? k, Object? v) => MapEntry('$k', v))
          : <String, Object?>{};
      return Part.fromFunctionCall(
        name: (fc['name'] as String?) ?? '',
        args: args,
        id: fc['id'] as String?,
      );
    }
    if (map['function_response'] is Map) {
      final Map<String, Object?> fr = (map['function_response'] as Map).map(
        (Object? k, Object? v) => MapEntry('$k', v),
      );
      final Map<String, Object?> response = (fr['response'] is Map)
          ? (fr['response'] as Map).map(
              (Object? k, Object? v) => MapEntry('$k', v),
            )
          : <String, Object?>{};
      return Part.fromFunctionResponse(
        name: (fr['name'] as String?) ?? '',
        response: response,
        id: fr['id'] as String?,
      );
    }
    if (map['inline_data'] is Map) {
      final Map<String, Object?> inline = (map['inline_data'] as Map).map(
        (Object? k, Object? v) => MapEntry('$k', v),
      );
      final String mimeType =
          (inline['mime_type'] as String?) ?? 'application/octet-stream';
      final String rawData = (inline['data'] as String?) ?? '';
      return Part.fromInlineData(
        mimeType: mimeType,
        data: base64Decode(rawData),
      );
    }
    if (map['file_data'] is Map) {
      final Map<String, Object?> file = (map['file_data'] as Map).map(
        (Object? k, Object? v) => MapEntry('$k', v),
      );
      return Part.fromFileData(
        fileUri: (file['file_uri'] as String?) ?? '',
        mimeType: file['mime_type'] as String?,
      );
    }
    if (map['text'] is String) {
      return Part.text(
        map['text'] as String,
        thought: (map['thought'] as bool?) ?? false,
      );
    }
    return null;
  } on Object {
    return null;
  }
}
