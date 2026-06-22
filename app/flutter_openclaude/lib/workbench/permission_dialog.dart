import 'package:flutter/material.dart';

import 'app_branding.dart';
import 'workbench_models.dart';

class PermissionDialog extends StatelessWidget {
  const PermissionDialog({
    super.key,
    required this.request,
    required this.onDecision,
  });

  final PermissionRequest request;
  final ValueChanged<String> onDecision;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(request.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$appDisplayName needs your permission to continue this step. Review the action before allowing it.',
            ),
            const SizedBox(height: 12),
            Text(request.riskSummary),
            const SizedBox(height: 12),
            Text(
              'Requested action',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            SelectableText(request.action),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Raw request'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(request.rawPayload),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            onDecision('deny');
            Navigator.of(context).pop();
          },
          child: const Text('Deny'),
        ),
        OutlinedButton(
          onPressed: () {
            onDecision('allow_all');
            Navigator.of(context).pop();
          },
          child: const Text('Allow all'),
        ),
        FilledButton(
          onPressed: () {
            onDecision('allow');
            Navigator.of(context).pop();
          },
          child: const Text('Allow once'),
        ),
      ],
    );
  }
}
