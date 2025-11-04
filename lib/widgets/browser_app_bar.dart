import 'package:flutter/material.dart';
import '../services/phishing_detector.dart';
import 'security_icon.dart';

class BrowserAppBar extends StatefulWidget implements PreferredSizeWidget {
  final TextEditingController urlController;
  final bool canGoBack;
  final bool canGoForward;
  final bool isCheckingPhishing;
  final PhishingResult? phishingResult;
  final VoidCallback onHome;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final Function(String) onSubmitUrl;

  const BrowserAppBar({
    super.key,
    required this.urlController,
    required this.canGoBack,
    required this.canGoForward,
    required this.isCheckingPhishing,
    this.phishingResult,
    required this.onHome,
    required this.onBack,
    required this.onForward,
    required this.onSubmitUrl,
  });

  @override
  State<BrowserAppBar> createState() => _BrowserAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(60);
}

class _BrowserAppBarState extends State<BrowserAppBar> {
  bool isUrlExpanded = false;
  final FocusNode _urlFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _urlFocusNode.addListener(() {
      setState(() {
        isUrlExpanded = _urlFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _urlFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary,
              colorScheme.primary.withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: AnimatedOpacity(
            opacity: isUrlExpanded ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: isUrlExpanded
                ? const SizedBox.shrink()
                : TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 200),
                    tween: Tween(begin: 0.95, end: 1.0),
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.home_rounded,
                                color: Colors.white),
                            onPressed: widget.onHome,
                            tooltip: 'Home',
                            splashRadius: 24,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          leadingWidth: isUrlExpanded ? 0 : 56,
          title: _buildUrlBar(colorScheme),
          actions: isUrlExpanded
              ? null
              : [
                  _buildAnimatedButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: widget.canGoBack ? widget.onBack : null,
                    tooltip: 'Back',
                    marginRight: 4,
                  ),
                  _buildAnimatedButton(
                    icon: Icons.arrow_forward_rounded,
                    onPressed: widget.canGoForward ? widget.onForward : null,
                    tooltip: 'Forward',
                    marginRight: 8,
                  ),
                ],
        ),
      ),
    );
  }

  Widget _buildAnimatedButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    required double marginRight,
  }) {
    return AnimatedScale(
      scale: onPressed != null ? 1.0 : 0.9,
      duration: const Duration(milliseconds: 200),
      child: AnimatedOpacity(
        opacity: onPressed != null ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 200),
        child: Container(
          margin: EdgeInsets.only(right: marginRight),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onPressed,
            tooltip: tooltip,
            splashRadius: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildUrlBar(ColorScheme colorScheme) {
    return Container(
      height: 48,
      margin: EdgeInsets.only(
        left: isUrlExpanded ? 16 : 0,
        right: isUrlExpanded ? 16 : 0,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (!isUrlExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8),
              child: SecurityIcon(
                phishingResult: widget.phishingResult,
                defaultColor: colorScheme.primary,
              ),
            ),
          Expanded(
            child: TextField(
              controller: widget.urlController,
              focusNode: _urlFocusNode,
              style: TextStyle(fontSize: 15, color: Colors.grey[800]),
              decoration: InputDecoration(
                hintText: 'Search or enter website',
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 15,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.only(
                  left: isUrlExpanded ? 16 : 0,
                  right: 16,
                ),
              ),
              onSubmitted: (value) {
                widget.onSubmitUrl(value);
                _urlFocusNode.unfocus();
              },
            ),
          ),
          if (widget.isCheckingPhishing && !isUrlExpanded)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 800),
                tween: Tween(begin: 0.8, end: 1.0),
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colorScheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          else if (!isUrlExpanded)
            const SizedBox(width: 8),
          if (isUrlExpanded)
            IconButton(
              icon: Icon(Icons.close, color: Colors.grey[600]),
              onPressed: () {
                _urlFocusNode.unfocus();
              },
              tooltip: 'Close',
            ),
        ],
      ),
    );
  }
}
