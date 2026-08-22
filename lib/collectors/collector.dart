import '../data/models/feed_source.dart';
import '../data/models/lead.dart';

/// The raw output of fetching one source, before scoring/storage.
class CollectResult {
  final List<Lead> items;
  final String status; // 'ok' | 'error'
  final String? error;
  const CollectResult(this.items, {this.status = 'ok', this.error});

  factory CollectResult.failure(String message) =>
      CollectResult(const [], status: 'error', error: message);
}

/// A pluggable source fetcher. RSS, World Bank, (future) email all implement
/// this, so the pipeline treats every source uniformly.
abstract class Collector {
  bool handles(FeedSource source);
  Future<CollectResult> fetch(FeedSource source);
}
