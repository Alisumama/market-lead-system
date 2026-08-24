import '../data/lead_repository.dart';
import '../scoring/keyword_scorer.dart';
import 'notification_service.dart';
import 'pipeline.dart';
import 'settings_service.dart';

/// Runs one collection pass with no UI — used by the OS scheduler (launchd /
/// Task Scheduler) on desktop and by the WorkManager isolate on Android, so the
/// radar keeps collecting while the app is closed. Reuses the same DB, scoring
/// config and notification prefs as the interactive app.
Future<void> runHeadlessRefresh() async {
  final settings = SettingsService();
  final repo = LeadRepository();
  final notifications = NotificationService();
  final scorer = KeywordScorer(await settings.scoringConfig());
  final pipeline = Pipeline(repo: repo, scorer: scorer);

  final batchStart = DateTime.now().toUtc().toIso8601String();
  try {
    final outcome = await pipeline.run();

    // Keep the "new since last fetch" highlight consistent with the in-app run.
    if (outcome.newLeads > 0) {
      await settings.setLastBatchAt(batchStart);
    }

    if (await settings.notifEnabled() && await settings.notifAfterRefresh()) {
      final minScore = await settings.notifMinScore();
      final count = outcome.newAtOrAbove(minScore);
      final onlyNew = await settings.notifOnlyNew();
      if (!(onlyNew && count == 0)) {
        final scope = minScore > 0 ? ' (score ≥ $minScore)' : '';
        await notifications.show(
          'Bastak Leads updated',
          count > 0
              ? '$count new lead${count == 1 ? '' : 's'}$scope found.'
              : 'No new leads this time.',
        );
      }
    }
  } catch (_) {
    // A background pass must never crash loudly; try again next tick.
  }
}
