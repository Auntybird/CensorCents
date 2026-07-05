/// Maps directly to a row in `public.users`.
///
/// This holds the user's configurable "how strict should the AI be" settings.
class UserProfile {
  final String id; // matches auth.users.id
  final double budgetThreshold; // monthly spending ceiling before the AI gets angry
  final String parentPersonality; // 'Strict' | 'Skeptical' | 'Passive-Aggressive'

  const UserProfile({
    required this.id,
    required this.budgetThreshold,
    required this.parentPersonality,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      // Supabase numeric columns can arrive as String or num depending on driver
      // version, so we defensively parse either.
      budgetThreshold: _toDouble(json['budget_threshold']),
      parentPersonality: json['parent_personality'] as String? ?? 'Strict',
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'budget_threshold': budgetThreshold,
        'parent_personality': parentPersonality,
      };
}
