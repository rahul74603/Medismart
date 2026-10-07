import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../db_helper.dart';
import '../pdf_helper.dart';
import 'billing_screen.dart';
import 'view_bill_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _bills = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  void _loadBills() async {
    final data = await DBHelper.getAllBills();
    if (mounted) {
      setState(() {
        _bills = data;
        _isLoading = false;
      });
    }
  }

  // 🔥 Safe Value Parser
  double _getSafeAmount(dynamic val) {
    if (val == null) return 0.0;
    try {
      return double.parse(val.toString());
    } catch (e) {
      return 0.0;
    }
  }

  void _deleteBill(Map<String, dynamic> bill) async {
    bool confirm = await showDialog(
      context: context, 
      builder: (c) => AlertDialog(
        title: const Text("Delete Bill?"),
        content: const Text("Stock will be restored."),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text("NO")),
          TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text("YES", style: TextStyle(color: Colors.red)))
        ]
      )
    ) ?? false;

    if(confirm) {
      await DBHelper.deleteBillWithRestoration(
        bill['id'], 
        bill['mobile'] ?? '', 
        _getSafeAmount(bill['net_amount']), 
        bill['payment_mode']
      );
      _loadBills();
    }
  }

  void _openPDF(Map<String, dynamic> bill) async {
    try {
      final items = await DBHelper.getBillItems(bill['id']);
      final File pdfFile = await PDFHelper.generateBill(billData: bill, items: items);
      
      if(await pdfFile.exists()) {
        await Share.shareXFiles([XFile(pdfFile.path)], text: "Invoice: ${bill['invoice_no']}");
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PDF Error")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _viewBill(Map<String, dynamic> bill) async {
    final items = await DBHelper.getBillItems(bill['id']);
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => ViewBillScreen(billData: bill, items: items)
    ));
  }

  void _editBill(Map<String, dynamic> bill) async {
    final items = await DBHelper.getBillItems(bill['id']);
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => BillingScreen(editBillData: bill, editItems: items)
    )).then((_) => _loadBills());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bill History"), backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : _bills.isEmpty 
          ? const Center(child: Text("No Bills Found"))
          : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _bills.length,
              itemBuilder: (ctx, i) {
                final bill = _bills[i];
                double amount = _getSafeAmount(bill['net_amount']); 

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(bill['customer_name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${bill['invoice_no']} | ${bill['date']}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("₹${amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                        const SizedBox(width: 5),
                        IconButton(
                          icon: const Icon(Icons.visibility, color: Colors.teal, size: 22),
                          onPressed: () => _viewBill(bill),
                          tooltip: "View Bill",
                        ),
                        IconButton(
                          icon: const Icon(Icons.share, color: Colors.deepOrange, size: 22),
                          onPressed: () => _openPDF(bill),
                          tooltip: "Share PDF",
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue, size: 22),
                          onPressed: () => _editBill(bill),
                          tooltip: "Edit Bill",
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 22),
                          onPressed: () => _deleteBill(bill),
                          tooltip: "Delete Bill",
                        ),
                      ]
                    ),
                  ),
                );
              },
            ),
    );
  }
}