import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class PhishingDetector {
  static const String backendUrl = 'https://da.sada.ai.kr';

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
        (async function() {
          const images = document.querySelectorAll('img');
          const imageArray = Array.from(images).slice(0, 5);
          const base64Images = [];

          for (const img of imageArray) {
            try {
              const canvas = document.createElement('canvas');
              canvas.width = img.naturalWidth || img.width;
              canvas.height = img.naturalHeight || img.height;
              const ctx = canvas.getContext('2d');
              ctx.drawImage(img, 0, 0);
              const base64 = canvas.toDataURL('image/png');
              base64Images.push(base64);
            } catch (e) {
              console.error('Failed to convert image to base64:', e);
              base64Images.push(null);
            }
          }

          return base64Images;
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

      // List<dynamic>? stylesheets = await controller.evaluateJavascript(
      //   source: '''
      //   (function() {
      //     const links = document.querySelectorAll('link[rel="stylesheet"]');
      //     return Array.from(links).slice(0, 5).map(l => l.href);
      //   })();
      // ''',
      // );

      // List<dynamic>? metaTags = await controller.evaluateJavascript(
      //   source: '''
      //   (function() {
      //     const metas = document.querySelectorAll('meta');
      //     return Array.from(metas).map(m => ({
      //       name: m.getAttribute('name'),
      //       property: m.getAttribute('property'),
      //       content: m.getAttribute('content')
      //     }));
      //   })();
      // ''',
      // );

      String? title = await controller.getTitle();

      List<dynamic>? stylesheets = [];
      List<dynamic>? metaTags = [];

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

        // Check for happygbs key
        String? dangerReason;
        if (data is Map && data.containsKey('happygbs')) {
          dangerReason = data['happygbs'] as String?;
          print('⚠️ DANGER DETECTED: $dangerReason');

          return PhishingResult(
            isPhishing: true,
            confidence: 1.0,
            reasons: [dangerReason ?? 'Dangerous website detected'],
            riskLevel: 'critical',
            riskItems: [],
            dangerReason: dangerReason,
          );
        }

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

        // If more than 5 dangerous elements, treat as critical danger
        if (riskItems.length > 5) {
          return PhishingResult(
            isPhishing: true,
            confidence: maxConfidence,
            reasons: reasons,
            riskLevel: 'critical',
            riskItems: riskItems,
            dangerReason: '이 웹사이트에서 ${riskItems.length}개의 위험 요소가 발견되었습니다.',
          );
        }

        return PhishingResult(
          isPhishing: isPhishing,
          confidence: maxConfidence,
          reasons: reasons,
          riskLevel: overallRiskLevel,
          riskItems: riskItems,
          dangerReason: null,
        );
      } else {
        return PhishingResult(
          isPhishing: false,
          confidence: 0.0,
          reasons: ['Backend error: ${response.statusCode}'],
          riskLevel: 'unknown',
          riskItems: [],
          dangerReason: null,
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
        dangerReason: null,
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
            cursor: pointer !important;
          }

          .safe-browser-risk-highlight::after {
            pointer-events: auto;
            border: 2px solid red;
            animation: safe-browser-pulse 1s infinite !important;
            backdrop-filter: blur(5px) !important;
            content: '' !important;
            position: absolute !important;
            top: -4px !important;
            left: -4px !important;
            right: -4px !important;
            bottom: -4px !important;
            z-index: 999998 !important;
          }

          .safe-browser-risk-highlight::before {
            content: attr(data-risk-reason) !important;
            position: absolute !important;
            top: 50% !important;
            left: 50% !important;
            transform: translate(-50%, -50%);
            z-index: 999999 !important;
            border-radius: 4px !important;
            padding: 8px 14px !important;
            background: #333 !important;
            color: white !important;
            font-size: 16px !important;
            font-weight: bold !important;
            white-space: nowrap !important;
            box-shadow: 0 2px 8px rgba(0,0,0,0.3) !important;
          }

          .safe-browser-risk-low::after {
            border-color: #FFC107 !important;
          }

          .safe-browser-risk-medium::after {
            border-color: #FF9800 !important;
          }

          .safe-browser-risk-high::after {
            border-color: #F44336 !important;
          }

          .safe-browser-risk-low::before {
            background: #FFC107 !important;
            color: #000 !important;
          }

          .safe-browser-risk-medium::before {
            background: #FF9800 !important;
            color: #000 !important;
          }

          .safe-browser-risk-high::before {
            background: #F44336 !important;
            color: white !important;
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

          const kormap = {"high": "위험", "medium": "주의", "low": "의심"};

          const shortReason = item.reason.length > 100 ? item.reason.substring(0, 100) + '...' : item.reason;
          // element.setAttribute('data-risk-reason', kormap[item.risk_level] + ': ' + shortReason);
          element.setAttribute('data-risk-reason', kormap[item.risk_level]);


          const originalPosition = window.getComputedStyle(element).position;
          if (originalPosition === 'static') {
            element.style.position = 'relative';
          }


          let clickHandler = function(e) {
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();

            element.classList.remove('safe-browser-risk-highlight', 'safe-browser-risk-low',
                                     'safe-browser-risk-medium', 'safe-browser-risk-high');
            element.removeAttribute('data-risk-reason');
            element.removeEventListener('click', clickHandler, true);

            setTimeout(function() {
              element.click();
            }, 50);

            return false;
          };


          element.addEventListener('click', clickHandler, true);

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
        el.removeAttribute('data-risk-reason');
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

  static Future<void> showDangerWarningOverlay(
    InAppWebViewController controller,
    String reason,
    List<RiskItem> riskItems,
  ) async {
    final riskItemsJson = jsonEncode(
      riskItems.map((item) => item.toJson()).toList(),
    );

    final overlayScript =
        '''
    (function() {
      // Remove existing overlay if present
      const existingOverlay = document.getElementById('safe-browser-danger-overlay');
      if (existingOverlay) {
        existingOverlay.remove();
      }

      const riskItems = $riskItemsJson;
      const reason = ${jsonEncode(reason)};

      const kormap = {"high": "높음", "medium": "중간", "low": "낮음"};

      function getRiskColor(riskLevel) {
        switch(riskLevel.toLowerCase()) {
          case 'low': return '#f9a825';
          case 'medium': return '#ff9800';
          case 'high': return '#ff5722';
          case 'critical': return '#f44336';
          default: return '#9e9e9e';
        }
      }

      // Create overlay HTML
      const overlayHTML = \`
        <div id="safe-browser-danger-overlay" style="
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background: #ffffff;
          z-index: 2147483647;
          overflow-y: auto;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        ">
          <div style="
            max-width: 600px;
            margin: 0 auto;
            padding: 24px;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
          ">
            <div style="text-align: center;">
              <div style="
                width: 120px;
                height: 120px;
                margin: 0 auto 32px;
                background: #c62828;
                border-radius: 60px;
                display: flex;
                align-items: center;
                justify-content: center;
              ">
                <svg width="72" height="72" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2">
                  <path d="M12 9v4m0 4h.01M5.07 19H19a2 2 0 001.664-3.125L13.664 4.125A2 2 0 0010.336 4.125L3.336 15.875A2 2 0 005.07 19z"/>
                </svg>
              </div>

              <h1 style="
                font-size: 32px;
                font-weight: bold;
                color: #b71c1c;
                margin: 0 0 16px 0;
              ">위험한 웹사이트</h1>

              <p style="
                font-size: 18px;
                color: #c62828;
                margin: 0 0 32px 0;
              ">이 웹사이트는 위험할 수 있습니다.</p>
            </div>

            <div style="
              background: white;
              border-radius: 16px;
              padding: 20px;
              box-shadow: 0 4px 12px rgba(0,0,0,0.1);
              width: 100%;
              margin-bottom: 48px;
            ">
              <div style="display: flex; align-items: center; margin-bottom: 12px;">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#c62828" stroke-width="2" style="margin-right: 8px;">
                  <circle cx="12" cy="12" r="10"/>
                  <line x1="12" y1="16" x2="12" y2="12"/>
                  <line x1="12" y1="8" x2="12.01" y2="8"/>
                </svg>
                <h2 style="
                  font-size: 18px;
                  font-weight: bold;
                  margin: 0;
                ">위험 사유</h2>
              </div>

              <p style="
                font-size: 16px;
                line-height: 1.5;
                font-weight: 600;
                margin: 0;
                color: #333;
              ">\${reason}</p>
            </div>

            <button id="safe-browser-go-back" style="
              width: 100%;
              background: #43a047;
              color: white;
              border: none;
              border-radius: 12px;
              padding: 16px 32px;
              font-size: 16px;
              font-weight: bold;
              cursor: pointer;
              margin-bottom: 16px;
              display: flex;
              align-items: center;
              justify-content: center;
            ">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-right: 8px;">
                <line x1="19" y1="12" x2="5" y2="12"/>
                <polyline points="12 19 5 12 12 5"/>
              </svg>
              안전한 페이지로 돌아가기
            </button>

            <button id="safe-browser-continue" style="
              width: 100%;
              background: transparent;
              color: #c62828;
              border: 2px solid #c62828;
              border-radius: 12px;
              padding: 16px 32px;
              font-size: 16px;
              font-weight: bold;
              cursor: pointer;
              display: flex;
              align-items: center;
              justify-content: center;
            ">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-right: 8px;">
                <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>
                <line x1="12" y1="9" x2="12" y2="13"/>
                <line x1="12" y1="17" x2="12.01" y2="17"/>
              </svg>
              위험을 감수하고 계속하기
            </button>
          </div>
        </div>
      \`;

      // Insert overlay into page
      document.body.insertAdjacentHTML('beforeend', overlayHTML);

      // Add event listeners
      document.getElementById('safe-browser-go-back').addEventListener('click', function() {
        window.flutter_inappwebview.callHandler('dangerWarningGoBack');
      });

      document.getElementById('safe-browser-continue').addEventListener('click', function() {
        window.flutter_inappwebview.callHandler('dangerWarningContinue');
      });

      console.log('Safe Browser: Danger warning overlay shown');
    })();
    ''';

    try {
      await controller.evaluateJavascript(source: overlayScript);
    } catch (e) {
      print('Error showing danger warning overlay: $e');
    }
  }

  static Future<void> removeDangerWarningOverlay(
    InAppWebViewController controller,
  ) async {
    final removeScript = '''
    (function() {
      const overlay = document.getElementById('safe-browser-danger-overlay');
      if (overlay) {
        overlay.remove();
        console.log('Safe Browser: Danger warning overlay removed');
      }
    })();
    ''';

    try {
      await controller.evaluateJavascript(source: removeScript);
    } catch (e) {
      print('Error removing danger warning overlay: $e');
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
  final String? dangerReason; // happygbs reason

  PhishingResult({
    required this.isPhishing,
    required this.confidence,
    required this.reasons,
    required this.riskLevel,
    this.riskItems = const [],
    this.dangerReason,
  });

  @override
  String toString() {
    return 'PhishingResult(isPhishing: $isPhishing, confidence: $confidence, riskLevel: $riskLevel, riskItems: ${riskItems.length}, dangerReason: $dangerReason)';
  }
}
