/// Whether a row represents money leaving the account (expense) or coming
/// in (income). Stored in Postgres as plain text ('expense' | 'income') so
/// it round-trips as a String — see `type` in the `transactions` table.
enum TransactionType {
  expense,
  income;

  String get value => name;

  static TransactionType fromValue(String? raw) {
    switch (raw) {
      case 'income':
        return TransactionType.income;
      case 'expense':
      default:
        return TransactionType.expense;
    }
  }
}

/// Maps directly to a row in `public.transactions`.
///
/// `aiFeedback` starts null (row just inserted) and is patched in later once
/// the Groq critique comes back — the UI listens for that patch via Realtime.
///
/// `type` distinguishes spending from income. Income rows still get an AI
/// critique (a much friendlier one), but are excluded from the "monthly
/// spend vs budget_threshold" math.
class TransactionModel {
  final String id;
  final String userId;
  final double amount;
  final String category;
  final DateTime timestamp;
  final String? aiFeedback;
  final TransactionType type;

  const TransactionModel({
    required this.id,
    required this.userId,
    required this.amount,
    required this.category,
    required this.timestamp,
    this.aiFeedback,
    this.type = TransactionType.expense,
  });

  bool get isIncome => type == TransactionType.income;
  bool get isExpense => type == TransactionType.expense;

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      amount: _toDouble(json['amount']),
      category: json['category'] as String? ?? 'Uncategorized',
      timestamp: DateTime.parse(json['timestamp'] as String),
      aiFeedback: json['ai_feedback'] as String?,
      // Older rows inserted before this column existed will come back null,
      // which fromValue() safely treats as an expense.
      type: TransactionType.fromValue(json['type'] as String?),
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  /// Payload used when creating a brand-new transaction (no id/feedback yet —
  /// id is generated server-side, feedback is patched in after the AI call).
  Map<String, dynamic> toInsertJson() => {
        'user_id': userId,
        'amount': amount,
        'category': category,
        'timestamp': timestamp.toIso8601String(),
        'type': type.value,
      };

  TransactionModel copyWith({String? aiFeedback, TransactionType? type}) {
    return TransactionModel(
      id: id,
      userId: userId,
      amount: amount,
      category: category,
      timestamp: timestamp,
      aiFeedback: aiFeedback ?? this.aiFeedback,
      type: type ?? this.type,
    );
  }
}