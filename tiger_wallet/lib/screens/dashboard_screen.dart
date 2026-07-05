import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../services/supabase_service.dart';
import '../services/wallet_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/add_transaction_sheet.dart';
import '../widgets/ai_feedback_sheet.dart';
import '../widgets/stern_avatar.dart';

/// The primary screen: stern avatar, budget progress, "Add Transaction"
/// button, and a scrollable history where each card shows the AI's
/// critique once it has landed.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _currency = NumberFormat.currency(symbol: '\$');

  // Tracks which transaction IDs we've already popped a feedback sheet for,
  // so the Realtime stream doesn't re-show the same critique on every rebuild.
  final Set<String> _shownFeedbackIds = {};

  @override
  void initState() {
    super.initState();
    // Kick off the initial load once the widget tree is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletController>().initialize();
    });
  }

  Future<void> _openAddTransactionSheet() async {
    final controller = context.read<WalletController>();
    final result = await AddTransactionSheet.show(context);
    if (result == null) return;

    final (amount, category) = result;
    await controller.submitTransaction(amount: amount, category: category);
  }

  /// Watches for any transaction whose ai_feedback just arrived and hasn't
  /// been shown yet, then pops the animated sheet for it (Step 5 of the flow).
  void _maybeShowNewFeedback(List<TransactionModel> transactions) {
    for (final tx in transactions) {
      if (tx.aiFeedback != null && !_shownFeedbackIds.contains(tx.id)) {
        _shownFeedbackIds.add(tx.id);
        final controller = context.read<WalletController>();
        final isOver = controller.profile != null &&
            controller.monthlyTotal > controller.profile!.budgetThreshold;

        // Defer to next frame to avoid calling showModalBottomSheet mid-build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          AiFeedbackSheet.show(
            context,
            feedbackText: tx.aiFeedback!,
            isOverBudget: isOver,
            category: tx.category,
            amount: tx.amount,
          );
        });
        break; // show one at a time
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WalletController>(
      builder: (context, controller, _) {
        if (controller.isLoading && controller.profile == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppColors.savingsGreen)),
          );
        }

        _maybeShowNewFeedback(controller.transactions);

        final mood = moodForRatio(controller.budgetProgress);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Tiger Wallet'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
                onPressed: () => SupabaseService.instance.signOut(),
              ),
            ],
          ),
          body: RefreshIndicator(
            color: AppColors.savingsGreen,
            onRefresh: controller.initialize,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(child: SternAvatar(mood: mood)),
                const SizedBox(height: 24),
                _BudgetSummaryCard(
                  monthlyTotal: controller.monthlyTotal,
                  threshold: controller.profile?.budgetThreshold ?? 0,
                  progress: controller.budgetProgress,
                  currency: _currency,
                ),
                const SizedBox(height: 24),
                Text('Recent Transactions', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                if (controller.transactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No transactions yet. Try to keep it that way.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  ...controller.transactions.map(
                    (tx) => _TransactionTile(transaction: tx, currency: _currency),
                  ),
                const SizedBox(height: 100), // room above the FAB
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: controller.isSubmitting ? null : _openAddTransactionSheet,
            icon: controller.isSubmitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.add),
            label: Text(controller.isSubmitting ? 'Judging...' : 'Add Transaction'),
          ),
        );
      },
    );
  }
}

/// Card showing spend-vs-threshold with a color-coded progress bar.
class _BudgetSummaryCard extends StatelessWidget {
  final double monthlyTotal;
  final double threshold;
  final double progress; // 0.0 - 2.0, clamped
  final NumberFormat currency;

  const _BudgetSummaryCard({
    required this.monthlyTotal,
    required this.threshold,
    required this.progress,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final isOver = monthlyTotal > threshold;
    final accent = isOver ? AppColors.overspendRed : AppColors.savingsGreen;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('This Month', style: TextStyle(color: AppColors.textSecondary)),
                Text(
                  isOver ? 'OVER BUDGET' : 'ON TRACK',
                  style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              currency.format(monthlyTotal),
              style: TextStyle(color: accent, fontSize: 32, fontWeight: FontWeight.bold),
            ),
            Text(
              'of ${currency.format(threshold)} budget',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: AppColors.surfaceElevated,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single row in the transaction history list.
class _TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final NumberFormat currency;

  const _TransactionTile({required this.transaction, required this.currency});

  @override
  Widget build(BuildContext context) {
    final hasFeedback = transaction.aiFeedback != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.category,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    Text(
                      DateFormat.yMMMd().add_jm().format(transaction.timestamp),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                Text(
                  currency.format(transaction.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                ),
              ],
            ),
            if (hasFeedback) ...[
              const Divider(height: 20, color: AppColors.surfaceElevated),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.record_voice_over, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      transaction.aiFeedback!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  SizedBox(
                    height: 12,
                    width: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textSecondary),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Awaiting judgement...',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
