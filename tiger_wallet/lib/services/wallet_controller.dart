import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/ai_verdict_stats.dart';
import '../models/feedback_event.dart';
import '../models/month_summary.dart';
import '../models/transaction_model.dart';
import '../models/user_profile_model.dart';
import 'groq_service.dart';
import 'supabase_service.dart';

/// Drives the dashboard: holds current profile + transactions + monthly
/// totals, and implements the core submit -> insert -> AI critique -> patch
/// workflow, plus editing/deleting a transaction (each with its own AI
/// correction roast).
///
/// Feedback popups are driven by [feedbackEvents] — an explicit stream that
/// only emits right after a submit/edit/delete actually happens. The UI
/// should listen to that stream rather than diffing the transaction list on
/// every rebuild; scanning the list on rebuild caused the popup to
/// resurface old feedback every time the page merely rebuilt (e.g. when
/// swiping between pages), since a rebuild has nothing to do with whether
/// new feedback actually arrived.
class WalletController extends ChangeNotifier {
  SupabaseService? _dbInstance;
  SupabaseService get _db => _dbInstance ??= SupabaseService.instance;

  GroqService? _aiInstance;
  GroqService get _ai => _aiInstance ??= GroqService.instance;

  UserProfile? profile;
  List<TransactionModel> transactions;
  double monthlyTotal = 0; // expenses only
  double monthlyIncome = 0;
  bool isLoading = false;
  bool isSubmitting = false;
  bool isUpdatingBudget = false;
  String? errorMessage;

  StreamSubscription<List<TransactionModel>>? _txSub;

  final StreamController<FeedbackEvent> _feedbackEventsController =
      StreamController<FeedbackEvent>.broadcast();

  /// Normal usage: `WalletController()` starts empty — call [initialize] to
  /// load everything from Supabase like the real app does.
  ///
  /// Test usage: pass [initialTransactions] (and optionally [initialProfile])
  /// to seed the controller directly, skipping Supabase/Groq entirely.
  /// [monthlyTotal] / [monthlyIncome] are derived from the seed data the
  /// same way [initialize] would derive them, so analytics getters
  /// ([expenseByCategoryThisMonth], [dailyNetTrend], [monthlyBalance],
  /// [budgetProgress], [isOverBudget], etc.) all behave correctly in unit
  /// tests without a live backend.
  WalletController({List<TransactionModel>? initialTransactions, UserProfile? initialProfile})
      : transactions = initialTransactions ?? [],
        profile = initialProfile {
    if (initialTransactions != null) {
      monthlyTotal = _sumForCurrentMonth(initialTransactions, TransactionType.expense);
      monthlyIncome = _sumForCurrentMonth(initialTransactions, TransactionType.income);
    }
  }

