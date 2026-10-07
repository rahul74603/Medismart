import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../db_helper.dart';
import '../pdf_helper.dart';
import '../services/receipt_helper.dart';
import 'billing_screen.dart';
import 'retail_billing_screen.dart';
import 'sales_return_screen.dart';
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

  void _printReceipt(Map<String, dynamic> bill) async {
    try {
      final items = await DBHelper.getBillItems(bill['id']);
      await ReceiptHelper.printBillReceipt(billData: bill, items: items);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Print error: $e"), backgroundColor: Colors.orange),
        );
      }
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
    final type = (bill['bill_type'] ?? 'Wholesale').toString();
    if (type == 'Retail') {
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => RetailBillingScreen(
          editBillData: bill,
          editItems: List<Map<String, dynamic>>.from(items),
        )
      )).then((_) => _loadBills());
    } else {
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => BillingScreen(editBillData: bill, editItems: items)
      )).then((_) => _loadBills());
    }
  }

  void _returnBill(Map<String, dynamic> bill) {
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => SalesReturnScreen(billData: bill)
    )).then((_) => _loadBills());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bill History"),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_return),
            tooltip: "Sales Returns",
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const ReturnsHistoryScreen())),
          ),
        ],
      ),
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
                final type = (bill['bill_type'] ?? '').toString();

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(bill['customer_name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${bill['invoice_no']} | ${bill['date']}${type.isNotEmpty ? ' | $type' : ''}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("₹${amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                        const SizedBox(width: 5),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (val) {
                            if (val == 'view') _viewBill(bill);
                            if (val == 'receipt') _printReceipt(bill);
                            if (val == 'edit') _editBill(bill);
                            if (val == 'return') _returnBill(bill);
                            if (val == 'share') _openPDF(bill);
                            if (val == 'delete') _deleteBill(bill);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility, color: Colors.teal, size: 20), SizedBox(width: 10), Text("View Bill")])),
                            PopupMenuItem(value: 'receipt', child: Row(children: [Icon(Icons.receipt_long, color: Colors.brown, size: 20), SizedBox(width: 10), Text("Thermal Receipt")])),
                            PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, color: Colors.blue, size: 20), SizedBox(width: 10), Text("Edit Bill")])),
                            PopupMenuItem(value: 'return', child: Row(children: [Icon(Icons.assignment_return, color: Colors.deepPurple, size: 20), SizedBox(width: 10), Text("Sales Return")])),
                            PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share, color: Colors.deepOrange, size: 20), SizedBox(width: 10), Text("Share PDF")])),
                            PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 20), SizedBox(width: 10), Text("Delete Bill")])),
                          ],
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
