import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../db_helper.dart';
import '../pdf_helper.dart';
import 'view_ledger_screen.dart'; // <--- NEW IMPORT
import '../services/lang_service.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const CustomerDetailsScreen({super.key, required this.customer});

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  List<Map<String, dynamic>> _ledger = [];
  double _currentDue = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  void _loadLedger() async {
    final data = await DBHelper.getCustomerLedger(widget.customer['mobile']);
    final freshCust = await DBHelper.getCustomerByMobile(widget.customer['mobile']);
    
    setState(() {
      _ledger = data;
      _currentDue = freshCust?['due_balance'] ?? 0.0;
      _isLoading = false;
    });
  }

  // --- 1. RECEIVE PAYMENT ---
  void _showPaymentDialog() {
    final amtCtrl = TextEditingController();
    final remarkCtrl = TextEditingController(text: "Cash Payment");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lang.t('cu_menu_pay')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amtCtrl, keyboardType: TextInputType.number, autofocus: true, decoration: InputDecoration(labelText: Lang.t('cd_amount'), border: OutlineInputBorder(), prefixIcon: Icon(Icons.currency_rupee))),
            const SizedBox(height: 10),
            TextField(controller: remarkCtrl, decoration: InputDecoration(labelText: Lang.t('cd_remarks'), border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Lang.t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              double amt = double.tryParse(amtCtrl.text) ?? 0.0;
              if (amt > 0) {
                await DBHelper.addPayment(widget.customer['mobile'], amt, remarkCtrl.text);
                Navigator.pop(ctx);
                _loadLedger(); 
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('cd_received')), backgroundColor: Colors.green));
              }
            },
            child: Text(Lang.t('cu_receive')),
          )
        ],
      ),
    );
  }

  // --- 2. GENERATE PDF & SHARE (UPDATED) ---
  void _shareLedger() async {
    if (_ledger.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('cd_notx'))));
      return;
    }

    final freshCust = await DBHelper.getCustomerByMobile(widget.customer['mobile']);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(Lang.t('cd_stmt'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 20),

            // 1. VIEW PDF (IN-APP) - NEW UPDATE
            ListTile(
              leading: const Icon(Icons.remove_red_eye, color: Colors.blue),
              title: Text(Lang.t('cd_view')),
              onTap: () {
                Navigator.pop(ctx); // Close Menu
                // Open Viewer
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => ViewLedgerScreen(
                    customer: freshCust!, 
                    ledgerData: _ledger
                  )
                ));
              },
            ),

            // 2. SHARE PDF (WHATSAPP)
            ListTile(
              leading: const Icon(FontAwesomeIcons.whatsapp, color: Colors.green),
              title: Text(Lang.t('cd_wa')),
              onTap: () async { 
                Navigator.pop(ctx); 
                // Share ke liye file generate karni padegi
                final File pdfFile = await PDFHelper.generateLedgerPDF(
                  customerName: freshCust!['name'] ?? 'Customer',
                  mobile: widget.customer['mobile'] ?? '',
                  ledgerEntries: _ledger,
                  totalDue: (freshCust!['total_due'] as num?)?.toDouble() ?? 0.0,
                );
                Share.shareXFiles([XFile(pdfFile.path)], text: "Account Statement for ${widget.customer['name']}"); 
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.customer['name'], style: const TextStyle(fontSize: 16)), Text(widget.customer['mobile'], style: const TextStyle(fontSize: 12))]),
        backgroundColor: Colors.teal, foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf), 
            tooltip: "Download/Share Report",
            onPressed: _shareLedger // Connect Button
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: _currentDue > 0 ? Colors.red.shade50 : Colors.green.shade50,
            child: Column(
              children: [
                const Text("Current Balance Due", style: TextStyle(color: Colors.grey)),
                Text("₹${_currentDue.toStringAsFixed(0)}", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _currentDue > 0 ? Colors.red : Colors.green)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _ledger.isEmpty 
              ? const Center(child: Text("No Transaction History"))
              : ListView.builder(
                  itemCount: _ledger.length,
                  itemBuilder: (ctx, i) {
                    final item = _ledger[i];
                    bool isBill = item['type'] == 'BILL';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isBill ? Colors.red.shade100 : Colors.green.shade100,
                        child: Icon(isBill ? Icons.arrow_upward : Icons.arrow_downward, color: isBill ? Colors.red : Colors.green, size: 18),
                      ),
                      title: Text(item['desc'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(item['date'].toString().substring(0, 16)),
                      trailing: Text(
                        isBill ? "- ₹${item['debit'].toStringAsFixed(0)}" : "+ ₹${item['credit'].toStringAsFixed(0)}",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isBill ? Colors.red : Colors.green),
                      ),
                    );
                  },
                ),
          )
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5, offset: const Offset(0, -2))]),
        child: ElevatedButton.icon(
          onPressed: _showPaymentDialog,
          icon: const Icon(FontAwesomeIcons.handHoldingDollar, color: Colors.white),
          label: const Text("RECEIVE PAYMENT", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 15)),
        ),
      ),
    );
  }
}