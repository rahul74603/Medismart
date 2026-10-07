import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import 'supplier_order_screen.dart';
import '../services/staff_mode.dart';
import '../services/lang_service.dart';

/// STOCK MANAGEMENT - grouped by product, batches inside (FEFO ordered).
/// One product can have multiple batches; billing auto-picks earliest expiry.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  // Full List of Types
  final List<String> _medTypes = [
    'TABLET', 'CAPSULE', 'SOFT GELATIN', 'SYRUP', 'SUSPENSION', 'DRY SYRUP',
    'DROPS', 'EYE DROPS', 'EAR DROPS', 'NASAL DROPS', 'INJECTION', 'INFUSION',
    'INSULIN', 'VACCINE', 'CREAM', 'OINTMENT', 'GEL', 'LOTION', 'LINIMENT',
    'POWDER', 'SPRAY', 'NASAL SPRAY', 'INHALER', 'RESPULES', 'SACHET',
    'TONIC', 'MOUTHWASH', 'SUPPOSITORY', 'PATCH', 'STRIP', 'BABY FOOD',
    'BABY CARE', 'DIAPER', 'SANITIZER', 'MASK', 'BANDAGE', 'COTTON',
    'GAUZE', 'GLOVES', 'SURGICAL', 'PERSONAL CARE', 'AYURVEDIC',
    'HOMEOPATHIC', 'COSMETIC', 'DEVICE', 'GENERAL', 'OTHER',
  ];
  final List<int> _gstSlabs = [0, 5, 12, 18, 28];

  String _selectedType = 'TABLET';

  @override
  void initState() {
    super.initState();
    _refreshItems();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refreshItems() async {
    final data = await DBHelper.getItems();
    if(mounted) {
      setState(() {
        _items = data;
        _filteredItems = data;
        _isLoading = false;
      });
    }
  }

  void _filterItems(String query) {
    setState(() {
      _filteredItems = _items.where((i) =>
        i['name'].toLowerCase().contains(query.toLowerCase()) ||
        (i['chemical'] != null && i['chemical'].toString().toLowerCase().contains(query.toLowerCase()))
      ).toList();
    });
  }

  /// Group batch rows by product name.
  List<Map<String, dynamic>> get _groups {
    final Map<String, List<Map<String, dynamic>>> map = {};
    for (var row in _filteredItems) {
      final name = (row['name'] ?? '').toString();
      if (name.isEmpty) continue;
      map.putIfAbsent(name, () => []).add(row);
    }
    final List<Map<String, dynamic>> out = [];
    map.forEach((name, rows) {
      final sorted = DBHelper.sortBatchesFEFO(rows);
      int total = 0;
      String chemical = '';
      String rack = '';
      int minStock = 10;
      for (var r in sorted) {
        total += (((r['quantity'] as num?)?.toInt()) ?? 0);
        if (chemical.isEmpty && (r['chemical'] ?? '').toString().isNotEmpty) {
          chemical = r['chemical'].toString();
        }
        if (rack.isEmpty && (r['rack'] ?? '').toString().isNotEmpty) {
          rack = r['rack'].toString();
        }
        minStock = ((r['min_stock'] as num?)?.toInt()) ?? 10;
      }
      out.add({
        'name': name,
        'chemical': chemical,
        'rack': rack,
        'rows': sorted,
        'total_qty': total,
        'min_stock': minStock,
      });
    });
    out.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return out;
  }

  /// Product-level status: 0=ok, 1=low stock, 2=expiring soon, 3=expired
  int _groupStatus(List<Map<String, dynamic>> rows, int totalQty, int minStock) {
    int status = 0;
    if (totalQty <= minStock) status = 1;
    final now = DateTime.now();
    final warning = now.add(const Duration(days: 90));
    for (var r in rows) {
      final exp = DBHelper.parseExpiry((r['expiryDate'] ?? '').toString());
      if (exp == null) continue;
      if (exp.isBefore(now)) return 3;
      if (exp.isBefore(warning)) status = 2;
    }
    return status;
  }

  Color _groupColor(int status) {
    switch (status) {
      case 3:
        return Colors.red.shade50;
      case 2:
        return Colors.amber.shade50;
      case 1:
        return Colors.green.shade50;
      default:
        return Colors.white;
    }
  }

  Color _groupBorder(int status) {
    switch (status) {
      case 3:
        return Colors.red;
      case 2:
        return Colors.amber.shade700;
      case 1:
        return Colors.green;
      default:
        return Colors.grey.shade300;
    }
  }

  String _nearestExpiry(List<Map<String, dynamic>> rows) {
    DateTime? best;
    for (var r in rows) {
      final exp = DBHelper.parseExpiry((r['expiryDate'] ?? '').toString());
      if (exp == null) continue;
      if (best == null || exp.isBefore(best)) best = exp;
    }
    return best == null ? '-' : DateFormat('dd/MM/yyyy').format(best);
  }

  String _mrpLabel(List<Map<String, dynamic>> rows) {
    double min = double.infinity, max = 0;
    for (var r in rows) {
      double p = ((r['price'] as num?)?.toDouble()) ?? 0.0;
      if (p < min) min = p;
      if (p > max) max = p;
    }
    if (min == double.infinity) return '-';
    if ((max - min).abs() < 0.005) return "₹${max.toStringAsFixed(1)}";
    return "₹${min.toStringAsFixed(1)}-${max.toStringAsFixed(1)}";
  }

  Color _getCardColor(Map<String, dynamic> item) {
    try {
      DateTime expiry = DateFormat('dd/MM/yyyy').parse(item['expiryDate']);
      DateTime now = DateTime.now();
      DateTime warningDate = now.add(const Duration(days: 90));
      if (expiry.isBefore(now)) return Colors.red.shade50;
      if (expiry.isBefore(warningDate)) return Colors.amber.shade50;
    } catch (e) {}
    int qty = item['quantity'] ?? 0;
    int minStock = item['min_stock'] ?? 10;
    if (qty <= minStock) return Colors.green.shade50;
    return Colors.white;
  }

  Color _getBorderColor(Map<String, dynamic> item) {
     Color bg = _getCardColor(item);
     if (bg == Colors.red.shade50) return Colors.red;
     if (bg == Colors.amber.shade50) return Colors.amber.shade700;
     if (bg == Colors.green.shade50) return Colors.green;
     return Colors.grey.shade300;
  }

  // --- FORM LOGIC (item = edit batch, prefill = new batch of existing product) ---
  void _showForm({Map<String, dynamic>? item, Map<String, dynamic>? prefill}) {
    final nameCtrl = TextEditingController(text: item?['name'] ?? prefill?['name']);
    final chemicalCtrl = TextEditingController(text: item?['chemical'] ?? prefill?['chemical'] ?? '');
    final batchCtrl = TextEditingController(text: item?['batch']);
    final rackCtrl = TextEditingController(text: item?['rack'] ?? prefill?['rack'] ?? '');
    final barcodeCtrl = TextEditingController(text: item?['barcode'] ?? prefill?['barcode'] ?? '');
    final minStockCtrl = TextEditingController(text: item?['min_stock']?.toString() ?? '10');
    final qtyCtrl = TextEditingController(text: item?['quantity']?.toString());

    final priceCtrl = TextEditingController(text: item?['price']?.toString() ?? prefill?['price']?.toString() ?? '');
    final wholesaleCtrl = TextEditingController(text: item?['wholesale_price']?.toString() ?? prefill?['wholesale_price']?.toString() ?? '');

    final expiryCtrl = TextEditingController(text: item?['expiryDate']);
    final tabsPerStripCtrl = TextEditingController(text: "10");

    String currentType = ((item?['type'] ?? prefill?['type'] ?? 'TABLET') as String).toUpperCase();
    if (!_medTypes.contains(currentType)) currentType = 'TABLET';
    _selectedType = currentType;

    int currentGST = item?['gst_percent'] ?? prefill?['gst_percent'] ?? 0;

    final bool isBatchAdd = item == null && prefill != null;
    final String title = item != null
        ? "Edit Medicine"
        : (isBatchAdd ? "Add Batch - ${prefill!['name']}" : "Add New Medicine");

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool isStripSelected = _selectedType == 'STRIP';

            void calculateWholesaleRate() {
              double mrp = double.tryParse(priceCtrl.text) ?? 0.0;
              if (mrp > 0) {
                double basicRate = mrp / (1 + (currentGST / 100));
                wholesaleCtrl.text = basicRate.toStringAsFixed(2);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 17)),
              contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInput(nameCtrl, "Medicine Name", "e.g. Dolo 650", Icons.medical_services, readOnly: isBatchAdd),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: InputDecoration(
                        labelText: Lang.t('st_type'),
                        prefixIcon: const Icon(Icons.category, color: Colors.deepOrange),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true, fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      ),
                      items: _medTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) {
                        setDialogState(() { _selectedType = val!; });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (isStripSelected)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Lang.t('st_strip'), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _buildInput(qtyCtrl, "No. of Strips", "10", Icons.layers, isNum: true)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildInput(tabsPerStripCtrl, "Tabs/Strip", "10", Icons.close, isNum: true)),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildInput(qtyCtrl, "Quantity (Total Units)", "e.g. 100", Icons.numbers, isNum: true),
                      ),

                    _buildInput(chemicalCtrl, "Salt / Chemical", "e.g. Paracetamol", Icons.science),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _buildInput(batchCtrl, "Batch", "B-102", Icons.qr_code)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildInput(rackCtrl, "Rack", "A-1", Icons.shelves)),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _buildInput(barcodeCtrl, Lang.t('st_barcode'), Lang.t('st_scan'), Icons.qr_code)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildInput(minStockCtrl, Lang.t('st_min'), '10', Icons.warning_amber, isNum: true)),
                    ]),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (val) => calculateWholesaleRate(),
                            decoration: InputDecoration(
                              labelText: isStripSelected ? Lang.t('st_mrp_strip') : Lang.t('st_mrp_unit'),
                              hintText: "100",
                              prefixIcon: const Icon(Icons.currency_rupee, color: Colors.green, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true, fillColor: Colors.green.shade50, isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<int>(
                            value: currentGST,
                            decoration: InputDecoration(
                              labelText: "GST %",
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true, fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
                            ),
                            items: _gstSlabs.map((g) => DropdownMenuItem(value: g, child: Text("$g%"))).toList(),
                            onChanged: (val) {
                              setDialogState(() {
                                currentGST = val!;
                                calculateWholesaleRate();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: wholesaleCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: Lang.t('st_basic'),
                        hintText: Lang.t('st_auto'),
                        prefixIcon: const Icon(Icons.calculate, color: Colors.blue, size: 18),
                        suffixText: "(Auto)",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true, fillColor: Colors.blue.shade50, isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: expiryCtrl,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: Lang.t('st_exp'),
                        hintText: Lang.t('st_sel_date'),
                        prefixIcon: const Icon(Icons.calendar_month, color: Colors.deepOrange),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true, fillColor: Colors.grey.shade50
                      ),
                      onTap: () async {
                        DateTime? picked = await showDatePicker(
                          context: context, initialDate: DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime(2000), lastDate: DateTime(2100)
                        );
                        if (picked != null) expiryCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
                      },
                    ),
                  ],
                ),
              ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Lang.t('cancel'), style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty) {
                       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('st_name_req'))));
                       return;
                    }
                    try {
                      int enteredQty = int.tryParse(qtyCtrl.text) ?? 0;
                      double enteredMRP = double.tryParse(priceCtrl.text) ?? 0.0;
                      double enteredWholesale = double.tryParse(wholesaleCtrl.text) ?? 0.0;

                      int finalQty = enteredQty;
                      double finalPricePerUnit = enteredMRP;
                      double finalWholesalePerUnit = enteredWholesale;

                      if (_selectedType == 'STRIP') {
                         int perStrip = int.tryParse(tabsPerStripCtrl.text) ?? 1;
                         finalQty = enteredQty * perStrip;
                         if (perStrip > 0) {
                           finalPricePerUnit = enteredMRP / perStrip;
                           finalWholesalePerUnit = enteredWholesale / perStrip;
                         }
                      }

                      Map<String, dynamic> data = {
                        'name': nameCtrl.text,
                        'chemical': chemicalCtrl.text,
                        'type': _selectedType == 'STRIP' ? 'TABLET' : _selectedType,
                        'batch': batchCtrl.text,
                        'rack': rackCtrl.text,
                        'barcode': barcodeCtrl.text.trim(),
                        'min_stock': int.tryParse(minStockCtrl.text) ?? 10,
                        'quantity': finalQty,
                        'price': double.parse(finalPricePerUnit.toStringAsFixed(4)),
                        'wholesale_price': double.parse(finalWholesalePerUnit.toStringAsFixed(4)),
                        'gst_percent': currentGST,
                        'expiryDate': expiryCtrl.text.isEmpty ? "01/01/2030" : expiryCtrl.text
                      };

                      if (item == null) {
                        await DBHelper.addItem(data);
                      } else {
                        data['id'] = item['id'];
                        await DBHelper.updateItem(data);
                      }
                      Navigator.pop(ctx);
                      _refreshItems();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('st_saved')), backgroundColor: Colors.green));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(Lang.t('st_save_item'), style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            );
          }
        );
      },
    );
  }

  void _deleteItem(int id, String label) async {
    bool confirm = await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(Lang.t('st_del')),
            content: Text("$label\n\n${Lang.t('st_del_msg')}"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(Lang.t('no'))),
              TextButton(onPressed: () => Navigator.pop(c, true), child: Text(Lang.t('yes'), style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    await DBHelper.deleteItem(id);
    _refreshItems();
  }

  Widget _buildInput(TextEditingController c, String label, String hint, IconData icon, {bool isNum = false, bool readOnly = false}) {
    return TextField(
      controller: c,
      readOnly: readOnly,
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label, hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.deepOrange, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        filled: true, fillColor: readOnly ? Colors.grey.shade200 : Colors.grey.shade50, isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        title: Text(Lang.t('st_title'), style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
        centerTitle: true,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFF6D00), Color(0xFFFF9100)], begin: Alignment.topLeft, end: Alignment.bottomRight))),
        elevation: 5, iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
            tooltip: Lang.t('st_order'),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SupplierOrderScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0,5))]
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _filterItems,
              decoration: InputDecoration(
                hintText: Lang.t('st_search'),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); _filterItems(''); }),
                filled: true, fillColor: const Color(0xFFF2F5F8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0)
              ),
            ),
          ),
          Expanded(
            child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
            : groups.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade300), Text(Lang.t('st_empty'), style: TextStyle(color: Colors.grey))]))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: groups.length,
                  itemBuilder: (ctx, i) {
                    final g = groups[i];
                    final List<Map<String, dynamic>> rows =
                        List<Map<String, dynamic>>.from(g['rows'] as List);
                    final int totalQty = (g['total_qty'] as num).toInt();
                    final int minStock = (g['min_stock'] as num?)?.toInt() ?? 10;
                    final int status = _groupStatus(rows, totalQty, minStock);
                    final Color cardColor = _groupColor(status);
                    final Color borderColor = _groupBorder(status);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: cardColor, borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: borderColor, width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 8, offset: const Offset(0, 4))]
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.7),
                                shape: BoxShape.circle,
                                border: Border.all(color: borderColor, width: 2)),
                            child: Text("$totalQty",
                                style: TextStyle(
                                    color: borderColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                          ),
                          title: Text(g['name'],
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.black87),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((g['chemical'] as String).isNotEmpty)
                                Text("(${g['chemical']})",
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        fontStyle: FontStyle.italic)),
                              const SizedBox(height: 4),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _badge("${rows.length} Batch${rows.length > 1 ? 'es' : ''}", Colors.deepOrange),
                                    const SizedBox(width: 4),
                                    _badge("Exp: ${_nearestExpiry(rows)}", status >= 2 ? Colors.red : Colors.teal),
                                    const SizedBox(width: 4),
                                    _badge("MRP: ${_mrpLabel(rows)}", Colors.green),
                                    const SizedBox(width: 4),
                                    if ((g['rack'] as String).isNotEmpty)
                                      _badge("Rack: ${g['rack']}", Colors.blue),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          children: [
                            ...rows.map((row) {
                              final int q = (((row['quantity'] as num?)?.toInt()) ?? 0);
                              final Color bColor = _getBorderColor(row);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: bColor.withOpacity(0.5)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: bColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text("$q",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: bColor)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("Batch: ${(row['batch'] ?? '-').toString()}",
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13)),
                                          Text(
                                              "Exp: ${(row['expiryDate'] ?? '-').toString()} • Rate ₹${(((row['wholesale_price'] as num?)?.toDouble()) ?? 0).toStringAsFixed(1)} • GST ${row['gst_percent']}%",
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600])),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      onPressed: () => _showForm(item: row),
                                    ),
                                    if (!StaffMode.enabled) const SizedBox(width: 12),
                                    if (!StaffMode.enabled)
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                        onPressed: () => _deleteItem(
                                            (row['id'] as num).toInt(),
                                            "${row['name']} (Batch ${row['batch']})"),
                                      ),
                                  ],
                                ),
                              );
                            }),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _showForm(prefill: {
                                  'name': g['name'],
                                  'chemical': g['chemical'],
                                  'type': (rows.first['type'] ?? 'TABLET').toString(),
                                  'rack': g['rack'],
                                  'price': rows.first['price'],
                                  'wholesale_price': rows.first['wholesale_price'],
                                  'gst_percent': rows.first['gst_percent'],
                                  'barcode': rows.first['barcode'] ?? '',
                                }),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text("Add Batch"),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.deepOrange,
                                  side: const BorderSide(color: Colors.deepOrange),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        backgroundColor: Colors.deepOrange,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Add Item", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // Helper Badge Widget
  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5)
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}
