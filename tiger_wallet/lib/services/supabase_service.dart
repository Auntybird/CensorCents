import 'package:supabase_flutter/supabase_flutter.dart';
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
    );

    final inserted = await _client
        .from('transactions')
        .insert(draft.toInsertJson())
        .select()
        .single();

    return TransactionModel.fromJson(inserted);
  }

  /// Step 4 of the workflow: patch the same row with the AI's critique text.
  Future<void> updateTransactionFeedback({
    required String transactionId,
    required String feedback,
  }) async {
    await _client
        .from('transactions')
        .update({'ai_feedback': feedback})
        .eq('id', transactionId);
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
}