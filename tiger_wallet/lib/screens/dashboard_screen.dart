import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/feedback_event.dart';
import '../models/savings_goal.dart';
import '../models/transaction_model.dart';
import '../services/supabase_service.dart';
import '../services/wallet_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/add_goal_sheet.dart';
import '../widgets/add_transaction_sheet.dart';
import '../widgets/ai_feedback_sheet.dart';
import '../widgets/edit_budget_sheet.dart';
import '../widgets/stern_avatar.dart';
import 'analytics_screen.dart';
import 'settings_screen.dart';

const List<String> _kPageTitles = ['CensorCents', 'Transactions', 'Analytics'];

/// The primary shell after login: a horizontally swipeable 3-page view.
///   Page 1 (Home)         — stern avatar + budget summary + edit budget
///   Page 2 (Transactions) — full history + "Add Transaction" FAB, each row
///                            editable/deletable
///   Page 3 (Analytics)    — spending charts (AnalyticsBody)
/// Swipe left/right or tap the dot indicator to move between them.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _currency = NumberFormat.currency(symbol: '\$');
  final _pageController = PageController();
  int _currentPage = 0;

  StreamSubscription<FeedbackEvent>? _feedbackSub;

  @override
  void initState() {
    super.initState();
    final controller = context.read<WalletController>();

    // Kick off the initial load once the widget tree is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.initialize();
    });

    // The ONLY thing that pops the AI feedback sheet. This fires exactly
    // once per submit/edit/delete, regardless of how many times the widget
    // tree rebuilds for unrelated reasons (like swiping between pages) — so
    // it can never resurface old feedback on its own.
    _feedbackSub = controller.feedbackEvents.listen((event) {
      if (!mounted) return;
      AiFeedbackSheet.show(
        context,
        feedbackText: event.message,
        isOverBudget: controller.isOverBudget,
        category: event.category,
        amount: event.amount,
        type: event.type,
        note: event.note,
        isCorrection: event.isCorrection,
      );
    });
  }

  @override
  void dispose() {
    _feedbackSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openAddTransactionSheet() async {
    final controller = context.read<WalletController>();
    final result = await AddTransactionSheet.show(context);
    if (result == null) return;

    final (amount, category, type, note) = result;
    await controller.submitTransaction(
      amount: amount,
      category: category,
      type: type,
      note: note,
    );
  }

  Future<void> _openEditTransactionSheet(TransactionModel tx) async {
    final controller = context.read<WalletController>();
    final result = await AddTransactionSheet.show(context, existing: tx);
    if (result == null) return;

    final (amount, category, type, note) = result;
    await controller.editTransaction(
      original: tx,
      amount: amount,
      category: category,
      type: type,
      note: note,
    );
  }

  Future<void> _confirmDeleteTransaction(TransactionModel tx) async {
    final controller = context.read<WalletController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Delete this entry?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'This permanently removes "${tx.category}" (${_currency.format(tx.amount)}). This can\'t be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.overspendRed)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await controller.deleteTransaction(tx);
    }
  }

  Future<void> _openEditBudgetSheet() async {
    final controller = context.read<WalletController>();
    final profile = controller.profile;
    if (profile == null) return;

    final result = await EditBudgetSheet.show(
      context,
      currentThreshold: profile.budgetThreshold,
      currentPersonality: profile.parentPersonality,
    );
    if (result == null) return;

    final (threshold, personality) = result;
    await controller.updateBudget(
      budgetThreshold: threshold,
      parentPersonality: personality,
    );
  }

  Future<void> _openAddGoalSheet() async {
    final controller = context.read<WalletController>();
    final result = await AddGoalSheet.show(context);
    if (result == null) return;

    final (name, targetAmount, targetDate) = result;
    await controller.addGoal(name: name, targetAmount: targetAmount, targetDate: targetDate);
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

        return Scaffold(
          appBar: AppBar(
            title: Text(_kPageTitles[_currentPage]),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
                onPressed: () => SupabaseService.instance.signOut(),
              ),
            ],
          ),
          body: PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPage = index),
            children: [
              _HomePage(
                controller: controller,
                currency: _currency,
                onEditBudget: _openEditBudgetSheet,
                onAddGoal: _openAddGoalSheet,
              ),
              _TransactionsPage(
                controller: controller,
                currency: _currency,
                onAddTransaction: _openAddTransactionSheet,
                onEditTransaction: _openEditTransactionSheet,
                onDeleteTransaction: _confirmDeleteTransaction,
              ),
              const AnalyticsBody(),
            ],
          ),
          // Tappable dot indicator so the pages are discoverable even before
          // someone thinks to swipe.
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_kPageTitles.length, (index) {
                  final isActive = index == _currentPage;
                  return GestureDetector(
                    onTap: () => _goToPage(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.savingsGreen : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          floatingActionButton: _currentPage == 1
              ? FloatingActionButton.extended(
                  onPressed: controller.isSubmitting ? null : _openAddTransactionSheet,
                  icon: controller.isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.add),
                  label: Text(controller.isSubmitting ? 'Judging...' : 'Add Transaction'),
                )
              : null,
        );
      },
    );
  }
}

