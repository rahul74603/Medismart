import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import 'supplier_order_screen.dart';
import 'expiry_claim_screen.dart';
import '../services/staff_mode.dart';

class AlertsScreen extends StatefulWidget {
  final String alertType; // 'STOCK' or 'EXPIRY'
  const AlertsScreen({super.key, required this.alertType});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final data = await DBHelper.getItems();
    List<Map<String, dynamic>> tempFiltered = [];

    DateTime now = DateTime.now();
    DateTime warningDate = now.add(const Duration(days: 90)); 

    for (var item in data) {
      if (widget.alertType == 'STOCK') {
        // --- LOW STOCK LOGIC ---
        int qty = item['quantity'] ?? 0;
        int minStock = item['min_stock'] ?? 10;
        if (qty <= minStock) {
          tempFiltered.add(item);
        }
      } else if (widget.alertType == 'EXPIRY') {
        // --- EXPIRY LOGIC ---
        try {
          String expStr = item['expiryDate'];
          DateTime expiry = DateFormat('dd/MM/yyyy').parse(expStr);
          
          if (expiry.isBefore(now) || expiry.isBefore(warningDate)) {
            tempFiltered.add(item);
          }
        } catch (e) {
          print("Date Error: $e");
        }
      }
    }

    if(mounted) {
      setState(() {
        _allItems = data;
        _filteredItems = tempFiltered;
        _isLoading = false;
      });
    }
  }

  // --- 🎨 COLOR & STATUS LOGIC ---
  Map<String, dynamic> _getStatus(Map<String, dynamic> item) {
    // 1. LOW STOCK -> PURE GREEN 🟢
    if (widget.alertType == 'STOCK') {
      return {'color': Colors.green, 'text': 'Low Stock'};
    }
    
    // 2. EXPIRY LOGIC
    try {
      DateTime expiry = DateFormat('dd/MM/yyyy').parse(item['expiryDate']);
      DateTime now = DateTime.now();

      if (expiry.isBefore(now)) {
        // ALREADY EXPIRED -> RED 🔴
        return {'color': Colors.red, 'text': 'EXPIRED'};
      } else {
        // EXPIRING SOON -> YELLOW/AMBER 🟡
        return {'color': Colors.amber.shade700, 'text': 'Expiring Soon'};
      }
    } catch (e) {
      return {'color': Colors.grey, 'text': 'Invalid'};
    }
  }

  @override
  Widget build(BuildContext context) {
    // HEADER COLOR: Stock = Green, Expiry = Red
    String title = widget.alertType == 'STOCK' ? "Low Stock Alerts" : "Expiry Alerts";
    Color themeColor = widget.alertType == 'STOCK' ? Colors.green : Colors.red;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: themeColor,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      floatingActionButton: (!StaffMode.enabled && !_isLoading && _filteredItems.isNotEmpty)
          ? FloatingActionButton.extended(
              backgroundColor: themeColor,
              onPressed: () {
                if (widget.alertType == 'STOCK') {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SupplierOrderScreen()));
                } else {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ExpiryClaimScreen()));
                }
              },
              icon: Icon(
                  widget.alertType == 'STOCK'
                      ? FontAwesomeIcons.whatsapp
                      : Icons.fact_check,
                  color: Colors.white),
              label: Text(
                  widget.alertType == 'STOCK'
                      ? "Order on WhatsApp"
                      : "Claim Manager",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: themeColor))
          : _filteredItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      Text("No alerts found!", style: GoogleFonts.poppins(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: _filteredItems.length,
                  itemBuilder: (ctx, i) {
                    final item = _filteredItems[i];
                    final status = _getStatus(item); // Color fetch

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          border: Border(left: BorderSide(color: status['color'], width: 6)), // Thicker border
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                          child: Row(
                            children: [
                              // 1. QUANTITY CIRCLE
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: status['color'].withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    "${item['quantity']}",
                                    style: TextStyle(fontWeight: FontWeight.bold, color: status['color'], fontSize: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              
                              // 2. DETAILS (Using Column to prevent Overflow)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'], 
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    
                                    // WRAP USE KIYA HAI OVERFLOW HATANE KE LIYE
                                    Wrap(
                                      spacing: 10, // Horizontal space
                                      runSpacing: 4, // Vertical space if wrapped
                                      children: [
                                        _infoBadge(Icons.calendar_today, item['expiryDate']),
                                        _infoBadge(Icons.shelves, "Rack: ${item['rack']}"),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // 3. STATUS BADGE
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: status['color'],
                                  borderRadius: BorderRadius.circular(8)
                                ),
                                child: Text(
                                  status['text'], 
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  // Chota Badge banane ka function
  Widget _infoBadge(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: Colors.grey[800], fontSize: 12)),
      ],
    );
  }
}