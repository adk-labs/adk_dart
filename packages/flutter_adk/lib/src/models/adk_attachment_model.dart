import 'dart:typed_data';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/foundation.dart';

/// Represents a media or document attachment in [AdkChatMessage].
@immutable
class AdkAttachment {
  /// Creates an [AdkAttachment].
  const AdkAttachment({
    required this.name,
    required this.mimeType,
    this.bytes,
    this.uri,
    this.sizeBytes,
  });

  /// Creates an image attachment from in-memory byte buffer.
  factory AdkAttachment.imageBytes({
    required String name,
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) {
    return AdkAttachment(
      name: name,
      mimeType: mimeType,
      bytes: bytes,
      sizeBytes: bytes.lengthInBytes,
    );
  }

  /// Creates a generic file attachment (PDF, audio, document) from bytes.
  factory AdkAttachment.fileBytes({
    required String name,
    required Uint8List bytes,
    required String mimeType,
  }) {
    return AdkAttachment(
      name: name,
      mimeType: mimeType,
      bytes: bytes,
      sizeBytes: bytes.lengthInBytes,
    );
  }

  /// Creates a remote or storage URI file attachment.
  factory AdkAttachment.uri({
    required String name,
    required String uri,
    required String mimeType,
    int? sizeBytes,
  }) {
    return AdkAttachment(
      name: name,
      uri: uri,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
    );
  }

  /// File name with extension (e.g. `diagram.png`, `contract.pdf`).
  final String name;

  /// MIME type (e.g. `image/png`, `image/jpeg`, `application/pdf`, `audio/mp3`).
  final String mimeType;

  /// Raw byte payload for in-memory uploads.
  final Uint8List? bytes;

  /// Remote URL or cloud storage URI.
  final String? uri;

  /// Size of the file in bytes if known.
  final int? sizeBytes;

  /// Whether this attachment is an image.
  bool get isImage => mimeType.startsWith('image/');

  /// Whether this attachment is a PDF document.
  bool get isPdf => mimeType == 'application/pdf';

  /// Whether this attachment is an audio file.
  bool get isAudio => mimeType.startsWith('audio/');

  /// Converts this attachment into an ADK [adk.Part] for multimodal inference.
  adk.Part toPart() {
    if (bytes != null) {
      return adk.Part(
        inlineData: adk.InlineData(
          mimeType: mimeType,
          data: bytes!,
          displayName: name,
        ),
      );
    }
    if (uri != null) {
      return adk.Part(
        fileData: adk.FileData(
          fileUri: uri!,
          mimeType: mimeType,
          displayName: name,
        ),
      );
    }
    return adk.Part.text('Attachment: $name');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AdkAttachment &&
        other.name == name &&
        other.mimeType == mimeType &&
        other.uri == uri &&
        other.sizeBytes == sizeBytes;
  }

  @override
  int get hashCode => Object.hash(name, mimeType, uri, sizeBytes);
}
