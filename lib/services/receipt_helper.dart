import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../db_helper.dart';
import 'app_prefs.dart';

/// Thermal receipt printing (58mm / 80mm) via the system print dialog.
/// Works with any printer Android supports, including Bluetooth/USB thermal
/// printers paired through the manufacturer's print plugin (XPrinter, Epson...).
///
/// NOTE (future upgrade): for direct Bluetooth ESC/POS printing without a
/// system dialog, plug a BT-thermal package here behind these same methods.
class ReceiptHelper {
  static double _safeVal(dynamic v) {
    try {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  static int _safeInt(dynamic v) {
    try {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString().split('.')[0]) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static String _s(dynamic v) => v == null ? '' : v.toString();

  /// Prints a sale bill as a thermal receipt. Returns true if dialog opened.
  static Future<bool> printBillReceipt({
    required Map<String, dynamic> billData,
    required List<Map<String, dynamic>> items,
  }) async {
    final bytes = await buildBillReceiptBytes(billData: billData, items: items);
    final inv = _s(billData['invoice_no']);
    return await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Receipt_$inv',
    );
  }

  /// Prints a sales-return slip as a thermal receipt.
  static Future<bool> printReturnReceipt({
    required Map<String, dynamic> retData,
    required List<Map<String, dynamic>> items,
  }) async {
    final bytes = await buildReturnReceiptBytes(retData: retData, items: items);
    final no = _s(retData['return_no']);
    return await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Return_$no',
    );
  }

  // ---------------- BUILDERS ----------------

  /// Estimated receipt height (points) so the slip fits on one page
  /// without feeding excess blank paper.
  static double _receiptHeight({
    required int itemCount,
    required int widthMm,
    required bool hasQr,
    required bool hasTerms,
  }) {
    final perItem = widthMm == 58 ? 38.0 : 32.0;
    final h = 300.0 +
        itemCount * perItem +
        (hasQr ? 140.0 : 0.0) +
        (hasTerms ? 26.0 : 0.0);
    return h.clamp(250.0, 4000.0);
  }

  static Future<Uint8List> buildBillReceiptBytes({
    required Map<String, dynamic> billData,
    required List<Map<String, dynamic>> items,
  }) async {
    final shop = await DBHelper.getShopDetails();
    final widthMm = await AppPrefs.getReceiptWidth();
    final upiId = await AppPrefs.getUpiId();
    // Uploaded shop QR (Settings) — printed as-is; else auto UPI QR.
    pw.MemoryImage? qrImg;
    try {
      final qp = await AppPrefs.getQrPath();
      if (qp.isNotEmpty) {
        final qf = File(qp);
        if (await qf.exists()) qrImg = pw.MemoryImage(await qf.readAsBytes());
      }
    } catch (_) {}
    final double w = (widthMm == 58 ? 58 : 80) * PdfPageFormat.mm;
    final double h = _receiptHeight(
      itemCount: items.length,
      widthMm: widthMm,
      hasQr: upiId.isNotEmpty || qrImg != null,
      hasTerms: _s(shop['terms']).isNotEmpty,
    );

    final doc = pw.Document();
    final mono = pw.Font.courier();
    final monoBold = pw.Font.courierBold();

    pw.Widget divider() => pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Text(
            List.filled(widthMm == 58 ? 32 : 42, '-').join(),
            style: pw.TextStyle(font: mono, fontSize: 7),
          ),
        );

    pw.Widget kv(String k, String v, {bool bold = false}) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(k, style: pw.TextStyle(font: mono, fontSize: 8)),
            pw.Text(v,
                style: pw.TextStyle(
                    font: bold ? monoBold : mono, fontSize: 8)),
          ],
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat:
            PdfPageFormat(w, h, marginAll: 4 * PdfPageFormat.mm),
        build: (_) => [
          pw.Center(
            child: pw.Text(
              _s(shop['shop_name']).isEmpty
                  ? 'MEDICAL STORE'
                  : _s(shop['shop_name']).toUpperCase(),
              style: pw.TextStyle(
                  font: monoBold, fontSize: widthMm == 58 ? 11 : 13),
              textAlign: pw.TextAlign.center,
            ),
          ),
          if (_s(shop['address']).isNotEmpty)
            pw.Center(
                child: pw.Text(_s(shop['address']),
                    style: pw.TextStyle(font: mono, fontSize: 7.5),
                    textAlign: pw.TextAlign.center)),
          if (_s(shop['phone']).isNotEmpty)
            pw.Center(
                child: pw.Text('Ph: ${_s(shop['phone'])}',
                    style: pw.TextStyle(font: mono, fontSize: 7.5))),
          if (_s(shop['gstin']).isNotEmpty)
            pw.Center(
                child: pw.Text('GSTIN: ${_s(shop['gstin'])}',
                    style: pw.TextStyle(font: mono, fontSize: 7.5))),
          if (_s(shop['dl_no']).isNotEmpty)
            pw.Center(
                child: pw.Text('DL: ${_s(shop['dl_no'])}',
                    style: pw.TextStyle(font: mono, fontSize: 7.5))),
          divider(),
          kv('Bill No:', _s(billData['invoice_no']), bold: true),
          kv('Date:', _s(billData['date'])),
          kv('Customer:', _s(billData['customer_name'])),
          if (_s(billData['mobile']).isNotEmpty)
            kv('Mobile:', _s(billData['mobile'])),
          kv('Pay Mode:', _s(billData['payment_mode'])),
          divider(),
          // Header
          pw.Row(children: [
            pw.Expanded(
                flex: 5,
                child: pw.Text('Item',
                    style: pw.TextStyle(font: monoBold, fontSize: 8))),
            pw.Expanded(
                child: pw.Text('Qty',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(font: monoBold, fontSize: 8))),
            pw.Expanded(
                flex: 2,
                child: pw.Text('Rate',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(font: monoBold, fontSize: 8))),
            pw.Expanded(
                flex: 2,
                child: pw.Text('Amt',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(font: monoBold, fontSize: 8))),
          ]),
          divider(),
          ...items.map((it) {
            final name = _s(it['name'] ?? it['item_name']);
            final qty = _safeInt(it['sold_qty'] ?? it['qty']);
            final free = _safeInt(it['free_qty']);
            final rate = _safeVal(it['price'] ?? it['rate']);
            final total = _safeVal(it['total']);
            final batch = _s(it['batch']);
            final maxLen = widthMm == 58 ? 24 : 32;
            final shortName =
                name.length > maxLen ? '${name.substring(0, maxLen - 1)}…' : name;
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(children: [
                  pw.Expanded(
                      flex: 5,
                      child: pw.Text(shortName,
                          style: pw.TextStyle(font: mono, fontSize: 8))),
                  pw.Expanded(
                      child: pw.Text('$qty',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(font: mono, fontSize: 8))),
                  pw.Expanded(
                      flex: 2,
                      child: pw.Text(rate.toStringAsFixed(2),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(font: mono, fontSize: 8))),
                  pw.Expanded(
                      flex: 2,
                      child: pw.Text(total.toStringAsFixed(2),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(font: monoBold, fontSize: 8))),
                ]),
                if (batch.isNotEmpty && batch != '-')
                  pw.Text('  B:$batch${free > 0 ? '  Free:$free' : ''}',
                      style: pw.TextStyle(font: mono, fontSize: 6.5)),
                if ((batch.isEmpty || batch == '-') && free > 0)
                  pw.Text('  Free:$free',
                      style: pw.TextStyle(font: mono, fontSize: 6.5)),
              ],
            );
          }),
          divider(),
          kv('Sub Total:', 'Rs.${_safeVal(billData['sub_total']).toStringAsFixed(2)}'),
          if (_safeVal(billData['discount']) > 0)
            kv('Discount:', '-Rs.${_safeVal(billData['discount']).toStringAsFixed(2)}'),
          if (_safeVal(billData['gst_amount']) > 0)
            kv('GST:', 'Rs.${_safeVal(billData['gst_amount']).toStringAsFixed(2)}'),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('NET AMOUNT',
                  style: pw.TextStyle(font: monoBold, fontSize: 11)),
              pw.Text('Rs.${_safeVal(billData['net_amount']).toStringAsFixed(2)}',
                  style: pw.TextStyle(font: monoBold, fontSize: 11)),
            ],
          ),
          divider(),
          if (upiId.isNotEmpty || qrImg != null) ...[
            pw.Center(
              child: qrImg != null
                  ? pw.Image(qrImg, width: 90, height: 90)
                  : pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data:
                          'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(_s(shop['shop_name']))}&am=${_safeVal(billData['net_amount']).toStringAsFixed(2)}&cu=INR',
                      width: 90,
                      height: 90,
                    ),
            ),
            pw.Center(
                child: pw.Text('Scan to Pay (UPI)',
                    style: pw.TextStyle(font: mono, fontSize: 7.5))),
            if (upiId.isNotEmpty)
              pw.Center(
                  child: pw.Text(upiId,
                      style: pw.TextStyle(font: mono, fontSize: 7.5))),
            divider(),
          ],
          if (_s(shop['terms']).isNotEmpty)
            pw.Center(
                child: pw.Text(_s(shop['terms']),
                    style: pw.TextStyle(font: mono, fontSize: 6.5),
                    textAlign: pw.TextAlign.center)),
          pw.SizedBox(height: 4),
          pw.Center(
              child: pw.Text('Thank You! Visit Again',
                  style: pw.TextStyle(font: monoBold, fontSize: 8.5))),
          pw.Center(
              child: pw.Text('Powered by MediSmart',
                  style: pw.TextStyle(font: mono, fontSize: 6.5))),
        ],
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> buildReturnReceiptBytes({
    required Map<String, dynamic> retData,
    required List<Map<String, dynamic>> items,
  }) async {
    final shop = await DBHelper.getShopDetails();
    final widthMm = await AppPrefs.getReceiptWidth();
    final double w = (widthMm == 58 ? 58 : 80) * PdfPageFormat.mm;
    final double h = _receiptHeight(
      itemCount: items.length,
      widthMm: widthMm,
      hasQr: false,
      hasTerms: false,
    );

    final doc = pw.Document();
    final mono = pw.Font.courier();
    final monoBold = pw.Font.courierBold();

    pw.Widget divider() => pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Text(
            List.filled(widthMm == 58 ? 32 : 42, '-').join(),
            style: pw.TextStyle(font: mono, fontSize: 7),
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat:
            PdfPageFormat(w, h, marginAll: 4 * PdfPageFormat.mm),
        build: (_) => [
          pw.Center(
            child: pw.Text(
              _s(shop['shop_name']).isEmpty
                  ? 'MEDICAL STORE'
                  : _s(shop['shop_name']).toUpperCase(),
              style: pw.TextStyle(
                  font: monoBold, fontSize: widthMm == 58 ? 11 : 13),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Center(
              child: pw.Text('** SALES RETURN **',
                  style: pw.TextStyle(font: monoBold, fontSize: 10))),
          divider(),
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Return No:',
                    style: pw.TextStyle(font: mono, fontSize: 8)),
                pw.Text(_s(retData['return_no']),
                    style: pw.TextStyle(font: monoBold, fontSize: 8)),
              ]),
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Date:',
                    style: pw.TextStyle(font: mono, fontSize: 8)),
                pw.Text(_s(retData['date']),
                    style: pw.TextStyle(font: mono, fontSize: 8)),
              ]),
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Bill:',
                    style: pw.TextStyle(font: mono, fontSize: 8)),
                pw.Text(_s(retData['invoice_no']),
                    style: pw.TextStyle(font: mono, fontSize: 8)),
              ]),
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Customer:',
                    style: pw.TextStyle(font: mono, fontSize: 8)),
                pw.Text(_s(retData['customer_name']),
                    style: pw.TextStyle(font: mono, fontSize: 8)),
              ]),
          divider(),
          ...items.map((it) {
            final name = _s(it['name'] ?? it['item_name']);
            final qty = _safeInt(it['qty']);
            final rate = _safeVal(it['rate']);
            final total = _safeVal(it['total']);
            return pw.Row(children: [
              pw.Expanded(
                  flex: 5,
                  child: pw.Text(
                      name.length > 26 ? '${name.substring(0, 25)}…' : name,
                      style: pw.TextStyle(font: mono, fontSize: 8))),
              pw.Expanded(
                  child: pw.Text('$qty',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(font: mono, fontSize: 8))),
              pw.Expanded(
                  flex: 2,
                  child: pw.Text(rate.toStringAsFixed(2),
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(font: mono, fontSize: 8))),
              pw.Expanded(
                  flex: 2,
                  child: pw.Text(total.toStringAsFixed(2),
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(font: monoBold, fontSize: 8))),
            ]);
          }),
          divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('REFUND',
                  style: pw.TextStyle(font: monoBold, fontSize: 11)),
              pw.Text(
                  'Rs.${_safeVal(retData['total_amount']).toStringAsFixed(2)}',
                  style: pw.TextStyle(font: monoBold, fontSize: 11)),
            ],
          ),
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Mode:',
                    style: pw.TextStyle(font: mono, fontSize: 8)),
                pw.Text(
                    _s(retData['refund_mode']) == 'Udhaar'
                        ? 'Adjusted in Udhaar'
                        : 'Cash Refund',
                    style: pw.TextStyle(font: mono, fontSize: 8)),
              ]),
          divider(),
          pw.Center(
              child: pw.Text('Powered by MediSmart',
                  style: pw.TextStyle(font: mono, fontSize: 6.5))),
        ],
      ),
    );
    return doc.save();
  }
}
