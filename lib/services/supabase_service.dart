import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category_budget.dart';
import '../models/savings_goal.dart';
import '../models/transaction_model.dart';
import '../models/user_profile_model.dart';

/// Single point of contact with Supabase: auth, the `users` profile table,
/// and the `transactions` table. Keeping all queries in one service makes it
/// trivial to swap backends later and keeps RLS assumptions in one place.
class SupabaseService {
  SupabaseService._internal();
  static final SupabaseService instance = SupabaseService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  // --------------------------------------------------------------------
  // AUTH
  // --------------------------------------------------------------------

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    // The `public.users` row is auto-created by the `on_auth_user_created`
    // trigger defined in supabase_schema.sql — no manual insert needed here.
    return _client.auth.signUp(email: email, password: password);
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  // --------------------------------------------------------------------
  // USER PROFILE
  // --------------------------------------------------------------------

  /// Fetches the caller's own profile row (budget_threshold, personality).
  /// RLS guarantees this can only ever return the signed-in user's row.
  Future<UserProfile> fetchUserProfile() async {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('No authenticated user.');

    final row = await _client.from('users').select().eq('id', uid).single();

    return UserProfile.fromJson(row);
  }

  /// Lets the user adjust their own budget ceiling / persona from settings.
  Future<void> updateUserProfile({
    double? budgetThreshold,
    String? parentPersonality,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('No authenticated user.');

    final updates = <String, dynamic>{
      if (budgetThreshold != null) 'budget_threshold': budgetThreshold,
      if (parentPersonality != null) 'parent_personality': parentPersonality,
    };
    if (updates.isEmpty) return;

    await _client.from('users').update(updates).eq('id', uid);
  }

  // --------------------------------------------------------------------
  // TRANSACTIONS
  // --------------------------------------------------------------------

  /// All transactions for the signed-in user, most recent first.
  Future<List<TransactionModel>> fetchTransactions() async {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('No authenticated user.');

    final rows = await _client
        .from('transactions')
        .select()
        .eq('user_id', uid)
        .order('timestamp', ascending: false);

    return (rows as List)
        .map((row) => TransactionModel.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Sum of EXPENSE transaction amounts within the current calendar month.
  /// Used to decide whether the user is over/under their budget_threshold.
  /// Income rows are intentionally excluded — they shouldn't make the AI
  /// think the user has "spent" more.
  Future<double> fetchCurrentMonthTotal() async {
    return _sumCurrentMonth(TransactionType.expense);
  }

  /// Sum of INCOME transaction amounts within the current calendar month.
  /// Handy for a "money in vs money out" summary on the dashboard.
  Future<double> fetchCurrentMonthIncome() async {
    return _sumCurrentMonth(TransactionType.income);
  }

  Future<double> _sumCurrentMonth(TransactionType type) async {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('No authenticated user.');

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    final rows = await _client
        .from('transactions')
        .select('amount')
        .eq('user_id', uid)
        .eq('type', type.value)
        .gte('timestamp', monthStart.toIso8601String());

    double total = 0;
    for (final row in rows as List) {
      final value = row['amount'];
      total += value is num ? value.toDouble() : double.parse(value.toString());
    }
    return total;
  }

  /// Step 1 of the workflow: insert the raw transaction (no AI feedback yet).
  /// Returns the inserted row so we have its generated `id` for the later patch.
  Future<TransactionModel> insertTransaction({
    required double amount,
    required String category,
    TransactionType type = TransactionType.expense,
    String? note,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('No authenticated user.');

    final draft = TransactionModel(
      id: '', // ignored on insert — Postgres generates this
      userId: uid,
      amount: amount,
      category: category,
      timestamp: DateTime.now(),
      type: type,
      note: note,
    );

    final inserted = await _client
        .from('transactions')
        .insert(draft.toInsertJson())
        .select()
        .single();

    return TransactionModel.fromJson(inserted);
  }

  /// Step 4 of the workflow: patch the same row with the AI's critique text
  /// (and, from here on, its recorded sentiment — approved or disappointed —
  /// which is what powers the "AI verdict" percentage on analytics).
  Future<void> updateTransactionFeedback({
    required String transactionId,
    required String feedback,
    TransactionSentiment? sentiment,
  }) async {
    await _client
        .from('transactions')
        .update({
          'ai_feedback': feedback,
          if (sentiment != null) 'sentiment': sentiment.value,
        })
        .eq('id', transactionId);
  }

  /// Lets the user fix a transaction they entered wrong. Overwrites amount,
  /// category, type, and note; `ai_feedback` gets patched separately
  /// afterwards once the "you typed it wrong the first time" roast comes back.
  Future<TransactionModel> updateTransaction({
    required String transactionId,
    required double amount,
    required String category,
    required TransactionType type,
    String? note,
  }) async {
    final updated = await _client
        .from('transactions')
        .update({
          'amount': amount,
          'category': category,
          'type': type.value,
          'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
        })
        .eq('id', transactionId)
        .select()
        .single();

    return TransactionModel.fromJson(updated);
  }

  /// Permanently removes a transaction the user decided was a mistake.
  Future<void> deleteTransaction(String transactionId) async {
    await _client.from('transactions').delete().eq('id', transactionId);
  }

  /// Realtime stream of the transactions table, filtered to the current user.
  /// The dashboard listens on this so the AI's scolding appears the instant
  /// the `ai_feedback` column gets patched — no manual refresh needed.
  Stream<List<TransactionModel>> watchTransactions() {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('No authenticated user.');

    return _client
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('timestamp', ascending: false)
        .map((rows) => rows.map(TransactionModel.fromJson).toList());
  }

  // --------------------------------------------------------------------
  // SAVINGS GOALS
  // --------------------------------------------------------------------

  Future<List<SavingsGoal>> fetchGoals() async {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('No authenticated user.');

    final rows = await _client
        .from('goals')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);

    return (rows as List).map((r) => SavingsGoal.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<SavingsGoal> insertGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('No authenticated user.');

    final draft = SavingsGoal(
      id: '',
      userId: uid,
      name: name,
      targetAmount: targetAmount,
      targetDate: targetDate,
      createdAt: DateTime.now(),
    );

    final inserted = await _client.from('goals').insert(draft.toInsertJson()).select().single();
    return SavingsGoal.fromJson(inserted);
  }

  Future<void> deleteGoal(String goalId) async {
    await _client.from('goals').delete().eq('id', goalId);
  }

  // --------------------------------------------------------------------
  // CATEGORY BUDGETS
  // --------------------------------------------------------------------

  Future<List<CategoryBudget>> fetchCategoryBudgets() async {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('No authenticated user.');

    final rows = await _client.from('category_budgets').select().eq('user_id', uid);
    return (rows as List).map((r) => CategoryBudget.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// One row per (user, category) — `upsert` so re-saving an existing
  /// category's limit updates it instead of creating a duplicate. Requires
  /// a unique constraint on (user_id, category) — see the schema note.
  Future<void> upsertCategoryBudget({
    required String category,
    required double monthlyLimit,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('No authenticated user.');

    await _client
        .from('category_budgets')
        .upsert(
          CategoryBudget(id: '', userId: uid, category: category, monthlyLimit: monthlyLimit)
              .toUpsertJson(uid),
          onConflict: 'user_id,category',
        );
  }

  Future<void> deleteCategoryBudget(String categoryBudgetId) async {
    await _client.from('category_budgets').delete().eq('id', categoryBudgetId);
  }

  // --------------------------------------------------------------------
  // DATA EXPORT / ACCOUNT DELETION
  // --------------------------------------------------------------------

  /// Everything needed for a full data export — kept as one call so the
  /// export screen only needs a single loading state.
  Future<List<TransactionModel>> fetchAllDataForExport() => fetchTransactions();

  /// Deletes all of the signed-in user's app data (transactions, goals,
  /// category budgets, profile row) and signs them out.
  ///
  /// This does NOT delete the underlying Supabase Auth account/credentials —
  /// that requires the `service_role` key via the Admin API, which must
  /// never be embedded in a client app (it bypasses RLS entirely). Doing
  /// that safely needs a server-side piece (e.g. a Supabase Edge Function
  /// the client calls, which then uses the service role internally). What's
  /// implemented here is the part that's safe to do straight from the
  /// client: wipe every row that belongs to the user.
  Future<void> deleteAllUserData() async {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('No authenticated user.');

    await _client.from('transactions').delete().eq('user_id', uid);
    await _client.from('goals').delete().eq('user_id', uid);
    await _client.from('category_budgets').delete().eq('user_id', uid);
    await _client.from('users').delete().eq('id', uid);
    await signOut();
  }
}