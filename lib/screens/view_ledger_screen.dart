import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../pdf_helper.dart';

class ViewLedgerScreen extends StatelessWidget {
  final Map<String, dynamic> customer;
  final List<Map<String, dynamic>> ledgerData;

  const ViewLedgerScreen({
    super.key,
    required this.customer,
    required this.ledgerData,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${customer['name']} Statement"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: PdfPreview(
        build: (format) async {
          // Ledger PDF Generate karega aur yahi dikhayega
          File file = await PDFHelper.generateLedgerPDF(
            customerName: customer['name'] ?? 'Customer',
            mobile: customer['mobile'] ?? '',
            ledgerEntries: ledgerData,
            totalDue: (customer['total_due'] as num?)?.toDouble() ?? 0.0,
          );
          return file.readAsBytes();
        },
        initialPageFormat: PdfPageFormat.a4,
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
        loadingWidget: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}