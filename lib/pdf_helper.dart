import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'db_helper.dart';
import 'services/app_prefs.dart';

class PDFHelper {
  
  // 🔥 SAFETY FUNCTIONS (No Changes) 🔥
  static double _safeVal(dynamic value) {
    try {
      if (value == null) return 0.0;
      if (value is int) return value.toDouble();
      if (value is double) return value;
      return double.tryParse(value.toString()) ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  static int _safeInt(dynamic value) {
    try {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      return int.tryParse(value.toString().split('.')[0]) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // --- INVOICE GENERATOR ---
  static Future<File> generateBill({
    required Map<String, dynamic> billData, 
    required List<Map<String, dynamic>> items
  }) async {
    final pdf = pw.Document();
    final shop = await DBHelper.getShopDetails();
    
    String shopName = shop['shop_name'] ?? "MY MEDICAL STORE";
    String address = shop['address'] ?? "";
    String gstin = shop['gstin'] ?? "";
    String phone = shop['phone'] ?? "";
    String dlNo = shop['dl_no'] ?? "";

    // UPI QR (Settings): uploaded shop QR image, else auto-generated UPI QR.
    final upiId = await AppPrefs.getUpiId();
    pw.MemoryImage? qrImg;
    try {
      final qp = await AppPrefs.getQrPath();
      if (qp.isNotEmpty) {
        final qf = File(qp);
        if (await qf.exists()) qrImg = pw.MemoryImage(await qf.readAsBytes());
      }
    } catch (_) {}

    // --- TAX CALCULATION (Same as Old) ---
    double totalTaxableCalc = 0.0;
    double totalGstCalc = 0.0;

    for (var item in items) {
      double rate = _safeVal(item['price'] ?? item['rate']);
      int qty = _safeInt(item['sold_qty'] ?? item['qty']);
      int gstRate = _safeInt(item['gst_percent']);
      double rowTaxable = rate * qty;
      double rowGstAmt = (rowTaxable * gstRate) / 100;

      totalTaxableCalc += rowTaxable;
      totalGstCalc += rowGstAmt;
    }

    double discountVal = _safeVal(billData['discount']);
    double netAmountVal = _safeVal(billData['net_amount']);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(15),
        
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 5),
            child: pw.Text("Page ${context.pageNumber} of ${context.pagesCount} | Computer Generated Invoice", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          );
        },

        build: (pw.Context context) {
          return [
            // 1. HEADER
            pw.Center(child: pw.Text(shopName.toUpperCase(), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.black))),
            pw.SizedBox(height: 5),
            pw.Center(child: pw.Column(children: [
              if(dlNo.isNotEmpty || gstin.isNotEmpty) pw.Text((dlNo.isNotEmpty ? "DL: $dlNo" : "") + (dlNo.isNotEmpty && gstin.isNotEmpty ? " | " : "") + (gstin.isNotEmpty ? "GSTIN: $gstin" : ""), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              if(address.isNotEmpty || phone.isNotEmpty) pw.Text((address.isNotEmpty ? address : "") + (address.isNotEmpty && phone.isNotEmpty ? " | " : "") + (phone.isNotEmpty ? "Ph: $phone" : ""), style: pw.TextStyle(fontSize: 10)),
            ])),
            pw.SizedBox(height: 15),

            // 2. CUSTOMER DETAILS (🔥 Dr. Name Added Here 🔥)
            pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1), borderRadius: pw.BorderRadius.circular(5)),
              padding: const pw.EdgeInsets.all(10),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text("Inv No: ${billData['invoice_no']}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.SizedBox(height: 2),
                    pw.Text("Date: ${billData['date']}", style: const pw.TextStyle(fontSize: 10)),
                  ])),
                  pw.SizedBox(width: 10),
                  pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text("Customer: ${billData['customer_name']}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    
                    // 👇👇 DOCTOR NAME ADDED HERE 👇👇
                    pw.Text("Dr. Name: ${billData['doctor_name'] ?? 'Self'}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)), 
                    
                    if((billData['customer_address'] ?? '').toString().trim().isNotEmpty) pw.Text("Addr: ${billData['customer_address']}", style: const pw.TextStyle(fontSize: 9)),
                    if((billData['customer_gstin'] ?? '').toString().trim().isNotEmpty) pw.Text("GSTIN: ${billData['customer_gstin']}", style: const pw.TextStyle(fontSize: 9)),
                  ])),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // 3. ITEMS TABLE
            pw.Table.fromTextArray(
              border: pw.TableBorder.all(width: 0.5, color: PdfColors.black),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.black),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignments: {
                0: pw.Alignment.centerLeft, 1: pw.Alignment.center, 2: pw.Alignment.center,
                3: pw.Alignment.center, 4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight,
                6: pw.Alignment.center, 7: pw.Alignment.center, 8: pw.Alignment.centerRight
              },
              headers: ['Item', 'Batch', 'Exp', 'Type', 'MRP', 'Rate', 'Qty', 'GST%', 'Total'],
              data: items.map((item) {
                double rate = _safeVal(item['price'] ?? item['rate']);
                double mrp = _safeVal(item['mrp']);
                int qty = _safeInt(item['sold_qty'] ?? item['qty']);
                int gst = _safeInt(item['gst_percent']);
                double total = _safeVal(item['total']);
                if(total == 0) total = (rate * qty) + ((rate * qty * gst)/100);
                
                String qtyText = "$qty";
                int free = _safeInt(item['free_qty']);
                if(free > 0) qtyText += "+$free";

                return [
                  (item['name'] ?? item['item_name'] ?? 'Item').toString().toUpperCase(),
                  item['batch'] ?? '-',
                  item['expiryDate'] ?? item['exp_date'] ?? '-',
                  item['type'] ?? item['item_type'] ?? '-',
                  mrp.toStringAsFixed(2),
                  rate.toStringAsFixed(2),
                  qtyText,
                  "$gst%",
                  total.toStringAsFixed(2)
                ];
              }).toList(),
            ),

            // 🔥🔥 UPDATED TOTAL SECTION WITH GAP 🔥🔥
            pw.SizedBox(height: 90), // Table ke baad 90px ka gap (Jaisa aapne maanga)
            pw.Divider(thickness: 1, color: PdfColors.grey), // Beech me divider line
            pw.SizedBox(height: 50), // Line ke baad thoda aur gap

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left Side: Tax Info
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text("Tax Summary:", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Taxable Amt: Rs.${totalTaxableCalc.toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 8)),
                  pw.Text("Total GST: Rs.${totalGstCalc.toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 10),
                  pw.Text("Terms & Conditions:", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text("1. Goods once sold will not be taken back.", style: const pw.TextStyle(fontSize: 7)),
                  pw.Text("2. Subject to local jurisdiction.", style: const pw.TextStyle(fontSize: 7)),
                ]),

                // Right Side: Grand Total Box
                pw.Container(
                  width: 180,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1.5),
                    borderRadius: pw.BorderRadius.circular(5),
                    color: PdfColors.grey100, // Total box me halka background color
                  ),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    if(discountVal > 0)
                      _footerRow("Discount", -discountVal, color: PdfColors.red),
                    
                    pw.Text("GRAND TOTAL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text("Rs. ${netAmountVal.toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                  ])
                )
              ]
            ),
            // UPI QR footer (addition only — layout untouched)
            if (upiId.isNotEmpty || qrImg != null) ...[
              pw.SizedBox(height: 12),
              pw.Center(
                child: qrImg != null
                    ? pw.Image(qrImg, width: 110, height: 110)
                    : pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(shopName)}&am=${netAmountVal.toStringAsFixed(2)}&cu=INR',
                        width: 110,
                        height: 110,
                      ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text("Scan to Pay (UPI)", style: const pw.TextStyle(fontSize: 9))),
              if (upiId.isNotEmpty)
                pw.Center(child: pw.Text(upiId, style: const pw.TextStyle(fontSize: 9))),
            ],
          ];
        }
      )
    );
    final output = await getTemporaryDirectory();
    final file = File("${output.path}/Invoice_${billData['invoice_no']}.pdf");
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _footerRow(String label, double amount, {PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, color: color)),
          pw.Text("Rs.${amount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: color)),
        ]
      )
    );
  }

  // --- LEDGER PDF (Same as Old) ---
  static Future<File> generateLedgerPDF({
    required String customerName, required String mobile, required List<Map<String, dynamic>> ledgerEntries, required double totalDue,
  }) async {
    final pdf = pw.Document();
    final shop = await DBHelper.getShopDetails();
    String shopName = shop['shop_name'] ?? "MY MEDICAL STORE";

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (pw.Context context) {
        return [
          pw.Text("LEDGER STATEMENT", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text("$shopName\nCustomer: $customerName | Mob: $mobile"),
          pw.Divider(),
          pw.Table.fromTextArray(
            headers: ['Date', 'Description', 'Debit', 'Credit', 'Balance'],
            data: ledgerEntries.map((e) => [
              e['date'] ?? '', e['description'] ?? '', 
              _safeVal(e['debit']).toStringAsFixed(2), _safeVal(e['credit']).toStringAsFixed(2), _safeVal(e['balance']).toStringAsFixed(2)
            ]).toList()
          ),
          pw.SizedBox(height: 20),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text("Total Due: Rs.${totalDue.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
        ];
      }
    ));
    final output = await getTemporaryDirectory();
    final file = File("${output.path}/Ledger_$mobile.pdf");
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}