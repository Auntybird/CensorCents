import 'transaction_model.dart';

/// One calendar month's worth of activity — feeds the monthly overview
/// chart and the month-by-month drill-down on the analytics dashboard.
/// Built client-side from the full transaction history already held by
/// WalletController (no extra Supabase round-trips needed), the same way
/// other budgeting apps group a running ledger by month.
class MonthSummary {
  /// First day of the month, local time — use this as the stable key/id.
  final DateTime month;
  final double income;
  final double expense;

  /// This month's transactions, most recent first.
  final List<TransactionModel> transactions;

  const MonthSummary({
    required this.month,
    required this.income,
    required this.expense,
    required this.transactions,
  });

  double get net => income - expense;
  int get transactionCount => transactions.length;

  /// True if [other] falls in the same calendar month/year as this summary.
  bool matches(DateTime other) =>
      other.year == month.year && other.month == month.month;
}