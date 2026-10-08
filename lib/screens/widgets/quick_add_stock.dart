import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../db_helper.dart';
import '../../services/lang_service.dart';
import '../../services/qr_medicine_parser.dart';
import '../../services/gemini_service.dart';
import '../qr_scan_screen.dart';

/// Quick "Add Stock" dialog used inside billing screens (retail + wholesale).
/// Adds a new batch row for [name] WITHOUT leaving the bill.
/// Returns true if stock was saved, null/false otherwise.
class QuickAddStock {
  static Future<bool?> show(
    BuildContext context, {
    required String name,
    Map<String, dynamic>? prefill,
    int needQty = 0,
    int inStock = 0,
  }) {
    final p = prefill ?? {};
    final batchCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(
        text: needQty > 0 ? needQty.toString() : '');
    final ptrCtrl = TextEditingController(
        text: ((p['wholesale_price'] as num?)?.toDouble() ?? 0).toString());
    final rateCtrl = TextEditingController(
        text: ((p['price'] as num?)?.toDouble() ?? 0).toString());
    final mrpCtrl = TextEditingController(
        text: ((p['mrp'] as num?)?.toDouble() ?? 0).toString());
    final gstCtrl = TextEditingController(
        text: ((p['gst_percent'] as num?)?.toInt() ?? 0).toString());
    DateTime expiry = DateTime.now().add(const Duration(days: 730));

    Widget fld(TextEditingController c, String label,
        {bool isNum = false, bool isDec = false}) {
      return Expanded(
        child: TextField(
          controller: c,
          keyboardType: isNum
              ? TextInputType.number
               : isDec
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
          inputFormatters:
              isNum ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true),
        ),
      );
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Lang.t('as_title'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              Text(name.toUpperCase(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.teal)),
              Text(
                  '${Lang.t('as_instock')}: $inStock${needQty > 0 ? ' • ${Lang.t('as_need')}: $needQty' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final raw = await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const QrScanScreen()));
                        if (raw == null || raw.toString().trim().isEmpty) {
                          return;
                        }
                        final qr = QrMedicineParser.parse(raw.toString());
                        int n = 0;
                        bool aiUsed = false;
                        if (qr.batch.isNotEmpty) {
                          batchCtrl.text = qr.batch;
                          n++;
                        }
                        if (qr.mrp.isNotEmpty) {
                          mrpCtrl.text = qr.mrp;
                          n++;
                        }
                        if (qr.expiry.isNotEmpty) {
                          try {
                            final parts = qr.expiry.split('/');
                            final dt = DateTime(int.parse(parts[2]),
                                int.parse(parts[1]), int.parse(parts[0]));
                            setD(() => expiry = dt);
                            n++;
                          } catch (_) {}
                        }
                        if (n == 0) {
                          final ai = await GeminiService.tryQrWithLoader(
                              context, raw.toString());
                          if (ai != null) {
                            if (ai.batch.isNotEmpty) {
                              batchCtrl.text = ai.batch;
                              n++;
                            }
                            if (ai.mrp.isNotEmpty) {
                              mrpCtrl.text = ai.mrp;
                              n++;
                            }
                            if (ai.expiry.isNotEmpty) {
                              try {
                                final parts = ai.expiry.split('/');
                                final dt = DateTime(int.parse(parts[2]),
                                    int.parse(parts[1]),
                                    int.parse(parts[0]));
                                setD(() => expiry = dt);
                                n++;
                              } catch (_) {}
                            }
                            aiUsed = n > 0;
                          }
                        }
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(n > 0
                                ? Lang.t(aiUsed ? 'qr_ai' : 'qr_filled')
                                : Lang.t('qr_none')),
                            backgroundColor:
                                n > 0 ? Colors.green : Colors.orange));
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(Lang.t('qr_scan')),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  fld(batchCtrl, Lang.t('as_batch')),
                  const SizedBox(width: 8),
                  fld(qtyCtrl, Lang.t('as_qty'), isNum: true),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  fld(ptrCtrl, Lang.t('as_ptr'), isDec: true),
                  const SizedBox(width: 8),
                  fld(rateCtrl, Lang.t('as_rate'), isDec: true),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  fld(mrpCtrl, Lang.t('as_mrp'), isDec: true),
                  const SizedBox(width: 8),
                  fld(gstCtrl, Lang.t('as_gst'), isNum: true),
                ]),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                        context: ctx,
                        initialDate: expiry,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2040));
                    if (d != null) setD(() => expiry = d);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                        labelText: Lang.t('as_exp'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: const Icon(Icons.calendar_month, size: 20)),
                    child: Text(DateFormat('dd/MM/yyyy').format(expiry)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(Lang.t('cancel'))),
            ElevatedButton(
              onPressed: () async {
                final batch = batchCtrl.text.trim();
                final qty = int.tryParse(qtyCtrl.text) ?? 0;
                if (batch.isEmpty || qty <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(Lang.t('as_fill')),
                      backgroundColor: Colors.red));
                  return;
                }
                await DBHelper.addItem({
                  'name': name,
                  'chemical': (p['chemical'] ?? '').toString(),
                  'type': (p['type'] ?? '').toString(),
                  'batch': batch,
                  'rack': (p['rack'] ?? '').toString(),
                  'quantity': qty,
                  'price': double.tryParse(rateCtrl.text) ?? 0.0,
                  'wholesale_price':
                      double.tryParse(ptrCtrl.text) ?? 0.0,
                  'gst_percent': int.tryParse(gstCtrl.text) ?? 0,
                  'expiryDate': DateFormat('dd/MM/yyyy').format(expiry),
                  'min_stock': 10,
                  'barcode': '',
                });
                if (context.mounted) {
                  Navigator.pop(ctx, true);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(Lang.t('as_added')),
                      backgroundColor: Colors.green));
                }
              },
              child: Text(Lang.t('as_save')),
            ),
          ],
        ),
      ),
    );
  }
}
