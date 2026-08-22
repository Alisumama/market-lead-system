import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/lead.dart';
import '../../data/reports_repository.dart';
import '../../services/export_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_bar_bits.dart';

const _palette = <Color>[
  Color(0xFF33A337),
  Color(0xFF6C63FF),
  Color(0xFFE8A317),
  Color(0xFF00BCD4),
  Color(0xFFEC407A),
  Color(0xFF5C6BC0),
  Color(0xFF26A69A),
  Color(0xFFFF7043),
];

const _cold = Color(0xFF9AA0A6);
const _warm = Color(0xFFE8A317);
const _hot = AppTheme.brandGreen;

typedef _Trend = ({DateTime day, int total, int hot});
typedef _Band = ({String label, int cold, int warm, int hot});

class _ReportsData {
  final ReportOverview overview;
  final List<int> scoreHist;
  final List<CountRow> status;
  final List<CountRow> countries;
  final List<CountRow> projectTypes;
  final List<SourcePerf> sources;
  final List<CountRow> companies;
  final List<_Band> bands;
  final List<_Trend> trend;
  final Map<String, int> heatmap;
  const _ReportsData({
    required this.overview,
    required this.scoreHist,
    required this.status,
    required this.countries,
    required this.projectTypes,
    required this.sources,
    required this.companies,
    required this.bands,
    required this.trend,
    required this.heatmap,
  });
}

