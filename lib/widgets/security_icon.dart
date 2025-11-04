import 'package:flutter/material.dart';
import '../services/phishing_detector.dart';

class SecurityIcon extends StatefulWidget {
  final PhishingResult? phishingResult;
  final Color defaultColor;

  const SecurityIcon({
    super.key,
    this.phishingResult,
    required this.defaultColor,
  });

  @override
  State<SecurityIcon> createState() => _SecurityIconState();
}

class _SecurityIconState extends State<SecurityIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_controller);

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void didUpdateWidget(SecurityIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger animation when phishing result changes
    if (oldWidget.phishingResult != widget.phishingResult &&
        widget.phishingResult != null) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'low':
        return Colors.yellow.shade700;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.deepOrange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    IconData iconData;
    Color iconColor;

    if (widget.phishingResult == null) {
      // Default secure icon
      iconData = Icons.lock_rounded;
      iconColor = widget.defaultColor;
    } else if (widget.phishingResult!.isPhishing) {
      // Warning icon for phishing
      iconData = Icons.warning_rounded;
      iconColor = _getRiskColor(widget.phishingResult!.riskLevel);
    } else {
      // Shield icon for verified safe
      iconData = Icons.shield_rounded;
      iconColor = Colors.green;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Transform.rotate(
            angle: _rotationAnimation.value,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: child,
                );
              },
              child: Icon(
                iconData,
                key: ValueKey(iconData),
                size: 18,
                color: iconColor,
              ),
            ),
          ),
        );
      },
    );
  }
}
