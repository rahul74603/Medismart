import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db_helper.dart';
import '../services/lang_service.dart';
import 'package:intl/intl.dart';

/// Daily cash summary (Day Close) + expense tracker (kharcha).
class DayCloseScreen extends StatefulWidget {
  const DayCloseScreen({super.key});

  @override
  State<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends State<DayCloseScreen> {
  Map<String, dynamic> _sum = {};
  List<Map<String, dynamic>> _expenses = [];
  bool _loading = true;

  final List<String> _cats = ['exp_chai', 'exp_light', 'exp_salary', 'exp_rent', 'exp_transport', 'exp_mobile', 'exp_other'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _sum = await DBHelper.getDaySummary(DateTime.now());
    _expenses = await DBHelper.getTodayExpenses();
    if (mounted) setState(() => _loading = false);
  }

  double get _cashIn {
    double v = 0;
    for (final k in ['Cash', 'UPI']) {
      v += ((_sum[k] as num?)?.toDouble()) ?? 0.0;
    }
    return v;
  }

  double get _udhaar => ((_sum['Udhaar'] as num?)?.toDouble()) ?? 0.0;
  double get _profit => ((_sum['profit'] as num?)?.toDouble()) ?? 0.0;
  double get _purchase => ((_sum['purchase'] as num?)?.toDouble()) ?? 0.0;
  double get _expenseTotal => _expenses.fold(0.0, (s, e) => s + (((e['amount'] as num?)?.toDouble()) ?? 0.0));
  double get _refunds => ((_sum['refunds'] as num?)?.toDouble()) ?? 0.0;
  double get _collection => ((_sum['collection'] as num?)?.toDouble()) ?? 0.0;
  double get _net => _cashIn + _collection - _purchase - _expenseTotal - _refunds;

  Future<void> _addExpense() async {
    final amtC = TextEditingController();
    final noteC = TextEditingController();
    String cat = _cats[0];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(Lang.t('dc_add_exp')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: cat,
                items: _cats.map((c) => DropdownMenuItem(value: c, child: Text(Lang.t(c)))).toList(),
                onChanged: (v) => setS(() => cat = v ?? _cats[0]),
                decoration: InputDecoration(labelText: Lang.t('dc_cat')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amtC,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: Lang.t('dc_amount')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteC,
                decoration: InputDecoration(labelText: Lang.t('dc_note')),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(Lang.t('cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(Lang.t('save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(amtC.text.trim()) ?? 0;
    if (amt <= 0) return;
    await DBHelper.addExpense({
      'date': DateFormat('dd/MM/yyyy').format(DateTime.now()),
      'category': Lang.t(cat),
      'amount': amt,
      'note': noteC.text.trim(),
    });
    _load();
  }

  Future<void> _delExpense(int id) async {
    await DBHelper.deleteExpense(id);
    _load();
  }

  Future<void> _share() async {
    final p = await SharedPreferences.getInstance();
    final shop = p.getString('shop_name') ?? 'MediSmart';
    final d = DateTime.now();
    final ds = '${d.day}/${d.month}/${d.year}';
    final hi = Lang.code == 'hi';
    final text = hi
        ? '📊 *$shop*\nदिन का हिसाब — $ds\n\n💰 बिक्री वसूली: ₹${_cashIn.toStringAsFixed(0)}\n💵 उधार वसूली: ₹${_collection.toStringAsFixed(0)}\n📒 उधार दिया: ₹${_udhaar.toStringAsFixed(0)}\n🛒 खरीद में दिया: ₹${_purchase.toStringAsFixed(0)}\n🧾 खर्चे: ₹${_expenseTotal.toStringAsFixed(0)}\n↩️ वापसी: ₹${_refunds.toStringAsFixed(0)}\n\n✅ *हाथ में नकद: ₹${_net.toStringAsFixed(0)}*\n📈 मुनाफ़ा: ₹${_profit.toStringAsFixed(0)}'
        : '📊 *$shop*\nDay Close — $ds\n\n💰 Sale collected: ₹${_cashIn.toStringAsFixed(0)}\n💵 Udhaar collected: ₹${_collection.toStringAsFixed(0)}\n📒 Udhaar given: ₹${_udhaar.toStringAsFixed(0)}\n🛒 Purchase paid: ₹${_purchase.toStringAsFixed(0)}\n🧾 Expenses: ₹${_expenseTotal.toStringAsFixed(0)}\n↩️ Refunds: ₹${_refunds.toStringAsFixed(0)}\n\n✅ *Net cash in hand: ₹${_net.toStringAsFixed(0)}*\n📈 Profit: ₹${_profit.toStringAsFixed(0)}';
    await Share.share(text);
  }

  Widget _row(String label, double v, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color)),
          Text('₹${v.toStringAsFixed(0)}',
              style: TextStyle(fontSize: bold ? 19 : 15, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Lang.t('dc_title')),
        backgroundColor: const Color(0xFF0F766E),
        actions: [IconButton(icon: const Icon(Icons.share), tooltip: Lang.t('share'), onPressed: _share)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  Card(
                    margin: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _row('💰 ${Lang.t('dc_sale')}', _cashIn, color: Colors.green.shade800),
                        _row('📒 ${Lang.t('dc_udhaar')}', _udhaar, color: Colors.orange.shade800),
                        _row('🛒 ${Lang.t('dc_purchase')}', _purchase, color: Colors.brown),
                        _row('🧾 ${Lang.t('dc_expense')}', _expenseTotal, color: Colors.red.shade700),
                        _row('💵 ${Lang.t('dc_collect')}', _collection, color: Colors.green.shade800),
                        _row('↩️ ${Lang.t('dc_returns')}', _refunds, color: Colors.red.shade700),
                        const Divider(),
                        _row('✅ ${Lang.t('dc_net')}', _net, bold: true, color: _net >= 0 ? Colors.green.shade800 : Colors.red),
                        _row('📈 ${Lang.t('profit')}', _profit, color: Colors.teal.shade800),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${Lang.t('dc_expenses')} (${_expenses.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        TextButton.icon(
                          onPressed: _addExpense,
                          icon: const Icon(Icons.add),
                          label: Text(Lang.t('dc_add_exp')),
                        ),
                      ],
                    ),
                  ),
                  if (_expenses.isEmpty)
                    Padding(padding: const EdgeInsets.all(16), child: Text(Lang.t('dc_no_exp'), style: const TextStyle(color: Colors.grey))),
                  ..._expenses.map((e) => ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.receipt)),
                        title: Text('${e['category']}'),
                        subtitle: Text('${e['note'] ?? ''}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('₹${((e['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _delExpense((e['id'] as num).toInt()),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _share,
        icon: const Icon(Icons.share),
        label: Text(Lang.t('dc_share')),
        backgroundColor: const Color(0xFF0F766E),
      ),
    );
  }
}