String _dk(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _repo = ReportsRepository();
  int _days = 30;
  late Future<_ReportsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReportsData> _load() async {
    final freshDays = context.read<AppState>().freshDays;
    final days = _days;
    final r = await Future.wait<dynamic>([
      _repo.overview(freshDays: freshDays),
      _repo.scoreHistogram(),
      _repo.byStatus(),
      _repo.topCountries(limit: 8),
      _repo.byProjectType(),
      _repo.sourcePerformance(limit: 12),
      _repo.topCompanies(limit: 8),
      _repo.scoreBandsByCountry(limit: 6),
      _repo.intakeWithHot(days: days),
      _repo.intakeByDay(days: 119),
    ]);

    final hotMap = r[8] as Map<String, ({int total, int hot})>;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final trend = <_Trend>[];
    for (var i = days - 1; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final e = hotMap[_dk(d)];
      trend.add((day: d, total: e?.total ?? 0, hot: e?.hot ?? 0));
    }
    final heat = <String, int>{
      for (final c in (r[9] as List<CountRow>)) c.label: c.count
    };

    return _ReportsData(
      overview: r[0] as ReportOverview,
      scoreHist: r[1] as List<int>,
      status: r[2] as List<CountRow>,
      countries: r[3] as List<CountRow>,
      projectTypes: r[4] as List<CountRow>,
      sources: r[5] as List<SourcePerf>,
      companies: r[6] as List<CountRow>,
      bands: (r[7] as List).cast<_Band>(),
      trend: trend,
      heatmap: heat,
    );
  }

  void _reload() => setState(() => _future = _load());
  void _setDays(int d) => setState(() {
        _days = d;
        _future = _load();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_ReportsData>(
        future: _future,
        builder: (context, snap) {
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                backgroundColor: translucentBarColor(context),
                flexibleSpace: frostedFlexibleSpace(),
                leading: mobileBrandLeading(context),
                leadingWidth: 58,
                automaticallyImplyLeading: false,
                titleSpacing: mobileBrandLeading(context) == null ? 20 : 4,
                title: const Text('Reports'),
                actions: [
                  IconButton(
                    tooltip: 'Export digest (CSV)',
                    onPressed:
                        snap.hasData ? () => _exportDigest(snap.data!) : null,
                    icon: const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    tooltip: 'Refresh reports',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              if (!snap.hasData)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
                  sliver: SliverToBoxAdapter(child: _body(context, snap.data!)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, _ReportsData d) {
    final o = d.overview;

    final gauge = _SectionCard(
      title: 'Average score',
      icon: Icons.speed,
      child: _GaugeCard(avg: o.avgScore, hot: o.hot, warm: o.warm, cold: o.cold),
    );
    final scoreCard = _SectionCard(
      title: 'Score distribution',
      icon: Icons.insights,
      child: _ScoreBars(hist: d.scoreHist),
    );
    final pipelineCard = _SectionCard(
      title: 'Pipeline',
      icon: Icons.donut_large,
      child: _Donut(
        centerTop: '${o.total}',
        centerBottom: 'leads',
        data: [
          for (final s in _statusOrdered(d.status))
            (LeadStatusX.fromStorage(s.label).label, s.count,
                _statusColor(s.label)),
        ],
      ),
    );
    final projectCard = _SectionCard(
      title: 'Project types',
      icon: Icons.category_outlined,
      child: _Donut(
        centerTop: '${d.projectTypes.fold<int>(0, (a, b) => a + b.count)}',
        centerBottom: 'items',
        data: [
          for (var i = 0; i < d.projectTypes.length; i++)
            (d.projectTypes[i].label, d.projectTypes[i].count,
                _palette[i % _palette.length]),
        ],
      ),
    );
    final bandsCard = _SectionCard(
      title: 'Score bands by country',
      icon: Icons.stacked_bar_chart,
      child: _StackedBars(bands: d.bands),
    );
    final countriesCard = _SectionCard(
      title: 'Top countries',
      icon: Icons.public,
      child: _ProgressList(
        rows: [for (final c in d.countries) (c.label, c.count, c.hot)],
        colorForIndex: (i) => _palette[i % _palette.length],
      ),
    );
    final companiesCard = d.companies.isEmpty
        ? null
        : _SectionCard(
            title: 'Top companies',
            icon: Icons.business,
            child: _ProgressList(
              rows: [for (final c in d.companies) (c.label, c.count, 0)],
              colorForIndex: (i) => Colors.blueGrey,
            ),
          );
    final trendCard = _SectionCard(
      title: 'Lead intake trend',
      icon: Icons.show_chart,
      trailingWidget: _RangeSelector(days: _days, onChanged: _setDays),
      child: _DualArea(trend: d.trend),
    );
    final heatCard = _SectionCard(
      title: 'Activity — last ~17 weeks',
      icon: Icons.grid_on,
      child: _Heatmap(counts: d.heatmap),
    );
    final sourcesCard = _SectionCard(
      title: 'Source performance',
      icon: Icons.rss_feed,
      child: _SourceList(sources: d.sources),
    );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 880;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroRow(o: o),
          const SizedBox(height: 2),
          if (wide) ...[
            _row(gauge, scoreCard),
            _row(pipelineCard, projectCard),
            trendCard,
            bandsCard,
            _row(countriesCard, companiesCard ?? const SizedBox.shrink()),
            heatCard,
            sourcesCard,
          ] else ...[
            gauge,
            scoreCard,
            pipelineCard,
            projectCard,
            trendCard,
            bandsCard,
            countriesCard,
            ?companiesCard,
            heatCard,
            sourcesCard,
          ],
        ],
      );
    });
  }

  Widget _row(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 14),
          Expanded(child: b),
        ],
      );

  List<CountRow> _statusOrdered(List<CountRow> rows) {
    const order = ['fresh', 'reviewing', 'contacted', 'won', 'lost', 'archived'];
    final map = {for (final r in rows) r.label: r};
    return [
      for (final k in order)
        if ((map[k]?.count ?? 0) > 0) map[k]!,
    ];
  }

  Color _statusColor(String s) => switch (s) {
        'fresh' => const Color(0xFF42A5F5),
        'reviewing' => const Color(0xFFE8A317),
        'contacted' => const Color(0xFF6C63FF),
        'won' => AppTheme.brandGreen,
        'lost' => const Color(0xFFEF5350),
        _ => Colors.grey,
      };

  Future<void> _exportDigest(_ReportsData d) async {
    final b = StringBuffer();
    void l([String s = '']) => b.writeln(s);
    final o = d.overview;
    l('BASTAK LEADS — REPORT DIGEST');
    l('Generated (local): ${DateTime.now()}');
    l();
    l('OVERVIEW');
    l('Total,${o.total}');
    l('Hot (8+),${o.hot}');
    l('Warm (4-7),${o.warm}');
    l('Cold (<4),${o.cold}');
    l('Relevant,${o.relevant}');
    l('Fresh,${o.fresh}');
    l('Favorites,${o.favorites}');
    l('Average score,${o.avgScore.toStringAsFixed(2)}');
    l();
    l('SCORE DISTRIBUTION');
    for (var i = 0; i <= 10; i++) {
      l('$i,${d.scoreHist[i]}');
    }
    l();
    l('PIPELINE');
    for (final s in d.status) {
      l('${LeadStatusX.fromStorage(s.label).label},${s.count}');
    }
    l();
    l('TOP COUNTRIES,count,hot');
    for (final c in d.countries) {
      l('${c.label},${c.count},${c.hot}');
    }
    l();
    l('PROJECT TYPES');
    for (final p in d.projectTypes) {
      l('${p.label},${p.count}');
    }
    l();
    l('SOURCE PERFORMANCE,total,hot,avg');
    for (final s in d.sources) {
      l('${s.name.replaceAll(",", " ")},${s.total},${s.hot},${s.avgScore.toStringAsFixed(2)}');
    }
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    try {
      final path = await ExportService()
          .exportText(b.toString(), 'bastak_report_$stamp.csv');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Report saved → $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }
}

// ============================ Hero cards ============================

class _HeroRow extends StatelessWidget {
  final ReportOverview o;
  const _HeroRow({required this.o});

  @override
  Widget build(BuildContext context) {
    final total = o.total == 0 ? 1 : o.total;
    final cards = [
      _HeroStat('Total leads', o.total, '${o.relevant} relevant',
          o.relevant / total, const Color(0xFF6C63FF), Icons.inbox_rounded),
      _HeroStat('Hot (8+)', o.hot, 'of total', o.hot / total,
          AppTheme.brandGreen, Icons.local_fire_department),
      _HeroStat('Warm (4–7)', o.warm, 'of total', o.warm / total,
          const Color(0xFFE8A317), Icons.trending_up),
      _HeroStat('Fresh', o.fresh, 'avg ${o.avgScore.toStringAsFixed(1)}',
          o.fresh / total, const Color(0xFF00BCD4), Icons.schedule),
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = 14.0;
      final cols = c.maxWidth >= 880 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final card in cards) SizedBox(width: w, child: card)],
      );
    });
  }
}

