import 'package:http/http.dart' as http;

class WebSearchResult {
  final String title;
  final String snippet;
  final String url;

  WebSearchResult({
    required this.title,
    required this.snippet,
    required this.url,
  });
}

class WebSearchService {
  static const _baseUrl = 'https://html.duckduckgo.com/html/';

  /// Searches DuckDuckGo and returns top results.
  Future<List<WebSearchResult>> search(String query,
      {int maxResults = 5}) async {
    final response = await http
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'Reins/1.4.0',
          },
          body: 'q=${Uri.encodeComponent(query)}',
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return [];

    return _parseResults(response.body, maxResults);
  }

  /// Parses DuckDuckGo HTML results page.
  List<WebSearchResult> _parseResults(String html, int maxResults) {
    final results = <WebSearchResult>[];

    // DuckDuckGo HTML lite has results in <a class="result__a"> tags
    // and snippets in <a class="result__snippet"> tags
    final resultPattern = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>.*?'
      r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
      dotAll: true,
    );

    for (final match in resultPattern.allMatches(html)) {
      if (results.length >= maxResults) break;

      final rawUrl = match.group(1) ?? '';
      final title = _stripHtml(match.group(2) ?? '');
      final snippet = _stripHtml(match.group(3) ?? '');

      // DuckDuckGo wraps URLs in a redirect - extract the actual URL
      final actualUrl = _extractUrl(rawUrl);

      if (title.isNotEmpty && actualUrl.isNotEmpty) {
        results.add(WebSearchResult(
          title: title,
          snippet: snippet,
          url: actualUrl,
        ));
      }
    }

    return results;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  String _extractUrl(String ddgUrl) {
    // DuckDuckGo lite wraps URLs: //duckduckgo.com/l/?uddg=ENCODED_URL&...
    final uddgMatch = RegExp(r'uddg=([^&]+)').firstMatch(ddgUrl);
    if (uddgMatch != null) {
      return Uri.decodeComponent(uddgMatch.group(1)!);
    }
    // If it's already a direct URL
    if (ddgUrl.startsWith('http')) return ddgUrl;
    return '';
  }

  /// Formats search results as context for the LLM prompt.
  static String formatResultsAsContext(List<WebSearchResult> results) {
    if (results.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('Web search results:');
    buffer.writeln();
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('[${i + 1}] ${r.title}');
      buffer.writeln('URL: ${r.url}');
      buffer.writeln(r.snippet);
      buffer.writeln();
    }
    buffer.writeln(
        'Use the above search results to help answer the user\'s question. Cite sources when relevant.');
    return buffer.toString();
  }
}
