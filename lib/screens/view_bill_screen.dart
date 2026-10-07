import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// 🔥 CORRECT IMPORT
import '../pdf_helper.dart'; 

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Invoice: ${widget.billData['invoice_no']}"),
        backgroundColor: Colors.deepOrange, 
        foregroundColor: Colors.white,
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