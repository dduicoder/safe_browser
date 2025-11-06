import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class PhishingDetector {
  static const String backendUrl = 'https://hp0308.pythonanywhere.com';

  static Future<Map<String, dynamic>> extractPageData(
    InAppWebViewController controller,
    String url,
  ) async {
    try {
      String? html = await controller.getHtml();

      if (html != null && html.length > 30000) {
        html = html.substring(0, 30000);
      }

      List<dynamic>? imageSources = await controller.evaluateJavascript(
        source: '''
        (function() {
          const images = document.querySelectorAll('img');
          return Array.from(images).slice(0, 10).map(img => img.src);
        })();
      ''',
      );

      List<dynamic>? links = await controller.evaluateJavascript(
        source: '''
        (function() {
          const anchors = document.querySelectorAll('a');
          return Array.from(anchors).slice(0, 10).map(a => a.href);
        })();
      ''',
      );

      List<dynamic>? scripts = await controller.evaluateJavascript(
        source: '''
        (function() {
          const scriptTags = document.querySelectorAll('script[src]');
          return Array.from(scriptTags).slice(0, 5).map(s => s.src);
        })();
      ''',
      );

      List<dynamic>? stylesheets = await controller.evaluateJavascript(
        source: '''
        (function() {
          const links = document.querySelectorAll('link[rel="stylesheet"]');
          return Array.from(links).slice(0, 5).map(l => l.href);
        })();
      ''',
      );

      //
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

      String? title = await controller.getTitle();

      final pageData = {
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

      print(
        '📤 Sending data: HTML length=${html?.length ?? 0}, images=${(imageSources ?? []).length}, links=${(links ?? []).length}',
      );

      return pageData;
    } catch (e) {
      print('Error extracting page data: $e');
      return {
        'url': url,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  static Future<PhishingResult> checkForPhishing(
    Map<String, dynamic> pageData,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/analyze'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(pageData),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('🔍 Backend response: $data');

        List<RiskItem> riskItems = [];

        if (data is List) {
          riskItems = data.map((item) => RiskItem.fromJson(item)).toList();
        } else if (data is Map && data.containsKey('raw_response')) {
          try {
            final rawResponse = data['raw_response'] as String;
            final cleanedResponse = rawResponse
                .replaceAll('```json', '')
                .replaceAll('```', '')
                .trim();
            final parsedData = jsonDecode(cleanedResponse);
            if (parsedData is List) {
              riskItems = parsedData
                  .map((item) => RiskItem.fromJson(item))
                  .toList();
            }
          } catch (e) {
            print('Error parsing raw_response: $e');
          }
        }

        bool isPhishing = riskItems.isNotEmpty;
        String overallRiskLevel = 'unknown';
        double maxConfidence = 0.0;
        List<String> reasons = [];

        if (riskItems.isNotEmpty) {
          final riskLevelPriority = {'high': 3, 'medium': 2, 'low': 1};
          int maxPriority = 0;

          for (var item in riskItems) {
            maxConfidence = maxConfidence > item.confidence
                ? maxConfidence
                : item.confidence;
            reasons.add(item.reason);

            final priority = riskLevelPriority[item.riskLevel] ?? 0;
            if (priority > maxPriority) {
              maxPriority = priority;
              overallRiskLevel = item.riskLevel;
            }
          }
        }

        print(
          '📊 Parsed result: isPhishing=$isPhishing, riskLevel=$overallRiskLevel, items=${riskItems.length}',
        );

        return PhishingResult(
          isPhishing: isPhishing,
          confidence: maxConfidence,
          reasons: reasons,
          riskLevel: overallRiskLevel,
          riskItems: riskItems,
        );
      } else {
        return PhishingResult(
          isPhishing: false,
          confidence: 0.0,
          reasons: ['Backend error: ${response.statusCode}'],
          riskLevel: 'unknown',
          riskItems: [],
        );
      }
    } catch (e) {
      print('Error checking for phishing: $e');
      return PhishingResult(
        isPhishing: false,
        confidence: 0.0,
        reasons: ['Network error: $e'],
        riskLevel: 'unknown',
        riskItems: [],
      );
    }
  }

  static Future<PhishingResult> analyzePage(
    InAppWebViewController controller,
    String url,
  ) async {
    final pageData = await extractPageData(controller, url);

    final result = await checkForPhishing(pageData);

    return result;
  }

  static Future<void> highlightRiskyElements(
    InAppWebViewController controller,
    List<RiskItem> riskItems,
  ) async {
    if (riskItems.isEmpty) return;

    final riskItemsJson = jsonEncode(
      riskItems.map((item) => item.toJson()).toList(),
    );

    final highlightScript =
        '''
    (function() {
      
      const riskItems = $riskItemsJson;

      
      let styleElement = document.getElementById('safe-browser-risk-styles');
      if (!styleElement) {
        styleElement = document.createElement('style');
        styleElement.id = 'safe-browser-risk-styles';
        styleElement.textContent = \`
          .safe-browser-risk-highlight {
            position: relative !important;
            animation: safe-browser-pulse 2s infinite !important;
          }

          .safe-browser-risk-highlight::before {
            content: '' !important;
            position: absolute !important;
            top: -4px !important;
            left: -4px !important;
            right: -4px !important;
            bottom: -4px !important;
            pointer-events: none !important;
            z-index: 999999 !important;
            border-radius: 4px !important;
          }

          .safe-browser-risk-low::before {
            border: 3px solid rgba(255, 193, 7, 0.8) !important;
            background: rgba(255, 193, 7, 0.1) !important;
          }

          .safe-browser-risk-medium::before {
            border: 3px solid rgba(255, 152, 0, 0.8) !important;
            background: rgba(255, 152, 0, 0.15) !important;
          }

          .safe-browser-risk-high::before {
            border: 3px solid rgba(244, 67, 54, 0.9) !important;
            background: rgba(244, 67, 54, 0.2) !important;
          }

          .safe-browser-risk-tooltip {
            position: absolute !important;
            top: -8px !important;
            right: -8px !important;
            background: #333 !important;
            color: white !important;
            padding: 6px 10px !important;
            border-radius: 4px !important;
            font-size: 12px !important;
            font-weight: bold !important;
            z-index: 1000000 !important;
            white-space: nowrap !important;
            box-shadow: 0 2px 8px rgba(0,0,0,0.3) !important;
            cursor: pointer !important;
          }

          .safe-browser-risk-tooltip-low {
            background: #FFC107 !important;
            color: #000 !important;
          }

          .safe-browser-risk-tooltip-medium {
            background: #FF9800 !important;
            color: #000 !important;
          }

          .safe-browser-risk-tooltip-high {
            background: #F44336 !important;
            color: white !important;
          }

          .safe-browser-risk-reason {
            position: absolute !important;
            top: 100% !important;
            right: -8px !important;
            margin-top: 4px !important;
            background: rgba(0, 0, 0, 0.9) !important;
            color: white !important;
            padding: 8px 12px !important;
            border-radius: 4px !important;
            font-size: 11px !important;
            max-width: 250px !important;
            z-index: 1000001 !important;
            display: none !important;
            box-shadow: 0 4px 12px rgba(0,0,0,0.4) !important;
            line-height: 1.4 !important;
          }

          .safe-browser-risk-tooltip:hover + .safe-browser-risk-reason,
          .safe-browser-risk-reason:hover {
            display: block !important;
          }

          @keyframes safe-browser-pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.7; }
          }
        \`;
        document.head.appendChild(styleElement);
      }

      
      function evaluateXPath(xpath) {
        try {
          const result = document.evaluate(
            xpath,
            document,
            null,
            XPathResult.FIRST_ORDERED_NODE_TYPE,
            null
          );
          return result.singleNodeValue;
        } catch (e) {
          console.error('XPath evaluation failed:', xpath, e);
          return null;
        }
      }

      
      function findElement(xpath) {
        
        let element = evaluateXPath(xpath);
        if (element) return element;

        
        try {
          element = document.querySelector(xpath);
          if (element) return element;
        } catch (e) {}

        
        const textMatch = xpath.match(/text\\(\\)=['"](.+?)['"]/);
        if (textMatch) {
          const searchText = textMatch[1].toLowerCase();
          const allElements = document.querySelectorAll('a, button, span, div, p, h1, h2, h3, h4, h5, h6');
          for (let el of allElements) {
            if (el.textContent.toLowerCase().includes(searchText)) {
              return el;
            }
          }
        }

        return null;
      }

      
      let highlightCount = 0;
      riskItems.forEach((item, index) => {
        const element = findElement(item.xpath);

        if (element && !element.classList.contains('safe-browser-risk-highlight')) {
          
          element.classList.add('safe-browser-risk-highlight');
          element.classList.add('safe-browser-risk-' + item.risk_level);

          
          const tooltip = document.createElement('div');
          tooltip.className = 'safe-browser-risk-tooltip safe-browser-risk-tooltip-' + item.risk_level;
          tooltip.textContent = '⚠️ ' + item.risk_level.toUpperCase();
          tooltip.style.position = 'absolute';

          
          const reasonPopup = document.createElement('div');
          reasonPopup.className = 'safe-browser-risk-reason';
          reasonPopup.innerHTML = '<strong>위험 요소:</strong><br>' +
                                  item.reason +
                                  '<br><small>신뢰도: ' +
                                  Math.round(item.confidence * 100) + '%</small>';

          
          const originalPosition = window.getComputedStyle(element).position;
          if (originalPosition === 'static') {
            element.style.position = 'relative';
          }

          
          element.appendChild(tooltip);
          element.appendChild(reasonPopup);

          highlightCount++;

          console.log('Highlighted risky element:', item.xpath, item.risk_level);
        } else if (!element) {
          console.warn('Could not find element for xpath:', item.xpath);
        }
      });

      console.log('Safe Browser: Highlighted ' + highlightCount + ' risky elements');
      return highlightCount;
    })();
    ''';

    try {
      await controller.evaluateJavascript(source: highlightScript);
    } catch (e) {
      print('Error highlighting risky elements: $e');
    }
  }

  static Future<void> clearHighlights(InAppWebViewController controller) async {
    final clearScript = '''
    (function() {
      
      const highlightedElements = document.querySelectorAll('.safe-browser-risk-highlight');
      highlightedElements.forEach(el => {
        el.classList.remove('safe-browser-risk-highlight', 'safe-browser-risk-low',
                            'safe-browser-risk-medium', 'safe-browser-risk-high');

        
        const tooltips = el.querySelectorAll('.safe-browser-risk-tooltip, .safe-browser-risk-reason');
        tooltips.forEach(t => t.remove());
      });

      
      const styleElement = document.getElementById('safe-browser-risk-styles');
      if (styleElement) {
        styleElement.remove();
      }

      console.log('Safe Browser: Cleared all risk highlights');
    })();
    ''';

    try {
      await controller.evaluateJavascript(source: clearScript);
    } catch (e) {
      print('Error clearing highlights: $e');
    }
  }
}

class RiskItem {
  final String xpath;
  final double confidence;
  final String reason;
  final String riskLevel;

  RiskItem({
    required this.xpath,
    required this.confidence,
    required this.reason,
    required this.riskLevel,
  });

  factory RiskItem.fromJson(Map<String, dynamic> json) {
    return RiskItem(
      xpath: json['xpath'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      reason: json['reason'] ?? '',
      riskLevel: json['risk_level'] ?? 'low',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'xpath': xpath,
      'confidence': confidence,
      'reason': reason,
      'risk_level': riskLevel,
    };
  }

  @override
  String toString() {
    return 'RiskItem(xpath: $xpath, confidence: $confidence, riskLevel: $riskLevel)';
  }
}

class PhishingResult {
  final bool isPhishing;
  final double confidence;
  final List<String> reasons;
  final String riskLevel;
  final List<RiskItem> riskItems;

  PhishingResult({
    required this.isPhishing,
    required this.confidence,
    required this.reasons,
    required this.riskLevel,
    this.riskItems = const [],
  });

  @override
  String toString() {
    return 'PhishingResult(isPhishing: $isPhishing, confidence: $confidence, riskLevel: $riskLevel, riskItems: ${riskItems.length})';
  }
}
