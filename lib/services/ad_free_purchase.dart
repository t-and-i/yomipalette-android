import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google Play Console: create ONE non-consumable product with this exact ID.
/// Its Japan base price must be configured in Play Console, not in the app.
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

/// Client-side purchase integration for internal testing.
///
/// Important: this accepts Google Play Billing purchase notifications, and
/// retains a local entitlement for offline usage. Local purchase data is NOT
/// cryptographic verification. Before production, integrate server-side
/// verification using Google Play Developer API and handle revocations.
/// Do not put Play Developer API credentials in the Android APK.
class AdFreePurchaseController extends ChangeNotifier {
  AdFreePurchaseController({AdFreeBillingGateway? gateway})
    : _gateway = gateway ?? const GooglePlayBillingGateway();

  static const _entitlementKey = 'ad_free_owned_v1';

  final AdFreeBillingGateway _gateway;
  StreamSubscription<List<PurchaseDetails>>? _updates;
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
  bool get canBuy => !_owned && _available && !_busy && _product != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    // Register before restoring purchases to avoid losing any events.
    _updates = _gateway.purchases.listen(
      (purchases) => unawaited(handleUpdates(purchases)),
      onError: (Object error) {
        _message = 'Unable to update purchases.';
        _notify();
      },
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      _owned = prefs.getBool(_entitlementKey) ?? false;
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
      _notify();
      await _gateway.restore();
    } catch (error) {
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
    // Purchase results arrive asynchronously via purchaseStream.
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

  Future<void> handleUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != adFreeProductId) continue;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _busy = true;
          _message =
              'Payment pending. Ads will remain until payment completes.';
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // A nonempty store receipt is a minimal sanity check, NOT a secure
          // replacement for Google Play Developer API verification.
          if (purchase.verificationData.serverVerificationData.isEmpty) {
            _busy = false;
            _message = 'Could not validate the purchase information.';
            break;
          }
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_entitlementKey, true);
            _owned = true;
            _message = null;
          } catch (_) {
            _message = 'Unable to save the purchase status.';
          }
          _busy = false;
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
      if (purchase.pendingCompletePurchase &&
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) &&
          _owned) {
        try {
          await _gateway.complete(purchase);
        } catch (_) {
          _message = 'Google Play could not finalize the purchase.';
        }
      }
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    super.dispose();
  }
}
