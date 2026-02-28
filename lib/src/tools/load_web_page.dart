import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const Duration _defaultLoadWebPageTimeout = Duration(seconds: 10);
const int _defaultLoadWebPageMaxResponseBytes = 1024 * 1024;

Future<String> loadWebPage(
  String url, {
  Duration timeout = _defaultLoadWebPageTimeout,
  int maxResponseBytes = _defaultLoadWebPageMaxResponseBytes,
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

  final HttpClient client = HttpClient();
  client.connectionTimeout = timeout;
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
