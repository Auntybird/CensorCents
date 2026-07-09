import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../theme/app_theme.dart';

/// Elegant animated bottom sheet used to present the AI's real-time
/// critique the moment `ai_feedback` lands on a transaction row.
///
/// [isOverBudget] controls the accent color for EXPENSE entries (red scold
/// vs green praise). INCOME entries always render in green since money
/// coming in is never itself a budget violation — the actual wording still
/// always comes from Groq.
class AiFeedbackSheet extends StatelessWidget {
  final String feedbackText;
  final bool isOverBudget;
  final String category;
  final double amount;
  final TransactionType type;
  final String? note;

  const AiFeedbackSheet({
    super.key,
    required this.feedbackText,
    required this.isOverBudget,
    required this.category,
    required this.amount,
    this.type = TransactionType.expense,
    this.note,
  });

  static Future<void> show(
    BuildContext context, {
    required String feedbackText,
    required bool isOverBudget,
    required String category,
    required double amount,
    TransactionType type = TransactionType.expense,
    String? note,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AiFeedbackSheet(
        feedbackText: feedbackText,
        isOverBudget: isOverBudget,
        category: category,
        amount: amount,
        type: type,
        note: note,
      ),
    );
  }

  bool get _isIncome => type == TransactionType.income;

  @override
  Widget build(BuildContext context) {
    final accent = _isIncome
        ? AppColors.savingsGreen
        : (isOverBudget ? AppColors.overspendRed : AppColors.savingsGreen);

    // TweenAnimationBuilder gives a nice pop/slide-in without needing a
    // dedicated AnimationController + StatefulWidget boilerplate.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 40),
          child: Opacity(opacity: value.clamp(0, 1), child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.3),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isIncome
                      ? Icons.trending_up_rounded
                      : (isOverBudget ? Icons.warning_rounded : Icons.emoji_events_rounded),
                  color: accent,
                ),
                const SizedBox(width: 8),
                Text(
                  _isIncome
                      ? 'CENSORCENTS NOTES YOUR INCOME'
                      : (isOverBudget ? 'CENSORCENTS IS DISAPPOINTED' : 'CENSORCENTS APPROVES'),
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '"$feedbackText"',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$category · \$${amount.toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            if (note != null && note!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '"${note!.trim()}"',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Yes, Boss'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}