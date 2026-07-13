/// Maps to a row in `public.goals`. Progress isn't stored directly — it's
/// derived by WalletController from the user's net balance (income minus
/// expense) accumulated since the goal was created, so there's no separate
/// "contribute to goal" flow to build or maintain.
class SavingsGoal {
  final String id;
  final String userId;
  final String name;
  final double targetAmount;
  final DateTime? targetDate;
  final DateTime createdAt;

  const SavingsGoal({
    required this.id,
    required this.userId,
    required this.name,
    required this.targetAmount,
    this.targetDate,
    required this.createdAt,
  });

  factory SavingsGoal.fromJson(Map<String, dynamic> json) {
    return SavingsGoal(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      targetAmount: _toDouble(json['target_amount']),
      targetDate: json['target_date'] == null ? null : DateTime.parse(json['target_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  Map<String, dynamic> toInsertJson() => {
        'user_id': userId,
        'name': name,
        'target_amount': targetAmount,
        'target_date': targetDate?.toIso8601String(),
      };
}