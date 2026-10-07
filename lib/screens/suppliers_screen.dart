import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart'; // 📞 CALL & SMS KE LIYE ZARURI
import '../db_helper.dart';
import 'purchase_screen.dart';
import 'purchase_history_screen.dart';
import 'expiry_claim_screen.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  void _loadSuppliers() async {
    final data = await DBHelper.getSuppliers();
    if(mounted) {
      setState(() {
        _suppliers = data;
        _isLoading = false;
      });
    }
  }

  // --- 📞 NEW: CALL FUNCTION ---
  Future<void> _makePhoneCall(String? mobile) async {
    if (mobile == null || mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No mobile number found")));
      return;
    }
    final Uri launchUri = Uri(scheme: 'tel', path: mobile);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch dialer")));
    }
  }

  // --- 💬 NEW: SMS FUNCTION ---
  Future<void> _sendSms(String? mobile) async {
    if (mobile == null || mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No mobile number found")));
      return;
    }
    final Uri launchUri = Uri(scheme: 'sms', path: mobile);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch SMS")));
    }
  }

  // --- 1. ADD / EDIT SUPPLIER ---
  void _showSupplierForm({Map<String, dynamic>? supplier}) {
    final nameCtrl = TextEditingController(text: supplier?['name']);
    final companyCtrl = TextEditingController(text: supplier?['company']);
    final mobileCtrl = TextEditingController(text: supplier?['mobile']);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(supplier == null ? "Add Supplier" : "Edit Supplier"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Supplier Name", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 10),
            TextField(controller: companyCtrl, decoration: const InputDecoration(labelText: "Company / Agency", border: OutlineInputBorder(), prefixIcon: Icon(Icons.business))),
            const SizedBox(height: 10),
            TextField(controller: mobileCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Mobile", border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              
              Map<String, dynamic> data = {
                'name': nameCtrl.text,
                'company': companyCtrl.text,
                'mobile': mobileCtrl.text,
                'gstin': '', // Optional
                'address': '' // Optional
              };

              if (supplier == null) {
                await DBHelper.addSupplier(data);
              } else {
                await (await DBHelper.database).update('suppliers', data, where: "id = ?", whereArgs: [supplier['id']]);
              }
              Navigator.pop(ctx);
              _loadSuppliers();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            child: const Text("SAVE"),
          )
        ],
      ),
    );
  }

  // --- 2. ADD TRANSACTION (PURCHASE / PAYMENT) ---
  void _showTransactionDialog(Map<String, dynamic> supplier, String type) {
    // type: 'Purchase' (Bill Aaya - Credit) or 'Payment' (Paisa Diya - Debit)
    final amountCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == 'Purchase' ? "New Purchase Bill" : "Payment Out"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             Text(type == 'Purchase' ? "Adding Bill Amount to Payable" : "Reducing Balance (Payment Given)", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
             const SizedBox(height: 15),
             TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount (₹)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.currency_rupee)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: remarkCtrl,
              decoration: InputDecoration(labelText: type == 'Purchase' ? "Bill No / Invoice No" : "Remark / Cheque No", border: const OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              double amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount <= 0) return;

              // Type Casting for Balance
              double currentBal = (supplier['balance'] as num?)?.toDouble() ?? 0.0;
              double newBal = type == 'Purchase' ? (currentBal + amount) : (currentBal - amount);

              // Update Supplier Master
              await (await DBHelper.database).update('suppliers', {'balance': newBal}, where: "id = ?", whereArgs: [supplier['id']]);

              // Add to Ledger
              await (await DBHelper.database).insert('supplier_ledger', {
                'supplier_id': supplier['id'],
                'date': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                'description': remarkCtrl.text.isEmpty ? type : "${type}: ${remarkCtrl.text}",
                'debit': type == 'Payment' ? amount : 0.0,
                'credit': type == 'Purchase' ? amount : 0.0,
                'balance': newBal
              });

              Navigator.pop(ctx);
              _loadSuppliers();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Entry Saved!"), backgroundColor: Colors.green));
            },
            style: ElevatedButton.styleFrom(backgroundColor: type == 'Purchase' ? Colors.red : Colors.green, foregroundColor: Colors.white),
            child: Text(type.toUpperCase()),
          )
        ],
      ),
    );
  }

  // --- 3. GENERATE LEDGER PDF ---
  Future<Uint8List> _generateLedgerBytes(Map<String, dynamic> supplier) async {
    final db = await DBHelper.database;
    final ledger = await db.query('supplier_ledger', where: "supplier_id = ?", whereArgs: [supplier['id']], orderBy: "id DESC");
    final shopDetails = await DBHelper.getShopDetails();
    final pdf = pw.Document();

    double finalBalance = (supplier['balance'] as num?)?.toDouble() ?? 0.0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
               pw.Text(shopDetails['shop_name'] ?? "MY SHOP", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20)),
               pw.Text("Supplier Ledger Statement", style: const pw.TextStyle(fontSize: 14)),
               pw.Divider(),
               pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                 pw.Text("Supplier: ${supplier['name']} (${supplier['company']})", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                 pw.Text("Mobile: ${supplier['mobile']}"),
               ]),
               pw.SizedBox(height: 15),

               pw.TableHelper.fromTextArray(
                headers: ['Date', 'Description', 'Purchase (Cr)', 'Payment (Dr)', 'Balance'],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.black),
                data: ledger.map((e) {
                  double credit = (e['credit'] as num?)?.toDouble() ?? 0.0;
                  double debit = (e['debit'] as num?)?.toDouble() ?? 0.0;
                  double bal = (e['balance'] as num?)?.toDouble() ?? 0.0;

                  return [
                    e['date'],
                    e['description'],
                    credit > 0 ? credit.toString() : '-',
                    debit > 0 ? debit.toString() : '-',
                    bal.toString()
                  ];
                }).toList()
               ),
               
               pw.Spacer(),
               pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text("Net Payable: Rs. ${finalBalance.toStringAsFixed(2)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16))),
            ]
          );
        }
      )
    );
    return pdf.save();
  }

  void _viewLedger(Map<String, dynamic> s) async {
    Navigator.push(context, MaterialPageRoute(builder: (c) => Scaffold(
      appBar: AppBar(title: const Text("Supplier Ledger"), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: PdfPreview(build: (f) => _generateLedgerBytes(s))
    )));
  }

  void _shareLedger(Map<String, dynamic> s) async {
    final bytes = await _generateLedgerBytes(s);
    final output = await getTemporaryDirectory();
    final file = File("${output.path}/Supplier_${s['name']}.pdf");
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: "Supplier Ledger");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Supplier Management"), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : 
        _suppliers.isEmpty 
        ? const Center(child: Text("No Suppliers Added"))
        : ListView.builder(
            itemCount: _suppliers.length,
            itemBuilder: (ctx, i) {
              final s = _suppliers[i];
              double bal = (s['balance'] as num?)?.toDouble() ?? 0.0;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ExpansionTile(
                  leading: CircleAvatar(backgroundColor: Colors.brown.shade50, child: const Icon(Icons.local_shipping, color: Colors.brown)),
                  title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${s['company']} | Bal: ₹${bal.toStringAsFixed(0)}", style: TextStyle(color: bal > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(10),
                      // 👇👇 CHANGED Row to Wrap to accommodate new buttons properly 👇👇
                      child: Wrap(
                        spacing: 20, // Horizontal gap
                        runSpacing: 15, // Vertical gap
                        alignment: WrapAlignment.center,
                        children: [
                          // 🆕 CALL BUTTON
                          _actionBtn("Call", Icons.phone, Colors.indigo, () => _makePhoneCall(s['mobile'])),
                          // 🆕 MESSAGE BUTTON
                          _actionBtn("Msg", Icons.message, Colors.lightBlue, () => _sendSms(s['mobile'])),
                          
                          _actionBtn("Purchase", Icons.note_add, Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseScreen(supplierId: (s['id'] as num).toInt(), supplierName: s['name'].toString()))).then((_) => _loadSuppliers())),
                          _actionBtn("Bills", Icons.receipt_long, Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseHistoryScreen(supplierId: (s['id'] as num).toInt(), supplierName: s['name'].toString())))),
                          _actionBtn("Claims", Icons.fact_check, Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExpiryClaimScreen(supplierId: (s['id'] as num).toInt(), supplierName: s['name'].toString())))),
                          _actionBtn("Payment", Icons.payment, Colors.green, () => _showTransactionDialog(s, 'Payment')),
                          _actionBtn("Ledger", Icons.picture_as_pdf, Colors.blue, () => _viewLedger(s)),
                          _actionBtn("Share", Icons.share, Colors.orange, () => _shareLedger(s)),
                          _actionBtn("Edit", Icons.edit, Colors.grey, () => _showSupplierForm(supplier: s)),
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSupplierForm(),
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min, // Fix size
        children: [
          CircleAvatar(radius: 18, backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color, size: 18)),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 10))
        ],
      ),
    );
  }
}