class _HeroStat extends StatelessWidget {
  final String label, sub;
  final int value;
  final double percent;
  final Color color;
  final IconData icon;
  const _HeroStat(
      this.label, this.value, this.sub, this.percent, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant)),
                  ),
                ]),
                const SizedBox(height: 12),
                _AnimatedCount(value: value, style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800)),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _PercentRing(percent: percent.clamp(0, 1), color: color, size: 52),
        ],
      ),
    );
  }
}

class _AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle style;
  const _AnimatedCount({required this.value, required this.style});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text('${v.round()}', style: style),
    );
  }
}

class _PercentRing extends StatelessWidget {
  final double percent;
  final Color color;
  final double size;
  const _PercentRing(
      {required this.percent, required this.color, this.size = 54});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: percent),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => CustomPaint(
          painter: _RingPainter(v, color),
          child: Center(
            child: Text('${(v * 100).round()}%',
                style: TextStyle(
                    fontSize: size * 0.24,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double percent;
  final Color color;
  _RingPainter(this.percent, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.15));
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * percent,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.percent != percent || old.color != color;
}

// ============================ Gauge ============================

class _GaugeCard extends StatelessWidget {
  final double avg;
  final int hot, warm, cold;
  const _GaugeCard(
      {required this.avg,
      required this.hot,
      required this.warm,
      required this.cold});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = AppTheme.scoreColor(avg.round());
    return Column(
      children: [
        SizedBox(
          height: 116,
          width: 200,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (avg / 10).clamp(0, 1)),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => CustomPaint(
              painter: _GaugePainter(v, color, scheme.surfaceContainerHighest),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(avg.toStringAsFixed(1),
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: color)),
                    Text('/ 10 avg',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _miniStat('Hot', hot, _hot),
            _miniStat('Warm', warm, _warm),
            _miniStat('Cold', cold, _cold),
          ],
        ),
      ],
    );
  }

  Widget _miniStat(String label, int v, Color c) => Column(
        children: [
          Text('$v',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: c)),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}

class _GaugePainter extends CustomPainter {
  final double value; // 0..1
  final Color color;
  final Color track;
  _GaugePainter(this.value, this.color, this.track);
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final center = Offset(size.width / 2, size.height - 4);
    final radius = math.min(size.width / 2, size.height) - stroke / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
        rect,
        math.pi,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = track);
    canvas.drawArc(
        rect,
        math.pi,
        math.pi * value,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(colors: [
            color.withValues(alpha: 0.6),
            color,
          ]).createShader(rect));
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}

