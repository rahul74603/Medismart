import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import '../services/receipt_helper.dart';
import '../services/app_prefs.dart';
import '../services/whatsapp_helper.dart';

/// FAST RETAIL (counter) BILLING
/// Walk-in customer -> search -> tap -> qty -> print. No GSTIN/address needed.
/// Rate defaults to MRP. Stock is picked batch-wise, earliest-expiry-first (FEFO).
class RetailBillingScreen extends StatefulWidget {
  final Map<String, dynamic>? editBillData;
  final List<Map<String, dynamic>>? editItems;

  const RetailBillingScreen({super.key, this.editBillData, this.editItems});

  @override
  State<RetailBillingScreen> createState() => _RetailBillingScreenState();
}

class _RetailBillingScreenState extends State<RetailBillingScreen> {
  List<Map<String, dynamic>> _allBatches = []; // raw stock rows (one row = one batch)
  List<Map<String, dynamic>> _products = []; // grouped by product name
  List<Map<String, dynamic>> _filteredProducts = [];
  List<Map<String, dynamic>> _cart = [];

  String _invoiceNo = "Loading...";
  DateTime _billDate = DateTime.now();
  bool _isSaving = false;
  bool _isEditMode = false;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _discountCtrl = TextEditingController(text: "0");

  String _payMode = 'Cash'; // Cash | UPI | Udhaar

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _mobileCtrl.addListener(() {
      if (_mobileCtrl.text.length == 10 && !_isEditMode) {
        _fetchCustomerDetails(_mobileCtrl.text);
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _searchCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  void _loadInitialData() async {
    final batches = await DBHelper.getItems();
    String inv = await DBHelper.getNewInvoiceNo();

    if (widget.editBillData != null && widget.editItems != null) {
      _isEditMode = true;
      inv = widget.editBillData!['invoice_no'] ?? inv;
      _mobileCtrl.text = widget.editBillData!['mobile'] ?? '';
      _nameCtrl.text = (widget.editBillData!['customer_name'] ?? '').toString();
      try {
        _billDate = DateFormat('dd/MM/yyyy HH:mm').parse(widget.editBillData!['date']);
      } catch (_) {
        _billDate = DateTime.now();
      }
      _discountCtrl.text = (widget.editBillData!['discount'] ?? 0).toString();
      String pm = (widget.editBillData!['payment_mode'] ?? 'Cash').toString();
      _payMode = (pm == 'UPI' || pm == 'Udhaar') ? pm : 'Cash';

      _cart = List.from(widget.editItems!.map((e) {
        double price = ((e['price'] ?? e['rate']) as num?)?.toDouble() ?? 0.0;
        double mrp = ((e['mrp'] as num?) ?? price).toDouble();
        if (mrp == 0) mrp = price;
        return {
          'id': ((e['stock_id'] as num?)?.toInt()) ?? 0,
          'name': e['name'] ?? e['item_name'] ?? 'Item',
          'batch': e['batch'] ?? '',
          'mrp': mrp,
          'price': price,
          'gst_percent': ((e['gst_percent'] as num?)?.toInt()) ?? 0,
          'sold_qty': ((e['sold_qty'] ?? e['qty']) as num?)?.toInt() ?? 0,
          'free_qty': ((e['free_qty'] as num?)?.toInt()) ?? 0,
          'cost': ((e['cost_rate'] as num?)?.toDouble()) ?? 0.0,
          'max_qty': 99999,
          'total': ((e['total'] as num?)?.toDouble()) ?? 0.0,
          'expiryDate': e['expiryDate'] ?? '',
          'type': e['type'] ?? '',
        };
      }));

      // Link edit lines to current batch rows for stock validation
      for (var line in _cart) {
        Map<String, dynamic>? row;
        try {
          int sid = (line['id'] as num?)?.toInt() ?? 0;
          if (sid > 0) {
            row = batches.firstWhere((b) => b['id'] == sid);
          } else {
            row = batches.firstWhere(
                (b) => b['name'] == line['name'] && (b['batch'] ?? '') == (line['batch'] ?? ''));
            line['id'] = row['id'];
          }
        } catch (_) {
          row = null;
        }
        if (row != null) {
          int stockQty = ((row['quantity'] as num?)?.toInt()) ?? 0;
          line['max_qty'] = stockQty + (line['sold_qty'] as int) + (line['free_qty'] as int);
          if ((line['gst_percent'] as int) == 0) {
            line['gst_percent'] = ((row['gst_percent'] as num?)?.toInt()) ?? 0;
          }
          if ((((line['cost'] as num?)?.toDouble()) ?? 0.0) == 0.0) {
            line['cost'] = ((row['wholesale_price'] as num?)?.toDouble()) ?? 0.0;
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _allBatches = batches;
        _products = _groupProducts(batches);
        _filteredProducts = _products;
        _invoiceNo = inv;
      });
    }
  }

  /// Group batch rows into products for fast counter search.
  List<Map<String, dynamic>> _groupProducts(List<Map<String, dynamic>> batches) {
    final Map<String, List<Map<String, dynamic>>> map = {};
    for (var b in batches) {
      final name = (b['name'] ?? '').toString();
      if (name.isEmpty) continue;
      map.putIfAbsent(name, () => []).add(b);
    }
    final List<Map<String, dynamic>> out = [];
    map.forEach((name, rows) {
      int total = 0;
      double mrp = 0;
      String chemical = '';
      for (var r in rows) {
        total += (((r['quantity'] as num?)?.toInt()) ?? 0);
        double p = ((r['price'] as num?)?.toDouble()) ?? 0.0;
        if (p > mrp) mrp = p;
        if (chemical.isEmpty && (r['chemical'] ?? '').toString().isNotEmpty) {
          chemical = r['chemical'].toString();
        }
      }
      out.add({
        'name': name,
        'chemical': chemical,
        'total_qty': total,
        'mrp': mrp,
        'batches': DBHelper.sortBatchesFEFO(rows),
      });
    });
    out.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return out;
  }

  void _fetchCustomerDetails(String mobile) async {
    final cust = await DBHelper.getCustomerByMobile(mobile);
    if (cust != null && mounted) {
      setState(() {
        _nameCtrl.text = (cust['name'] ?? '').toString();
      });
      double due = ((cust['total_due'] as num?)?.toDouble()) ?? 0.0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(due > 0
            ? "Customer Found! Old Due: Rs.${due.toStringAsFixed(0)}"
            : "Customer Found!"),
        duration: const Duration(milliseconds: 1200),
        backgroundColor: due > 0 ? Colors.orange : Colors.green,
      ));
    }
  }

  void _runFilter(String keyword) {
    if (keyword.isEmpty) {
      setState(() => _filteredProducts = _products);
    } else {
      final k = keyword.toLowerCase();
      setState(() {
        _filteredProducts = _products
            .where((p) =>
                (p['name'] as String).toLowerCase().contains(k) ||
                (p['chemical'] as String).toLowerCase().contains(k))
            .toList();
      });
    }
  }

  /// Hardware scanner / keyboard Enter: barcode exact match = instant add.
  void _onSearchSubmit() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    // 1. Barcode exact match
    final row = await DBHelper.getItemByBarcode(q);
    if (row != null) {
      final name = (row['name'] ?? '').toString();
      try {
        final prod = _products.firstWhere((p) => p['name'] == name);
        _searchCtrl.clear();
        _runFilter('');
        setState(() {});
        _showQtyDialog(prod);
        return;
      } catch (_) {}
    }
    // 2. Single filtered product = open it directly
    if (_filteredProducts.length == 1) {
      final prod = _filteredProducts.first;
      _searchCtrl.clear();
      _runFilter('');
      setState(() {});
      _showQtyDialog(prod);
    }
  }

  /// Qty of a batch row already used in current cart.
  int _cartQtyFor(int stockId) {
    int sum = 0;
    for (var l in _cart) {
      if (((l['id'] as num?)?.toInt() ?? -1) == stockId) {
        sum += ((l['sold_qty'] as num?)?.toInt() ?? 0) +
            ((l['free_qty'] as num?)?.toInt() ?? 0);
      }
    }
    return sum;
  }

  /// FEFO allocation: earliest-expiry batches first. Returns null if short.
  List<Map<String, dynamic>>? _allocateFEFO(
      List<Map<String, dynamic>> batches, int qty) {
    int remaining = qty;
    final List<Map<String, dynamic>> alloc = [];
    for (var b in batches) {
      if (remaining <= 0) break;
      int stockId = ((b['id'] as num?)?.toInt()) ?? 0;
      int avail = (((b['quantity'] as num?)?.toInt()) ?? 0) - _cartQtyFor(stockId);
      if (avail <= 0) continue;
      int take = remaining <= avail ? remaining : avail;
      alloc.add({'row': b, 'take': take});
      remaining -= take;
    }
    return remaining > 0 ? null : alloc;
  }

  // ---------- QTY DIALOG (fast stepper) ----------
  void _showQtyDialog(Map<String, dynamic> product) async {
    final List<Map<String, dynamic>> subs =
        await DBHelper.getSubstitutes((product['name'] ?? '').toString());
    if (!mounted) return;
    final List<Map<String, dynamic>> batches =
        List<Map<String, dynamic>>.from(product['batches'] as List);
    int inStock = batches.fold(
        0, (s, b) => s + ((((b['quantity'] as num?)?.toInt()) ?? 0)));
    // minus already in cart
    int inCart = 0;
    for (var l in _cart) {
      if (l['name'] == product['name']) {
        inCart += ((l['sold_qty'] as num?)?.toInt() ?? 0);
      }
    }
    int available = inStock - inCart;
    if (available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Out of stock!"), backgroundColor: Colors.red));
      return;
    }

    double mrp = ((product['mrp'] as num?)?.toDouble()) ?? 0.0;
    final qtyCtrl = TextEditingController(text: "1");
    final rateCtrl = TextEditingController(text: mrp.toString());

    // FEFO preview: which batch will be picked
    String fefoInfo = batches
        .where((b) =>
            ((((b['quantity'] as num?)?.toInt()) ?? 0) -
                _cartQtyFor(((b['id'] as num?)?.toInt()) ?? 0)) >
            0)
        .map((b) =>
            "${(b['batch'] ?? '-').toString()} (Exp ${(b['expiryDate'] ?? '-').toString()})")
        .take(2)
        .join(' → ');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product['name'],
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 17)),
              Text("MRP ₹$mrp | Available: $available",
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (fefoInfo.isNotEmpty)
                Text("Auto batch (FEFO): $fefoInfo",
                    style: const TextStyle(
                        fontSize: 11, color: Colors.teal)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _stepBtn(Icons.remove, () {
                    int q = int.tryParse(qtyCtrl.text) ?? 1;
                    if (q > 1) setD(() => qtyCtrl.text = "${q - 1}");
                  }),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                          border: OutlineInputBorder()),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      onChanged: (_) => setD(() {}),
                    ),
                  ),
                  _stepBtn(Icons.add, () {
                    int q = int.tryParse(qtyCtrl.text) ?? 0;
                    if (q < available) {
                      setD(() => qtyCtrl.text = "${q + 1}");
                    }
                  }),
                ],
              ),
              const SizedBox(height: 10),
              // Quick qty chips
              Wrap(
                spacing: 8,
                children: [2, 5, 10, 15, 20, 30]
                    .where((q) => q <= available)
                    .map((q) => ActionChip(
                          label: Text("$q"),
                          onPressed: () =>
                              setD(() => qtyCtrl.text = "$q"),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: rateCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Rate (default MRP)",
                  border: OutlineInputBorder(),
                  prefixText: "₹",
                  isDense: true,
                ),
              ),
              if (subs.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Same salt, saste options:",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.green)),
                      const SizedBox(height: 6),
                      ...subs.take(3).map((s) => InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _showQtyDialog(s);
                            },
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(s['name'],
                                        style: const TextStyle(
                                            fontSize: 13)),
                                  ),
                                  Text(
                                      "₹${((s['mrp'] as num).toDouble()).toStringAsFixed(1)} • ${s['total_qty']}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.green)),
                                ],
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
              ],
            ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                int qty = int.tryParse(qtyCtrl.text) ?? 0;
                double rate = double.tryParse(rateCtrl.text) ?? 0.0;
                if (qty <= 0) return;
                if (qty > available) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("Only $available available!"),
                      backgroundColor: Colors.red));
                  return;
                }
                final alloc = _allocateFEFO(batches, qty);
                if (alloc == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Not enough stock in batches!"),
                          backgroundColor: Colors.red));
                  return;
                }
                setState(() {
                  for (var a in alloc) {
                    final row = a['row'] as Map<String, dynamic>;
                    final take = a['take'] as int;
                    _cart.add({
                      'id': row['id'],
                      'name': row['name'],
                      'batch': row['batch'] ?? '',
                      'mrp': (((row['price'] as num?)?.toDouble()) ?? rate),
                      'price': rate,
                      'cost': (((row['wholesale_price'] as num?)?.toDouble()) ?? 0.0),
                      'gst_percent':
                          (((row['gst_percent'] as num?)?.toInt()) ?? 0),
                      'sold_qty': take,
                      'free_qty': 0,
                      'max_qty': (((row['quantity'] as num?)?.toInt()) ?? 0),
                      'total': take * rate,
                      'expiryDate': row['expiryDate'] ?? '',
                      'type': row['type'] ?? '',
                    });
                  }
                  _searchCtrl.clear();
                  _filteredProducts = _products;
                });
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white),
              child: const Text("ADD"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.teal.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.teal, size: 26),
      ),
    );
  }

  // ---------- CART STEPPER ----------
  void _changeCartQty(int index, int delta) {
    final line = _cart[index];
    int q = ((line['sold_qty'] as num?)?.toInt()) ?? 0;
    int stockId = ((line['id'] as num?)?.toInt()) ?? 0;
    // max = batch stock (fresh) + what's already in this line
    int batchStock = 0;
    try {
      final row = _allBatches.firstWhere((b) => b['id'] == stockId);
      batchStock = ((row['quantity'] as num?)?.toInt()) ?? 0;
    } catch (_) {
      batchStock = (line['max_qty'] as num?)?.toInt() ?? 99999;
    }
    // other lines using same batch
    int usedElsewhere = 0;
    for (int i = 0; i < _cart.length; i++) {
      if (i == index) continue;
      if (((( _cart[i]['id'] as num?)?.toInt()) ?? -1) == stockId) {
        usedElsewhere += ((_cart[i]['sold_qty'] as num?)?.toInt() ?? 0);
      }
    }
    int max = batchStock - usedElsewhere;
    int nq = q + delta;
    if (nq <= 0) {
      setState(() => _cart.removeAt(index));
      return;
    }
    if (nq > max) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Only $max available in this batch!"),
          backgroundColor: Colors.red,
          duration: const Duration(milliseconds: 800)));
      return;
    }
    setState(() {
      line['sold_qty'] = nq;
      line['total'] = nq * (((line['price'] as num?)?.toDouble()) ?? 0.0);
    });
  }

  // ---------- TOTALS ----------
  Map<String, double> _calc() {
    double gross = 0, gst = 0;
    double discPct = double.tryParse(_discountCtrl.text) ?? 0.0;
    for (var l in _cart) {
      double rate = ((l['price'] as num?)?.toDouble()) ?? 0.0;
      int qty = ((l['sold_qty'] as num?)?.toInt()) ?? 0;
      int g = ((l['gst_percent'] as num?)?.toInt()) ?? 0;
      double taxable = rate * qty;
      taxable -= (taxable * discPct) / 100;
      gst += (taxable * g) / 100;
      gross += rate * qty;
    }
    double discAmt = (gross * discPct) / 100;
    double taxable = gross - discAmt;
    double net = taxable + gst;
    return {
      'gross': gross,
      'discount': discAmt,
      'taxable': taxable,
      'gst': gst,
      'net': net,
      'round': net.roundToDouble(),
    };
  }

  // ---------- SAVE ----------
  Future<void> _saveBill({required bool andPrint}) async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cart is empty!")));
      return;
    }
    if (_payMode == 'Udhaar' && _mobileCtrl.text.trim().length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Udhaar ke liye 10-digit mobile zaroori hai!"),
          backgroundColor: Colors.red));
      return;
    }
    setState(() => _isSaving = true);
    try {
      if (_isEditMode && widget.editBillData != null) {
        await DBHelper.deleteBillWithRestoration(
          widget.editBillData!['id'],
          (widget.editBillData!['mobile'] ?? '').toString(),
          ((widget.editBillData!['net_amount'] as num?)?.toDouble()) ?? 0.0,
          (widget.editBillData!['payment_mode'] ?? 'Cash').toString(),
        );
      } else {
        _invoiceNo = await DBHelper.getNewInvoiceNo();
      }

      final c = _calc();
      String custName = _nameCtrl.text.trim().isEmpty
          ? "Walk-in Customer"
          : _nameCtrl.text.trim();

      Map<String, dynamic> billData = {
        'invoice_no': _invoiceNo,
        'customer_name': custName,
        'doctor_name': '',
        'mobile': _mobileCtrl.text.trim(),
        'date': DateFormat('dd/MM/yyyy HH:mm').format(_billDate),
        'sub_total': c['gross'],
        'discount': c['discount'],
        'gst_percent': 0,
        'gst_amount': c['gst'],
        'net_amount': c['round'],
        'payment_mode': _payMode,
        'bill_type': 'Retail',
        'customer_gstin': '',
        'customer_address': '',
      };

      List<Map<String, dynamic>> itemsForDB = _cart
          .map((l) => {
                'stock_id': l['id'],
                'name': l['name'],
                'batch': l['batch'] ?? '',
                'qty': l['sold_qty'],
                'free_qty': l['free_qty'] ?? 0,
                'price': l['price'],
                'mrp': l['mrp'] ?? 0,
                'cost_rate': l['cost'] ?? 0,
                'total': l['total'] ?? 0,
                'gst_percent': l['gst_percent'] ?? 0,
              })
          .toList();

      billData['id'] = await DBHelper.saveBill(billData, itemsForDB);

      if (!mounted) return;

      // Thermal print if asked (or auto-print setting for quick saves)
      bool doPrint = andPrint;
      if (!andPrint && !_isEditMode) {
        doPrint = await AppPrefs.getAutoPrint();
      }
      if (doPrint) {
        try {
          await ReceiptHelper.printBillReceipt(
              billData: billData, items: List.from(_cart));
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text("Print dialog error: $e"),
                backgroundColor: Colors.orange));
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEditMode
            ? "Bill Updated: $_invoiceNo"
            : "Bill Saved: $_invoiceNo (${_payMode})"),
        backgroundColor: Colors.green,
      ));

      if (_isEditMode) {
        Navigator.pop(context);
      } else {
        // WhatsApp bill option (if mobile number hai)
        if (_mobileCtrl.text.trim().length == 10) {
          await _showWhatsAppOption(billData);
        }
        // Fresh bill for next customer (fast counter flow)
        final batches = await DBHelper.getItems();
        final inv = await DBHelper.getNewInvoiceNo();
        if (!mounted) return;
        setState(() {
          _allBatches = batches;
          _products = _groupProducts(batches);
          _filteredProducts = _products;
          _cart = [];
          _invoiceNo = inv;
          _billDate = DateTime.now();
          _nameCtrl.clear();
          _mobileCtrl.clear();
          _searchCtrl.clear();
          _discountCtrl.text = "0";
          _payMode = 'Cash';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showWhatsAppOption(Map<String, dynamic> billData) async {
    if (!mounted) return;
    final send = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Bill Saved!"),
        content: Text(
            "${billData['invoice_no']} • ₹${((billData['net_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}\n\nCustomer ko WhatsApp pe bill bhejein?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text("Skip")),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.chat, size: 18),
            label: const Text("WHATSAPP"),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
    if (send == true && mounted) {
      await WhatsAppHelper.shareBillPdf(context, billData);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _calc();
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEditMode ? "Edit Retail Bill" : "Retail Billing",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("Inv: $_invoiceNo • ${DateFormat('dd MMM, hh:mm a').format(_billDate)}",
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Customer strip
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      hintText: "Customer name (optional)",
                      prefixIcon:
                          const Icon(Icons.person, size: 18, color: Colors.teal),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _mobileCtrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    decoration: InputDecoration(
                      hintText: "Mobile",
                      counterText: "",
                      prefixIcon:
                          const Icon(Icons.phone, size: 18, color: Colors.teal),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _runFilter,
              onSubmitted: (_) => _onSearchSubmit(),
              autofocus: false,
              decoration: InputDecoration(
                hintText: "🔍 Search dawai ya salt... (jaise: Dolo)",
                prefixIcon: const Icon(Icons.search, color: Colors.teal),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _runFilter('');
                          setState(() {});
                        })
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
              onTap: () => setState(() {}),
            ),
          ),
          // Product list
          Expanded(
            flex: 5,
            child: _filteredProducts.isEmpty
                ? const Center(
                    child: Text("No medicines found",
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    itemCount: _filteredProducts.length > 60
                        ? 60
                        : _filteredProducts.length,
                    itemBuilder: (ctx, i) {
                      final p = _filteredProducts[i];
                      int qty = (p['total_qty'] as num).toInt();
                      bool out = qty <= 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: out
                                ? Colors.red.shade50
                                : Colors.teal.shade50,
                            child: Text("$qty",
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: out ? Colors.red : Colors.teal)),
                          ),
                          title: Text(p['name'],
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: (p['chemical'] as String).isNotEmpty
                              ? Text(p['chemical'],
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic))
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  "₹${((p['mrp'] as num).toDouble()).toStringAsFixed(1)}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: out ? Colors.grey : Colors.teal,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.add,
                                    color: Colors.white, size: 18),
                              ),
                            ],
                          ),
                          onTap: out ? null : () => _showQtyDialog(p),
                        ),
                      );
                    },
                  ),
          ),
          // Cart
          if (_cart.isNotEmpty)
            Expanded(
              flex: 4,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, -3))
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Cart (${_cart.length})",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _cart.clear()),
                            icon: const Icon(Icons.delete_outline,
                                size: 16, color: Colors.red),
                            label: const Text("Clear",
                                style: TextStyle(
                                    color: Colors.red, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _cart.length,
                        itemBuilder: (ctx, i) {
                          final l = _cart[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(l['name'],
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13)),
                                      Text(
                                          "B:${l['batch']} • ₹${(((l['price'] as num?)?.toDouble()) ?? 0).toStringAsFixed(1)}",
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600])),
                                    ],
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _changeCartQty(i, -1),
                                  child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius:
                                              BorderRadius.circular(6)),
                                      child: const Icon(Icons.remove,
                                          size: 16, color: Colors.red)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: Text("${l['sold_qty']}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                ),
                                InkWell(
                                  onTap: () => _changeCartQty(i, 1),
                                  child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius:
                                              BorderRadius.circular(6)),
                                      child: const Icon(Icons.add,
                                          size: 16, color: Colors.green)),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                      "₹${(((l['total'] as num?)?.toDouble()) ?? 0).toStringAsFixed(0)}",
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
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
          // Bottom bar: discount + pay mode + total + buttons
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    // Discount
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _discountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "Disc %",
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(10)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Pay mode
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'Cash',
                              label: Text("Cash",
                                  style: TextStyle(fontSize: 11))),
                          ButtonSegment(
                              value: 'UPI',
                              label: Text("UPI",
                                  style: TextStyle(fontSize: 11))),
                          ButtonSegment(
                              value: 'Udhaar',
                              label: Text("Udhaar",
                                  style: TextStyle(fontSize: 11))),
                        ],
                        selected: {_payMode},
                        onSelectionChanged: (s) =>
                            setState(() => _payMode = s.first),
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if ((c['gst'] ?? 0) > 0)
                          Text(
                              "incl GST ₹${(c['gst']!).toStringAsFixed(0)}",
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600])),
                        Text("₹${(c['round']!).toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _isSaving ? null : () => _saveBill(andPrint: false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          side: const BorderSide(
                              color: Colors.teal, width: 2),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12)),
                        ),
                        child: const Text("SAVE",
                            style: TextStyle(
                                color: Colors.teal,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving
                            ? null
                            : () => _saveBill(andPrint: true),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2))
                            : const Icon(Icons.print,
                                color: Colors.white, size: 20),
                        label: Text(
                            _isEditMode
                                ? "UPDATE BILL"
                                : "SAVE & PRINT",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12)),
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
