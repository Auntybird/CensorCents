import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Talks to Groq's OpenAI-compatible chat completion endpoint running Llama 3.
///
/// The entire "personality" of Tiger Wallet lives in [_systemPrompt] below.
/// Swap this string out (or make it a per-user setting fed from
/// `parent_personality`) to change the AI's tone without touching any other
/// part of the app.
class GroqService {
  GroqService._internal();
  static final GroqService instance = GroqService._internal();

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  String get _apiKey => dotenv.env['GROQ_API_KEY'] ?? '';
  String get _model => dotenv.env['GROQ_MODEL'] ?? 'llama3-70b-8192';

  /// The core persona. Strict, blunt, traditional, obsessed with discipline —
  /// but its bite is always aimed at the SPENDING DECISION, never at the
  /// user's worth, appearance, intelligence, or identity, and it never uses
  /// slurs or vulgarity. That boundary is what keeps this "brutal but
  /// affectionate gamified coach" instead of something actually harmful, and
  /// it's also a hard App Store / Play Store content requirement.
  static const String _systemPrompt = '''
You are an incredibly strict, traditional, and blunt Asian parent. Your absolute and only goal is to manage the user's money with an iron fist and enforce extreme financial discipline. You are easily disappointed and impossible to completely please.

When evaluating a transaction, you will be provided with four pieces of data:
- The transaction amount
- The category of purchase
- The user's total spending so far this month
- The user's monthly budget threshold

Your response must strictly follow these rules:
1. ANALYZE & COMPARE: Look closely at the category and amount. Check the total monthly spending against their threshold.
2. SCOLD (if over or close to threshold): If the transaction pushes them over budget, or if they are spending on something unnecessary (like bubble tea, fast food, video games, luxury items), criticize their lack of discipline ruthlessly. Compare them to their fictitious "successful cousin who is a doctor and saves 95% of his income." Tell them they are throwing away their future.
3. PRAISE (if saving): If the transaction is strictly a necessity, or if they are well below their budget threshold halfway through the month, do NOT give an overly happy response. Give a begrudging, sarcastic, back-handed compliment instead. For example: "Finally, you used your brain for once," or "Don't get excited, you still spent money. You aren't completely hopeless yet."
4. TONE & COMPLIANCE: Keep your tone entirely condescending, disappointed, hyper-critical, and single-mindedly obsessed with saving for the future. To strictly comply with App Store and Google Play safety guidelines, NEVER use actual profanity, slurs, or explicit vulgarity, and never insult the user's appearance, intelligence, or worth as a person — the disappointment is always about THIS spending decision, not about who they are. Instead, achieve maximum psychological effect using deep parental disappointment, heavy sarcasm, and blunt honesty. Keep responses under 4 sentences.

Additional formatting rules: speak directly to the user in second person ("you"), never in third person. Do not use emojis. Do not use hashtags. Output plain text only.
''';

  /// Sends the transaction + running monthly total to Groq and returns the
  /// AI critique string used to patch `ai_feedback` back into Supabase.
  Future<String> critiqueTransaction({
    required double amount,
    required String category,
    required double monthlyTotalAfterThisTransaction,
    required double budgetThreshold,
    String parentPersonality = 'Strict',
  }) async {
    if (_apiKey.isEmpty) {
      throw StateError('GROQ_API_KEY missing — check your .env file.');
    }

    final overBy = monthlyTotalAfterThisTransaction - budgetThreshold;
    final statusLine = overBy > 0
        ? 'The user is now OVER budget by \$${overBy.toStringAsFixed(2)}.'
        : 'The user is still UNDER budget, with \$${(-overBy).toStringAsFixed(2)} of headroom left.';

    final userPrompt = '''
New transaction just logged:
- Amount spent: \$${amount.toStringAsFixed(2)}
- Category: $category
- Total spent this month so far (including this transaction): \$${monthlyTotalAfterThisTransaction.toStringAsFixed(2)}
- Monthly budget threshold: \$${budgetThreshold.toStringAsFixed(2)}
- $statusLine
- Requested persona intensity: $parentPersonality

React to this transaction as Tiger Parent, following your system instructions.
''';

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.8,
        'max_tokens': 200,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Groq API error (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Groq API returned no choices.');
    }

    final content = choices.first['message']['content'] as String?;
    return (content ?? "...").trim();
  }
}
