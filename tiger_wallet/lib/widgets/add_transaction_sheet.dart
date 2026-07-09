import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../theme/app_theme.dart';

const List<String> kExpenseCategories = [
  'Food & Dining',
  'Shopping',
  'Entertainment',
  'Transport',
  'Bills & Utilities',
  'Groceries',
  'Other',
];

const List<String> kIncomeCategories = [
  'Salary',
  'Freelance',
  'Gift',
  'Investment',
  'Refund',
  'Other Income',
];

/// Modal form: type (income/expense) + amount + category. Doubles as both
/// "Add Transaction" and "Edit Transaction" — pass [existing] to pre-fill
/// the form and switch the copy/button to editing mode. On submit, returns
/// an (amount, category, type) triple via Navigator.pop, or null if
/// cancelled.
class AddTransactionSheet extends StatefulWidget {
  final TransactionModel? existing;

  const AddTransactionSheet({super.key, this.existing});

  static Future<(double, String, TransactionType)?> show(
    BuildContext context, {
    TransactionModel? existing,
  }) {
    return showModalBottomSheet<(double, String, TransactionType)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddTransactionSheet(existing: existing),
    );
  }

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;

  late TransactionType _type;
  late String _selectedCategory;

  bool get _isEditing => widget.existing != null;

  List<String> get _categoriesForType =>
      _type == TransactionType.expense ? kExpenseCategories : kIncomeCategories;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? TransactionType.expense;
    _amountController = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(2) : '',
    );
    // If we're editing and the existing category is still valid for this
    // type, keep it; otherwise fall back to the first option for the type.
    _selectedCategory = (existing != null && _categoriesForType.contains(existing.category))
        ? existing.category
        : _categoriesForType.first;
  }

  void _onTypeChanged(TransactionType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      // Reset category to the first valid option for the new type so we
      // never submit e.g. "Groceries" tagged as income.
      _selectedCategory = _categoriesForType.first;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountController.text);
    Navigator.of(context).pop((amount, _selectedCategory, _type));
  }

  @override
  Widget build(BuildContext context) {
    // Padding pushes the sheet above the on-screen keyboard.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final accent = _type == TransactionType.expense
        ? AppColors.overspendRed
        : AppColors.savingsGreen;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                _isEditing
                    ? 'Fix Your Mistake'
                    : (_type == TransactionType.expense
                        ? 'Confess Your Spending'
                        : 'Report Your Income'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (_isEditing) ...[
                const SizedBox(height: 4),
                const Text(
                  "She's going to hear about this one.",
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              // Expense / Income toggle.
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Expense'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Income'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) => _onTypeChanged(selection.first),
                style: SegmentedButton.styleFrom(
                  backgroundColor: AppColors.surfaceElevated,
                  foregroundColor: AppColors.textSecondary,
                  selectedForegroundColor: Colors.black,
                  selectedBackgroundColor: accent,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Amount (\$)',
                  prefixIcon: Icon(Icons.attach_money, color: AppColors.textSecondary),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter an amount';
                  }
                  final parsed = double.tryParse(value);
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid positive number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                dropdownColor: AppColors.surfaceElevated,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.category_outlined, color: AppColors.textSecondary),
                ),
                items: _categoriesForType
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedCategory = value);
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(
                    _isEditing
                        ? 'Save Changes'
                        : (_type == TransactionType.expense ? 'Submit' : 'Add Income'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}