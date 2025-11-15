import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'services/phishing_detector.dart';
import 'widgets/phishing_warning_dialog.dart';
import 'widgets/browser_app_bar.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Safe Browser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5E35B1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(elevation: 0, centerTitle: false),
      ),
      home: const WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage>
    with SingleTickerProviderStateMixin {
  InAppWebViewController? webViewController;
  PullToRefreshController? pullToRefreshController;
  final TextEditingController urlController = TextEditingController();
  String currentUrl = 'https://www.google.com';
  double loadingProgress = 0;
  bool canGoBack = false;
  bool canGoForward = false;
  bool isCheckingPhishing = false;
  PhishingResult? phishingResult;
  late AnimationController _fadeController;
  Set<String> approvedDangerousUrls = {}; // URLs user approved to visit

  @override
  void initState() {
    super.initState();
    urlController.text = currentUrl;

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: const Color(0xFF5E35B1)),
      onRefresh: () async {
        webViewController?.reload();
      },
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    urlController.dispose();
    super.dispose();
  }

  void loadUrl(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void updateNavigationButtons() async {
    canGoBack = await webViewController?.canGoBack() ?? false;
    canGoForward = await webViewController?.canGoForward() ?? false;
    setState(() {});
  }

  Future<void> checkPageForPhishing(String url) async {
    if (webViewController == null) return;

    // Skip check if user has approved this URL
    if (approvedDangerousUrls.contains(url)) {
      print('⚠️ Skipping phishing check for approved URL: $url');
      return;
    }

    setState(() {
      isCheckingPhishing = true;
      phishingResult = null;
    });

    try {
      final result = await PhishingDetector.analyzePage(
        webViewController!,
        url,
      );

      setState(() {
        phishingResult = result;
        isCheckingPhishing = false;
      });

      // Check if this is a dangerous site (happygbs or >5 risk items)
      if (result.dangerReason != null) {
        // Show JavaScript overlay on the page
        await PhishingDetector.showDangerWarningOverlay(
          webViewController!,
          result.dangerReason!,
          result.riskItems,
        );
        return;
      }

      if (result.riskItems.isNotEmpty) {
        await PhishingDetector.highlightRiskyElements(
          webViewController!,
          result.riskItems,
        );
      }

      // if (result.isPhishing && mounted) {
      //   final riskLevelPriority = {
      //     'low': 1,
      //     'medium': 2,
      //     'high': 3,
      //     'critical': 4,
      //   };
      //   final priority = riskLevelPriority[result.riskLevel.toLowerCase()] ?? 0;

      //   if (priority >= 2) {
      //     showPhishingWarning(result);
      //   }
      // }
    } catch (e) {
      setState(() {
        isCheckingPhishing = false;
      });
      print('Error checking for phishing: $e');
    }
  }

  void showPhishingWarning(PhishingResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PhishingWarningDialog(
        result: result,
        webViewController: webViewController,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: BrowserAppBar(
        urlController: urlController,
        canGoBack: canGoBack,
        canGoForward: canGoForward,
        isCheckingPhishing: isCheckingPhishing,
        phishingResult: phishingResult,
        onHome: () {
          loadUrl(currentUrl);
          urlController.text = currentUrl;
        },
        onBack: () {
          webViewController?.goBack();
        },
        onForward: () {
          webViewController?.goForward();
        },
        onSubmitUrl: (value) {
          loadUrl(value);
        },
        onSecurityIconTap: () {
          if (phishingResult != null) {
            showPhishingWarning(phishingResult!);
          }
        },
      ),
      body: Column(
        children: [
          if (loadingProgress < 1.0)
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 200),
              tween: Tween(begin: 0, end: loadingProgress),
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                  minHeight: 3,
                );
              },
            ),

          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(currentUrl)),
              pullToRefreshController: pullToRefreshController,
              initialSettings: InAppWebViewSettings(
                useShouldOverrideUrlLoading: true,
                mediaPlaybackRequiresUserGesture: false,
                javaScriptEnabled: true,
                javaScriptCanOpenWindowsAutomatically: true,
              ),
              onWebViewCreated: (controller) {
                webViewController = controller;

                // Add JavaScript handlers for danger warning buttons
                controller.addJavaScriptHandler(
                  handlerName: 'dangerWarningGoBack',
                  callback: (args) async {
                    // Remove overlay and go back
                    await PhishingDetector.removeDangerWarningOverlay(controller);
                    controller.goBack();
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'dangerWarningContinue',
                  callback: (args) async {
                    // Get current URL and add to approved list
                    final url = await controller.getUrl();
                    if (url != null) {
                      approvedDangerousUrls.add(url.toString());
                    }
                    // Remove overlay
                    await PhishingDetector.removeDangerWarningOverlay(controller);

                    // Show highlights for dangerous elements
                    if (phishingResult != null && phishingResult!.riskItems.isNotEmpty) {
                      await PhishingDetector.highlightRiskyElements(
                        controller,
                        phishingResult!.riskItems,
                      );
                    }
                  },
                );
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                return NavigationActionPolicy.ALLOW;
              },
              onLoadStart: (controller, url) async {
                setState(() {
                  loadingProgress = 0;
                  if (url != null) {
                    urlController.text = url.toString();
                  }
                });
                updateNavigationButtons();

                await PhishingDetector.clearHighlights(controller);
              },
              onLoadStop: (controller, url) async {
                setState(() {
                  loadingProgress = 1.0;
                });
                updateNavigationButtons();
                pullToRefreshController?.endRefreshing();

                if (url != null) {
                  checkPageForPhishing(url.toString());
                }
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  loadingProgress = progress / 100;
                });
              },
              onUpdateVisitedHistory: (controller, url, androidIsReload) {
                updateNavigationButtons();
              },
            ),
          ),
        ],
      ),
    );
  }
}