/// PAGE 1 — avatar, budget summary card, error banner.
class _HomePage extends StatelessWidget {
  final WalletController controller;
  final NumberFormat currency;
  final VoidCallback onEditBudget;
  final VoidCallback onAddGoal;

  const _HomePage({
    required this.controller,
    required this.currency,
    required this.onEditBudget,
    required this.onAddGoal,
  });

  @override
  Widget build(BuildContext context) {
    final mood = moodForRatio(controller.budgetProgress);

    return RefreshIndicator(
      color: AppColors.savingsGreen,
      onRefresh: controller.initialize,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: SternAvatar(mood: mood)),
          const SizedBox(height: 24),
          if (controller.errorMessage != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.overspendRed.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.overspendRed, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.overspendRed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'AI ENGINE FAILURE:\n${controller.errorMessage}',
                      style: const TextStyle(
                        color: AppColors.overspendRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _BudgetSummaryCard(
            monthlyTotal: controller.monthlyTotal,
            monthlyIncome: controller.monthlyIncome,
            balance: controller.monthlyBalance,
            threshold: controller.profile?.budgetThreshold ?? 0,
            progress: controller.budgetProgress,
            currency: currency,
            onEdit: onEditBudget,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: controller.isRoasting ? null : controller.roastMeNow,
              icon: controller.isRoasting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.overspendRed),
                    )
                  : const Icon(Icons.local_fire_department_outlined, size: 18, color: AppColors.overspendRed),
              label: Text(
                controller.isRoasting ? 'Judging...' : 'Roast Me Now',
                style: const TextStyle(color: AppColors.overspendRed),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.overspendRed),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Savings Goals', style: Theme.of(context).textTheme.headlineMedium),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: AppColors.savingsGreen),
                onPressed: onAddGoal,
                tooltip: 'Add goal',
              ),
            ],
          ),
          if (controller.goals.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No goals yet. Ambitious of you to skip this.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ...controller.goals.map((goal) => _GoalCard(
                  goal: goal,
                  progress: controller.goalProgress(goal),
                  currency: currency,
                  reached: controller.isGoalReached(goal),
                  onClaim: () => controller.celebrateGoalReached(goal),
                  onDelete: () => controller.removeGoal(goal),
                )),
          const SizedBox(height: 24),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swipe_left_alt_rounded, size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 6),
                  Text(
                    'Swipe left for transactions & analytics',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// PAGE 2 — full transaction history list (the "Add Transaction" action
/// lives on the shell's FloatingActionButton while this page is visible).
/// Each row can be edited or deleted via its overflow menu.
class _TransactionsPage extends StatelessWidget {
  final WalletController controller;
  final NumberFormat currency;
  final VoidCallback onAddTransaction;
  final ValueChanged<TransactionModel> onEditTransaction;
  final ValueChanged<TransactionModel> onDeleteTransaction;

  const _TransactionsPage({
    required this.controller,
    required this.currency,
    required this.onAddTransaction,
    required this.onEditTransaction,
    required this.onDeleteTransaction,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.savingsGreen,
      onRefresh: controller.initialize,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Recent Transactions',
                  style: Theme.of(context).textTheme.headlineMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: controller.isSubmitting ? null : onAddTransaction,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.savingsGreen,
                  side: const BorderSide(color: AppColors.savingsGreen),
                ),
              ),
            ],
          ),
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
              (tx) => _TransactionTile(
                transaction: tx,
                currency: currency,
                onEdit: () => onEditTransaction(tx),
                onDelete: () => onDeleteTransaction(tx),
              ),
            ),
        ],
      ),
    );
  }
}

