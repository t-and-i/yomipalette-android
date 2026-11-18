import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/ad_free_purchase.dart';
import '../services/trial_access.dart';

/// Status and purchase action; entitlement policy lives in controllers.
class AccessPurchaseSection extends StatelessWidget {
  const AccessPurchaseSection({
    required this.purchase,
    required this.strings,
    this.trial,
    this.compact = false,
    super.key,
  });

  final AdFreePurchaseController purchase;
  final TrialAccessController? trial;
  final AppStrings strings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final licensed = purchase.isLicensed;
    final expired = trial?.isExpired ?? false;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 0, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) const Divider(height: 24),
          Text(
            strings.get('accessTitle'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          if (licensed)
            Text(strings.get('accessLicensed'))
          else ...[
            if (trial != null && !trial!.initialized)
              Text(strings.get('trialChecking'))
            else if (expired)
              Text(strings.get('trialExpired'))
            else if (trial != null)
              Text(
                strings
                    .get('trialRemaining')
                    .replaceFirst('{days}', trial!.daysRemaining.toString()),
              ),
            if (!compact) ...[
              const SizedBox(height: 6),
              Text(
                strings.get('accessDescription'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: purchase.canBuy ? purchase.buy : null,
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(
                purchase.product == null
                    ? strings.get('accessBuy')
                    : '${strings.get('accessBuy')} · ${purchase.product!.price}',
              ),
            ),
          ],
          if (!licensed)
            TextButton.icon(
              onPressed: purchase.storeAvailable && !purchase.busy
                  ? purchase.restorePurchases
                  : null,
              icon: const Icon(Icons.restore),
              label: Text(strings.get('accessRestore')),
            ),
          if (purchase.busy) const LinearProgressIndicator(),
          if (purchase.message != null)
            Text(
              strings.get('accessStoreNotice'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
