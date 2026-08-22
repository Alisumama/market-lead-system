import 'models/feed_source.dart';
import 'models/lead.dart';

/// The seed feed registry, ported from the original sources.yaml. These are
/// inserted on first launch (built_in = true) and are fully editable / removable
/// by the user afterwards. Only reliable, keyless, cross-platform feeds are
/// enabled by default (RSS + Google News + World Bank procurement).
const List<FeedSource> kDefaultSources = [
  // --- Global industry news (native RSS) ---
  FeedSource(
    name: 'World-Grain — Articles',
    url: 'https://www.world-grain.com/rss/articles',
    kind: SourceKind.rss,
    country: 'global',
    enabled: true,
    builtIn: true,
  ),
  FeedSource(
    name: 'Milling and Grain — Articles',
    url: 'https://www.millingandgrain.com/feed',
    kind: SourceKind.rss,
    country: 'global',
    enabled: true,
    builtIn: true,
  ),
  FeedSource(
    name: 'Grain Journal — Articles',
    url: 'https://www.grainjournal.com/rss.xml',
    kind: SourceKind.rss,
    country: 'global',
    enabled: true,
    builtIn: true,
  ),
  FeedSource(
    name: 'Miller Magazine (Google News site feed)',
    url: 'https://news.google.com/rss/search?q=site:millermagazine.com&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.rss,
    country: 'global',
    enabled: true,
    builtIn: true,
  ),
  FeedSource(
    name: 'Feed & Grain (Google News site feed)',
    url: 'https://news.google.com/rss/search?q=(mill%20OR%20milling%20OR%20grain%20OR%20plant%20OR%20facility)%20site:feedandgrain.com&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.rss,
    country: 'global',
    enabled: true,
    builtIn: true,
  ),

  // --- Intent-targeted Google News searches (the highest-signal feeds) ---
  FeedSource(
    name: 'Mill projects — build / commission (global)',
    url: 'https://news.google.com/rss/search?q=%28%22flour%20mill%22%20OR%20%22grain%20mill%22%20OR%20%22roller%20mill%22%20OR%20%22milling%20plant%22%20OR%20%22milling%20complex%22%29%20%28new%20OR%20construction%20OR%20commissioned%20OR%20inaugurated%20OR%20expansion%29&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.rss,
    country: 'global',
    enabled: true,
    builtIn: true,
  ),
  FeedSource(
    name: 'Mill tenders & contracts (global)',
    url: 'https://news.google.com/rss/search?q=%28%22flour%20mill%22%20OR%20%22grain%20mill%22%20OR%20%22milling%20plant%22%20OR%20%22flour%20factory%22%29%20%28tender%20OR%20procurement%20OR%20%22contract%20signed%22%20OR%20%22contract%20awarded%22%20OR%20turnkey%29&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.rss,
    country: 'global',
    enabled: true,
    builtIn: true,
  ),
  FeedSource(
    name: 'Grain/flour processing capacity & investment (global)',
    url: 'https://news.google.com/rss/search?q=%28%22wheat%20processing%22%20OR%20%22grain%20processing%22%20OR%20%22flour%20production%22%20OR%20%22flour%20factory%22%20OR%20%22milling%20complex%22%29%20%28investment%20OR%20modernization%20OR%20capacity%20OR%20expansion%29&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.rss,
    country: 'global',
    enabled: true,
    builtIn: true,
  ),
  FeedSource(
    name: 'Değirmen / un fabrikası — yatırım & ihale (TR)',
    url: 'https://news.google.com/rss/search?q=%28%22un%20fabrikas%C4%B1%22%20OR%20%22un%20de%C4%9Firmeni%22%20OR%20%22de%C4%9Firmen%20tesisi%22%29%20%28yat%C4%B1r%C4%B1m%20OR%20ihale%20OR%20yeni%20OR%20modernizasyon%20OR%20kapasite%29&hl=tr&gl=TR&ceid=TR:tr',
    kind: SourceKind.rss,
    language: 'tr',
    country: 'tr',
    enabled: true,
    builtIn: true,
  ),
  FeedSource(
    name: 'Мукомольный завод / мельничный комплекс (RU)',
    url: 'https://news.google.com/rss/search?q=%28%22%D0%BC%D1%83%D0%BA%D0%BE%D0%BC%D0%BE%D0%BB%D1%8C%D0%BD%D1%8B%D0%B9%20%D0%B7%D0%B0%D0%B2%D0%BE%D0%B4%22%20OR%20%22%D0%BC%D0%B5%D0%BB%D1%8C%D0%BD%D0%B8%D1%87%D0%BD%D1%8B%D0%B9%20%D0%BA%D0%BE%D0%BC%D0%BF%D0%BB%D0%B5%D0%BA%D1%81%22%29%20%28%D0%BD%D0%BE%D0%B2%D1%8B%D0%B9%20OR%20%D1%82%D0%B5%D0%BD%D0%B4%D0%B5%D1%80%20OR%20%D0%B8%D0%BD%D0%B2%D0%B5%D1%81%D1%82%D0%B8%D1%86%D0%B8%D0%B8%29&hl=ru&gl=RU&ceid=RU:ru',
    kind: SourceKind.rss,
    language: 'ru',
    country: 'ru',
    enabled: true,
    builtIn: true,
  ),

  // --- Development-bank / IFI project feeds ---
  FeedSource(
    name: 'IFC — milling/grain projects (Google News)',
    url: 'https://news.google.com/rss/search?q=(flour%20OR%20grain%20OR%20wheat%20OR%20maize%20OR%20silo%20OR%20%22flour%20mill%22%20OR%20%22food%20processing%22)%20-mining%20-ore%20site:ifc.org&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.rss,
    country: 'global',
    enabled: true,
    builtIn: true,
  ),
  FeedSource(
    name: 'EBRD — milling/grain projects (Google News)',
    url: 'https://news.google.com/rss/search?q=(mill%20OR%20milling%20OR%20flour%20OR%20grain%20OR%20silo%20OR%20%22food%20processing%22)%20site:ebrd.com&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.rss,
    country: 'global',
    enabled: true,
    builtIn: true,
  ),
  FeedSource(
    name: 'AfDB — milling/grain projects (Google News)',
    url: 'https://news.google.com/rss/search?q=(mill%20OR%20milling%20OR%20flour%20OR%20grain%20OR%20silo%20OR%20%22food%20processing%22)%20site:afdb.org&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.rss,
    country: 'global',
    enabled: false,
    builtIn: true,
  ),

  // --- Per-market Google News searches (disabled by default; enable as needed) ---
  FeedSource(
    name: 'Pakistan — flour mill (project/tender/expansion)',
    url: 'https://news.google.com/rss/search?q=%22flour%20mill%22%20(project%20OR%20tender%20OR%20expansion)%20Pakistan&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.googleAlert,
    country: 'pk',
    enabled: false,
    builtIn: true,
  ),
  FeedSource(
    name: 'Nigeria — flour mill / milling (tender/investment)',
    url: 'https://news.google.com/rss/search?q=%28%22flour%20mill%22%20OR%20grain%20OR%20milling%29%20%28tender%20OR%20procurement%20OR%20%22new%20project%22%20OR%20investment%29%20Nigeria&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.googleAlert,
    country: 'ng',
    enabled: false,
    builtIn: true,
  ),
  FeedSource(
    name: 'Kenya — flour mill / milling (tender/investment)',
    url: 'https://news.google.com/rss/search?q=%28%22flour%20mill%22%20OR%20grain%20OR%20milling%29%20%28tender%20OR%20procurement%20OR%20%22new%20project%22%20OR%20investment%29%20Kenya&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.googleAlert,
    country: 'ke',
    enabled: false,
    builtIn: true,
  ),
  FeedSource(
    name: 'Egypt — flour mill / milling (tender/investment)',
    url: 'https://news.google.com/rss/search?q=%28%22flour%20mill%22%20OR%20grain%20OR%20milling%29%20%28tender%20OR%20procurement%20OR%20%22new%20project%22%20OR%20investment%29%20Egypt&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.googleAlert,
    country: 'eg',
    enabled: false,
    builtIn: true,
  ),
  FeedSource(
    name: 'Middle East — flour mill (project/tender/expansion)',
    url: 'https://news.google.com/rss/search?q=%22flour%20mill%22%20(project%20OR%20tender%20OR%20expansion)%20(%22Middle%20East%22%20OR%20Egypt%20OR%20Saudi%20OR%20UAE)&hl=en-US&gl=US&ceid=US:en',
    kind: SourceKind.googleAlert,
    country: 'middle_east',
    enabled: false,
    builtIn: true,
  ),

  // --- World Bank procurement notices (actual tenders — highest quality) ---
  // Handled specially by WorldBankCollector; the URL is the API endpoint.
  FeedSource(
    name: 'World Bank — procurement notices (target markets)',
    url: 'https://search.worldbank.org/api/v2/procnotices',
    kind: SourceKind.worldBank,
    country: 'global',
    enabled: true,
    builtIn: true,
  ),
];
