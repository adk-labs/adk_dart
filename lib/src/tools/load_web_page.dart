/// Web page fetching and text extraction utilities for tool execution.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const Duration _defaultLoadWebPageTimeout = Duration(seconds: 10);
const int _defaultLoadWebPageMaxResponseBytes = 1024 * 1024;

/// The extracted readable text for [url] or an error message string.
///
/// Only HTTP/HTTPS URLs are supported.
Future<String> loadWebPage(
  String url, {
  Duration timeout = _defaultLoadWebPageTimeout,
  int maxResponseBytes = _defaultLoadWebPageMaxResponseBytes,
  bool allowPrivateAddresses = false,
}) async {
  if (maxResponseBytes <= 0) {
    throw ArgumentError.value(
      maxResponseBytes,
      'maxResponseBytes',
      'maxResponseBytes must be greater than 0.',
    );
  }

  final Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException catch (e) {
    return 'Failed to fetch URL "$url": invalid URL (${e.message}).';
  }
  if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return 'Failed to fetch URL "$url": only http and https URLs are supported.';
  }
  if (uri.host.trim().isEmpty) {
    return 'Failed to fetch URL "$url": host is missing.';
  }
  if (!allowPrivateAddresses) {
    final String? blockedReason = await _blockedTargetReason(
      uri.host,
      timeout: timeout,
    );
    if (blockedReason != null) {
      return 'Failed to fetch URL "$url": $blockedReason.';
    }
  }

  final HttpClient client = HttpClient();
  client.connectionTimeout = timeout;
  client.findProxy = (Uri _) => 'DIRECT';
  try {
    final HttpClientRequest request = await client.getUrl(uri).timeout(timeout);
    request.followRedirects = false;
    final HttpClientResponse response = await request.close().timeout(timeout);

    if (response.statusCode != HttpStatus.ok) {
      final String reason = response.reasonPhrase.trim();
      final String reasonSuffix = reason.isNotEmpty ? ' ($reason)' : '';
      return 'Failed to fetch URL "$url": HTTP ${response.statusCode}$reasonSuffix.';
    }

    final BytesBuilder bytes = BytesBuilder(copy: false);
    int totalBytes = 0;
    await for (final List<int> chunk in response.timeout(timeout)) {
      totalBytes += chunk.length;
      if (totalBytes > maxResponseBytes) {
        return 'Failed to fetch URL "$url": response exceeded $maxResponseBytes bytes.';
      }
      bytes.add(chunk);
    }

    final String html = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    final String text = _extractText(html);
    return text
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.split(RegExp(r'\s+')).length > 3)
        .join('\n');
  } on TimeoutException {
    return 'Failed to fetch URL "$url": timed out after ${_formatDuration(timeout)}.';
  } on SocketException catch (e) {
    return 'Failed to fetch URL "$url": network error (${e.message}).';
  } on HttpException catch (e) {
    return 'Failed to fetch URL "$url": HTTP error (${e.message}).';
  } finally {
    client.close(force: true);
  }
}

Future<String?> _blockedTargetReason(
  String host, {
  required Duration timeout,
}) async {
  final String normalizedHost = host.trim().toLowerCase();
  if (normalizedHost == 'localhost' || normalizedHost.endsWith('.localhost')) {
    return 'host resolves to a local or private address';
  }

  final List<InternetAddress> addresses;
  try {
    addresses = await InternetAddress.lookup(normalizedHost).timeout(timeout);
  } on TimeoutException {
    return 'DNS lookup timed out after ${_formatDuration(timeout)}';
  } on SocketException catch (e) {
    return 'DNS lookup failed (${e.message})';
  }

  if (addresses.isEmpty) {
    return 'host did not resolve to any address';
  }
  for (final InternetAddress address in addresses) {
    if (_isRestrictedAddress(address)) {
      return 'host resolves to a local or private address';
    }
  }
  return null;
}

bool _isRestrictedAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  final List<int> bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
    return _isRestrictedIpv4(bytes);
  }
  if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
    final bool unspecified = bytes.every((int byte) => byte == 0);
    if (unspecified) {
      return true;
    }
    // Unique local addresses fc00::/7 are not safe for arbitrary fetches.
    if ((bytes[0] & 0xfe) == 0xfc) {
      return true;
    }
    // IPv4-mapped IPv6 address ::ffff:a.b.c.d.
    final bool ipv4Mapped =
        bytes.take(10).every((int byte) => byte == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    if (ipv4Mapped) {
      return _isRestrictedIpv4(bytes.sublist(12));
    }
  }
  return false;
}

bool _isRestrictedIpv4(List<int> bytes) {
  final int first = bytes[0];
  final int second = bytes[1];
  if (first == 0 || first == 10 || first == 127 || first >= 224) {
    return true;
  }
  if (first == 100 && second >= 64 && second <= 127) {
    return true;
  }
  if (first == 169 && second == 254) {
    return true;
  }
  if (first == 172 && second >= 16 && second <= 31) {
    return true;
  }
  if (first == 192 && second == 168) {
    return true;
  }
  if (first == 192 && second == 0) {
    return true;
  }
  if (first == 198 && (second == 18 || second == 19)) {
    return true;
  }
  return false;
}

String _formatDuration(Duration duration) {
  if (duration.inMilliseconds % 1000 == 0) {
    return '${duration.inSeconds}s';
  }
  return '${duration.inMilliseconds}ms';
}

String _extractText(String html) {
  String text = html;
  text = text.replaceAll(
    RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
    ' ',
  );
  text = text.replaceAll(
    RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
    ' ',
  );
  text = text.replaceAll(RegExp(r'<[^>]+>', caseSensitive: false), '\n');
  text = text.replaceAll('&nbsp;', ' ');
  text = text.replaceAll('&amp;', '&');
  text = text.replaceAll('&lt;', '<');
  text = text.replaceAll('&gt;', '>');
  text = text.replaceAll('&quot;', '"');
  text = text.replaceAll('&#39;', '\'');
  return text;
}
