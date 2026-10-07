import 'package:flutter/material.dart';
import '../db_helper.dart';

/// Purchase history - all purchases or filtered by supplier.
class PurchaseHistoryScreen extends StatefulWidget {
  final int? supplierId;
  final String? supplierName;

  const PurchaseHistoryScreen({super.key, this.supplierId, this.supplierName});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final data = widget.supplierId != null
        ? await DBHelper.getPurchasesBySupplier(widget.supplierId!)
        : await DBHelper.getAllPurchases();
    if (mounted) {
      setState(() {
        _list = data;
        _isLoading = false;
      });
    }
  }

  void _viewItems(Map<String, dynamic> p) async {
    final items = await DBHelper.getPurchaseItems((p['id'] as num).toInt());
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("${p['purchase_no']} • ${p['supplier_name']}",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                          "B:${(it['batch'] ?? '-').toString()} • Qty ${it['qty']}+${it['free_qty']} • @₹${((it['rate'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}",
                          style: const TextStyle(fontSize: 11)),
                      trailing: Text("₹${((it['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}",
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
        ],
      ),
    );
  }

  void _deletePurchase(Map<String, dynamic> p) async {
    bool confirm = await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Delete Purchase?"),
            content: Text(
                "${p['purchase_no']} delete hoga, stock kam hoga aur supplier udhaar adjust hoga.\n\nNote: jo maal bik chuka hai, woh purchase delete nahi hogi."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("NO")),
              TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text("YES", style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    final res = await DBHelper.deletePurchase((p['id'] as num).toInt());
    if (!mounted) return;
    if (res == 'ok') {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Purchase deleted!"), backgroundColor: Colors.green));
      _load();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplierName != null
            ? "Bills: ${widget.supplierName}"
            : "Purchase History"),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.brown))
          : _list.isEmpty
              ? const Center(child: Text("No purchases yet"))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _list.length,
                  itemBuilder: (ctx, i) {
                    final p = _list[i];
                    double net = ((p['net_amount'] as num?)?.toDouble()) ?? 0.0;
                    double paid = ((p['paid_amount'] as num?)?.toDouble()) ?? 0.0;
                    double due = net - paid;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.brown.shade50,
                          child: const Icon(Icons.receipt_long, color: Colors.brown, size: 20),
                        ),
                        title: Text("${p['purchase_no']} • ${p['supplier_name']}",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(
                            "${p['date']} • Paid ₹${paid.toStringAsFixed(0)}${due > 0 ? ' • Due ₹${due.toStringAsFixed(0)}' : ' • Full Paid ✓'}",
                            style: TextStyle(
                                fontSize: 12,
                                color: due > 0 ? Colors.red : Colors.green,
                                fontWeight: FontWeight.w600)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("₹${net.toStringAsFixed(0)}",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            IconButton(
                              icon: const Icon(Icons.visibility, color: Colors.brown, size: 20),
                              onPressed: () => _viewItems(p),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                              onPressed: () => _deletePurchase(p),
                            ),
                          ],
                        ),
                        onTap: () => _viewItems(p),
                      ),
                    );
                  },
                ),
    );
  }
}