  static double _sumForCurrentMonth(List<TransactionModel> txs, TransactionType type) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    double total = 0;
    for (final tx in txs) {
      if (tx.type == type && !tx.timestamp.isBefore(monthStart)) {
        total += tx.amount;
      }
    }
    return total;
  }

  /// Listen to this to know exactly when to pop the AI feedback sheet.
  Stream<FeedbackEvent> get feedbackEvents => _feedbackEventsController.stream;

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

  /// Sum of expense amounts for an arbitrary month, grouped by category —
  /// generalizes [expenseByCategoryThisMonth] so the analytics drill-down
  /// can chart spending for any past month, not just the current one.
  Map<String, double> expenseByCategoryForMonth(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final totals = <String, double>{};

    for (final tx in transactions) {
      if (tx.isExpense && !tx.timestamp.isBefore(start) && tx.timestamp.isBefore(end)) {
        totals[tx.category] = (totals[tx.category] ?? 0) + tx.amount;
      }
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in sorted) e.key: e.value};
  }

  /// Every transaction grouped into calendar months, most recent month
  /// first — the same "gather everything, split by month" view other
  /// budgeting apps show. Each [MonthSummary] carries that month's income,
  /// expense, and the transactions themselves for drill-down.
  List<MonthSummary> get monthlySummaries {
    final grouped = <DateTime, List<TransactionModel>>{};

    for (final tx in transactions) {
      final key = DateTime(tx.timestamp.year, tx.timestamp.month, 1);
      grouped.putIfAbsent(key, () => []).add(tx);
    }

    final summaries = grouped.entries.map((entry) {
      final txs = entry.value..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final income = txs.where((t) => t.isIncome).fold(0.0, (sum, t) => sum + t.amount);
      final expense = txs.where((t) => t.isExpense).fold(0.0, (sum, t) => sum + t.amount);
      return MonthSummary(month: entry.key, income: income, expense: expense, transactions: txs);
    }).toList();

    summaries.sort((a, b) => b.month.compareTo(a.month));
    return summaries;
  }

  /// How often the AI has approved vs been disappointed, across every
  /// judged transaction (submits and edit/delete corrections alike).
  AiVerdictStats get aiVerdictStats {
    var approved = 0;
    var disappointed = 0;
    for (final tx in transactions) {
      if (tx.sentiment == TransactionSentiment.approved) approved++;
      if (tx.sentiment == TransactionSentiment.disappointed) disappointed++;
    }
    return AiVerdictStats(approvedCount: approved, disappointedCount: disappointed);
  }

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
  /// The realtime subscription only keeps [transactions] in sync (so edits/
  /// deletes/inserts from any source show up promptly) — it does NOT drive
  /// any popups. Popups only ever come from [feedbackEvents].
  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();
    try {
      profile = await _db.fetchUserProfile();
      transactions = await _db.fetchTransactions();
      monthlyTotal = await _db.fetchCurrentMonthTotal();
      monthlyIncome = await _db.fetchCurrentMonthIncome();

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

  /// Executes the full submit -> insert -> AI critique -> patch workflow,
  /// then emits a [FeedbackEvent] so the UI shows the critique exactly once.
  Future<void> submitTransaction({
    required double amount,
    required String category,
    TransactionType type = TransactionType.expense,
    String? note,
  }) async {
    if (profile == null) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      final inserted = await _db.insertTransaction(
        amount: amount,
        category: category,
        type: type,
        note: note,
      );

      monthlyTotal = await _db.fetchCurrentMonthTotal();
      monthlyIncome = await _db.fetchCurrentMonthIncome();

      final feedback = await _ai.critiqueTransaction(
        amount: amount,
        category: category,
        monthlyTotalAfterThisTransaction: monthlyTotal,
        budgetThreshold: profile!.budgetThreshold,
        parentPersonality: profile!.parentPersonality,
        type: type,
        note: note,
      );

      // Same rule the UI already uses for red/green accents: income is
      // always a grudging approval, expenses depend on whether this entry
      // pushed the user over budget. Recorded once here rather than
      // re-derived from the free-text critique later.
      final sentiment = type == TransactionType.income
          ? TransactionSentiment.approved
          : (monthlyTotal > profile!.budgetThreshold
              ? TransactionSentiment.disappointed
              : TransactionSentiment.approved);

      await _db.updateTransactionFeedback(
        transactionId: inserted.id,
        feedback: feedback,
        sentiment: sentiment,
      );

      _feedbackEventsController.add(FeedbackEvent(
        message: feedback,
        category: category,
        amount: amount,
        type: type,
        note: note,
        isCorrection: false,
      ));
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  /// Lets the user fix a transaction they typed in wrong. Overwrites the
  /// row, gets a fresh "you couldn't even get this right the first time"
  /// roast from Groq, patches it into `ai_feedback`, and emits the popup.
  Future<void> editTransaction({
    required TransactionModel original,
    required double amount,
    required String category,
    required TransactionType type,
    String? note,
  }) async {
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _db.updateTransaction(
        transactionId: original.id,
        amount: amount,
        category: category,
        type: type,
        note: note,
      );

      monthlyTotal = await _db.fetchCurrentMonthTotal();
      monthlyIncome = await _db.fetchCurrentMonthIncome();

      final roast = await _ai.critiqueCorrection(
        action: TransactionAction.edited,
        category: category,
        amount: amount,
        note: note,
      );

      await _db.updateTransactionFeedback(
        transactionId: original.id,
        feedback: roast,
        // Corrections are always mockery, never praise — the mistake itself
        // is the point, regardless of how the fixed entry compares to budget.
        sentiment: TransactionSentiment.disappointed,
      );

      _feedbackEventsController.add(FeedbackEvent(
        message: roast,
        category: category,
        amount: amount,
        type: type,
        note: note,
        isCorrection: true,
      ));
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  /// Deletes a transaction outright and pops a roast for it. The roast is
  /// fetched before the delete so we still have the category/amount to
  /// describe — there's no row left afterwards to patch `ai_feedback` onto,
  /// so this is shown as a one-off popup rather than persisted anywhere.
  Future<void> deleteTransaction(TransactionModel transaction) async {
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      final roast = await _ai.critiqueCorrection(
        action: TransactionAction.deleted,
        category: transaction.category,
        amount: transaction.amount,
        note: transaction.note,
      );

      await _db.deleteTransaction(transaction.id);

      monthlyTotal = await _db.fetchCurrentMonthTotal();
      monthlyIncome = await _db.fetchCurrentMonthIncome();

      _feedbackEventsController.add(FeedbackEvent(
        message: roast,
        category: transaction.category,
        amount: transaction.amount,
        type: transaction.type,
        note: transaction.note,
        isCorrection: true,
      ));
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
    _feedbackEventsController.close();
    super.dispose();
  }
}