// ============================ Section wrapper ============================

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailingWidget;
  final Widget child;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon, size: 17, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                ?trailingWidget,
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  final int days;
  final ValueChanged<int> onChanged;
  const _RangeSelector({required this.days, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(value: 7, label: Text('7d')),
        ButtonSegment(value: 30, label: Text('30d')),
        ButtonSegment(value: 90, label: Text('90d')),
      ],
      selected: {days},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

// ============================ Charts ============================

class _ScoreBars extends StatelessWidget {
  final List<int> hist;
  const _ScoreBars({required this.hist});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = hist.fold<int>(1, (m, v) => v > m ? v : m).toDouble();
    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxV * 1.18,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (g, gi, r, ri) => BarTooltipItem('${r.toY.round()}',
                  const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxV / 3).ceilToDouble().clamp(1, 1e9),
            getDrawingHorizontalLine: (v) => FlLine(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, m) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${v.toInt()}',
                      style: TextStyle(
                          fontSize: 10, color: scheme.onSurfaceVariant)),
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i <= 10; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: hist[i].toDouble(),
                  width: 15,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(6)),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppTheme.scoreColor(i),
                      AppTheme.scoreColor(i).withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _StackedBars extends StatelessWidget {
  final List<_Band> bands;
  const _StackedBars({required this.bands});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (bands.isEmpty) return const _Empty();
    final maxV = bands
        .fold<int>(1, (m, b) => (b.cold + b.warm + b.hot) > m
            ? (b.cold + b.warm + b.hot)
            : m)
        .toDouble();
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: maxV * 1.15,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(enabled: true),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (maxV / 3).ceilToDouble().clamp(1, 1e9),
                getDrawingHorizontalLine: (v) => FlLine(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                    strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= bands.length) {
                        return const SizedBox.shrink();
                      }
                      final lbl = bands[i].label;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                            lbl.length > 7 ? lbl.substring(0, 7) : lbl,
                            style: TextStyle(
                                fontSize: 9, color: scheme.onSurfaceVariant)),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < bands.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: (bands[i].cold + bands[i].warm + bands[i].hot)
                          .toDouble(),
                      width: 22,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                      rodStackItems: [
                        BarChartRodStackItem(
                            0, bands[i].cold.toDouble(), _cold),
                        BarChartRodStackItem(
                            bands[i].cold.toDouble(),
                            (bands[i].cold + bands[i].warm).toDouble(),
                            _warm),
                        BarChartRodStackItem(
                            (bands[i].cold + bands[i].warm).toDouble(),
                            (bands[i].cold + bands[i].warm + bands[i].hot)
                                .toDouble(),
                            _hot),
                      ],
                    ),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          children: const [
            _LegendDot(color: _hot, label: 'Hot'),
            _LegendDot(color: _warm, label: 'Warm'),
            _LegendDot(color: _cold, label: 'Cold'),
          ],
        ),
      ],
    );
  }
}

class _DualArea extends StatelessWidget {
  final List<_Trend> trend;
  const _DualArea({required this.trend});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (trend.length < 2) return const _Empty();
    final maxV =
        trend.fold<int>(1, (m, r) => r.total > m ? r.total : m).toDouble();
    List<FlSpot> series(int Function(_Trend) f) => [
          for (var i = 0; i < trend.length; i++)
            FlSpot(i.toDouble(), f(trend[i]).toDouble())
        ];
    return Column(
      children: [
        Row(
          children: const [
            _LegendDot(color: AppTheme.brandGreen, label: 'All leads'),
            SizedBox(width: 16),
            _LegendDot(color: Color(0xFFE8A317), label: 'Hot (8+)'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxV * 1.25,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (maxV / 3).ceilToDouble().clamp(1, 1e9),
                getDrawingHorizontalLine: (v) => FlLine(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                    strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: (trend.length / 4).ceilToDouble(),
                    getTitlesWidget: (v, m) {
                      final i = v.round();
                      if (i < 0 || i >= trend.length) {
                        return const SizedBox.shrink();
                      }
                      final d = trend[i].day;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                            '${d.month}/${d.day}',
                            style: TextStyle(
                                fontSize: 9, color: scheme.onSurfaceVariant)),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots
                      .map((s) => LineTooltipItem('${s.y.round()}',
                          TextStyle(
                              color: s.bar.color ?? Colors.white,
                              fontWeight: FontWeight.w700)))
                      .toList(),
                ),
              ),
              lineBarsData: [
                _line(series((t) => t.total), AppTheme.brandGreen, true),
                _line(series((t) => t.hot), const Color(0xFFE8A317), false),
              ],
            ),
          ),
        ),
      ],
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color, bool fill) =>
      LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.3,
        color: color,
        barWidth: 3,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: fill,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.30),
              color.withValues(alpha: 0.02),
            ],
          ),
        ),
      );
}