/// Card showing spend-vs-threshold with a color-coded progress bar, plus an
/// income/expense/balance breakdown and a tap target to edit the budget.
/// One savings goal: progress bar, amount toward target, and either a
/// "Claim" button (once reached, to trigger the AI's grudging credit) or a
/// delete button. Claiming is a manual tap rather than auto-detected on
/// rebuild — auto-popping a sheet based on scanning state during build is
/// exactly the pattern that caused the transaction-feedback popup bug
/// earlier, so goal celebration deliberately avoids it.
class _GoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final double progress;
  final NumberFormat currency;
  final bool reached;
  final VoidCallback onClaim;
  final VoidCallback onDelete;

  const _GoalCard({
    required this.goal,
    required this.progress,
    required this.currency,
    required this.reached,
    required this.onClaim,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = goal.targetAmount <= 0 ? 0.0 : (progress / goal.targetAmount).clamp(0.0, 1.0);
    final accent = reached ? AppColors.savingsGreen : AppColors.textSecondary;

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
                Expanded(
                  child: Text(
                    goal.name,
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.textSecondary),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: AppColors.surfaceElevated,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${currency.format(progress)} of ${currency.format(goal.targetAmount)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                if (reached)
                  TextButton.icon(
                    onPressed: onClaim,
                    icon: const Icon(Icons.emoji_events_outlined, size: 16, color: AppColors.savingsGreen),
                    label: const Text('Claim', style: TextStyle(color: AppColors.savingsGreen, fontSize: 12)),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetSummaryCard extends StatelessWidget {
  final double monthlyTotal;
  final double monthlyIncome;
  final double balance;
  final double threshold;
  final double progress; // 0.0 - 2.0, clamped
  final NumberFormat currency;
  final VoidCallback onEdit;

  const _BudgetSummaryCard({
    required this.monthlyTotal,
    required this.monthlyIncome,
    required this.balance,
    required this.threshold,
    required this.progress,
    required this.currency,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isOver = monthlyTotal > threshold;
    final accent = isOver ? AppColors.overspendRed : AppColors.savingsGreen;
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
                const Text('This Month', style: TextStyle(color: AppColors.textSecondary)),
                Row(
                  children: [
                    Text(
                      isOver ? 'OVER BUDGET' : 'ON TRACK',
                      style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onEdit,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.edit_outlined, size: 16, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.arrow_downward, size: 14, color: AppColors.savingsGreen),
                    const SizedBox(width: 4),
                    Text(
                      'Income: ${currency.format(monthlyIncome)}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.arrow_upward, size: 14, color: AppColors.overspendRed),
                    const SizedBox(width: 4),
                    Text(
                      'Spent: ${currency.format(monthlyTotal)}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: balanceColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Balance', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  Text(
                    '${balance >= 0 ? '+' : '-'}${currency.format(balance.abs())}',
                    style: TextStyle(color: balanceColor, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single row in the transaction history list, with an overflow menu for
/// editing or deleting the entry.
class _TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final NumberFormat currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TransactionTile({
    required this.transaction,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasFeedback = transaction.aiFeedback != null;
    final isIncome = transaction.isIncome;
    final amountColor = isIncome ? AppColors.savingsGreen : AppColors.textPrimary;
    final signedAmount =
        '${isIncome ? '+' : '-'}${currency.format(transaction.amount)}';

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isIncome) ...[
                            const Icon(Icons.arrow_downward, size: 14, color: AppColors.savingsGreen),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            transaction.category,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      Text(
                        DateFormat.yMMMd().add_jm().format(transaction.timestamp),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      if (transaction.note != null && transaction.note!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '"${transaction.note!.trim()}"',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  signedAmount,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: amountColor),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
                  color: AppColors.surfaceElevated,
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18, color: AppColors.textPrimary),
                          SizedBox(width: 8),
                          Text('Edit', style: TextStyle(color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: AppColors.overspendRed),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: AppColors.overspendRed)),
                        ],
                      ),
                    ),
                  ],
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