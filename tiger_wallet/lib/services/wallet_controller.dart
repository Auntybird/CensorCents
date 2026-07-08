import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../models/user_profile_model.dart';
import 'groq_service.dart';
import 'supabase_service.dart';

/// Drives the dashboard: holds current profile + transactions + monthly
/// total, and implements the exact 5-step workflow described in the spec:
///
///   1. User submits amount + category from the form.
///   2. Write the raw transaction to Supabase (no ai_feedback yet).
///   3. Compute new monthly total -> call Groq for the critique.
///   4. Patch the same transaction row with ai_feedback.
///   5. UI (subscribed via Realtime stream) reflects the update immediately.
class WalletController extends ChangeNotifier {
  final SupabaseService _db = SupabaseService.instance;
  final GroqService _ai = GroqService.instance;

  UserProfile? profile;
  List<TransactionModel> transactions = [];
  double monthlyTotal = 0; // expenses only
  double monthlyIncome = 0;
  bool isLoading = false;
  bool isSubmitting = false;
  String? errorMessage;

  StreamSubscription<List<TransactionModel>>? _txSub;

  bool get isOverBudget =>
      profile != null && monthlyTotal > profile!.budgetThreshold;

  double get budgetProgress {
    if (profile == null || profile!.budgetThreshold <= 0) return 0;
    return (monthlyTotal / profile!.budgetThreshold).clamp(0.0, 2.0);
  }

  /// Income minus expenses for the current calendar month. Positive means
  /// the user is in the black this month, negative means they spent more
  /// than they brought in.
  double get monthlyBalance => monthlyIncome - monthlyTotal;

  /// Sum of expense amounts this month, grouped by category — feeds the
  /// analytics breakdown chart. Sorted descending so the biggest spend
  /// category comes first.
  Map<String, double> get expenseByCategoryThisMonth {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final totals = <String, double>{};

    for (final tx in transactions) {
      if (tx.isExpense && !tx.timestamp.isBefore(monthStart)) {
        totals[tx.category] = (totals[tx.category] ?? 0) + tx.amount;
      }
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in sorted) e.key: e.value};
  }

  /// Net (income - expense) for each of the last [days] calendar days,
  /// oldest first — feeds the trend line chart. Days with no activity show
  /// up as 0 so the chart has a continuous x-axis.
  List<MapEntry<DateTime, double>> dailyNetTrend({int days = 14}) {
    final today = DateTime.now();
    final startDay = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: days - 1));

    final totals = <DateTime, double>{
      for (int i = 0; i < days; i++) startDay.add(Duration(days: i)): 0.0,
    };

    for (final tx in transactions) {
      final day = DateTime(tx.timestamp.year, tx.timestamp.month, tx.timestamp.day);
      if (day.isBefore(startDay)) continue;
      final delta = tx.isIncome ? tx.amount : -tx.amount;
      totals[day] = (totals[day] ?? 0) + delta;
    }

    final entries = totals.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  bool isUpdatingBudget = false;

  /// Lets the user edit their own budget ceiling / persona from settings.
  /// Refreshes [profile] (and the derived budget getters) on success.
  Future<void> updateBudget({
    double? budgetThreshold,
    String? parentPersonality,
  }) async {
    isUpdatingBudget = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _db.updateUserProfile(
        budgetThreshold: budgetThreshold,
        parentPersonality: parentPersonality,
      );
      profile = await _db.fetchUserProfile();
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isUpdatingBudget = false;
      notifyListeners();
    }
  }

  /// Loads the profile + transaction history and opens the realtime feed.
  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();
    try {
      profile = await _db.fetchUserProfile();
      transactions = await _db.fetchTransactions();
      monthlyTotal = await _db.fetchCurrentMonthTotal();
      monthlyIncome = await _db.fetchCurrentMonthIncome();

      // Realtime: whenever ANY row changes (insert or the later ai_feedback
      // update), refresh the in-memory list so the UI updates automatically.
      _txSub?.cancel();
      _txSub = _db.watchTransactions().listen((rows) {
        transactions = rows;
        notifyListeners();
      });
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Executes the full submit -> insert -> AI critique -> patch workflow.
  Future<void> submitTransaction({
    required double amount,
    required String category,
    TransactionType type = TransactionType.expense,
  }) async {
    if (profile == null) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      // STEP 2: write the basic transaction to Supabase first, so the entry
      // shows up instantly even before the AI responds.
      final inserted = await _db.insertTransaction(
        amount: amount,
        category: category,
        type: type,
      );

      // STEP 3a: recompute the running monthly totals including this entry.
      // Only the expense total feeds the budget math; income is tracked
      // separately so it never counts as "spending".
      monthlyTotal = await _db.fetchCurrentMonthTotal();
      monthlyIncome = await _db.fetchCurrentMonthIncome();

      // STEP 3b: call Groq for the critique text.
      final feedback = await _ai.critiqueTransaction(
        amount: amount,
        category: category,
        monthlyTotalAfterThisTransaction: monthlyTotal,
        budgetThreshold: profile!.budgetThreshold,
        parentPersonality: profile!.parentPersonality,
        type: type,
      );

      // STEP 4: patch the transaction row with the AI's text.
      await _db.updateTransactionFeedback(
        transactionId: inserted.id,
        feedback: feedback,
      );

      // STEP 5 happens automatically: the Realtime subscription above
      // receives the UPDATE event and refreshes `transactions`.
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _txSub?.cancel();
    super.dispose();
  }
}