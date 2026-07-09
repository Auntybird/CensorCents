import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/ai_verdict_stats.dart';
import '../models/month_summary.dart';
import '../models/transaction_model.dart';
import '../services/wallet_controller.dart';
import '../theme/app_theme.dart';

/// Read-only analytics dashboard: income vs expense for the month, how
/// often the AI approved vs was disappointed, a category breakdown, a
/// rolling daily net-balance trend, and a full monthly overview with
/// drill-down into any past month's transactions. Pulls entirely from data
/// WalletController already has in memory — no extra Supabase round-trips.
///
/// This is the bare content (no Scaffold/AppBar) so it can be embedded as a
/// page inside the dashboard's swipeable PageView. [AnalyticsScreen] below
/// wraps it in a Scaffold for standalone use (e.g. if you ever want it
/// pushed as its own route again).
class AnalyticsBody extends StatefulWidget {
  const AnalyticsBody({super.key});

  @override
  State<AnalyticsBody> createState() => _AnalyticsBodyState();
}

class _AnalyticsBodyState extends State<AnalyticsBody> {
  DateTime? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$');

    return Consumer<WalletController>(
      builder: (context, controller, _) {
        if (controller.transactions.isEmpty) {
          return const Center(
            child: Text(
              'No data yet. Add a transaction first.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        final categoryTotals = controller.expenseByCategoryThisMonth;
        final trend = controller.dailyNetTrend(days: 14);
        final monthlySummaries = controller.monthlySummaries;
        final verdict = controller.aiVerdictStats;

        // Default to the most recent month with data.
        final selectedMonth = _selectedMonth ?? monthlySummaries.first.month;
        final selectedSummary = monthlySummaries.firstWhere(
          (m) => m.matches(selectedMonth),
          orElse: () => MonthSummary(month: selectedMonth, income: 0, expense: 0, transactions: const []),
        );

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _IncomeVsExpenseCard(
              income: controller.monthlyIncome,
              expense: controller.monthlyTotal,
              balance: controller.monthlyBalance,
              currency: currency,
            ),
            const SizedBox(height: 24),
            if (verdict.total > 0) ...[
              Text('The AI\'s Verdict', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              _AiVerdictCard(verdict: verdict),
              const SizedBox(height: 32),
            ],
            Text('Spending by Category', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            if (categoryTotals.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No expenses logged this month yet.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              _CategoryBarChart(categoryTotals: categoryTotals, currency: currency),
            const SizedBox(height: 32),
            Text('Last 14 Days: Net Balance', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            _DailyNetLineChart(trend: trend),
            const SizedBox(height: 32),
            Text('Monthly Overview', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            const Text(
              'Every transaction, split by month.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            _MonthlyBarChart(summaries: monthlySummaries, currency: currency),
            const SizedBox(height: 16),
            _MonthChipRow(
              summaries: monthlySummaries,
              selectedMonth: selectedMonth,
              currency: currency,
              onSelect: (month) => setState(() => _selectedMonth = month),
            ),
            const SizedBox(height: 20),
            _MonthDetailCard(summary: selectedSummary, currency: currency),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }
}

/// Standalone wrapper kept around in case you want analytics reachable as
/// its own pushed route somewhere (e.g. from a settings menu) in addition
/// to living as a swipe page on the dashboard.
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: const AnalyticsBody(),
    );
  }
}

/// Big income / expense / net summary at the top of the analytics screen.
class _IncomeVsExpenseCard extends StatelessWidget {
  final double income;
  final double expense;
  final double balance;
  final NumberFormat currency;

  const _IncomeVsExpenseCard({
    required this.income,
    required this.expense,
    required this.balance,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final balanceColor = balance >= 0 ? AppColors.savingsGreen : AppColors.overspendRed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatColumn(
                  label: 'Income',
                  value: currency.format(income),
                  color: AppColors.savingsGreen,
                  icon: Icons.arrow_downward,
                ),
                _StatColumn(
                  label: 'Expense',
                  value: currency.format(expense),
                  color: AppColors.overspendRed,
                  icon: Icons.arrow_upward,
                ),
                _StatColumn(
                  label: 'Balance',
                  value: '${balance >= 0 ? '+' : '-'}${currency.format(balance.abs())}',
                  color: balanceColor,
                  icon: balance >= 0 ? Icons.trending_up : Icons.trending_down,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Simple stacked proportion bar: green share = income, red share = expense,
            // relative to whichever of the two is larger this month.
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    Expanded(
                      flex: (income * 100).round().clamp(1, 1000000),
                      child: Container(color: AppColors.savingsGreen),
                    ),
                    Expanded(
                      flex: (expense * 100).round().clamp(1, 1000000),
                      child: Container(color: AppColors.overspendRed),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }
}

/// How often the AI approved vs was disappointed, as a proportion bar plus
/// percentages — the "report card" view of the whole judging system.
class _AiVerdictCard extends StatelessWidget {
  final AiVerdictStats verdict;

  const _AiVerdictCard({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final approvedPercent = verdict.approvedPercent;
    final disappointedPercent = verdict.disappointedPercent;
    final approvedCount = verdict.approvedCount;
    final disappointedCount = verdict.disappointedCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded, size: 16, color: AppColors.savingsGreen),
                    const SizedBox(width: 6),
                    Text(
                      'Approved  ${approvedPercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: AppColors.savingsGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      'Disappointed  ${disappointedPercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: AppColors.overspendRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.warning_rounded, size: 16, color: AppColors.overspendRed),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    Expanded(
                      flex: approvedCount.clamp(1, 1000000),
                      child: Container(color: AppColors.savingsGreen),
                    ),
                    Expanded(
                      flex: disappointedCount.clamp(1, 1000000),
                      child: Container(color: AppColors.overspendRed),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$approvedCount approved · $disappointedCount disappointed, out of ${approvedCount + disappointedCount} judged entries',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal-ish bar chart of expense totals grouped by category, largest
/// first. Capped to the top 6 categories so the chart stays readable.
class _CategoryBarChart extends StatelessWidget {
  final Map<String, double> categoryTotals;
  final NumberFormat currency;

  const _CategoryBarChart({required this.categoryTotals, required this.currency});

  @override
  Widget build(BuildContext context) {
    final entries = categoryTotals.entries.take(6).toList();
    final maxValue = entries.map((e) => e.value).fold<double>(0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          maxY: maxValue * 1.2,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final entry = entries[group.x.toInt()];
                return BarTooltipItem(
                  '${entry.key}\n${currency.format(entry.value)}',
                  const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= entries.length) return const SizedBox.shrink();
                  final label = entries[index].key;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      label.length > 8 ? '${label.substring(0, 8)}…' : label,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (int i = 0; i < entries.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: entries[i].value,
                    color: AppColors.overspendRed,
                    width: 22,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Line chart of running daily net balance (income - expense) over the
/// requested window. Green above zero, red below — drawn as a single line
/// since the sign already carries the story.
class _DailyNetLineChart extends StatelessWidget {
  final List<MapEntry<DateTime, double>> trend;

  const _DailyNetLineChart({required this.trend});

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), trend[i].value),
    ];
    final maxAbs = trend
        .map((e) => e.value.abs())
        .fold<double>(1, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: -maxAbs * 1.2,
          maxY: maxAbs * 1.2,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxAbs / 2 == 0 ? 1 : maxAbs / 2,
            getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.surfaceElevated, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: (trend.length / 4).clamp(1, trend.length).floorToDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= trend.length) return const SizedBox.shrink();
                  final date = trend[index].key;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      DateFormat.Md().format(date),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((spot) {
                final date = trend[spot.x.toInt()].key;
                return LineTooltipItem(
                  '${DateFormat.MMMd().format(date)}\n\$${spot.y.toStringAsFixed(2)}',
                  const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.savingsGreen,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.savingsGreen.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grouped bar chart: one pair of bars (income green, expense red) per
/// month, oldest on the left — the classic "money in vs money out over
/// time" view most budgeting apps lead with. Capped to the most recent 6
/// months so it stays legible on a phone screen.
class _MonthlyBarChart extends StatelessWidget {
  final List<MonthSummary> summaries; // most-recent-first, per WalletController
  final NumberFormat currency;

  const _MonthlyBarChart({required this.summaries, required this.currency});

  @override
  Widget build(BuildContext context) {
    // Chronological order (oldest -> newest) for a left-to-right timeline.
    final months = summaries.take(6).toList().reversed.toList();
    final maxValue = months
        .expand((m) => [m.income, m.expense])
        .fold<double>(0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxValue == 0 ? 1 : maxValue * 1.2,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final m = months[group.x.toInt()];
                final label = rodIndex == 0 ? 'Income' : 'Expense';
                final value = rodIndex == 0 ? m.income : m.expense;
                return BarTooltipItem(
                  '${DateFormat.yMMM().format(m.month)}\n$label: ${currency.format(value)}',
                  const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= months.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      DateFormat.MMM().format(months[index].month),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (int i = 0; i < months.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: months[i].income,
                    color: AppColors.savingsGreen,
                    width: 10,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  BarChartRodData(
                    toY: months[i].expense,
                    color: AppColors.overspendRed,
                    width: 10,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
                barsSpace: 4,
              ),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrollable row of month chips ("Jul 2026", "Jun 2026", ...)
/// — tap one to drive the drill-down section below.
class _MonthChipRow extends StatelessWidget {
  final List<MonthSummary> summaries; // most-recent-first
  final DateTime selectedMonth;
  final NumberFormat currency;
  final ValueChanged<DateTime> onSelect;

  const _MonthChipRow({
    required this.summaries,
    required this.selectedMonth,
    required this.currency,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: summaries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final summary = summaries[index];
          final isSelected = summary.matches(selectedMonth);
          final netColor = summary.net >= 0 ? AppColors.savingsGreen : AppColors.overspendRed;

          return GestureDetector(
            onTap: () => onSelect(summary.month),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.surfaceElevated : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.savingsGreen : AppColors.surfaceElevated,
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat.yMMM().format(summary.month),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${summary.net >= 0 ? '+' : '-'}${currency.format(summary.net.abs())}',
                    style: TextStyle(color: netColor, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Drill-down for whichever month is selected: net summary, a category
/// breakdown scoped to that month, and a capped list of that month's
/// transactions (full detail/editing still lives on the Transactions page).
class _MonthDetailCard extends StatelessWidget {
  final MonthSummary summary;
  final NumberFormat currency;

  const _MonthDetailCard({required this.summary, required this.currency});

  static const int _maxTransactionsShown = 8;

  @override
  Widget build(BuildContext context) {
    final netColor = summary.net >= 0 ? AppColors.savingsGreen : AppColors.overspendRed;
    final shown = summary.transactions.take(_maxTransactionsShown).toList();
    final remaining = summary.transactionCount - shown.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat.yMMMM().format(summary.month),
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${summary.net >= 0 ? '+' : '-'}${currency.format(summary.net.abs())}',
                  style: TextStyle(color: netColor, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.transactionCount} transaction${summary.transactionCount == 1 ? '' : 's'} · '
              '${currency.format(summary.income)} in · ${currency.format(summary.expense)} out',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (shown.isEmpty)
              const Text(
                'No transactions this month.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              )
            else ...[
              for (final tx in shown) _MonthDetailRow(transaction: tx, currency: currency),
              if (remaining > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '+$remaining more — see the Transactions page for the full list.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact, read-only row for one transaction inside the month drill-down.
class _MonthDetailRow extends StatelessWidget {
  final TransactionModel transaction;
  final NumberFormat currency;

  const _MonthDetailRow({required this.transaction, required this.currency});

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.isIncome;
    final amountColor = isIncome ? AppColors.savingsGreen : AppColors.textPrimary;
    final signedAmount = '${isIncome ? '+' : '-'}${currency.format(transaction.amount)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.category,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                ),
                Text(
                  DateFormat.MMMd().format(transaction.timestamp),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            signedAmount,
            style: TextStyle(color: amountColor, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}