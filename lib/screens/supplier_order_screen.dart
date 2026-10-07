import 'package:flutter/material.dart';
import '../db_helper.dart';
import '../services/whatsapp_helper.dart';
import '../services/lang_service.dart';

/// SUPPLIER ORDER - low stock products select karo, qty set karo,
/// supplier ko WhatsApp pe order bhejo. 1-tap reorder!
class SupplierOrderScreen extends StatefulWidget {
  const SupplierOrderScreen({super.key});

  @override
  State<SupplierOrderScreen> createState() => _SupplierOrderScreenState();
}

class _SupplierOrderScreenState extends State<SupplierOrderScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _suppliers = [];
  int? _selectedSupplierId;
  bool _isLoading = true;
  final Map<String, int> _orderQty = {}; // product name -> order qty
  final Set<String> _checked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final items = await DBHelper.getItems();
    final suppliers = await DBHelper.getSuppliers();

    // Group by product, keep low-stock ones
    final Map<String, List<Map<String, dynamic>>> map = {};
    for (var r in items) {
      final name = (r['name'] ?? '').toString();
      if (name.isEmpty) continue;
      map.putIfAbsent(name, () => []).add(r);
    }
    List<Map<String, dynamic>> low = [];
    map.forEach((name, rows) {
      int total = 0;
      int minStock = 10;
      for (var r in rows) {
        total += (((r['quantity'] as num?)?.toInt()) ?? 0);
        minStock = ((r['min_stock'] as num?)?.toInt()) ?? 10;
      }
      if (total <= minStock) {
        int suggested = (minStock * 3 - total);
        if (suggested < minStock) suggested = minStock;
        low.add({
          'name': name,
          'qty': total,
          'min_stock': minStock,
          'suggested': suggested,
        });
      }
    });
    low.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    if (mounted) {
      setState(() {
        _products = low;
        _suppliers = suppliers;
        for (var p in low) {
          _orderQty[p['name']] = (p['suggested'] as num).toInt();
        }
        _isLoading = false;
      });
    }
  }

  void _toggleAll(bool? v) {
    setState(() {
      if (v == true) {
        _checked.addAll(_products.map((p) => p['name'] as String));
      } else {
        _checked.clear();
      }
    });
  }

  Future<void> _sendOrder() async {
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar( SnackBar(
          content: Text(Lang.t('pu_sup_req')),
          backgroundColor: Colors.red));
      return;
    }
    if (_checked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Lang.t('so_noprod'))));
      return;
    }
    Map<String, dynamic>? supplier;
    try {
      supplier =
          _suppliers.firstWhere((s) => s['id'] == _selectedSupplierId);
    } catch (_) {
      supplier = null;
    }
    if (supplier == null) return;

    final lines = _checked
        .map((name) => {'name': name, 'qty': _orderQty[name] ?? 0})
        .where((l) => ((l['qty'] as num?)?.toInt() ?? 0) > 0)
        .toList();
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar( SnackBar(
          content: Text(Lang.t('so_qty0')), backgroundColor: Colors.red));
      return;
    }
    await WhatsAppHelper.sendSupplierOrder(context, supplier, lines);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        title: Text(Lang.t('so_title')),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    children: [
                      DropdownButtonFormField<int>(
                        value: _selectedSupplierId,
                        hint: Text(Lang.t('pu_supplier')),
                        isDense: true,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.local_shipping,
                              size: 18, color: Colors.green),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        items: _suppliers
                            .map((s) => DropdownMenuItem<int>(
                                  value: (s['id'] as num).toInt(),
                                  child: Text("${s['name']}",
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedSupplierId = v),
                      ),
                      if (_products.isNotEmpty)
                        CheckboxListTile(
                          value: _checked.length == _products.length &&
                              _products.isNotEmpty,
                          activeColor: Colors.green,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              "${Lang.t('so_all')} (${_products.length} ${Lang.t('so_lowitems')})",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          onChanged: _toggleAll,
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _products.isEmpty
                      ?  Center(
                          child: Text(
                              Lang.t('so_full'),
                              style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _products.length,
                          itemBuilder: (ctx, i) {
                            final p = _products[i];
                            final name = p['name'] as String;
                            final sel = _checked.contains(name);
                            final qty = _orderQty[name] ?? 0;
                            return Card(
                              color: sel
                                  ? Colors.green.shade50
                                  : Colors.white,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: sel
                                        ? Colors.green
                                        : Colors.grey.shade200),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: sel,
                                      activeColor: Colors.green,
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _checked.add(name);
                                          } else {
                                            _checked.remove(name);
                                          }
                                        });
                                      },
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14)),
                                          Text(
                                              "${Lang.t('w_stock')}: ${p['qty']} • ${Lang.t('so_min')}: ${p['min_stock']}",
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600])),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle,
                                          color: Colors.red),
                                      onPressed: qty > 1
                                          ? () => setState(() =>
                                              _orderQty[name] = qty - 1)
                                          : null,
                                    ),
                                    SizedBox(
                                      width: 44,
                                      child: Text("$qty",
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16)),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle,
                                          color: Colors.green),
                                      onPressed: () => setState(() =>
                                          _orderQty[name] = qty + 1),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (_products.isNotEmpty)
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _sendOrder,
                        icon: const Icon(Icons.send,
                            color: Colors.white, size: 20),
                        label: Text(
                            "${Lang.t('so_send')} (${_checked.length})",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
