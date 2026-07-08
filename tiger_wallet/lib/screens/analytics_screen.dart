import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/wallet_controller.dart';
import '../theme/app_theme.dart';

/// Read-only analytics dashboard: income vs expense for the month, a
/// category breakdown of spending, and a rolling daily net-balance trend.
/// Pulls entirely from data WalletController already has in memory — no
/// extra Supabase round-trips needed.
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: Consumer<WalletController>(
        builder: (context, controller, _) {
          final categoryTotals = controller.expenseByCategoryThisMonth;
          final trend = controller.dailyNetTrend(days: 14);

          if (controller.transactions.isEmpty) {
            return const Center(
              child: Text(
                'No data yet. Add a transaction first.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }

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
              const SizedBox(height: 40),
            ],
          );
        },
      ),
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