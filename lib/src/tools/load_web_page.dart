import 'dart:convert';
import 'dart:io';

Future<String> loadWebPage(String url) async {
  final Uri uri = Uri.parse(url);
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    request.followRedirects = false;
    final HttpClientResponse response = await request.close();
    final List<int> bytes = await response.fold<List<int>>(<int>[], (
      List<int> acc,
      List<int> chunk,
    ) {
      acc.addAll(chunk);
      return acc;
    });

    if (response.statusCode != HttpStatus.ok) {
      return 'Failed to fetch url: $url';
    }

    final String html = utf8.decode(bytes, allowMalformed: true);
    final String text = _extractText(html);
    return text
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.split(RegExp(r'\s+')).length > 3)
        .join('\n');
  } finally {
    client.close(force: true);
  }
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
