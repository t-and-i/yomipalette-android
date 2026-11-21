import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'purchase_verifier.dart';
import 'offline_entitlement_cache.dart';

/// New permanent license; retain existing remove_ads purchases as grandfathered.
const fullAccessProductId = 'full_access';
const legacyAdFreeProductId = 'remove_ads';
const adFreeProductId = fullAccessProductId;

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
    OfflineEntitlementStore? offlineStore,
    DateTime Function()? clock,
  }) : _gateway = gateway ?? const GooglePlayBillingGateway(),
       _verifier = verifier ?? createPurchaseVerifier(),
       _ownsVerifier = verifier == null,
       _offline = offlineStore ?? SignedOfflineEntitlementStore(),
       _offlineEnabled = offlineStore != null || !billingQaMode,
       _clock = clock ?? DateTime.now;

  // Historical QA entitlement: never trust this stored flag in production.
  static const _qaEntitlementKey = 'ad_free_owned_v1';

  final AdFreeBillingGateway _gateway;
  final PurchaseVerifier _verifier;
  final bool _ownsVerifier;
  final OfflineEntitlementStore _offline;
  final bool _offlineEnabled;
  final DateTime Function() _clock;
  bool _offlineReady = false;
  DateTime? _onlineVerifiedAt;
  DateTime? _lastCachedRecheck;
  bool _checkingCachedPurchase = false;
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

  bool get isLicensed {
    final now = _clock().toUtc();
    final online =
        _owned &&
        (billingQaMode ||
            (_onlineVerifiedAt != null &&
                !now.isBefore(
                  _onlineVerifiedAt!.subtract(const Duration(minutes: 1)),
                ) &&
                // If secure storage is unavailable, allow only a brief
                // freshly verified in-memory online session. Never use this
                // as a substitute for the signed 72-hour offline grant.
                now.isBefore(
                  _onlineVerifiedAt!.add(const Duration(minutes: 5)),
                )));
    return online || (_offlineReady && _offline.hasValidGrant);
  }

  // Kept for existing integrations and tests during the migration.
  bool get isAdFree => isLicensed;
  bool get storeAvailable => _available;
  bool get busy => _busy;
  ProductDetails? get product => _product;
  String? get message => _message;
  bool get canBuy =>
      !isLicensed &&
      _available &&
      !_busy &&
      _product != null &&
      (billingQaMode || _offlineReady) &&
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
      if (_offlineEnabled) {
        try {
          await _offline.initialize();
          _offlineReady = true;
        } catch (_) {
          // Online billing is still available if encrypted storage fails.
          _offlineReady = false;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      // Offline entitlement caching requires a signed server-issued grant.
      // Legacy QA flags must never unlock the app in ordinary Play releases.
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
      final result = await _gateway.queryProducts({
        fullAccessProductId,
        legacyAdFreeProductId,
      });
      _product = result.productDetails
          .where((item) => item.id == fullAccessProductId)
          .firstOrNull;
      if (result.error != null) {
        _message = result.error!.message;
      } else if (_product == null) {
        _message = 'The full access item is not available in Google Play yet.';
      }
      if (_verifier is UnconfiguredPurchaseVerifier) {
        _message = 'Secure purchase verification is not configured.';
      }
      _notify();
      await _gateway.restore();
      await _revalidateCachedPurchase();
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
      await _revalidateCachedPurchase(force: true);
      await _gateway.restore();
    } catch (_) {
      _message = 'Could not restore purchases.';
      _notify();
    }
  }

  /// Re-evaluate a signed grant on foreground, then check purchase revocation
  /// online using the receipt kept in Android Keystore-backed storage.
  Future<void> refreshEntitlement() async {
    if (_offlineReady) {
      try {
        await _offline.refresh();
      } catch (_) {
        // A storage outage must never create an offline entitlement.
      }
    }
    _notify();
    try {
      _available = await _gateway.isAvailable();
      if (_available) {
        await _revalidateCachedPurchase();
        await _gateway.restore();
      }
    } catch (_) {
      // Preserve only the remaining signed offline window.
    }
    _notify();
  }

  Future<PurchaseVerificationOutcome> _verifyPurchase(
    PurchaseDetails purchase,
  ) async {
    if (_offlineReady && _verifier is OfflineGrantPurchaseVerifier) {
      try {
        final deviceId = await _offline.getDeviceId();
        return await (_verifier as OfflineGrantPurchaseVerifier)
            .verifyForDevice(purchase, deviceId);
      } catch (_) {
        // Fallback to the existing online-only verification protocol.
      }
    }
    return PurchaseVerificationOutcome(await _verifier.verify(purchase));
  }

  Future<void> _saveVerifiedGrant(
    String? grant,
    String productId,
    String receipt,
  ) async {
    if (_offlineReady && grant != null && grant.isNotEmpty) {
      try {
        if (await _offline.accept(grant)) {
          await _offline.rememberPurchase(productId, receipt);
        }
      } catch (_) {
        // Failed storage/signature verification never grants offline access.
      }
    }
  }

  Future<void> _revalidateCachedPurchase({bool force = false}) async {
    if (!_offlineReady ||
        _verifier is! OfflineGrantPurchaseVerifier ||
        _checkingCachedPurchase) {
      return;
    }
    final now = _clock().toUtc();
    if (!force &&
        _lastCachedRecheck != null &&
        now.difference(_lastCachedRecheck!) < const Duration(minutes: 3)) {
      return;
    }
    final cached = await _offline.getCachedPurchase();
    if (cached == null) return;
    _checkingCachedPurchase = true;
    _lastCachedRecheck = now;
    try {
      final receipt = PurchaseDetails(
        productID: cached.productId,
        purchaseID: null,
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: cached.token,
          source: 'google_play',
        ),
        transactionDate: null,
        status: PurchaseStatus.restored,
      );
      final outcome = await _verifyPurchase(receipt);
      if (_disposed) return;
      switch (outcome.result) {
        case PurchaseVerificationResult.verified:
          await _saveVerifiedGrant(
            outcome.offlineGrant,
            cached.productId,
            cached.token,
          );
          _owned = true;
          _onlineVerifiedAt = _clock().toUtc();
          _message = null;
          break;
        case PurchaseVerificationResult.rejected:
          _owned = false;
          _onlineVerifiedAt = null;
          await _offline.clear();
          if (billingQaMode) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_qaEntitlementKey, false);
          }
          _message = 'Google Play purchase verification was rejected.';
          break;
        case PurchaseVerificationResult.unavailable:
          // Keep only the unexpired signed grant; do not extend its TTL.
          break;
      }
      _notify();
    } catch (_) {
      // Temporary backend/storage failure does not reset the signed expiry.
    } finally {
      _checkingCachedPurchase = false;
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
      if (_disposed ||
          (purchase.productID != fullAccessProductId &&
              purchase.productID != legacyAdFreeProductId)) {
        continue;
      }
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _busy = true;
          _message =
              'Payment pending. Full access begins after payment completes.';
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final verification = await _verifyPurchase(purchase);
          if (_disposed) return;
          final prefs = await SharedPreferences.getInstance();
          switch (verification.result) {
            case PurchaseVerificationResult.verified:
              if (billingQaMode) {
                await prefs.setBool(_qaEntitlementKey, true);
              }
              await _saveVerifiedGrant(
                verification.offlineGrant,
                purchase.productID,
                purchase.verificationData.serverVerificationData,
              );
              _owned = true;
              _onlineVerifiedAt = _clock().toUtc();
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
              _onlineVerifiedAt = null;
              if (_offlineReady) {
                try {
                  await _offline.clear();
                } catch (_) {
                  // In-memory entitlement is dropped even on storage failure.
                }
              }
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
