import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import '../services/receipt_helper.dart';

/// SALES RETURN ENTRY - customer se dawai wapas lena.
/// Stock restores to the SAME batch. Refund = Cash or Udhaar adjust.
class SalesReturnScreen extends StatefulWidget {
  final Map<String, dynamic> billData;

  const SalesReturnScreen({super.key, required this.billData});

  @override
  State<SalesReturnScreen> createState() => _SalesReturnScreenState();
}

class _SalesReturnScreenState extends State<SalesReturnScreen> {
  List<Map<String, dynamic>> _lines = []; // bill lines with returnable qty
  bool _isLoading = true;
  bool _isSaving = false;
  String _returnNo = "Loading...";
  String _refundMode = 'Cash'; // Cash | Udhaar
  final TextEditingController _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _load() async {
    final billId = (widget.billData['id'] as num).toInt();
    final items = await DBHelper.getBillItems(billId);
    final retNo = await DBHelper.getNewReturnNo();

    List<Map<String, dynamic>> lines = [];
    for (var it in items) {
      int billedQty = ((it['qty'] as num?)?.toInt()) ?? 0;
      int billedFree = ((it['free_qty'] as num?)?.toInt()) ?? 0;
      final already = await DBHelper.getReturnedQty(
          billId,
          (it['item_name'] ?? '').toString(),
          (it['batch'] ?? '').toString());
      int maxQty = billedQty - (already['qty'] ?? 0);
      int maxFree = billedFree - (already['free_qty'] ?? 0);
      if (maxQty < 0) maxQty = 0;
      if (maxFree < 0) maxFree = 0;
      lines.add({
        'stock_id': ((it['stock_id'] as num?)?.toInt()) ?? 0,
        'name': (it['item_name'] ?? '').toString(),
        'batch': (it['batch'] ?? '').toString(),
        'rate': ((it['rate'] as num?)?.toDouble()) ?? 0.0,
        'billed_qty': billedQty,
        'billed_free': billedFree,
        'max_qty': maxQty,
        'max_free': maxFree,
        'ret_qty': 0,
        'ret_free': 0,
      });
    }

    if (mounted) {
      setState(() {
        _lines = lines;
        _returnNo = retNo;
        _isLoading = false;
      });
    }
  }

  double get _total {
    double t = 0;
    for (var l in _lines) {
      t += (((l['ret_qty'] as num?)?.toInt()) ?? 0) *
          (((l['rate'] as num?)?.toDouble()) ?? 0.0);
    }
    return t;
  }

  bool get _hasSelection =>
      _lines.any((l) => (((l['ret_qty'] as num?)?.toInt()) ?? 0) > 0);

  void _bump(int i, String key, int delta, int max) {
    int v = (((_lines[i][key] as num?)?.toInt()) ?? 0) + delta;
    if (v < 0) v = 0;
    if (v > max) v = max;
    setState(() => _lines[i][key] = v);
  }

