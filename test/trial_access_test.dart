import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_text_mp3_mobile/services/trial_access.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts on first use; remains active through day 29', () async {
    var clock = DateTime.utc(2026, 11, 18, 5);
    final trial = TrialAccessController(clock: () => clock);
    await trial.initialize();
    expect(trial.isActive, isTrue);
    expect(trial.daysRemaining, 30);
    clock = clock.add(const Duration(days: 29, hours: 1));
    await trial.refresh();
    expect(trial.daysRemaining, 1);
    expect(trial.isActive, isTrue);
    trial.dispose();
  });

  test('expires at 30 days, persists across restarts', () async {
    var clock = DateTime.utc(2026, 11, 18);
    final trial = TrialAccessController(clock: () => clock);
    await trial.initialize();
    clock = clock.add(const Duration(days: 30));
    await trial.refresh();
    expect(trial.isExpired, isTrue);
    expect(trial.daysRemaining, 0);
    trial.dispose();

    final restarted = TrialAccessController(clock: () => clock);
    await restarted.initialize();
    expect(restarted.isExpired, isTrue);
    restarted.dispose();
  });

  test('clock rollback cannot restore an expired trial', () async {
    var clock = DateTime.utc(2026, 11, 18);
    final trial = TrialAccessController(clock: () => clock);
    await trial.initialize();
    clock = clock.add(const Duration(days: 31));
    await trial.refresh();
    expect(trial.isExpired, isTrue);
    clock = clock.subtract(const Duration(days: 29));
    await trial.refresh();
    expect(trial.isExpired, isTrue);
    trial.dispose();
  });

  test('never restarts trial if just reopened', () async {
    var clock = DateTime.utc(2026, 11, 18);
    final first = TrialAccessController(clock: () => clock);
    await first.initialize();
    first.dispose();
    clock = clock.add(const Duration(days: 15));
    final second = TrialAccessController(clock: () => clock);
    await second.initialize();
    expect(second.daysRemaining, 15);
    second.dispose();
  });
}
