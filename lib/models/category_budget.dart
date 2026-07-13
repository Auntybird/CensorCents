/// Maps to a row in `public.category_budgets` — a per-category spending cap
/// that layers on top of the single overall `budget_threshold`. One row per
/// (user, category); upserted rather than duplicated when edited.
class CategoryBudget {
  final String id;
  final String userId;
  final String category;
  final double monthlyLimit;

  const CategoryBudget({
    required this.id,
    required this.userId,
    required this.category,
    required this.monthlyLimit,
  });

  factory CategoryBudget.fromJson(Map<String, dynamic> json) {
    return CategoryBudget(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      category: json['category'] as String,
      monthlyLimit: _toDouble(json['monthly_limit']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  Map<String, dynamic> toUpsertJson(String userId) => {
        'user_id': userId,
        'category': category,
        'monthly_limit': monthlyLimit,
      };
}