  Future<void> _save() async {
    if (!_hasSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Koi item select nahi kiya!")));
      return;
    }
    String mobile = (widget.billData['mobile'] ?? '').toString();
    if (_refundMode == 'Udhaar' && mobile.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Udhaar adjust ke liye customer mobile chahiye! (ye bill walk-in hai)"),
          backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSaving = true);
    try {
      _returnNo = await DBHelper.getNewReturnNo();
      Map<String, dynamic> ret = {
        'return_no': _returnNo,
        'bill_id': widget.billData['id'],
        'invoice_no': widget.billData['invoice_no'],
        'customer_name': widget.billData['customer_name'],
        'mobile': mobile,
        'date': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
        'total_amount': _total,
        'refund_mode': _refundMode,
        'reason': _reasonCtrl.text.trim(),
      };

      List<Map<String, dynamic>> lines = _lines
          .where((l) => (((l['ret_qty'] as num?)?.toInt()) ?? 0) > 0)
          .map((l) => {
                'stock_id': l['stock_id'],
                'name': l['name'],
                'batch': l['batch'],
                'qty': l['ret_qty'],
                'free_qty': l['ret_free'],
                'rate': l['rate'],
                'total': (((l['ret_qty'] as num?)?.toInt()) ?? 0) *
                    (((l['rate'] as num?)?.toDouble()) ?? 0.0),
              })
          .toList();

      await DBHelper.saveSalesReturn(ret, lines);

      if (!mounted) return;
      // Ask for receipt print
      bool? wantPrint = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Return Saved! ✓"),
          content: Text(
              "$_returnNo\nRefund: Rs.${_total.toStringAsFixed(0)} (${_refundMode == 'Udhaar' ? 'Udhaar me adjust' : 'Cash'})\n\nReturn slip print karein?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text("No")),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white),
              child: const Text("PRINT"),
            ),
          ],
        ),
      );
      if (wantPrint == true) {
        try {
          await ReceiptHelper.printReturnReceipt(
              retData: ret, items: lines);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text("Print error: $e"),
                backgroundColor: Colors.orange));
          }
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Sales Return",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("Bill: ${widget.billData['invoice_no']} • $_returnNo",
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.deepPurple.shade50,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    "${widget.billData['customer_name']} • ${widget.billData['date']}",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _lines.length,
                    itemBuilder: (ctx, i) {
                      final l = _lines[i];
                      bool exhausted =
                          (l['max_qty'] as int) <= 0 && (l['max_free'] as int) <= 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(l['name'],
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15)),
                                  ),
                                  Text("₹${((l['rate'] as num).toDouble()).toStringAsFixed(1)}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Text(
                                  "Batch: ${l['batch']} • Billed: ${l['billed_qty']}+${l['billed_free']} Free • Returnable: ${l['max_qty']}+${l['max_free']}",
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600])),
                              if (exhausted)
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Text("✓ Fully returned already",
                                      style: TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                )
                              else ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Text("Return Qty:",
                                        style: TextStyle(fontSize: 13)),
                                    const SizedBox(width: 8),
                                    _miniBtn(Icons.remove,
                                        () => _bump(i, 'ret_qty', -1, l['max_qty'] as int)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text("${l['ret_qty']}",
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 17)),
                                    ),
                                    _miniBtn(Icons.add,
                                        () => _bump(i, 'ret_qty', 1, l['max_qty'] as int)),
                                    const Spacer(),
                                    if ((l['max_free'] as int) > 0) ...[
                                      const Text("Free:",
                                          style: TextStyle(fontSize: 13)),
                                      _miniBtn(Icons.remove,
                                          () => _bump(i, 'ret_free', -1, l['max_free'] as int)),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: Text("${l['ret_free']}",
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15)),
                                      ),
                                      _miniBtn(Icons.add,
                                          () => _bump(i, 'ret_free', 1, l['max_free'] as int)),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  child: Column(
                    children: [
                      TextField(
                        controller: _reasonCtrl,
                        decoration: InputDecoration(
                          hintText: "Reason (optional) - jaise: expiry najdeek, galat dawai...",
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                    value: 'Cash',
                                    label: Text("Cash Refund")),
                                ButtonSegment(
                                    value: 'Udhaar',
                                    label: Text("Udhaar Adjust")),
                              ],
                              selected: {_refundMode},
                              onSelectionChanged: (s) =>
                                  setState(() => _refundMode = s.first),
                              style: SegmentedButton.styleFrom(
                                  visualDensity: VisualDensity.compact),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("Refund",
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600])),
                              Text("₹${_total.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _save,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.assignment_return,
                                  color: Colors.white),
                          label: const Text("CONFIRM RETURN",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: Colors.deepPurple),
      ),
    );
  }
}

/// Returns history list.
class ReturnsHistoryScreen extends StatefulWidget {
  const ReturnsHistoryScreen({super.key});

  @override
  State<ReturnsHistoryScreen> createState() => _ReturnsHistoryScreenState();
}

class _ReturnsHistoryScreenState extends State<ReturnsHistoryScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final data = await DBHelper.getAllReturns();
    if (mounted) {
      setState(() {
        _list = data;
        _isLoading = false;
      });
    }
  }

  void _viewItems(Map<String, dynamic> r) async {
    final items = await DBHelper.getReturnItems((r['id'] as num).toInt());
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("${r['return_no']} • Bill ${r['invoice_no']}",
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: items.isEmpty
              ? const Text("No items")
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[i];
                    return ListTile(
                      dense: true,
                      title: Text((it['item_name'] ?? '').toString(),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                          "B:${(it['batch'] ?? '-').toString()} • Qty ${it['qty']}+${it['free_qty']} • @₹${((it['rate'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}",
                          style: const TextStyle(fontSize: 11)),
                      trailing: Text(
                          "₹${((it['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}",
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ReceiptHelper.printReturnReceipt(
                      retData: r, items: items);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text("Print error: $e"),
                        backgroundColor: Colors.orange));
                  }
                }
              },
              child: const Text("PRINT")),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Close")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sales Returns"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? const Center(child: Text("No returns yet"))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _list.length,
                  itemBuilder: (ctx, i) {
                    final r = _list[i];
                    double amt =
                        ((r['total_amount'] as num?)?.toDouble()) ?? 0.0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple.shade50,
                          child: const Icon(Icons.assignment_return,
                              color: Colors.deepPurple, size: 20),
                        ),
                        title: Text(
                            "${r['return_no']} • ${r['customer_name']}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(
                            "Bill ${r['invoice_no']} • ${r['date']} • ${r['refund_mode']}",
                            style: const TextStyle(fontSize: 12)),
                        trailing: Text("₹${amt.toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.deepPurple)),
                        onTap: () => _viewItems(r),
                      ),
                    );
                  },
                ),
    );
  }
}
