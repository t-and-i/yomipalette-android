import 'package:flutter/foundation.dart';

import 'signed_trial_cache.dart';
import 'purchase_verifier.dart' show billingQaMode;
import 'trial_verifier.dart';

/// Server-owned 30-day trial. Google login is required for new trial grants;
/// buying full_access in Google Play remains completely independent of login.
class TrialAccessController extends ChangeNotifier {
  TrialAccessController({
    TrialEntitlementStore? store,
    TrialIdentityProvider? identity,
    TrialVerifier? verifier,
    DateTime Function()? clock,
    bool allowQaTrial = billingQaMode,
  }) : _store = store ?? SignedTrialEntitlementStore(),
       _identity = identity ?? GoogleTrialIdentityProvider(),
       _verifier = verifier ?? createTrialVerifier(),
       _ownsVerifier = verifier == null,
       _allowQaTrial = allowQaTrial,
       _clock = clock ?? DateTime.now;

  static const duration = Duration(days: 30);
  final TrialEntitlementStore _store;
  final TrialIdentityProvider _identity;
  final TrialVerifier _verifier;
  final bool _ownsVerifier;
  final bool _allowQaTrial;
  final DateTime Function() _clock;

  bool _initialized = false;
  bool _disposed = false;
  bool _busy = false;
  bool _blocked = false;
  bool _expiredFromServer = false;
  DateTime? _lastServerAttempt;
  String? _message;

  bool get initialized => _initialized;
  bool get busy => _busy;
  bool get isActive =>
      _initialized && (_allowQaTrial || (_store.hasValidGrant && !_blocked));
  bool get isExpired =>
      _initialized &&
      !_allowQaTrial &&
      (_expiredFromServer ||
          _blocked ||
          (expiresAt != null && !_clock().toUtc().isBefore(expiresAt!)));
  DateTime? get startedAt => _store.startedAt;
  DateTime? get expiresAt => _store.expiresAt;
  String? get message => _message;
  bool get canSignIn =>
      !_busy &&
      _verifier is! UnconfiguredTrialVerifier &&
      googleTrialWebClientId.isNotEmpty;

  int get daysRemaining {
    final expiry = expiresAt;
    if (_allowQaTrial) return 30;
    if (!isActive || expiry == null) return 0;
    return (expiry.difference(_clock().toUtc()).inMilliseconds /
            Duration.millisecondsPerDay)
        .ceil()
        .clamp(0, 30);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _store.initialize();
      _initialized = true;
      _notify();
      // Existing signed trial can be used without network or Google sign-in.
      // Try silently refreshing it near its short offline expiration.
      await _refreshSilentlyIfNeeded();
    } catch (_) {
      // No trial access on storage failure; purchase verification remains usable.
      _initialized = true;
      _message = 'trialUnavailable';
      _notify();
    }
  }

  Future<void> refresh() async {
    if (!_initialized) return;
    try {
      await _store.refresh();
    } catch (_) {
      _message = 'trialUnavailable';
    }
    _notify();
    await _refreshSilentlyIfNeeded();
  }

  Future<void> _refreshSilentlyIfNeeded() async {
    if (_busy ||
        !_initialized ||
        _blocked ||
        _verifier is UnconfiguredTrialVerifier) {
      return;
    }
    final grantEnd = _store.grantExpiresAt;
    if (grantEnd == null ||
        grantEnd.difference(_clock().toUtc()) > const Duration(hours: 24)) {
      return;
    }
    final now = _clock().toUtc();
    if (_lastServerAttempt != null &&
        now.difference(_lastServerAttempt!) < const Duration(minutes: 3)) {
      return;
    }
    _lastServerAttempt = now;
    await _verify(silent: true);
  }

  Future<void> signIn() => _verify(silent: false);

  Future<void> _verify({required bool silent}) async {
    if (_busy || !_initialized || _verifier is UnconfiguredTrialVerifier) {
      return;
    }
    _busy = true;
    if (!silent) _message = null;
    _notify();
    try {
      final idToken = silent
          ? await _identity.signInSilently()
          : await _identity.signIn();
      if (idToken == null || idToken.isEmpty) {
        if (!silent) _message = 'trialSignInError';
        return;
      }
      final result = await _verifier.verify(
        idToken: idToken,
        deviceId: await _store.getDeviceId(),
      );
      switch (result.status) {
        case TrialVerificationStatus.active:
          if (result.grant == null || !await _store.accept(result.grant!)) {
            _message = 'trialUnavailable';
            break;
          }
          _blocked = false;
          _expiredFromServer = false;
          _message = null;
          break;
        case TrialVerificationStatus.expired:
          await _store.clear();
          _expiredFromServer = true;
          _message = null;
          break;
        case TrialVerificationStatus.blocked:
          await _store.clear();
          _blocked = true;
          _message = 'trialBlocked';
          break;
        case TrialVerificationStatus.unavailable:
          if (!silent) _message = 'trialUnavailable';
          break;
      }
    } catch (_) {
      if (!silent) _message = 'trialSignInError';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> signOut() async {
    if (_busy) return;
    _busy = true;
    _notify();
    try {
      await _identity.signOut();
      await _store.clear();
      _expiredFromServer = false;
      _blocked = false;
      _message = null;
    } catch (_) {
      _message = 'trialSignInError';
    } finally {
      _busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsVerifier) _verifier.dispose();
    super.dispose();
  }
}
