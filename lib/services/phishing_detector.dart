import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class PhishingDetector {
  // Replace with your actual backend URL
  static const String backendUrl = 'YOUR_BACKEND_URL/api/check-phishing';

  /// Extracts page data including HTML and resources
  static Future<Map<String, dynamic>> extractPageData(
    InAppWebViewController controller,
    String url,
  ) async {
    try {
      // Get the HTML content
      String? html = await controller.getHtml();

      // Extract all image sources using JavaScript
      List<dynamic>? imageSources = await controller.evaluateJavascript(
        source: '''
        (function() {
          const images = document.querySelectorAll('img');
          return Array.from(images).map(img => img.src);
        })();
      ''',
      );

      // Extract all link hrefs
      List<dynamic>? links = await controller.evaluateJavascript(
        source: '''
        (function() {
          const anchors = document.querySelectorAll('a');
          return Array.from(anchors).map(a => a.href);
        })();
      ''',
      );

      // Extract all script sources
      List<dynamic>? scripts = await controller.evaluateJavascript(
        source: '''
        (function() {
          const scriptTags = document.querySelectorAll('script[src]');
          return Array.from(scriptTags).map(s => s.src);
        })();
      ''',
      );

      // Extract all stylesheet sources
      List<dynamic>? stylesheets = await controller.evaluateJavascript(
        source: '''
        (function() {
          const links = document.querySelectorAll('link[rel="stylesheet"]');
          return Array.from(links).map(l => l.href);
        })();
      ''',
      );

      // Extract meta tags
      List<dynamic>? metaTags = await controller.evaluateJavascript(
        source: '''
        (function() {
          const metas = document.querySelectorAll('meta');
          return Array.from(metas).map(m => ({
            name: m.getAttribute('name'),
            property: m.getAttribute('property'),
            content: m.getAttribute('content')
          }));
        })();
      ''',
      );

      // Get page title
      String? title = await controller.getTitle();

      return {
        'url': url,
        'html': html ?? '',
        'title': title ?? '',
        'images': imageSources ?? [],
        'links': links ?? [],
        'scripts': scripts ?? [],
        'stylesheets': stylesheets ?? [],
        'metaTags': metaTags ?? [],
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('Error extracting page data: $e');
      return {
        'url': url,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Sends page data to backend for phishing analysis
  static Future<PhishingResult> checkForPhishing(
    Map<String, dynamic> pageData,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(backendUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(pageData),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PhishingResult(
          isPhishing: data['isPhishing'] ?? false,
          confidence: data['confidence']?.toDouble() ?? 0.0,
          reasons: List<String>.from(data['reasons'] ?? []),
          riskLevel: data['riskLevel'] ?? 'unknown',
        );
      } else {
        return PhishingResult(
          isPhishing: false,
          confidence: 0.0,
          reasons: ['Backend error: ${response.statusCode}'],
          riskLevel: 'unknown',
        );
      }
    } catch (e) {
      print('Error checking for phishing: $e');
      // return PhishingResult(
      //   isPhishing: true,
      //   confidence: 1.0,
      //   reasons: ['Network error: $e'],
      //   riskLevel: 'unknown',
      // );
      return PhishingResult(
        isPhishing: false,
        confidence: 0.0,
        reasons: ['Network error: $e'],
        riskLevel: 'unknown',
      );
    }
  }

  /// Analyzes a page for phishing indicators
  static Future<PhishingResult> analyzePage(
    InAppWebViewController controller,
    String url,
  ) async {
    // Extract page data
    final pageData = await extractPageData(controller, url);

    // Send to backend for analysis
    final result = await checkForPhishing(pageData);

    return result;
  }
}

class PhishingResult {
  final bool isPhishing;
  final double confidence;
  final List<String> reasons;
  final String riskLevel; // 'low', 'medium', 'high', 'critical', 'unknown'

  PhishingResult({
    required this.isPhishing,
    required this.confidence,
    required this.reasons,
    required this.riskLevel,
  });

  @override
  String toString() {
    return 'PhishingResult(isPhishing: $isPhishing, confidence: $confidence, riskLevel: $riskLevel)';
  }
}
