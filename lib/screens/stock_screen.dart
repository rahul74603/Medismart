import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';

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
  final List<String> _medTypes = ['Tablet', 'Capsule', 'Syrup', 'Injection', 'Cream', 'Ointment', 'Drops', 'Strip', 'Suppotry', 'Other'];
  final List<int> _gstSlabs = [0, 5, 12, 18, 28]; 

  String _selectedType = 'Tablet';

  @override
  void initState() {
    super.initState();
    _refreshItems();
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

  // --- FORM LOGIC ---
  void _showForm({Map<String, dynamic>? item}) {
    final nameCtrl = TextEditingController(text: item?['name']);
    final chemicalCtrl = TextEditingController(text: item?['chemical'] ?? '');
    final batchCtrl = TextEditingController(text: item?['batch']);
    final rackCtrl = TextEditingController(text: item?['rack']);
    final qtyCtrl = TextEditingController(text: item?['quantity']?.toString());
    
    final priceCtrl = TextEditingController(text: item?['price']?.toString());
    final wholesaleCtrl = TextEditingController(text: item?['wholesale_price']?.toString() ?? '');
    
    final expiryCtrl = TextEditingController(text: item?['expiryDate']);
    final tabsPerStripCtrl = TextEditingController(text: "10"); 

    String currentType = item?['type'] ?? 'Tablet';
    if (!_medTypes.contains(currentType)) currentType = 'Tablet';
    _selectedType = currentType;

    int currentGST = item?['gst_percent'] ?? 0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool isStripSelected = _selectedType == 'Strip';

            void calculateWholesaleRate() {
              double mrp = double.tryParse(priceCtrl.text) ?? 0.0;
              if (mrp > 0) {
                double basicRate = mrp / (1 + (currentGST / 100));
                wholesaleCtrl.text = basicRate.toStringAsFixed(2);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(item == null ? "Add New Medicine" : "Edit Medicine", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInput(nameCtrl, "Medicine Name", "e.g. Dolo 650", Icons.medical_services),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: InputDecoration(
                        labelText: "Type",
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
                            const Text("💊 Strip Calculation", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
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

                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (val) => calculateWholesaleRate(),
                            decoration: InputDecoration(
                              labelText: isStripSelected ? "MRP (Per Strip)" : "MRP (Per Unit)",
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
                        labelText: "Basic Rate (Excl. Tax)",
                        hintText: "Auto Calculated",
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
                        labelText: "Expiry Date",
                        hintText: "Select Date",
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
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name is required!")));
                       return;
                    }
                    try {
                      int enteredQty = int.tryParse(qtyCtrl.text) ?? 0;
                      double enteredMRP = double.tryParse(priceCtrl.text) ?? 0.0;
                      double enteredWholesale = double.tryParse(wholesaleCtrl.text) ?? 0.0;
                      
                      int finalQty = enteredQty;
                      double finalPricePerUnit = enteredMRP;
                      double finalWholesalePerUnit = enteredWholesale;

                      if (_selectedType == 'Strip') {
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
                        'type': _selectedType == 'Strip' ? 'Tablet' : _selectedType,
                        'batch': batchCtrl.text,
                        'rack': rackCtrl.text,
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
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Item Saved Successfully!"), backgroundColor: Colors.green));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("SAVE ITEM", style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            );
          }
        );
      },
    );
  }

  void _deleteItem(int id) async {
    await DBHelper.deleteItem(id);
    _refreshItems();
  }

  Widget _buildInput(TextEditingController c, String label, String hint, IconData icon, {bool isNum = false}) {
    return TextField(
      controller: c,
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label, hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.deepOrange, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        filled: true, fillColor: Colors.grey.shade50, isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        title: Text("Stock Management", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
        centerTitle: true,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFF6D00), Color(0xFFFF9100)], begin: Alignment.topLeft, end: Alignment.bottomRight))),
        elevation: 5, iconTheme: const IconThemeData(color: Colors.white),
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
                hintText: "Search Name or Salt...",
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
            : _filteredItems.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade300), const Text("No Items found", style: TextStyle(color: Colors.grey))]))
              : ListView.builder(
                  padding: const EdgeInsets.all(10), // Comfortable Padding
                  itemCount: _filteredItems.length,
                  itemBuilder: (ctx, i) {
                    final item = _filteredItems[i];
                    Color cardColor = _getCardColor(item);
                    Color borderColor = _getBorderColor(item);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: cardColor, borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: borderColor, width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 8, offset: const Offset(0, 4))]
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10), 
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), shape: BoxShape.circle, border: Border.all(color: borderColor, width: 2)),
                              child: Text("${item['quantity']}", style: TextStyle(color: borderColor, fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min, // Important
                                children: [
                                  Text(item['name'], style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  if(item['chemical'] != null && item['chemical'].isNotEmpty)
                                    Text("(${item['chemical']})", style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                                  const SizedBox(height: 4), 
                                  
                                  // 🔥 FIXED: Replaced Wrap with Scrollable Row to prevent overflow
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        _badge("Rack: ${item['rack'] ?? '-'}", Colors.blue),
                                        const SizedBox(width: 4),
                                        _badge("Batch: ${item['batch'] ?? '-'}", Colors.teal),
                                        const SizedBox(width: 4),
                                        _badge("Exp: ${item['expiryDate']}", Colors.red),
                                        const SizedBox(width: 4),
                                        _badge("MRP: ₹${item['price']}", Colors.green),
                                        const SizedBox(width: 4),
                                        if(item['gst_percent'] != null) _badge("GST: ${item['gst_percent']}%", Colors.deepPurple),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => _showForm(item: item), constraints: const BoxConstraints()),
                                const SizedBox(height: 10),
                                IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _deleteItem(item['id']), constraints: const BoxConstraints()),
                              ],
                            )
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