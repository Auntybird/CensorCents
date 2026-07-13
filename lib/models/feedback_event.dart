import 'transaction_model.dart';

/// Emitted by WalletController whenever a fresh AI response should be popped
/// up for the user to see — either the original critique right after
/// submitting a transaction, or a correction roast after editing/deleting
/// one. Driving the popup off explicit events like this (rather than diffing
/// the transaction list on every rebuild) means it only ever fires once per
/// real action, regardless of how many times the UI rebuilds for unrelated
/// reasons (like swiping between pages).
class FeedbackEvent {
  final String message;
  final String category;
  final double amount;
  final TransactionType type;
  final String? note;

  /// True for edit/delete roasts, false for the original post-submit critique.
  final bool isCorrection;

  const FeedbackEvent({
    required this.message,
    required this.category,
    required this.amount,
    required this.type,
    this.note,
    this.isCorrection = false,
  });
}