import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/category_budget.dart';
import '../services/wallet_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/add_transaction_sheet.dart'; // for kExpenseCategories

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _exporting = false;

  Future<void> _exportData() async {
    setState(() => _exporting = true);
    try {
      final controller = context.read<WalletController>();
      final transactions = await controller.exportData();

      final buffer = StringBuffer('date,type,category,amount,note,ai_feedback\n');
      for (final tx in transactions) {
        String csvEscape(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
        buffer.writeln(
          '${tx.timestamp.toIso8601String()},${tx.type.value},${csvEscape(tx.category)},'
          '${tx.amount},${csvEscape(tx.note)},${csvEscape(tx.aiFeedback)}',
        );
      }

      // Write to a real file, then hand it to the OS share sheet — this is
      // what actually triggers a "save / send / open in..." prompt, unlike
      // just showing the text in a dialog.
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${dir.path}/censorcents_export_$timestamp.csv');
      await file.writeAsString(buffer.toString());

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'CensorCents transaction export',
          text: 'Your CensorCents transaction export.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Delete all your data?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This permanently deletes every transaction, goal, and budget you have, and signs you out. '
          'This cannot be undone.\n\n'
          'Note: this removes your app data but not your login credentials — contact support if you '
          'also want your account itself removed.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Everything', style: TextStyle(color: AppColors.overspendRed)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await context.read<WalletController>().deleteAccount();
    }
  }

  Future<void> _openCategoryBudgetSheet(WalletController controller, {CategoryBudget? existing}) async {
    final limitController = TextEditingController(
      text: existing != null ? existing.monthlyLimit.toStringAsFixed(2) : '',
    );
    String selectedCategory = existing?.category ?? kExpenseCategories.first;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Category Budget', style: Theme.of(ctx).textTheme.headlineMedium),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                dropdownColor: AppColors.surfaceElevated,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Category'),
                items: kExpenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: existing != null
                    ? null // don't let editing an existing cap change which category it applies to
                    : (v) {
                        if (v != null) setSheetState(() => selectedCategory = v);
                      },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: limitController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Monthly limit (\$)'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      final limit = double.tryParse(limitController.text);
      if (limit != null && limit > 0) {
        await controller.saveCategoryBudget(category: selectedCategory, monthlyLimit: limit);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WalletController>(
      builder: (context, controller, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Category Budgets', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              const Text(
                'Optional per-category caps on top of your overall monthly budget.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (controller.categoryBudgets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No category budgets set.', style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                ...controller.categoryBudgets.map((b) => Card(
                      child: ListTile(
                        title: Text(b.category, style: const TextStyle(color: AppColors.textPrimary)),
                        subtitle: Text(
                          '\$${b.monthlyLimit.toStringAsFixed(2)} / month',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                              onPressed: () => _openCategoryBudgetSheet(controller, existing: b),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.overspendRed),
                              onPressed: () => controller.removeCategoryBudget(b),
                            ),
                          ],
                        ),
                      ),
                    )),
              OutlinedButton.icon(
                onPressed: () => _openCategoryBudgetSheet(controller),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Category Budget'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.savingsGreen,
                  side: const BorderSide(color: AppColors.savingsGreen),
                ),
              ),
              const SizedBox(height: 32),
              Text('Your Data', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _exporting ? null : _exportData,
                icon: _exporting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: const Text('Export My Data (CSV)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.surfaceElevated),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _confirmDeleteAccount,
                icon: const Icon(Icons.delete_forever_outlined, size: 18, color: AppColors.overspendRed),
                label: const Text('Delete My Data', style: TextStyle(color: AppColors.overspendRed)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.overspendRed),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }
}