class _Heatmap extends StatelessWidget {
  final Map<String, int> counts;
  const _Heatmap({required this.counts});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 17 weeks grid, aligned so each column is a Sun–Sat week.
    final start = today.subtract(const Duration(days: 118));
    final gridStart = start.subtract(Duration(days: start.weekday % 7));
    final cols = ((today.difference(gridStart).inDays) / 7).ceil() + 1;
    final maxV = counts.values.fold<int>(1, (m, v) => v > m ? v : m);

    Color cell(DateTime d) {
      if (d.isAfter(today)) return Colors.transparent;
      final v = counts[_dk(d)] ?? 0;
      if (v == 0) return scheme.surfaceContainerHighest.withValues(alpha: 0.5);
      final t = v / maxV;
      final a = t <= 0.25
          ? 0.30
          : t <= 0.5
              ? 0.5
              : t <= 0.75
                  ? 0.72
                  : 1.0;
      return AppTheme.brandGreen.withValues(alpha: a);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var col = 0; col < cols; col++)
                Column(
                  children: [
                    for (var row = 0; row < 7; row++)
                      Builder(builder: (_) {
                        final d = gridStart
                            .add(Duration(days: col * 7 + row));
                        return Container(
                          width: 13,
                          height: 13,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: cell(d),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Less',
                style: TextStyle(
                    fontSize: 10, color: scheme.onSurfaceVariant)),
            const SizedBox(width: 6),
            for (final a in [0.3, 0.5, 0.72, 1.0])
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                    color: AppTheme.brandGreen.withValues(alpha: a),
                    borderRadius: BorderRadius.circular(3)),
              ),
            const SizedBox(width: 6),
            Text('More',
                style: TextStyle(
                    fontSize: 10, color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

// ============================ Lists ============================

class _Donut extends StatelessWidget {
  final List<(String, int, Color)> data;
  final String centerTop;
  final String centerBottom;
  const _Donut(
      {required this.data,
      required this.centerTop,
      required this.centerBottom});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = data.fold<int>(0, (a, b) => a + b.$2);
    if (total == 0) return const _Empty();
    return Row(
      children: [
        SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 42,
                startDegreeOffset: -90,
                sections: [
                  for (final d in data)
                    if (d.$2 > 0)
                      PieChartSectionData(
                          value: d.$2.toDouble(),
                          color: d.$3,
                          radius: 20,
                          showTitle: false),
                ],
              )),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(centerTop,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                Text(centerBottom,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              for (final d in data)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration:
                            BoxDecoration(color: d.$3, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(d.$1,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text('${d.$2}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 38,
                      child: Text('${(d.$2 / total * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant)),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressList extends StatelessWidget {
  final List<(String, int, int)> rows;
  final Color Function(int index) colorForIndex;
  const _ProgressList({required this.rows, required this.colorForIndex});
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _Empty();
    final scheme = Theme.of(context).colorScheme;
    final maxV = rows.fold<int>(1, (m, r) => r.$2 > m ? r.$2 : m);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(rows[i].$1,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (rows[i].$3 > 0) ...[
                    const Icon(Icons.local_fire_department,
                        size: 13, color: AppTheme.brandGreen),
                    Text(' ${rows[i].$3}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.brandGreen,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                  ],
                  Text('${rows[i].$2}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: rows[i].$2 / maxV,
                    minHeight: 8,
                    backgroundColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    valueColor: AlwaysStoppedAnimation(colorForIndex(i)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SourceList extends StatelessWidget {
  final List<SourcePerf> sources;
  const _SourceList({required this.sources});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (sources.isEmpty) return const _Empty();
    final maxV = sources.fold<int>(1, (m, s) => s.total > m ? s.total : m);
    return Column(
      children: [
        for (var i = 0; i < sources.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                child: Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sources[i].name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: sources[i].total / maxV,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                        valueColor: AlwaysStoppedAnimation(
                            _palette[i % _palette.length]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${sources[i].total}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('avg ${sources[i].avgScore.toStringAsFixed(1)}',
                      style: TextStyle(
                          fontSize: 10, color: scheme.onSurfaceVariant)),
                ],
              ),
            ]),
          ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
            child: Text('No data yet',
                style: Theme.of(context).textTheme.bodySmall)),
      );
}
