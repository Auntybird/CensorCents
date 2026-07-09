import 'package:flutter_test/flutter_test.dart';
import 'package:CensorCents/models/transaction_model.dart';
import 'package:CensorCents/services/wallet_controller.dart';

void main() {
  test('WalletController starts with an empty, idle state', () {
    final controller = WalletController();

    expect(controller.isLoading, isFalse);
    expect(controller.isSubmitting, isFalse);
    expect(controller.profile, isNull);
    expect(controller.transactions, isEmpty);
    expect(controller.errorMessage, isNull);
  });

  test('WalletController exposes analytics helpers for the dashboard', () {
    final controller = WalletController(
      initialTransactions: [
        TransactionModel(
          id: '1',
          userId: 'u1',
          amount: 40,
          category: 'Food',
          timestamp: DateTime.now(),
          type: TransactionType.expense,
        ),
        TransactionModel(
          id: '2',
          userId: 'u1',
          amount: 20,
          category: 'Food',
          timestamp: DateTime.now(),
          type: TransactionType.expense,
        ),
        TransactionModel(
          id: '3',
          userId: 'u1',
          amount: 100,
          category: 'Paycheck',
          timestamp: DateTime.now(),
          type: TransactionType.income,
        ),
      ],
    );

    expect(controller.expenseByCategoryThisMonth['Food'], 60.0);
    expect(controller.dailyNetTrend(days: 3).length, 3);
  });
}
