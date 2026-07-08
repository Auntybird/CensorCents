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