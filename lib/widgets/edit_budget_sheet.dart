import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

const List<String> kParentPersonalities = [
  'Strict',
  'Skeptical',
  'Passive-Aggressive',
];

/// Lets the user edit their monthly budget ceiling and AI persona intensity.
/// Returns an (budgetThreshold, parentPersonality) pair via Navigator.pop,
/// or null if the user cancels.
class EditBudgetSheet extends StatefulWidget {
  final double currentThreshold;
  final String currentPersonality;

  const EditBudgetSheet({
    super.key,
    required this.currentThreshold,
    required this.currentPersonality,
  });

  static Future<(double, String)?> show(
    BuildContext context, {
    required double currentThreshold,
    required String currentPersonality,
  }) {
    return showModalBottomSheet<(double, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EditBudgetSheet(
        currentThreshold: currentThreshold,
        currentPersonality: currentPersonality,
      ),
    );
  }

  @override
  State<EditBudgetSheet> createState() => _EditBudgetSheetState();
}

class _EditBudgetSheetState extends State<EditBudgetSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _thresholdController;
  late String _selectedPersonality;

  @override
  void initState() {
    super.initState();
    _thresholdController = TextEditingController(
      text: widget.currentThreshold > 0
          ? widget.currentThreshold.toStringAsFixed(2)
          : '',
    );
    _selectedPersonality = kParentPersonalities.contains(widget.currentPersonality)
        ? widget.currentPersonality
        : kParentPersonalities.first;
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final threshold = double.parse(_thresholdController.text);
    Navigator.of(context).pop((threshold, _selectedPersonality));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

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
                'Set Your Budget',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                "Change this and she'll judge you against a new number.",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _thresholdController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Monthly Budget Threshold (\$)',
                  prefixIcon: Icon(Icons.savings_outlined, color: AppColors.textSecondary),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a budget amount';
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
                initialValue: _selectedPersonality,
                dropdownColor: AppColors.surfaceElevated,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Persona Intensity',
                  prefixIcon: Icon(Icons.psychology_alt_outlined, color: AppColors.textSecondary),
                ),
                items: kParentPersonalities
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedPersonality = value);
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Save Budget'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}