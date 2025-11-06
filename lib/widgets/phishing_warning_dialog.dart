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
      title: const Text('피싱 감지 결과'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              '위험도: ${result.riskLevel.toUpperCase()}',
              style: TextStyle(
                color: _getRiskColor(result.riskLevel),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '확률: ${(result.confidence * 100).toStringAsFixed(1)}%',
              style: TextStyle(color: Colors.grey[700]),
            ),
            if (result.reasons.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('이유:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...result.reasons.map(
                (reason) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(reason)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            webViewController?.goBack();
          },
          child: const Text('돌아가기'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('계속하기'),
        ),
      ],
    );
  }
}
