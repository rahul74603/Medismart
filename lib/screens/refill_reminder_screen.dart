import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db_helper.dart';
import '../services/lang_service.dart';
import '../services/whatsapp_helper.dart';
import 'package:intl/intl.dart';

/// BP/Sugar repeat-medicine reminders.
/// Data auto-tracked by DBHelper.saveBill into the `refills` table.
class RefillReminderScreen extends StatefulWidget {
  const RefillReminderScreen({super.key});

  @override
  State<RefillReminderScreen> createState() => _RefillReminderScreenState();
}

class _RefillReminderScreenState extends State<RefillReminderScreen> {
  List<Map<String, dynamic>> _all = [];
  String _q = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _all = await DBHelper.getAllRefills();
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _due {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _all.where((r) {
      final d = _nextDate(r);
      if (d == null) return false;
      if (_q.isNotEmpty) {
        final s = '${r['customer_name']} ${r['mobile']} ${r['item_name']}'.toLowerCase();
        if (!s.contains(_q.toLowerCase())) return false;
      }
      return !d.isAfter(today);
    }).toList()
        ..sort((a, b) => (_nextDate(a) ?? DateTime(2100)).compareTo(_nextDate(b) ?? DateTime(2100)));
  }

  List<Map<String, dynamic>> get _upcoming {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _all.where((r) {
      final d = _nextDate(r);
      if (d == null) return false;
      if (_q.isNotEmpty) {
        final s = '${r['customer_name']} ${r['mobile']} ${r['item_name']}'.toLowerCase();
        if (!s.contains(_q.toLowerCase())) return false;
      }
      return d.isAfter(today);
    }).toList()
        ..sort((a, b) => (_nextDate(a) ?? DateTime(2100)).compareTo(_nextDate(b) ?? DateTime(2100)));
  }

  DateTime? _nextDate(Map<String, dynamic> r) {
    try {
      return DateFormat('dd/MM/yyyy').parse((r['next_due'] ?? '').toString());
    } catch (_) {
      return null;
    }
  }

  String _dueLabel(Map<String, dynamic> r) {
    final d = _nextDate(r);
    if (d == null) return '-';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = d.difference(today).inDays;
    if (diff < 0) return '${-diff} ${Lang.t('rf_days_l')} ${Lang.t('rf_overdue')}';
    if (diff == 0) return Lang.t('rf_today');
    return '${Lang.t('rf_due_in')} $diff ${Lang.t('rf_days_l')}';
  }

  Future<void> _call(String mobile) async {
    final uri = Uri.parse('tel:$mobile');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsapp(Map<String, dynamic> r) async {
    final mob = (r['mobile'] ?? '').toString();
    final name = (r['customer_name'] ?? '').toString();
    final med = (r['item_name'] ?? '').toString();
    final msg = Lang.code == 'hi'
        ? '🙏 नमस्ते $name जी! आपकी दवाई *$med* खत्म होने वाली है। कृपया रिफिल के लिए दुकान पर आएं या जवाब दें।'
        : '🙏 Hello $name! Your medicine *$med* is due for refill. Please visit the shop or reply to order.';
    await WhatsAppHelper.sendCustomMessage(context, mob, msg);
  }

  Future<void> _markDone(Map<String, dynamic> r) async {
    await DBHelper.markRefillDone((r['id'] as num).toInt());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('done'))));
    _load();
  }

  Future<void> _editDays(Map<String, dynamic> r) async {
    final c = TextEditingController(text: '${r['days_supply'] ?? 30}');
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(Lang.t('rf_days')),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: Lang.t('rf_days_l')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(Lang.t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: Text(Lang.t('save'))),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    final days = int.tryParse(v);
    if (days == null || days <= 0) return;
    await DBHelper.updateRefillDays((r['id'] as num).toInt(), days);
    _load();
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(Lang.t('delete')),
        content: Text('${r['item_name']} (${r['customer_name']})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(Lang.t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(Lang.t('delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DBHelper.deleteRefill((r['id'] as num).toInt());
      _load();
    }
  }

  Widget _tile(Map<String, dynamic> r, bool overdue) {
    final mob = (r['mobile'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: overdue ? const Color(0xFFFEF2F2) : Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: overdue ? Colors.red : Colors.teal,
          child: Icon(overdue ? Icons.alarm : Icons.schedule, color: Colors.white),
        ),
        title: Text('${r['item_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${r['customer_name'] ?? ''} • $mob\n${_dueLabel(r)} • ${r['last_qty'] ?? ''} ${Lang.t('rf_days_l')}: ${r['days_supply']}'),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'call') _call(mob);
            if (v == 'wa') _whatsapp(r);
            if (v == 'done') _markDone(r);
            if (v == 'days') _editDays(r);
            if (v == 'del') _delete(r);
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'call', child: Text('📞 ${Lang.t('rf_call')}')),
            PopupMenuItem(value: 'wa', child: Text('💬 ${Lang.t('rf_wa')}')),
            PopupMenuItem(value: 'done', child: Text('✅ ${Lang.t('rf_done')}')),
            PopupMenuItem(value: 'days', child: Text('⏱ ${Lang.t('rf_days')}')),
            PopupMenuItem(value: 'del', child: Text('🗑 ${Lang.t('delete')}')),
          ],
        ),
        onTap: mob.isNotEmpty ? () => _whatsapp(r) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final due = _due;
    final up = _upcoming;
    return Scaffold(
      appBar: AppBar(title: Text(Lang.t('rf_title')), backgroundColor: const Color(0xFF0D9488)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim()),
                    decoration: InputDecoration(
                      hintText: Lang.t('rf_search'),
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Text('${Lang.t('rf_due')} (${due.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
                        ),
                        if (due.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(Lang.t('rf_no_due'), style: const TextStyle(color: Colors.grey)),
                          ),
                        ...due.map((r) => _tile(r, true)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('${Lang.t('rf_upcoming')} (${up.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal)),
                        ),
                        ...up.map((r) => _tile(r, false)),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
