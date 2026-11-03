import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/ad_free_purchase.dart';

/// Presentation only: business rules stay in AdFreePurchaseController.
class AdFreeSection extends StatelessWidget {
  const AdFreeSection({
    required this.purchase,
    required this.strings,
    super.key,
  });

  final AdFreePurchaseController purchase;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(height: 32),
      Text(
        strings.get('adFreeTitle'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 6),
      if (purchase.isAdFree)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.verified_outlined),
          title: Text(strings.get('adFreeActive')),
        )
      else ...[
        Text(
          strings.get('adFreeDescription'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: purchase.canBuy ? purchase.buy : null,
          icon: const Icon(Icons.do_not_disturb_on_outlined),
          label: Text(
            purchase.product == null
                ? strings.get('adFreePurchase')
                : '${strings.get('adFreePurchase')} · ${purchase.product!.price}',
          ),
        ),
        if (purchase.busy) const LinearProgressIndicator(),
      ],
      TextButton.icon(
        onPressed: purchase.storeAvailable && !purchase.busy
            ? purchase.restorePurchases
            : null,
        icon: const Icon(Icons.restore),
        label: Text(strings.get('adFreeRestore')),
      ),
      if (purchase.message != null)
        Text(
          strings.get('adFreeStoreNotice'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );
}
