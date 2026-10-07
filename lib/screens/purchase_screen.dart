import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import 'purchase_history_screen.dart';
import '../services/lang_service.dart';

/// PURCHASE ENTRY - distributor se maal kharidna.
/// Stock auto-increases (new batch row), supplier udhaar auto-tracks.
class PurchaseScreen extends StatefulWidget {
  final int? supplierId;
  final String? supplierName;

  const PurchaseScreen({super.key, this.supplierId, this.supplierName});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  List<Map<String, dynamic>> _suppliers = [];
  int? _selectedSupplierId;
  List<Map<String, dynamic>> _allBatches = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _cart = [];

  String _purchaseNo = "Loading...";
  DateTime _purchaseDate = DateTime.now();
  bool _isSaving = false;
  bool _isLoading = true;

  final TextEditingController _invoiceCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _discountCtrl = TextEditingController(text: "0");
  final TextEditingController _paidCtrl = TextEditingController(text: "0");
  String _payMode = 'Cash';

  final List<int> _gstSlabs = [0, 5, 12, 18, 28];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    _searchCtrl.dispose();
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    super.dispose();
  }

  void _loadData() async {
    final suppliers = await DBHelper.getSuppliers();
    final batches = await DBHelper.getItems();
    final purNo = await DBHelper.getNewPurchaseNo();
    if (!mounted) return;
    setState(() {
      _suppliers = suppliers;
      _allBatches = batches;
      _products = _groupProducts(batches);
      _purchaseNo = purNo;
      _isLoading = false;
      if (widget.supplierId != null &&
          suppliers.any((s) => s['id'] == widget.supplierId)) {
        _selectedSupplierId = widget.supplierId;
      }
    });
  }

  List<Map<String, dynamic>> _groupProducts(List<Map<String, dynamic>> batches) {
    final Map<String, Map<String, dynamic>> map = {};
    for (var b in batches) {
      final name = (b['name'] ?? '').toString();
      if (name.isEmpty) continue;
      map.putIfAbsent(name, () => {
            'name': name,
            'chemical': (b['chemical'] ?? '').toString(),
            'type': (b['type'] ?? 'TABLET').toString(),
            'rack': (b['rack'] ?? '').toString(),
            'rate': ((b['wholesale_price'] as num?)?.toDouble()) ?? 0.0,
            'mrp': ((b['price'] as num?)?.toDouble()) ?? 0.0,
            'gst': ((b['gst_percent'] as num?)?.toInt()) ?? 0,
          });
    }
    final out = map.values.toList();
    out.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return out;
  }

  List<Map<String, dynamic>> get _filteredProducts {
    final k = _searchCtrl.text.trim().toLowerCase();
    if (k.isEmpty) return _products;
    return _products
        .where((p) =>
            (p['name'] as String).toLowerCase().contains(k) ||
            (p['chemical'] as String).toLowerCase().contains(k))
        .toList();
  }

  // ---------- QUICK ADD SUPPLIER ----------
  void _quickAddSupplier() {
    final nameCtrl = TextEditingController();
    final compCtrl = TextEditingController();
    final mobCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lang.t('pu_new_sup_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: Lang.t('pu_name'), border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: compCtrl, decoration: InputDecoration(labelText: Lang.t('pu_company'), border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: mobCtrl, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: Lang.t('pu_mobile'), border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Lang.t('cancel'))),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              int id = await DBHelper.addSupplier({
                'name': nameCtrl.text.trim(),
                'company': compCtrl.text.trim(),
                'mobile': mobCtrl.text.trim(),
                'gstin': '',
                'address': '',
              });
              final suppliers = await DBHelper.getSuppliers();
              if (!mounted) return;
              setState(() {
                _suppliers = suppliers;
                _selectedSupplierId = id;
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white),
            child: Text(Lang.t('add')),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (d != null) setState(() => _purchaseDate = d);
  }

  // ---------- ADD ITEM DIALOG (existing product) ----------
  void _showAddItemDialog(Map<String, dynamic> product) {
    final batchCtrl = TextEditingController();
    final barcodeCtrl = TextEditingController(text: (product['barcode'] ?? '').toString());
    final expiryCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: "");
    final freeCtrl = TextEditingController(text: "0");
    final rateCtrl = TextEditingController(text: (product['rate'] as double).toString());
    final mrpCtrl = TextEditingController(text: (product['mrp'] as double).toString());
    int gst = (product['gst'] as int);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              Text(Lang.t('pu_new_batch'), style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(child: TextField(controller: batchCtrl, decoration: InputDecoration(labelText: Lang.t('pu_batch'), border: OutlineInputBorder(), isDense: true))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: expiryCtrl,
                      readOnly: true,
                      decoration: InputDecoration(labelText: Lang.t('pu_exp'), border: OutlineInputBorder(), isDense: true, suffixIcon: Icon(Icons.calendar_month, size: 18)),
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 730)), firstDate: DateTime(2000), lastDate: DateTime(2100));
                        if (d != null) expiryCtrl.text = DateFormat('dd/MM/yyyy').format(d);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(controller: barcodeCtrl, decoration: InputDecoration(labelText: Lang.t('pu_barcode'), border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.qr_code, size: 18))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, autofocus: true, decoration: InputDecoration(labelText: Lang.t('pu_qty'), border: OutlineInputBorder(), isDense: true))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: freeCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: Lang.t('pu_free'), border: OutlineInputBorder(), isDense: true))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: rateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: Lang.t('pu_rate'), border: OutlineInputBorder(), isDense: true, prefixText: "₹"))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: mrpCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "MRP", border: OutlineInputBorder(), isDense: true, prefixText: "₹"))),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: gst,
                  decoration: const InputDecoration(labelText: "GST %", border: OutlineInputBorder(), isDense: true),
                  items: _gstSlabs.map((g) => DropdownMenuItem(value: g, child: Text("$g%"))).toList(),
                  onChanged: (v) => setD(() => gst = v ?? 0),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Lang.t('cancel'))),
            ElevatedButton(
              onPressed: () {
                int qty = int.tryParse(qtyCtrl.text) ?? 0;
                int free = int.tryParse(freeCtrl.text) ?? 0;
                double rate = double.tryParse(rateCtrl.text) ?? 0.0;
                double mrp = double.tryParse(mrpCtrl.text) ?? 0.0;
                if (qty <= 0 || rate <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('pu_qty_rate')), backgroundColor: Colors.red));
                  return;
                }
                if (mrp <= 0) mrp = rate;
                setState(() {
                  _cart.add({
                    'name': product['name'],
                    'chemical': product['chemical'],
                    'type': product['type'],
                    'rack': product['rack'],
                    'batch': batchCtrl.text.trim(),
                    'barcode': barcodeCtrl.text.trim(),
                    'expiry': expiryCtrl.text.trim(),
                    'qty': qty,
                    'free_qty': free,
                    'rate': rate,
                    'mrp': mrp,
                    'gst_percent': gst,
                    'total': qty * rate,
                  });
                  _searchCtrl.clear();
                });
                Navigator.pop(ctx);
                setState(() {});
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white),
              child: Text(Lang.t('add')),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- NEW MEDICINE DIALOG ----------
  void _showNewMedicineDialog() {
    final nameCtrl = TextEditingController(text: _searchCtrl.text.trim());
    final batchCtrl = TextEditingController();
    final barcodeCtrl = TextEditingController();
    final expiryCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final freeCtrl = TextEditingController(text: "0");
    final rateCtrl = TextEditingController();
    final mrpCtrl = TextEditingController();
    int gst = 12;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(Lang.t('pu_new_med'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: Lang.t('pu_med_name'), border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: batchCtrl, decoration: InputDecoration(labelText: Lang.t('pu_batch'), border: OutlineInputBorder(), isDense: true))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: expiryCtrl,
                      readOnly: true,
                      decoration: InputDecoration(labelText: Lang.t('pu_exp'), border: OutlineInputBorder(), isDense: true),
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 730)), firstDate: DateTime(2000), lastDate: DateTime(2100));
                        if (d != null) expiryCtrl.text = DateFormat('dd/MM/yyyy').format(d);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: Lang.t('pu_qty'), border: OutlineInputBorder(), isDense: true))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: freeCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: Lang.t('pu_free'), border: OutlineInputBorder(), isDense: true))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: barcodeCtrl, decoration: InputDecoration(labelText: Lang.t('pu_barcode'), border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.qr_code, size: 18))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: rateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: Lang.t('pu_rate_req'), border: OutlineInputBorder(), isDense: true, prefixText: "₹"))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: mrpCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "MRP", border: OutlineInputBorder(), isDense: true, prefixText: "₹"))),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: gst,
                  decoration: const InputDecoration(labelText: "GST %", border: OutlineInputBorder(), isDense: true),
                  items: _gstSlabs.map((g) => DropdownMenuItem(value: g, child: Text("$g%"))).toList(),
                  onChanged: (v) => setD(() => gst = v ?? 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Lang.t('cancel'))),
            ElevatedButton(
              onPressed: () {
                int qty = int.tryParse(qtyCtrl.text) ?? 0;
                int free = int.tryParse(freeCtrl.text) ?? 0;
                double rate = double.tryParse(rateCtrl.text) ?? 0.0;
                double mrp = double.tryParse(mrpCtrl.text) ?? 0.0;
                if (nameCtrl.text.trim().isEmpty || qty <= 0 || rate <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('pu_name_qty')), backgroundColor: Colors.red));
                  return;
                }
                if (mrp <= 0) mrp = rate;
                setState(() {
                  _cart.add({
                    'name': nameCtrl.text.trim(),
                    'chemical': '',
                    'type': 'TABLET',
                    'rack': '',
                    'batch': batchCtrl.text.trim(),
                    'barcode': barcodeCtrl.text.trim(),
                    'expiry': expiryCtrl.text.trim(),
                    'qty': qty,
                    'free_qty': free,
                    'rate': rate,
                    'mrp': mrp,
                    'gst_percent': gst,
                    'total': qty * rate,
                  });
                  _searchCtrl.clear();
                });
                Navigator.pop(ctx);
                setState(() {});
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white),
              child: Text(Lang.t('add')),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- TOTALS ----------
  Map<String, double> _calc() {
    double gross = 0, gstAmt = 0;
    for (var l in _cart) {
      double rate = ((l['rate'] as num?)?.toDouble()) ?? 0.0;
      int qty = ((l['qty'] as num?)?.toInt()) ?? 0;
      int g = ((l['gst_percent'] as num?)?.toInt()) ?? 0;
      double line = rate * qty;
      gross += line;
      gstAmt += (line * g) / 100;
    }
    double disc = double.tryParse(_discountCtrl.text) ?? 0.0;
    double net = gross - disc + gstAmt;
    return {'gross': gross, 'gst': gstAmt, 'discount': disc, 'net': net < 0 ? 0 : net};
  }

  // ---------- SAVE ----------
  Future<void> _savePurchase() async {
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('pu_sup_req')), backgroundColor: Colors.red));
      return;
    }
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('pu_empty'))));
      return;
    }
    setState(() => _isSaving = true);
    try {
      _purchaseNo = await DBHelper.getNewPurchaseNo();
      final c = _calc();
      double paid = double.tryParse(_paidCtrl.text) ?? 0.0;
      if (paid > c['net']!) paid = c['net']!;

      String supName = '';
      try {
        supName = _suppliers.firstWhere((s) => s['id'] == _selectedSupplierId)['name'].toString();
      } catch (_) {}

      Map<String, dynamic> purchase = {
        'purchase_no': _purchaseNo,
        'supplier_id': _selectedSupplierId,
        'supplier_name': supName,
        'supplier_invoice': _invoiceCtrl.text.trim(),
        'date': DateFormat('dd/MM/yyyy HH:mm').format(_purchaseDate),
        'sub_total': c['gross'],
        'discount': c['discount'],
        'gst_amount': c['gst'],
        'net_amount': c['net'],
        'paid_amount': paid,
        'payment_mode': paid <= 0 ? 'Credit' : _payMode,
      };

      await DBHelper.savePurchase(purchase, List.from(_cart));

      if (!mounted) return;
      double due = c['net']! - paid;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(due > 0
            ? "Purchase Saved! Udhaar: Rs.${due.toStringAsFixed(0)}"
            : "Purchase Saved! Full Paid ✓"),
        backgroundColor: Colors.green,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _calc();
    double paid = double.tryParse(_paidCtrl.text) ?? 0.0;
    double due = (c['net']! - paid).clamp(0, double.infinity);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Lang.t('pu_title'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("${Lang.t('pu_no')}: $_purchaseNo", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: Lang.t('pu_hist'),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PurchaseHistoryScreen())),
          ),
          InkWell(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(DateFormat('dd-MMM').format(_purchaseDate), style: const TextStyle(fontSize: 12, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.brown))
          : Column(
              children: [
                // Supplier + invoice strip
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          value: _selectedSupplierId,
                          hint: Text(Lang.t('pu_supplier')),
                          isDense: true,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.local_shipping, size: 18, color: Colors.brown),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: _suppliers
                              .map((s) => DropdownMenuItem<int>(
                                    value: (s['id'] as num).toInt(),
                                    child: Text("${s['name']}", overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedSupplierId = v),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.person_add, color: Colors.brown),
                        tooltip: Lang.t('pu_new_sup'),
                        onPressed: _quickAddSupplier,
                      ),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _invoiceCtrl,
                          decoration: InputDecoration(
                            hintText: Lang.t('pu_bill_no'),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Search + new medicine
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: Lang.t('pu_search'),
                            prefixIcon: const Icon(Icons.search, color: Colors.brown),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _showNewMedicineDialog,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(Lang.t('pu_new')),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                ),
                // Product list
                Expanded(
                  flex: 4,
                  child: _filteredProducts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(Lang.t('pu_not_found'), style: TextStyle(color: Colors.grey)),
                              TextButton.icon(
                                onPressed: _showNewMedicineDialog,
                                icon: const Icon(Icons.add),
                                label: Text(Lang.t('pu_add_new')),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          itemCount: _filteredProducts.length > 60 ? 60 : _filteredProducts.length,
                          itemBuilder: (ctx, i) {
                            final p = _filteredProducts[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                dense: true,
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.brown.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                  child: const Icon(Icons.medication, color: Colors.brown, size: 20),
                                ),
                                title: Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                subtitle: Text("${Lang.t('pu_rate_lbl')} ₹${(p['rate'] as double).toStringAsFixed(1)} • MRP ₹${(p['mrp'] as double).toStringAsFixed(1)}",
                                    style: const TextStyle(fontSize: 11)),
                                trailing: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.brown, borderRadius: BorderRadius.circular(8)),
                                  child: const Icon(Icons.add, color: Colors.white, size: 16),
                                ),
                                onTap: () => _showAddItemDialog(p),
                              ),
                            );
                          },
                        ),
                ),
                // Cart lines
                if (_cart.isNotEmpty)
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -3))],
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("${Lang.t('pu_items')} (${_cart.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                TextButton(
                                  onPressed: () => setState(() => _cart.clear()),
                                  child: Text(Lang.t('pu_clear'), style: TextStyle(color: Colors.red, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: _cart.length,
                              itemBuilder: (ctx, i) {
                                final l = _cart[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(l['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                            Text(
                                              "B:${(l['batch'] ?? '-').toString()} • ${l['qty']}+${l['free_qty']} pcs • @₹${((l['rate'] as num).toDouble()).toStringAsFixed(1)}",
                                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text("₹${((l['total'] as num).toDouble()).toStringAsFixed(0)}",
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.red, size: 18),
                                        onPressed: () => setState(() => _cart.removeAt(i)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Bottom: totals + payment + save
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _discountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: Lang.t('pu_disc'),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _paidCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: Lang.t('pu_paid'),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _payMode,
                            items: const [
                              DropdownMenuItem(value: 'Cash', child: Text(Lang.t('cash'))),
                              DropdownMenuItem(value: 'UPI', child: Text(Lang.t('upi'))),
                              DropdownMenuItem(value: 'Cheque', child: Text(Lang.t('pu_cheque'))),
                            ],
                            onChanged: (v) => setState(() => _payMode = v ?? 'Cash'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${Lang.t('pu_gross')} ₹${c['gross']!.toStringAsFixed(0)} • GST ₹${c['gst']!.toStringAsFixed(0)}",
                              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                          Text(due > 0 ? "${Lang.t('udhaar')} ₹${due.toStringAsFixed(0)}" : Lang.t('pu_fullpaid'),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: due > 0 ? Colors.red : Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(Lang.t('pu_net'), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                              Text("₹${c['net']!.toStringAsFixed(0)}",
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.brown)),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _savePurchase,
                              icon: _isSaving
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.save, color: Colors.white),
                              label: Text(Lang.t('pu_save'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.brown,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
