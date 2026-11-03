import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'purchase_verifier.dart';

/// Google Play Console: one non-consumable item, Japanese price JPY 500.
const adFreeProductId = 'remove_ads';

abstract class AdFreeBillingGateway {
  Stream<List<PurchaseDetails>> get purchases;
  Future<bool> isAvailable();
  Future<ProductDetailsResponse> queryProducts(Set<String> ids);
  Future<bool> purchase(ProductDetails product);
  Future<void> restore();
  Future<void> complete(PurchaseDetails purchase);
}

class GooglePlayBillingGateway implements AdFreeBillingGateway {
  const GooglePlayBillingGateway();

  InAppPurchase get _store => InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchases => _store.purchaseStream;

  @override
  Future<bool> isAvailable() => _store.isAvailable();

  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> ids) =>
      _store.queryProductDetails(ids);

  @override
  Future<bool> purchase(ProductDetails product) => _store.buyNonConsumable(
    purchaseParam: PurchaseParam(productDetails: product),
  );

  @override
  Future<void> restore() => _store.restorePurchases();

  @override
  Future<void> complete(PurchaseDetails purchase) =>
      _store.completePurchase(purchase);
}

/// Purchase state is driven by Play events AND verification, not solely by a
/// locally persisted bool. Only explicit QA builds accept unverified receipts.
/// A production backend must verify purchases and handle voided purchases / RTDN.
class AdFreePurchaseController extends ChangeNotifier {
  AdFreePurchaseController({
    AdFreeBillingGateway? gateway,
    PurchaseVerifier? verifier,
  }) : _gateway = gateway ?? const GooglePlayBillingGateway(),
       _verifier = verifier ?? createPurchaseVerifier(),
       _ownsVerifier = verifier == null;

  // Historical QA entitlement: never trust this stored flag in production.
  static const _qaEntitlementKey = 'ad_free_owned_v1';

  final AdFreeBillingGateway _gateway;
  final PurchaseVerifier _verifier;
  final bool _ownsVerifier;
  StreamSubscription<List<PurchaseDetails>>? _updates;
  Future<void> _updateTail = Future<void>.value();
  final Set<String> _acknowledgedTokens = {};
  bool _disposed = false;
  bool _initialized = false;
  bool _owned = false;
  bool _available = false;
  bool _busy = false;
  ProductDetails? _product;
  String? _message;

  bool get isAdFree => _owned;
  bool get storeAvailable => _available;
  bool get busy => _busy;
  ProductDetails? get product => _product;
  String? get message => _message;
  bool get canBuy =>
      !_owned &&
      _available &&
      !_busy &&
      _product != null &&
      _verifier is! UnconfiguredPurchaseVerifier;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    // Observe Play changes before querying or restoring historical purchases.
    _updates = _gateway.purchases.listen(
      (purchases) => unawaited(handleUpdates(purchases)),
      onError: (Object error) {
        _busy = false;
        _message = 'Unable to update purchases.';
        _notify();
      },
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      // Offline entitlement caching requires a signed server-issued grant.
      // Legacy QA flags must never unlock ads in ordinary Play releases.
      _owned = billingQaMode
          ? (prefs.getBool(_qaEntitlementKey) ?? false)
          : false;
      _notify();
      _available = await _gateway.isAvailable();
      if (!_available) {
        _message = 'Google Play Billing is unavailable.';
        _notify();
        return;
      }
      final result = await _gateway.queryProducts({adFreeProductId});
      _product = result.productDetails
          .where((item) => item.id == adFreeProductId)
          .firstOrNull;
      if (result.error != null) {
        _message = result.error!.message;
      } else if (_product == null) {
        _message = 'The ad-free item is not available in Google Play yet.';
      }
      if (_verifier is UnconfiguredPurchaseVerifier) {
        _message = 'Secure purchase verification is not configured.';
      }
      _notify();
      await _gateway.restore();
    } catch (_) {
      _message = 'Google Play could not be contacted. Try again later.';
      _notify();
    }
  }

  Future<void> buy() async {
    final details = _product;
    if (!canBuy || details == null) return;
    _busy = true;
    _message = null;
    _notify();
    try {
      if (!await _gateway.purchase(details)) {
        _busy = false;
        _message = 'Google Play could not start the purchase.';
        _notify();
      }
    } catch (_) {
      _busy = false;
      _message = 'Could not start the purchase.';
      _notify();
    }
    // New purchase results arrive asynchronously through purchaseStream.
  }

  Future<void> restorePurchases() async {
    if (!_available || _busy) return;
    _message = null;
    _notify();
    try {
      await _gateway.restore();
    } catch (_) {
      _message = 'Could not restore purchases.';
      _notify();
    }
  }

  /// Serialize notifications, including overlapping batches from Play.
  /// A rejected Future must not poison later purchase notifications.
  Future<void> handleUpdates(List<PurchaseDetails> purchases) {
    final next = _updateTail.then((_) => _applyUpdates(purchases));
    _updateTail = next.catchError((Object _) {
      _busy = false;
      _message = 'Unable to process purchase updates.';
      _notify();
    });
    return next;
  }

  Future<void> _applyUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (_disposed || purchase.productID != adFreeProductId) continue;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _busy = true;
          _message =
              'Payment pending. Ads will remain until payment completes.';
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final verification = await _verifier.verify(purchase);
          if (_disposed) return;
          final prefs = await SharedPreferences.getInstance();
          switch (verification) {
            case PurchaseVerificationResult.verified:
              if (billingQaMode) {
                await prefs.setBool(_qaEntitlementKey, true);
              }
              _owned = true;
              _busy = false;
              _message = null;
              if (purchase.pendingCompletePurchase) {
                final token = purchase.verificationData.serverVerificationData;
                if (!_acknowledgedTokens.contains(token)) {
                  try {
                    await _gateway.complete(purchase);
                    _acknowledgedTokens.add(token);
                  } catch (_) {
                    _message = 'Google Play could not finalize the purchase.';
                  }
                }
              }
              break;
            case PurchaseVerificationResult.rejected:
              _owned = false;
              _busy = false;
              if (billingQaMode) {
                await prefs.setBool(_qaEntitlementKey, false);
              }
              _message = 'Google Play purchase verification was rejected.';
              break;
            case PurchaseVerificationResult.unavailable:
              // Do not grant, revoke, or acknowledge on a transient backend
              // failure. Restore will retry when verification is available.
              _busy = false;
              _message =
                  'Purchase verification unavailable; try restore later.';
              break;
          }
          break;
        case PurchaseStatus.error:
          _busy = false;
          _message = purchase.error?.message ?? 'Google Play purchase error.';
          break;
        case PurchaseStatus.canceled:
          _busy = false;
          _message = null;
          break;
      }
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    if (_ownsVerifier) _verifier.dispose();
    super.dispose();
  }
}
