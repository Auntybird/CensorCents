/// Maps directly to a row in `public.transactions`.
///
/// `aiFeedback` starts null (row just inserted) and is patched in later once
/// the Groq critique comes back — the UI listens for that patch via Realtime.
class TransactionModel {
  final String id;
  final String userId;
  final double amount;
  final String category;
  final DateTime timestamp;
  final String? aiFeedback;

  const TransactionModel({
    required this.id,
    required this.userId,
    required this.amount,
    required this.category,
    required this.timestamp,
    this.aiFeedback,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      amount: _toDouble(json['amount']),
      category: json['category'] as String? ?? 'Uncategorized',
      timestamp: DateTime.parse(json['timestamp'] as String),
      aiFeedback: json['ai_feedback'] as String?,
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
      };

  TransactionModel copyWith({String? aiFeedback}) {
    return TransactionModel(
      id: id,
      userId: userId,
      amount: amount,
      category: category,
      timestamp: timestamp,
      aiFeedback: aiFeedback ?? this.aiFeedback,
    );
  }
}
