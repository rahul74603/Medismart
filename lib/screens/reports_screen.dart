import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db_helper.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // Date Range (Default: This Month)
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  
  // Stats
  double _totalSale = 0.0;
  double _totalCash = 0.0;
  double _totalUdhaar = 0.0;
  int _totalBills = 0;
  double _avgBillValue = 0.0;

  // Chart Data
  Map<String, double> _dailySales = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final data = await DBHelper.getAllBills();
    if(mounted) {
      setState(() {
        _applyDateFilter(data);
        _isLoading = false;
      });
    }
  }

  void _applyDateFilter(List<Map<String, dynamic>> allBills) {
    _totalSale = 0.0;
    _totalCash = 0.0;
    _totalUdhaar = 0.0;
    _totalBills = 0;
    _dailySales = {};

    List<Map<String, dynamic>> filtered = allBills.where((bill) {
      try {
        DateFormat format = DateFormat("dd/MM/yyyy");
        DateTime billDate = format.parse(bill['date'].toString().split(' ')[0]);
        DateTime start = DateTime(_startDate.year, _startDate.month, _startDate.day);
        DateTime end = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
        return billDate.isAfter(start.subtract(const Duration(seconds: 1))) && 
               billDate.isBefore(end.add(const Duration(seconds: 1)));
      } catch (e) {
        return false;
      }
    }).toList();

    for (var bill in filtered) {
      double net = (bill['net_amount'] as num?)?.toDouble() ?? 0.0;
      _totalSale += net;
      if (bill['payment_mode'] == 'Udhaar') {
        _totalUdhaar += net;
      } else {
        // Cash, UPI, Card... sab collected me
        _totalCash += net;
      }

      // Graph Data
      String dateKey = bill['date'].toString().split(' ')[0].substring(0, 5); // dd/MM
      _dailySales[dateKey] = (_dailySales[dateKey] ?? 0) + net;
    }

    _totalBills = filtered.length;
    _avgBillValue = _totalBills > 0 ? _totalSale / _totalBills : 0.0;
    
    // Sort Chart Data
    var sortedKeys = _dailySales.keys.toList()..sort((a, b) => a.compareTo(b));
    _dailySales = { for (var k in sortedKeys) k : _dailySales[k]! };

    setState(() {});
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          primaryColor: Colors.teal,
          colorScheme: const ColorScheme.light(primary: Colors.teal),
        ),
        child: child!,
      )
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        // Reload data from DB to apply filter (or keep local copy if optimized)
        _loadData(); 
      });
    }
  }

  // --- PDF REPORT ---
  Future<void> _generateReportPDF() async {
    final pdf = pw.Document();
    final shopDetails = await DBHelper.getShopDetails();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(shopDetails['shop_name'] ?? "MY SHOP", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24)),
              pw.Text("Executive Sales Report", style: const pw.TextStyle(fontSize: 16)),
              pw.Divider(),
              pw.Text("Duration: ${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}"),
              pw.SizedBox(height: 20),
              
              pw.Row(children: [
                _pdfBox("Total Revenue", _totalSale, PdfColors.blue),
                pw.SizedBox(width: 10),
                _pdfBox("Cash + UPI", _totalCash, PdfColors.green),
                pw.SizedBox(width: 10),
                _pdfBox("Udhaar Given", _totalUdhaar, PdfColors.red),
              ]),
              
              pw.SizedBox(height: 20),
              pw.Text("Summary:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Bullet(text: "Total Orders Processed: $_totalBills"),
              pw.Bullet(text: "Average Bill Value: Rs. ${_avgBillValue.toStringAsFixed(0)}"),
              pw.Bullet(text: "Cash Recovery Rate: ${(_totalSale > 0 ? (_totalCash/_totalSale)*100 : 0).toStringAsFixed(1)}%"),
              
              pw.Spacer(),
              pw.Text("Generated via MediSmart ERP", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
            ]
          );
        }
      )
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/Summary_Report.pdf");
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: "Summary Report");
  }

  pw.Widget _pdfBox(String title, double value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: color, width: 2), borderRadius: pw.BorderRadius.circular(5)),
        child: pw.Column(children: [
          pw.Text(title, style: const pw.TextStyle(fontSize: 10)),
          pw.Text("Rs. ${value.toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: color))
        ])
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    String dateRange = "${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM').format(_endDate)}";
    
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5), // Light Grey Background
      appBar: AppBar(
        title: const Text("Business Analytics"), 
        backgroundColor: Colors.white, 
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // --- 1. DATE FILTER PILL ---
            Center(
              child: GestureDetector(
                onTap: _pickDateRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.teal),
                      const SizedBox(width: 8),
                      Text(dateRange, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(width: 5),
                      const Icon(Icons.arrow_drop_down, color: Colors.grey)
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),

            if (_totalSale == 0) 
               const Padding(padding: EdgeInsets.all(40), child: Text("No Sales Data Found", style: TextStyle(color: Colors.grey)))
            else ...[

              // --- 2. HERO CARD (TOTAL SALE) ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 10))]
                ),
                child: Column(
                  children: [
                    const Text("TOTAL REVENUE", style: TextStyle(color: Colors.white70, letterSpacing: 1, fontSize: 12)),
                    const SizedBox(height: 5),
                    Text("₹${_totalSale.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 40)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                      child: Text("$_totalBills Orders Processed", style: const TextStyle(color: Colors.white, fontSize: 12)),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // --- 3. CASH vs UDHAAR (Visual Split) ---
              Row(
                children: [
                  Expanded(child: _buildInfoCard("Cash + UPI", _totalCash, Colors.green, FontAwesomeIcons.sackDollar)),
                  const SizedBox(width: 15),
                  Expanded(child: _buildInfoCard("Udhaar Given", _totalUdhaar, Colors.red, FontAwesomeIcons.bookOpen)),
                ],
              ),

              const SizedBox(height: 20),

              // --- 4. RECOVERY METER (Progress Bar) ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Recovery Health", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 15),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _totalSale > 0 ? _totalCash / _totalSale : 0,
                        minHeight: 15,
                        backgroundColor: Colors.red.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade400),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${(_totalSale > 0 ? (_totalCash/_totalSale)*100 : 0).toStringAsFixed(0)}% Recovered", style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                        Text("${(_totalSale > 0 ? (_totalUdhaar/_totalSale)*100 : 0).toStringAsFixed(0)}% Pending", style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    )
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // --- 5. SIMPLE GRAPH (Last 7 Days) ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Daily Trend", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _dailySales.entries.map((e) {
                        // Simple scaling: Max height 60px
                        double max = _dailySales.values.reduce((curr, next) => curr > next ? curr : next);
                        double h = (e.value / max) * 60;
                        return Column(
                          children: [
                            Container(
                              width: 8, height: h,
                              decoration: BoxDecoration(color: Colors.indigo.shade300, borderRadius: BorderRadius.circular(5)),
                            ),
                            const SizedBox(height: 5),
                            Text(e.key, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        );
                      }).toList(),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 30),
              
              // --- 6. ACTION BUTTON ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _generateReportPDF,
                  icon: const Icon(Icons.share, color: Colors.white),
                  label: const Text("SHARE SUMMARY REPORT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, double value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            radius: 20,
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(child: Text("₹${value.toStringAsFixed(0)}", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 20))),
        ],
      ),
    );
  }
}