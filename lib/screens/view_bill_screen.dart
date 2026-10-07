import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
// 🔥 CORRECT IMPORT
import '../pdf_helper.dart';
import '../services/receipt_helper.dart';
import '../services/whatsapp_helper.dart';
import '../services/lang_service.dart';

class ViewBillScreen extends StatefulWidget {
  final Map<String, dynamic> billData;
  final List<Map<String, dynamic>> items;

  const ViewBillScreen({super.key, required this.billData, required this.items});

  @override
  State<ViewBillScreen> createState() => _ViewBillScreenState();
}

class _ViewBillScreenState extends State<ViewBillScreen> {

  Future<File> _generatePdf() async {
    // Calling the SAFE generator
    return await PDFHelper.generateBill(
      billData: widget.billData,
      items: widget.items
    );
  }

  Future<void> _whatsappBill() async {
    await WhatsAppHelper.shareBillPdf(context, widget.billData,
        items: widget.items);
  }

  Future<void> _printReceipt() async {
    try {
      await ReceiptHelper.printBillReceipt(
        billData: widget.billData,
        items: widget.items,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Print error: $e"), backgroundColor: Colors.orange),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Invoice: ${widget.billData['invoice_no']}"),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat),
            tooltip: Lang.t('vb_wa'),
            onPressed: _whatsappBill,
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: Lang.t('vb_print'),
            onPressed: _printReceipt,
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) async {
          final file = await _generatePdf();
          return file.readAsBytes();
        },
        canChangePageFormat: false,
        canChangeOrientation: false,
      ),
    );
  }
}
