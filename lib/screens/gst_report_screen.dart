import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../db_helper.dart';
import '../services/lang_service.dart';

/// Month-wise GST summary + slab-wise breakup + CA-ready CSV share.
/// NOTE: wholesale (GST) bills are B2B if a GSTIN was captured on the bill,
/// else counted under B2C. Sales numbers come from gst_percent on bill_items.
class GstReportScreen extends StatefulWidget {
  const GstReportScreen({super.key});

  @override
  State<GstReportScreen> createState() => _GstReportScreenState();
}

class _GstReportScreenState extends State<GstReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic> _gst = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _gst = await DBHelper.getMonthGst(_month.year, _month.month);
    if (mounted) setState(() => _loading = false);
  }

  void _shift(int d) {
    setState(() => _month = DateTime(_month.year, _month.month + d));
    _load();
  }

  String get _monthLabel {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[_month.month - 1]} ${_month.year}';
  }

  List<Map<String, dynamic>> get _oslabs => List<Map<String, dynamic>>.from(_gst['out_slabs'] ?? []);
  List<Map<String, dynamic>> get _islabs => List<Map<String, dynamic>>.from(_gst['in_slabs'] ?? []);

  double get _oTax => _oslabs.fold(0.0, (s, e) => s + (((e['tax'] as num?)?.toDouble()) ?? 0.0));
  double get _oVal => _oslabs.fold(0.0, (s, e) => s + (((e['taxable'] as num?)?.toDouble()) ?? 0.0));
  double get _iTax => _islabs.fold(0.0, (s, e) => s + (((e['tax'] as num?)?.toDouble()) ?? 0.0));
  double get _iVal => _islabs.fold(0.0, (s, e) => s + (((e['taxable'] as num?)?.toDouble()) ?? 0.0));

  Future<void> _shareCsv() async {
    final sb = StringBuffer();
    sb.writeln('GSTR Summary,$_monthLabel');
    sb.writeln('Section,GST %,Taxable Value,Tax Amount');
    for (final s in _oslabs) {
      sb.writeln('Outward (Sales),${s['rate']},${(s['taxable'] as num).toStringAsFixed(2)},${(s['tax'] as num).toStringAsFixed(2)}');
    }
    for (final s in _islabs) {
      sb.writeln('Inward (Purchase ITC),${s['rate']},${(s['taxable'] as num).toStringAsFixed(2)},${(s['tax'] as num).toStringAsFixed(2)}');
    }
    sb.writeln('Total Outward Tax,,${_oVal.toStringAsFixed(2)},${_oTax.toStringAsFixed(2)}');
    sb.writeln('Total Inward ITC,,${_iVal.toStringAsFixed(2)},${_iTax.toStringAsFixed(2)}');
    sb.writeln('Net GST Payable,,,${(_oTax - _iTax).toStringAsFixed(2)}');
    sb.writeln('B2B Invoices (with GSTIN),,,${_gst['b2b_count'] ?? 0}');
    sb.writeln('B2C Invoices,,,${_gst['b2c_count'] ?? 0}');
    await Share.share(sb.toString(), subject: 'GSTR $_monthLabel');
  }

  Widget _slabCard(String title, List<Map<String, dynamic>> slabs, double totVal, double totTax, Color color) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(Lang.t('gst_rate'), style: const TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text(Lang.t('gst_taxable'), style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                Expanded(child: Text(Lang.t('gst_tax'), style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
              ],
            ),
            const Divider(),
            if (slabs.isEmpty) const Text('-', style: TextStyle(color: Colors.grey)),
            ...slabs.map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text('${s['rate']}%')),
                      Expanded(
                          child: Text('₹${((s['taxable'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                              textAlign: TextAlign.right)),
                      Expanded(
                          child: Text('₹${((s['tax'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', textAlign: TextAlign.right)),
                    ],
                  ),
                )),
            const Divider(),
            Row(
              children: [
                const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('₹${totVal.toStringAsFixed(0)}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('₹${totTax.toStringAsFixed(0)}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Lang.t('gst_title')),
        backgroundColor: const Color(0xFFB45309),
        actions: [IconButton(icon: const Icon(Icons.share), tooltip: Lang.t('share'), onPressed: _shareCsv)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(icon: const Icon(Icons.chevron_left, size: 32), onPressed: () => _shift(-1)),
                      Text(_monthLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.chevron_right, size: 32), onPressed: () => _shift(1)),
                    ],
                  ),
                ),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: const Color(0xFFFFFBEB),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(Lang.t('gst_out')),
                          Text('₹${_oTax.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(Lang.t('gst_in')),
                          Text('₹${_iTax.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                        const Divider(),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(Lang.t('gst_payable'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('₹${(_oTax - _iTax).toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red)),
                        ]),
                        const SizedBox(height: 4),
                        Text('${Lang.t('gst_b2b')}: ${_gst['b2b_count'] ?? 0} • ${Lang.t('gst_b2c')}: ${_gst['b2c_count'] ?? 0}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
                _slabCard(Lang.t('gst_outward'), _oslabs, _oVal, _oTax, Colors.green.shade800),
                _slabCard(Lang.t('gst_inward'), _islabs, _iVal, _iTax, Colors.blue.shade800),
                const SizedBox(height: 16),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _shareCsv,
        icon: const Icon(Icons.share),
        label: Text(Lang.t('gst_share')),
        backgroundColor: const Color(0xFFB45309),
      ),
    );
  }
}
