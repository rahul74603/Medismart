import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import '../pdf_helper.dart'; // Correct Master Import
import 'view_bill_screen.dart'; // Ensure ViewBillScreen is imported
import '../services/lang_service.dart';

class BillingScreen extends StatefulWidget {
  final Map<String, dynamic>? editBillData;
  final List<Map<String, dynamic>?>? editItems;

  const BillingScreen({super.key, this.editBillData, this.editItems});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  // --- VARIABLES ---
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  List<Map<String, dynamic>> _cart = [];
  String _invoiceNo = "Loading...";
  bool _manualInv = false;
  DateTime _selectedDate = DateTime.now();
  
  bool _isSaving = false;
  bool _isEditMode = false;
  bool _isSearchFocused = false;

  // Customer Details (WHOLESALE STYLE)
  String _selectedTitle = "Mr."; 
  final List<String> _titles = ["M/s", "Mr.", "Mrs.", "Dr."];
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController(); 
  final TextEditingController _gstinCtrl = TextEditingController();
  
  // 🔥🔥 NEW DOCTOR CONTROLLER ADDED HERE 🔥🔥
  final TextEditingController _doctorCtrl = TextEditingController();   

  // Search & Calculation
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _discountCtrl = TextEditingController(text: "0"); 

  bool _isUdhaar = false;
  int _selectedGlobalGST = 0; 

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    _mobileCtrl.addListener(() {
      if(_mobileCtrl.text.length == 10 && !_isEditMode) {
        _fetchCustomerDetails(_mobileCtrl.text);
      }
    });
  }

  void _loadInitialData() async {
    final items = await DBHelper.getItems();
    String inv = await DBHelper.getNewInvoiceNo();

    if (widget.editBillData != null && widget.editItems != null) {
      _isEditMode = true;
      inv = widget.editBillData!['invoice_no'];
      _mobileCtrl.text = widget.editBillData!['mobile'] ?? '';
      
      try {
        _selectedDate = DateFormat('dd/MM/yyyy HH:mm').parse(widget.editBillData!['date']);
      } catch (e) {
        _selectedDate = DateTime.now();
      }

      String fullName = widget.editBillData!['customer_name'];
      bool titleFound = false;
      for (var t in _titles) {
        if (fullName.startsWith("$t ")) {
          _selectedTitle = t;
          _nameCtrl.text = fullName.substring(t.length + 1);
          titleFound = true;
          break;
        }
      }
      if (!titleFound) _nameCtrl.text = fullName;

      _gstinCtrl.text = widget.editBillData!['customer_gstin'] ?? '';
      _addressCtrl.text = widget.editBillData!['customer_address'] ?? '';
      
      // 🔥 LOAD DOCTOR NAME IF EDITING 🔥
      _doctorCtrl.text = widget.editBillData!['doctor_name'] ?? '';

      _discountCtrl.text = widget.editBillData!['discount'].toString();
      _isUdhaar = widget.editBillData!['payment_mode'] == 'Udhaar';
      _selectedGlobalGST = widget.editBillData!['gst_percent'] ?? 0;

      // Load Items - Support both field name formats (price/rate, sold_qty/qty, name/item_name)
      _cart = List.from(widget.editItems!.map((e) {
         double price = ((e!['price'] ?? e['rate']) as num?)?.toDouble() ?? 0.0;
         double mrp = ((e['mrp'] as num?) ?? price).toDouble();
         if (mrp == 0) mrp = price;
         return {
          'id': ((e!['stock_id'] as num?)?.toInt()) ?? 0,
          'name': e['name'] ?? e['item_name'] ?? 'Item',
          'batch': e['batch'] ?? '',
          'mrp': mrp,
          'price': price,
          'gst_percent': e['gst_percent'] ?? 0,
          'sold_qty': (e['sold_qty'] ?? e['qty']) as int? ?? 0,
          'free_qty': (e['free_qty'] as int?) ?? 0,
          'cost': ((e!['cost_rate'] as num?)?.toDouble()) ?? 0.0,
          'max_qty': 99999,
          'total': (e['total'] as num?)?.toDouble() ?? 0.0
        };
      }));
      
      for(var cartItem in _cart) {
          int sid = ((cartItem['id'] as num?)?.toInt()) ?? 0;
          var stockItem = items.firstWhere(
            (i) => sid > 0
              ? i['id'] == sid
              : (i['name'] == cartItem['name'] && (i['batch'] ?? '') == (cartItem['batch'] ?? '')),
            orElse: () => {});
          if(stockItem.isEmpty && sid == 0) {
            // Legacy fallback: match by name only
            stockItem = items.firstWhere((i) => i['name'] == cartItem['name'], orElse: () => {});
          }
          if(stockItem.isNotEmpty) {
            if (sid == 0) cartItem['id'] = stockItem['id'];
            // If bill item doesn't have GST percent, get it from stock item
            if (cartItem['gst_percent'] == 0) {
              cartItem['gst_percent'] = stockItem['gst_percent'] ?? 0;
            }
            if ((((cartItem['cost'] as num?)?.toDouble()) ?? 0.0) == 0.0) {
              cartItem['cost'] = ((stockItem['wholesale_price'] as num?)?.toDouble()) ?? 0.0;
            }
            int stockQty = (stockItem['quantity'] as num?)?.toInt() ?? 0;
            cartItem['max_qty'] = stockQty + cartItem['sold_qty'] + cartItem['free_qty'];
            if(cartItem['mrp'] == 0.0) {
              cartItem['mrp'] = (stockItem['mrp'] as num?)?.toDouble() ?? (stockItem['price'] as num?)?.toDouble() ?? 0.0;
            }
          }
      }
    }

    if(mounted) {
      setState(() {
        _allItems = items;
        _filteredItems = items;
        _invoiceNo = inv;
      });
    }
  }

  void _fetchCustomerDetails(String mobile) async {
    final cust = await DBHelper.getCustomerByMobile(mobile);
    if (cust != null) {
      setState(() {
        if(cust['title'] != null && _titles.contains(cust['title'])) {
          _selectedTitle = cust['title'];
        }
        _nameCtrl.text = cust['name'] ?? '';
        _gstinCtrl.text = cust['gstin'] ?? '';
        _addressCtrl.text = cust['address'] ?? '';
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(Lang.t('w_found')), 
        duration: Duration(milliseconds: 800),
        backgroundColor: Colors.green,
      ));
    }
  }

  Future<void> _pickDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030),
    );
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_selectedDate));
      if (pickedTime != null) {
        setState(() {
          _selectedDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
        });
      }
    }
  }

  void _addToCartDialog(Map<String, dynamic> item) async {
    final List<Map<String, dynamic>> subs =
        await DBHelper.getSubstitutes((item['name'] ?? '').toString());
    if (!mounted) return;
    TextEditingController qtyCtrl = TextEditingController(text: "");
    TextEditingController freeQtyCtrl = TextEditingController(text: "0");
    
    double initialRate = (item['wholesale_price'] != null && item['wholesale_price'] > 0) ? item['wholesale_price'] : item['price'];
    
    double mrp = 0.0;
    if (item['mrp'] != null && (item['mrp'] as num) > 0) {
      mrp = (item['mrp'] as num).toDouble();
    } else {
      mrp = (item['price'] as num).toDouble();
    }
    
    TextEditingController rateCtrl = TextEditingController(text: initialRate.toString());
    int availableStock = item['quantity'];

    // FEFO: all batches of this product with stock, earliest expiry first
    List<Map<String, dynamic>> batches = DBHelper.sortBatchesFEFO(
      _allItems.where((b) =>
        b['name'] == item['name'] && _availFor(b) > 0
      ).toList()
    );
    if (batches.isEmpty) batches = [item];
    Map<String, dynamic> selectedBatch = batches.firstWhere(
      (b) => b['id'] == item['id'], orElse: () => batches.first);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("MRP: ₹$mrp | Stock: $availableStock", style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: ((selectedBatch['id'] as num?)?.toInt()) ?? 0,
              decoration: const InputDecoration(
                labelText: Lang.t('w_batch'),
                border: OutlineInputBorder(), isDense: true),
              items: batches.map((b) {
                return DropdownMenuItem<int>(
                  value: ((b['id'] as num?)?.toInt()) ?? 0,
                  child: Text(
                    "${b['batch'] ?? '-'} • Exp ${b['expiryDate'] ?? '-'} • ${_availFor(b)}",
                    style: const TextStyle(fontSize: 12)),
                );
              }).toList(),
              onChanged: (v) {
                setD(() {
                  selectedBatch = batches.firstWhere(
                    (b) => (((b['id'] as num?)?.toInt()) ?? 0) == v,
                    orElse: () => batches.first);
                  double br = ((selectedBatch['wholesale_price'] as num?)?.toDouble()) ?? 0.0;
                  if (br <= 0) br = (((selectedBatch['price'] as num?)?.toDouble()) ?? 0.0);
                  rateCtrl.text = br.toString();
                });
              },
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
                    Text(Lang.t('w_salt'),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.green)),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 110),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            ...subs.take(4).map((s) => InkWell(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    final List<Map<String, dynamic>> sb =
                                        List<Map<String, dynamic>>.from(
                                            s['batches'] as List);
                                    if (sb.isNotEmpty) {
                                      _addToCartDialog(sb.first);
                                    }
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
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
                Expanded(child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, autofocus: true, decoration: InputDecoration(labelText: Lang.t('w_qty'), border: OutlineInputBorder()), inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: freeQtyCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: Lang.t('w_free'), border: OutlineInputBorder()), inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
            ]),
            const SizedBox(height: 10),
            TextField(controller: rateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: Lang.t('w_rate'), border: OutlineInputBorder(), prefixText: "₹")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Lang.t('cancel'))),
          ElevatedButton(
            onPressed: () {
              int qty = int.tryParse(qtyCtrl.text) ?? 0;
              int free = int.tryParse(freeQtyCtrl.text) ?? 0;
              double rate = double.tryParse(rateCtrl.text) ?? 0.0;

              if (qty <= 0) return;

              // FEFO allocation starting from the selected batch
              int startIdx = batches.indexWhere((b) => b['id'] == selectedBatch['id']);
              if (startIdx < 0) startIdx = 0;
              int remQty = qty, remFree = free;
              final List<Map<String, dynamic>> alloc = [];
              for (int bi = startIdx; bi < batches.length && (remQty + remFree) > 0; bi++) {
                final b = batches[bi];
                int avail = _availFor(b);
                if (avail <= 0) continue;
                int takeQ = remQty <= avail ? remQty : avail;
                avail -= takeQ;
                remQty -= takeQ;
                int takeF = remFree <= avail ? remFree : avail;
                remFree -= takeF;
                if (takeQ + takeF > 0) {
                  alloc.add({'row': b, 'q': takeQ, 'f': takeF});
                }
              }
              if ((remQty + remFree) > 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(Lang.t('w_nostock')), backgroundColor: Colors.red));
                return;
              }

              setState(() {
                for (var a in alloc) {
                  final b = a['row'] as Map<String, dynamic>;
                  final int q = a['q'] as int;
                  final int f = a['f'] as int;
                  double bMrp = (((b['mrp'] as num?)?.toDouble()) ?? 0.0);
                  if (bMrp <= 0) bMrp = (((b['price'] as num?)?.toDouble()) ?? rate);
                  int bId = ((b['id'] as num?)?.toInt()) ?? -2;
                  // Merge with existing line of same batch if present
                  int exIdx = _cart.indexWhere((c) => (((c['id'] as num?)?.toInt()) ?? -1) == bId);
                  if (exIdx >= 0) {
                    _cart[exIdx]['sold_qty'] = ((_cart[exIdx]['sold_qty'] as num).toInt()) + q;
                    _cart[exIdx]['free_qty'] = ((_cart[exIdx]['free_qty'] as num).toInt()) + f;
                    _cart[exIdx]['price'] = rate;
                    _cart[exIdx]['total'] = ((_cart[exIdx]['sold_qty'] as num).toInt()) * rate;
                  } else {
                    _cart.add({
                      'id': b['id'],
                      'name': b['name'],
                      'batch': b['batch'] ?? '-',
                      'mrp': bMrp,
                      'price': rate,
                      'cost': (((b['wholesale_price'] as num?)?.toDouble()) ?? 0.0),
                      'gst_percent': b['gst_percent'] ?? 0,
                      'sold_qty': q,
                      'free_qty': f,
                      'max_qty': (((b['quantity'] as num?)?.toInt()) ?? 0),
                      'total': q * rate,
                      'expiryDate': b['expiryDate'] ?? '-',
                      'type': b['type'] ?? '-'
                    });
                  }
                }
                _searchCtrl.clear();
                _filteredItems = _allItems;
              });
              Navigator.pop(ctx);
            },
            child: Text(Lang.t('add')),
          )
        ],
        ),
      ),
    );
  }

  // Edit cart item dialog
  void _editCartItem(int index) {
    final item = _cart[index];
    TextEditingController qtyCtrl = TextEditingController(text: item['sold_qty'].toString());
    TextEditingController freeQtyCtrl = TextEditingController(text: item['free_qty'].toString());
    TextEditingController rateCtrl = TextEditingController(text: item['price'].toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("MRP: ₹${item['mrp']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
                Expanded(child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, autofocus: true, decoration: InputDecoration(labelText: Lang.t('w_qty'), border: OutlineInputBorder()), inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: freeQtyCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: Lang.t('w_free'), border: OutlineInputBorder()), inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
            ]),
            const SizedBox(height: 10),
            TextField(controller: rateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: Lang.t('w_rate'), border: OutlineInputBorder(), prefixText: "₹")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Lang.t('cancel'))),
          ElevatedButton(
            onPressed: () {
              int qty = int.tryParse(qtyCtrl.text) ?? 0;
              int free = int.tryParse(freeQtyCtrl.text) ?? 0;
              double rate = double.tryParse(rateCtrl.text) ?? 0.0;

              if (qty <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('w_qty0')), backgroundColor: Colors.red));
                return;
              }

              setState(() {
                _cart[index]['sold_qty'] = qty;
                _cart[index]['free_qty'] = free;
                _cart[index]['price'] = rate;
                _cart[index]['total'] = qty * rate;
              });
              Navigator.pop(ctx);
            },
            child: Text(Lang.t('update')),
          )
        ],
      ),
    );
  }

  Map<String, dynamic> _calculateBill() {
    double grossTotal = 0.0;
    double totalGST = 0.0;
    double discPercent = double.tryParse(_discountCtrl.text) ?? 0.0;

    for(var item in _cart) {
      double rate = item['price'];
      int qty = item['sold_qty'];
      int gstRate = item['gst_percent'] ?? 0;

      double taxable = rate * qty;
      double discount = (taxable * discPercent) / 100;
      taxable -= discount;

      double gstAmt = (taxable * gstRate) / 100;
      
      grossTotal += (rate * qty);
      totalGST += gstAmt;
    }

    double discountAmt = (grossTotal * discPercent) / 100;
    double taxableTotal = grossTotal - discountAmt;
    double netAmount = taxableTotal + totalGST;
    
    return {
      'sub_total': grossTotal,
      'discount': discountAmt,
      'taxable': taxableTotal,
      'gst_amount': totalGST,
      'net_amount': netAmount,
      'round_off': netAmount.roundToDouble()
    };
  }

  // --- PREVIEW FUNCTION ---
  void _previewBill() {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('w_empty'))));
      return;
    }
    final calc = _calculateBill();
    String customerDisplayName = "$_selectedTitle ${_nameCtrl.text.trim()}";
    
    Map<String, dynamic> billData = {
      'invoice_no': _invoiceNo,
      'customer_name': customerDisplayName,
      'mobile': _mobileCtrl.text,
      'date': DateFormat('dd/MM/yyyy HH:mm').format(_selectedDate),
      'sub_total': calc['sub_total'],
      'discount': calc['discount'],
      'gst_percent': 0, 
      'gst_amount': calc['gst_amount'],
      'net_amount': calc['round_off'], 
      'payment_mode': _isUdhaar ? 'Udhaar' : 'Cash',
      'bill_type': 'Wholesale',
      'customer_gstin': _gstinCtrl.text.trim(),
      'customer_address': _addressCtrl.text.trim(),
      
      // 🔥 PASS DOCTOR NAME FOR PDF 🔥
      'doctor_name': _doctorCtrl.text.trim(),
    };

    Navigator.push(context, MaterialPageRoute(
      builder: (context) => ViewBillScreen(billData: billData, items: _cart)
    ));
  }

  // --- SAVE FUNCTION ---
  void _generateBill() async {
    if (_cart.isEmpty || _nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(Lang.t('w_add')),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _isSaving = true);
    
    try {
      print("Starting bill save...");
      
      // Delete old bill if editing
      if (_isEditMode && widget.editBillData != null) {
        print("Deleting old bill for edit mode...");
        await DBHelper.deleteBillWithRestoration(
          widget.editBillData!['id'],
          widget.editBillData!['mobile'] ?? '',
          (widget.editBillData!['net_amount'] as num?)?.toDouble() ?? 0.0,
          widget.editBillData!['payment_mode'] ?? 'Cash'
        );
      } else if (!_manualInv) {
        // For new bills, auto-generate only if user didn't set manually
        _invoiceNo = await DBHelper.getNewInvoiceNo();
      }

      // Calculate totals
      final calc = _calculateBill();
      String customerDisplayName = "$_selectedTitle ${_nameCtrl.text.trim()}";

      // Prepare bill data
      Map<String, dynamic> billData = {
        'invoice_no': _invoiceNo,
        'customer_name': customerDisplayName, 
        'mobile': _mobileCtrl.text,
        'date': DateFormat('dd/MM/yyyy HH:mm').format(_selectedDate),
        'sub_total': calc['sub_total'],
        'discount': calc['discount'],
        'gst_percent': 0,
        'gst_amount': calc['gst_amount'],
        'net_amount': calc['round_off'], 
        'payment_mode': _isUdhaar ? 'Udhaar' : 'Cash',
        'bill_type': 'Wholesale', 
        'customer_gstin': _gstinCtrl.text.trim(), 
        'customer_address': _addressCtrl.text.trim(),
        
        // 🔥 SAVE DOCTOR NAME 🔥
        'doctor_name': _doctorCtrl.text.trim(),
      };

      // Prepare items for database
      List<Map<String, dynamic>> itemsForDB = _cart.map((item) {
        return {
          'stock_id': item['id'],
          'name': item['name'],
          'batch': item['batch'] ?? '',
          'qty': item['sold_qty'],
          'free_qty': item['free_qty'] ?? 0,
          'price': item['price'],
          'mrp': item['mrp'] ?? 0,
          'cost_rate': item['cost'] ?? 0,
          'total': item['total'] ?? 0,
          'gst_percent': item['gst_percent'] ?? 0,
          'expiryDate': item['expiryDate'] ?? '',
          'type': item['type'] ?? '',
        };
      }).toList();

      print("Saving bill to database...");
      await DBHelper.saveBill(billData, itemsForDB);
      print("Bill saved successfully!");
      
      if (!mounted) return;
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEditMode ? Lang.t('w_updated') : Lang.t('w_saved')),
        backgroundColor: Colors.green,
      ));
      
      if (!mounted) return;
      
      // Navigate to ViewBillScreen for printing
      print("Navigating to ViewBillScreen...");
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (context) => ViewBillScreen(billData: billData, items: _cart)
      ));
      
    } catch (e) {
      print("Error saving bill: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Error: ${e.toString()}"),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _runFilter(String keyword) {
    if (keyword.isEmpty) {
      setState(() => _filteredItems = _allItems);
    } else {
      setState(() {
        _filteredItems = _allItems.where((item) => item['name'].toLowerCase().contains(keyword.toLowerCase())).toList();
      });
    }
  }

  /// Hardware scanner / keyboard Enter: barcode exact match = instant add.
  void _onSearchSubmit() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    final row = await DBHelper.getItemByBarcode(q);
    if (row != null) {
      try {
        final match = _allItems.firstWhere((b) => b['id'] == row['id']);
        _searchCtrl.clear();
        _runFilter('');
        _addToCartDialog(match);
      } catch (_) {}
    }
  }

  Future<void> _editInvoiceNo() async {
    final c = TextEditingController(text: _invoiceNo);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(Lang.t('inv_edit')),
        content: TextField(
          controller: c,
          decoration: InputDecoration(hintText: Lang.t('inv_hint')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Lang.t('cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: Text(Lang.t('save'))),
        ],
      ),
    );
    if (v == null) return;
    if (v.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Lang.t('inv_empty')), backgroundColor: Colors.red));
      return;
    }
    final excludeId = _isEditMode && widget.editBillData != null
        ? ((widget.editBillData!['id'] as num?)?.toInt())
        : null;
    if (await DBHelper.invoiceNoExists(v, excludeId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Lang.t('inv_dup')), backgroundColor: Colors.red));
      return;
    }
    if (!mounted) return;
    setState(() {
      _invoiceNo = v;
      _manualInv = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final calc = _calculateBill();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEditMode ? Lang.t('w_edit') : Lang.t('w_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("Inv: $_invoiceNo", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        backgroundColor: const Color(0xFFFF6F00),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            tooltip: Lang.t('inv_edit'),
            onPressed: _editInvoiceNo,
          ),
          InkWell(
            onTap: _pickDateTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(DateFormat('dd-MMM').format(_selectedDate), style: const TextStyle(fontSize: 12, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Container(
        color: Colors.grey.shade100,
        child: Column(
          children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Customer Input Form - Stylish Card
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    height: _isSearchFocused ? 0 : null,
                    child: _isSearchFocused
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepOrange.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6F00).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.person, color: Color(0xFFFF6F00), size: 20),
                            ),
                            const SizedBox(width: 10),
                            Text(Lang.t('w_cust'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: _mobileCtrl, keyboardType: TextInputType.phone, maxLength: 10, 
                              decoration: InputDecoration(
                                labelText: "Mobile", counterText: "", isDense: true, 
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.phone, size: 18),
                              ),
                            )),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(controller: _gstinCtrl, 
                              decoration: InputDecoration(
                                labelText: "GSTIN", isDense: true, 
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.badge, size: 18),
                              ),
                            )),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: DropdownButton<String>(
                                value: _selectedTitle,
                                underline: Container(),
                                items: _titles.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                                onChanged: (val) => setState(() => _selectedTitle = val!),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(controller: _nameCtrl, 
                              decoration: InputDecoration(
                                labelText: Lang.t('w_party'), isDense: true, 
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.business, size: 18),
                              ),
                            )),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 🔥🔥 DOCTOR NAME FIELD 🔥🔥
                        TextField(controller: _doctorCtrl, 
                          decoration: InputDecoration(
                            labelText: Lang.t('w_doctor'), isDense: true, 
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.local_hospital, size: 18),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥

                        TextField(controller: _addressCtrl, 
                          decoration: InputDecoration(
                            labelText: Lang.t('w_address'), isDense: true, 
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.location_on, size: 18),
                          ),
                        ),
                      ],
                    ),
                          ),
                  ),
                  
                  const SizedBox(height: 16),

                  // Search Bar - Modern Style
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepOrange.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _runFilter,
                      onSubmitted: (_) => _onSearchSubmit(),
                      onTap: () => setState(() => _isSearchFocused = true),
                      decoration: InputDecoration(
                        hintText: Lang.t('w_search'),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFFFF6F00)),
                        suffixIcon: _isSearchFocused
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.check_circle, color: Colors.green),
                                    onPressed: () {
                                      setState(() => _isSearchFocused = false);
                                      FocusScope.of(context).unfocus();
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.grey),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _runFilter('');
                                      setState(() => _isSearchFocused = false);
                                      FocusScope.of(context).unfocus();
                                    },
                                  ),
                                ],
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),

                  // Medicine List - Shows when search is focused
                  if (_isSearchFocused)
                    Container(
                      height: 250,
                      margin: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        itemCount: _filteredItems.length,
                        itemBuilder: (ctx, i) {
                          final item = _filteredItems[i];
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF6F00).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.medication, color: Colors.orange.shade700, size: 20),
                              ),
                              title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (item['quantity'] as int) > 10 ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text("${Lang.t('w_stock')}: ${item['quantity']}", 
                                      style: TextStyle(fontSize: 11, color: (item['quantity'] as int) > 10 ? Colors.green : Colors.red)),
                                  ),
                                  const SizedBox(width: 8),
                                  Text("B:${item['batch'] ?? '-'}", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                  const SizedBox(width: 8),
                                  Text("₹${item['price']}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF6F00),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.add, color: Colors.white, size: 16),
                              ),
                              onTap: () => _addToCartDialog(item),
                            ),
                          );
                        }
                      )
                    ),

                  const SizedBox(height: 20),
                  
                  // Cart Section - Animated
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    height: _isSearchFocused ? 0 : null,
                    child: _isSearchFocused
                        ? const SizedBox.shrink()
                        : Column(
                            children: [
                              // Cart Header
                              if (_cart.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.shopping_cart, color: Colors.deepPurple, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Text(Lang.t('w_cart'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6F00),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text("${_cart.length} ${Lang.t('w_items')}", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Cart List - Beautiful Cards
                  ..._cart.map((item) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.deepOrange.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6F00).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.medication, color: Colors.orange.shade700, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A1A1A))),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          _buildChip("MRP: ₹${item['mrp'].toStringAsFixed(1)}", Colors.grey.shade600),
                                          const SizedBox(width: 6),
                                          _buildChip("Rate: ₹${item['price'].toStringAsFixed(1)}", Colors.green),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text("₹${item['total'].toStringAsFixed(2)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFFF6F00))),
                                    const SizedBox(height: 4),
                                    Text("${item['sold_qty']} + ${item['free_qty']} ${Lang.t('pu_free')}", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Divider(color: Colors.grey.shade200),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    _buildChip("GST: ${item['gst_percent']}%", Colors.blue.shade100, Colors.blue.shade700),
                                    if (item['batch'] != null && item['batch'].toString().isNotEmpty && item['batch'] != '-') ...[
                                      const SizedBox(width: 6),
                                      _buildChip("Batch: ${item['batch']}", Colors.grey.shade200, Colors.grey.shade700),
                                    ],
                                  ],
                                ),
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: () => _editCartItem(_cart.indexOf(item)),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Icon(Icons.edit, color: Colors.blue.shade600, size: 16),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => setState(() => _cart.removeAt(_cart.indexOf(item))),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Icon(Icons.close, color: Colors.red.shade600, size: 16),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Summary Panel - Glassmorphism Style
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: _isSearchFocused ? 0 : null,
            child: _isSearchFocused
                ? const SizedBox.shrink()
                : Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Summary Rows
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildSummaryRow("Gross Amount", "₹${calc['sub_total'].toStringAsFixed(2)}", Colors.grey.shade600),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.discount, color: Colors.red, size: 16),
                              ),
                              const SizedBox(width: 8),
                              Text(Lang.t('w_disc'), style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                            ],
                          ),
                          SizedBox(
                            width: 70,
                            child: TextField(
                              controller: _discountCtrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.end,
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.red.shade300)),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      _buildSummaryRow("Taxable Amount", "₹${calc['taxable'].toStringAsFixed(2)}", null, true),
                      const SizedBox(height: 6),
                      _buildSummaryRow("GST Total", "₹${calc['gst_amount'].toStringAsFixed(2)}", Colors.blue.shade700),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _isUdhaar = !_isUdhaar),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _isUdhaar ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _isUdhaar ? Colors.red : Colors.green, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Icon(_isUdhaar ? Icons.credit_card : Icons.money, color: _isUdhaar ? Colors.red : Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Text(_isUdhaar ? Lang.t('w_credit') : Lang.t('w_cash'), 
                              style: TextStyle(color: _isUdhaar ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(Lang.t('w_net'), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        Text("₹${calc['round_off'].toStringAsFixed(0)}", 
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFFFF6F00))),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previewBill,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Color(0xFFFF6F00), width: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(Lang.t('w_preview'), style: TextStyle(color: Color(0xFFFF6F00), fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _generateBill,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6F00),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 5,
                        ),
                        child: _isSaving 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.print, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(_isEditMode ? Lang.t('w_update') : Lang.t('w_saveprint'), 
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
                ),
          )
        ],
      ),
      ),
    );
  }

  Widget _buildChip(String text, Color bgColor, [Color? textColor]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: textColor ?? Colors.grey.shade700, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildSummaryRow(String label, String value, Color? valueColor, [bool isBold = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: Colors.grey[700])),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.bold, color: valueColor ?? Colors.black)),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
        ],
      ),
    );
  }
}
