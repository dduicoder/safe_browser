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
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    urlController.text = currentUrl;

    // Initialize fade animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
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

    setState(() {
      isCheckingPhishing = true;
      phishingResult = null;
    });

    try {
      final result = await PhishingDetector.analyzePage(webViewController!, url);

      setState(() {
        phishingResult = result;
        isCheckingPhishing = false;
      });

      // Show warning dialog if phishing detected
      if (result.isPhishing && mounted) {
        showPhishingWarning(result);
      }
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
      ),
      body: Column(
        children: [
          // Loading progress bar
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
          // WebView with fade animation
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnimation,
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
                  _fadeController.forward(); // Initial fade in
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  // Allow all navigation to proceed
                  return NavigationActionPolicy.ALLOW;
                },
                onLoadStart: (controller, url) {
                  _fadeController.reverse(); // Fade out
                  setState(() {
                    loadingProgress = 0;
                    if (url != null) {
                      urlController.text = url.toString();
                    }
                  });
                  updateNavigationButtons();
                },
                onLoadStop: (controller, url) async {
                  setState(() {
                    loadingProgress = 1.0;
                  });
                  _fadeController.forward(); // Fade in
                  updateNavigationButtons();
                  pullToRefreshController?.endRefreshing();

                  // Check for phishing when page finishes loading
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
          ),
        ],
      ),
    );
  }
}
