import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/phishing_detector.dart';

class PhishingWarningDialog extends StatelessWidget {
  final PhishingResult result;
  final InAppWebViewController? webViewController;

  const PhishingWarningDialog({
    super.key,
    required this.result,
    this.webViewController,
  });

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
    return AlertDialog(
      icon: Icon(
        Icons.warning_rounded,
        color: _getRiskColor(result.riskLevel),
        size: 48,
      ),
      title: const Text('Potential Phishing Site Detected'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This site may be attempting to steal your information.',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Risk Level: ${result.riskLevel.toUpperCase()}',
            style: TextStyle(
              color: _getRiskColor(result.riskLevel),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%',
            style: TextStyle(color: Colors.grey[700]),
          ),
          if (result.reasons.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Reasons:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...result.reasons.map((reason) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(reason)),
                    ],
                  ),
                )),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            webViewController?.goBack();
          },
          child: const Text('Go Back'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Continue Anyway'),
        ),
      ],
    );
  }
}
