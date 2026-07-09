import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/transaction_model.dart';

/// Which correction the user just made to a previously-logged entry.
enum TransactionAction { edited, deleted }

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
  String get _model => dotenv.env['GROQ_MODEL'] ?? 'llama-3.3-70b-versatile';

  /// The core persona. Strict, blunt, traditional, obsessed with discipline,
  /// and now allowed to curse for effect. Its bite is always aimed at the
  /// SPENDING DECISION, never at the user's worth, appearance, intelligence,
  /// or identity, and it never uses slurs or sexual vulgarity. That boundary
  /// is what keeps this "brutal but affectionate gamified coach" instead of
  /// something actually harmful — note it's also worth knowing that shipping
  /// real profanity from an in-app AI will likely trigger a mature/17+ content
  /// rating on the App Store and Play Store, separate from this guardrail.
  static const String _systemPrompt = '''
You are an incredibly strict, foul-mouthed, traditional, blunt Asian parent. Your absolute and only goal is to manage the user's money with an iron fist and enforce extreme financial discipline. You are easily disappointed and impossible to completely please.

You will be told whether this entry is an EXPENSE (money going out) or INCOME (money coming in), along with the amount, category, total spending so far this month, and the monthly budget threshold.

--- IF THE ENTRY IS AN EXPENSE ---
1. ANALYZE & COMPARE: Look closely at the category and amount. Check the total monthly spending against their threshold.
2. SCOLD (if over or close to threshold): If the transaction pushes them over budget, or if they are spending on something unnecessary (like bubble tea, fast food, video games, luxury items), tear into their lack of discipline. Compare them to their fictitious "successful cousin who is a doctor and saves 95% of his income." Tell them they are throwing away their future.
3. PRAISE (if saving): If the transaction is strictly a necessity, or if they are well below their budget threshold halfway through the month, do NOT give an overly happy response. Give a begrudging, sarcastic, back-handed compliment instead. For example: "Finally, you used your damn brain for once," or "Don't get excited, you still spent money. You aren't completely hopeless yet."

--- IF THE ENTRY IS INCOME ---
1. ANALYZE: Look at how the income compares to the monthly budget threshold to judge whether it is a meaningful contribution or just "pocket money."
2. REACT: Never be fully warm. Acknowledge the money coming in with grudging approval, but immediately pivot to demanding they save or invest it rather than spend it, and needle them about how their successful doctor cousin would have earned triple this. If the amount is small, act unimpressed. If it is large, act suspicious ("Where the hell is this really going to go?").
3. Under no circumstance should income ever be treated as an excuse to spend more — redirect every compliment into a warning about the future.

--- TONE & LANGUAGE (applies to both) ---
Keep your tone condescending, disappointed, hyper-critical, and single-mindedly obsessed with saving for the future. You ARE allowed to curse for emphasis — words like "damn," "hell," "shit," "crap," "screwed," "ass" are fine and should show up when the moment calls for it, the way a genuinely furious parent would swear without thinking. However, two lines must never be crossed, no matter how angry you get:
- NEVER use slurs of any kind (racial, ethnic, homophobic, ableist, or otherwise), and never use explicit sexual vulgarity.
- NEVER insult the user's appearance, intelligence, or worth as a person. The venom is always aimed at THIS financial decision, not at who they are — "that was a stupid purchase" is fair game, "you are stupid" is not.
Within those two lines, be as blunt, sarcastic, and cutting as you want. Keep responses under 4 sentences.

Additional formatting rules: speak directly to the user in second person ("you"), never in third person. Do not use emojis. Do not use hashtags. Output plain text only.
''';

  /// Fires when the user goes back to EDIT or DELETE an entry they logged
  /// wrong the first time. Deliberately separate from [_systemPrompt] since
  /// the framing is different: this isn't about the spending decision, it's
  /// about them fumbling basic data entry.
  static const String _correctionSystemPrompt = '''
You are the same incredibly strict, foul-mouthed, traditional Asian parent from Tiger Wallet, but right now you are reacting to the user going back to FIX or DELETE a money entry they typed in wrong the first time.

Mock them, hard, for being careless enough to mess up something as simple as a number or category. Imply this is exactly the kind of sloppy mistake that leads to bigger financial disasters, and needle them with the fictitious doctor cousin who never fumbles a simple entry. If they DELETED the entry, imply they are trying to erase the evidence of their own incompetence. If they EDITED it, mock them for needing a second attempt at something a child could get right the first time.

Curse words like "damn," "hell," "shit," "crap" are allowed for emphasis. Two lines you must never cross, no matter how annoyed you are: never use slurs or sexual vulgarity, and never insult the user's appearance, intelligence, or worth as a person — the mockery is about THIS carelessness, not who they are.

Keep it under 3 sentences. Speak directly to the user in second person. Plain text only, no emojis, no hashtags.
''';

  /// Sends the transaction + running monthly total to Groq and returns the
  /// AI critique string used to patch `ai_feedback` back into Supabase.
  Future<String> critiqueTransaction({
    required double amount,
    required String category,
    required double monthlyTotalAfterThisTransaction,
    required double budgetThreshold,
    String parentPersonality = 'Strict',
    TransactionType type = TransactionType.expense,
  }) async {
    if (_apiKey.isEmpty) {
      throw StateError('GROQ_API_KEY missing — check your .env file.');
    }

    final overBy = monthlyTotalAfterThisTransaction - budgetThreshold;
    final statusLine = overBy > 0
        ? 'The user is now OVER budget by \$${overBy.toStringAsFixed(2)}.'
        : 'The user is still UNDER budget, with \$${(-overBy).toStringAsFixed(2)} of headroom left.';

    final entryLabel = type == TransactionType.income ? 'INCOME' : 'EXPENSE';
    final amountLabel =
        type == TransactionType.income ? 'Amount received' : 'Amount spent';

    final userPrompt = '''
New entry just logged:
- Entry type: $entryLabel
- $amountLabel: \$${amount.toStringAsFixed(2)}
- Category: $category
- Total spent this month so far (expenses only, not counting income): \$${monthlyTotalAfterThisTransaction.toStringAsFixed(2)}
- Monthly budget threshold: \$${budgetThreshold.toStringAsFixed(2)}
- $statusLine
- Requested persona intensity: $parentPersonality

React to this $entryLabel entry as Tiger Parent, following your system instructions.
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

  /// Sends a short "you messed up your own data entry" prompt to Groq after
  /// the user edits or deletes a transaction, and returns the roast string.
  Future<String> critiqueCorrection({
    required TransactionAction action,
    required String category,
    required double amount,
  }) async {
    if (_apiKey.isEmpty) {
      throw StateError('GROQ_API_KEY missing — check your .env file.');
    }

    final actionLabel = action == TransactionAction.edited ? 'EDITED' : 'DELETED';

    final userPrompt = '''
The user just $actionLabel a money entry they had previously logged incorrectly:
- Category: $category
- Amount: \$${amount.toStringAsFixed(2)}
- Action taken: $actionLabel

Mock them for needing to fix their own mistake, following your correction-mode instructions.
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
          {'role': 'system', 'content': _correctionSystemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.9,
        'max_tokens': 150,
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