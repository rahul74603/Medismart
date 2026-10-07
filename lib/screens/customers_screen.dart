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
import '../db_helper.dart';
import '../services/whatsapp_helper.dart';
import 'prescription_screen.dart';
import '../services/lang_service.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Map<String, dynamic>> _allCustomers = [];
  List<Map<String, dynamic>> _filteredCustomers = [];
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  void _loadCustomers() async {
    final data = await DBHelper.getAllCustomers();
    if(mounted) {
      setState(() {
        _allCustomers = data;
        _filteredCustomers = data;
        _isLoading = false;
      });
    }
  }

  void _runFilter(String keyword) {
    if (keyword.isEmpty) {
      setState(() => _filteredCustomers = _allCustomers);
    } else {
      setState(() {
        _filteredCustomers = _allCustomers.where((c) =>
          c['name'].toLowerCase().contains(keyword.toLowerCase()) ||
          c['mobile'].contains(keyword)
        ).toList();
      });
    }
  }

  // --- 1. RECEIVE PAYMENT LOGIC ---
  void _showPaymentDialog(Map<String, dynamic> customer) {
    final amountCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("${Lang.t('cu_pay')}: ${customer['name']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${Lang.t('cu_bal')}: ₹${customer['total_due'].toStringAsFixed(2)}", 
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                color: customer['total_due'] > 0 ? Colors.red : Colors.green
              )
            ),
            const SizedBox(height: 15),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: Lang.t('cu_amount'), border: OutlineInputBorder(), prefixIcon: Icon(Icons.currency_rupee)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: remarkCtrl,
              decoration: InputDecoration(labelText: Lang.t('cu_remark'), border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Lang.t('cancel'))),
          ElevatedButton(
            onPressed: () async {
              double amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount <= 0) return;

              double newBalance = customer['total_due'] - amount; 
              await (await DBHelper.database).update('customers', {'total_due': newBalance}, where: "id = ?", whereArgs: [customer['id']]);

              await (await DBHelper.database).insert('customer_ledger', {
                'mobile': customer['mobile'],
                'date': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                'description': remarkCtrl.text.isEmpty ? "Cash Payment Received" : "Payment: ${remarkCtrl.text}",
                'debit': 0.0,
                'credit': amount,
                'balance': newBalance
              });

              Navigator.pop(ctx);
              _loadCustomers();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('cu_updated')), backgroundColor: Colors.green));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            child: Text(Lang.t('cu_receive')),
          )
        ],
      ),
    );
  }

  // --- 2. PDF GENERATION LOGIC (FIXED CASTING ERRORS) ---
  Future<Uint8List> _generateLedgerBytes(Map<String, dynamic> customer) async {
    final db = await DBHelper.database;
    final ledger = await db.query('customer_ledger', where: "mobile = ?", whereArgs: [customer['mobile']], orderBy: "id DESC");
    final shopDetails = await DBHelper.getShopDetails();

    final pdf = pw.Document();
    
    double finalDue = (customer['total_due'] as num).toDouble();
    PdfColor finalColor = finalDue > 0 ? PdfColors.red : PdfColors.green;
    String finalStatus = finalDue > 0 ? "Total Due (Udhaar)" : "Advance Balance";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                child: pw.Column(children: [
                   pw.Text(shopDetails['shop_name'] ?? "MY SHOP", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20)),
                   pw.Text("Customer Ledger Statement", style: const pw.TextStyle(fontSize: 14)),
                ])
              ),
              pw.SizedBox(height: 10),
              
              // Customer Info
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("Customer: ${customer['name']}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text("Mobile: ${customer['mobile']}"),
              ]),
              pw.Divider(),

              // --- TABLE WITH FIXED CASTING ---
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2), 
                  1: const pw.FlexColumnWidth(4), 
                  2: const pw.FlexColumnWidth(2), 
                  3: const pw.FlexColumnWidth(2), 
                  4: const pw.FlexColumnWidth(2), 
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.black),
                    children: [
                      _pCell("Date", color: PdfColors.white, isBold: true),
                      _pCell("Description", color: PdfColors.white, isBold: true),
                      _pCell("Debit (Bill)", color: PdfColors.white, isBold: true),
                      _pCell("Credit (Paid)", color: PdfColors.white, isBold: true),
                      _pCell("Balance", color: PdfColors.white, isBold: true),
                    ]
                  ),
                  // Table Rows
                  ...ledger.map((entry) {
                    // FIXED: Explicit casting using (as num).toDouble()
                    double debit = (entry['debit'] as num?)?.toDouble() ?? 0.0;
                    double credit = (entry['credit'] as num?)?.toDouble() ?? 0.0;
                    double balance = (entry['balance'] as num?)?.toDouble() ?? 0.0;
                    
                    return pw.TableRow(
                      children: [
                        _pCell(entry['date'].toString()), // Cast to String
                        _pCell(entry['description'].toString()), // Cast to String
                        
                        // Debit (Red if > 0)
                        _pCell(debit > 0 ? debit.toStringAsFixed(2) : "-", color: debit > 0 ? PdfColors.red : PdfColors.black),
                        
                        // Credit (Green if > 0)
                        _pCell(credit > 0 ? credit.toStringAsFixed(2) : "-", color: credit > 0 ? PdfColors.green : PdfColors.black),
                        
                        _pCell(balance.toStringAsFixed(2)),
                      ]
                    );
                  }).toList()
                ]
              ),
              
              pw.Spacer(),
              
              // --- FINAL AMOUNT ---
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: finalColor, width: 2)),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, 
                  children: [
                     pw.Text(finalStatus, style: pw.TextStyle(fontSize: 14, color: finalColor)),
                     pw.Text("Rs. ${finalDue.abs().toStringAsFixed(2)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18, color: finalColor))
                  ]
                )
              ),
              
              pw.SizedBox(height: 10),
              pw.Text("Generated on: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
            ]
          );
        }
      )
    );
    return pdf.save();
  }

  // Helper for PDF Cells
  pw.Widget _pCell(String text, {PdfColor color = PdfColors.black, bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text, 
        style: pw.TextStyle(color: color, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: 10)
      )
    );
  }

  // --- 3. VIEW PDF ---
  void _viewLedger(Map<String, dynamic> customer) async {
    Navigator.push(context, MaterialPageRoute(
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: Text("${customer['name']} ${Lang.t('cu_ledger')}"), backgroundColor: Colors.teal, foregroundColor: Colors.white),
        body: PdfPreview(
          build: (format) => _generateLedgerBytes(customer),
        ),
      )
    ));
  }

  // --- 4. SHARE PDF ---
  void _shareLedger(Map<String, dynamic> customer) async {
    final bytes = await _generateLedgerBytes(customer);
    final output = await getTemporaryDirectory();
    final file = File("${output.path}/Ledger_${customer['mobile']}.pdf");
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: "Ledger for ${customer['name']}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Lang.t('cu_title')), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _runFilter,
              decoration: const InputDecoration(
                hintText: Lang.t('cu_search'),
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                filled: true, fillColor: Colors.white
              ),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator()) 
              : _filteredCustomers.isEmpty 
                ? Center(child: Text(Lang.t('cu_empty'))) 
                : ListView.builder(
                    itemCount: _filteredCustomers.length,
                    itemBuilder: (ctx, i) {
                      final cust = _filteredCustomers[i];
                      double due = (cust['total_due'] as num).toDouble();
                      Color statusColor = due > 0 ? Colors.red : (due < 0 ? Colors.green : Colors.grey);
                      String statusText = due > 0 ? "${Lang.t('cu_due')}: ₹${due.toStringAsFixed(2)}" : (due < 0 ? "${Lang.t('cu_adv')}: ₹${(-due).toStringAsFixed(2)}" : Lang.t('cu_settled'));

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.teal.shade50,
                            child: Text(cust['name'][0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          title: Text(cust['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(cust['mobile']),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(width: 10),
                              
                              // --- THREE DOTS MENU ---
                              PopupMenuButton(
                                onSelected: (val) {
                                  if (val == 'pay') _showPaymentDialog(cust);
                                  if (val == 'view') _viewLedger(cust);
                                  if (val == 'share') _shareLedger(cust);
                                  if (val == 'remind') WhatsAppHelper.sendUdhaarReminder(context, cust);
                                  if (val == 'rx') Navigator.push(context, MaterialPageRoute(builder: (_) => PrescriptionScreen(mobile: (cust['mobile'] ?? '').toString(), customerName: (cust['name'] ?? '').toString())));
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(value: 'pay', child: Row(children: [Icon(Icons.payment, color: Colors.green), SizedBox(width: 10), Text(Lang.t('cu_menu_pay'))])),
                                  PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility, color: Colors.blue), SizedBox(width: 10), Text(Lang.t('cu_menu_view'))])),
                                  PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share, color: Colors.orange), SizedBox(width: 10), Text(Lang.t('cu_menu_share'))])),
                                  PopupMenuItem(value: 'rx', child: Row(children: [Icon(Icons.medical_services, color: Colors.purple), SizedBox(width: 10), Text(Lang.t('cu_menu_rx'))])),
                                  if (due > 0)
                                    PopupMenuItem(value: 'remind', child: Row(children: [Icon(Icons.chat, color: Colors.green), SizedBox(width: 10), Text(Lang.t('cu_menu_remind'))])),
                                ]
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
    );
  }
}