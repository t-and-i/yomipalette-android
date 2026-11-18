import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local 30 x 24-hour trial. Device-local storage does not defend against
/// app-data deletion, reinstall, rooted devices, or a manipulated system clock.
class TrialAccessController extends ChangeNotifier {
  TrialAccessController({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const duration = Duration(days: 30);
  static const startedKey = 'trial_started_at_ms_v1';
  static const lastSeenKey = 'trial_last_seen_ms_v1';

  final DateTime Function() _clock;
  DateTime? _started;
  DateTime? _lastSeen;
  bool _initialized = false;
  bool _disposed = false;

  bool get initialized => _initialized;
  DateTime? get startedAt => _started;
  DateTime? get expiresAt => _started?.add(duration);
  bool get isActive =>
      _initialized &&
      _started != null &&
      _lastSeen != null &&
      _lastSeen!.isBefore(expiresAt!);
  bool get isExpired => _initialized && !isActive;

  int get daysRemaining {
    if (!isActive) return 0;
    return (expiresAt!.difference(_lastSeen!).inMilliseconds /
            Duration.millisecondsPerDay)
        .ceil();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final now = _clock().toUtc();
    final storedStart = prefs.getInt(startedKey);
    // Do not accept an invalid timestamp as a fresh trial.
    final start = storedStart == null
        ? now
        : DateTime.fromMillisecondsSinceEpoch(storedStart, isUtc: true);
    if (storedStart == null)
      await prefs.setInt(startedKey, start.millisecondsSinceEpoch);
    _started = start;
    _initialized = true;
    await refresh();
  }

  Future<void> refresh() async {
    if (!_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final now = _clock().toUtc();
    final storedLastSeen = prefs.getInt(lastSeenKey);
    final last = storedLastSeen == null
        ? _started!
        : DateTime.fromMillisecondsSinceEpoch(storedLastSeen, isUtc: true);
    // A backwards clock change must never increase remaining time.
    final effective = [
      _started!,
      last,
      now,
    ].reduce((a, b) => a.isAfter(b) ? a : b);
    _lastSeen = effective;
    await prefs.setInt(lastSeenKey, effective.millisecondsSinceEpoch);
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
