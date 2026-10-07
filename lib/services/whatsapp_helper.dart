import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../db_helper.dart';
import '../pdf_helper.dart';

/// WhatsApp integration via wa.me deep links (no extra package needed).
/// - Text messages (reminders, orders, claims) open directly in WhatsApp.
/// - Bill PDFs are shared via the system share sheet (user picks WhatsApp).
class WhatsAppHelper {
  /// Normalizes an Indian mobile number to wa.me format (e.g. 919876543210).
  /// Returns '' if the number is unusable.
  static String normalizeNumber(String? raw) {
    if (raw == null) return '';
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) return '91$digits';
    if (digits.length == 11 && digits.startsWith('0')) return '91${digits.substring(1)}';
    if (digits.length == 12 && digits.startsWith('91')) return digits;
    if (digits.length == 13 && digits.startsWith('091')) return digits.substring(1);
    return '';
  }

  static Future<bool> _openChat(String phone, String message) async {
    final url = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(url)) {
        return await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return false;
  }

  static void _noWhatsApp(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("WhatsApp nahi khul paya! Number ya WhatsApp check karo."),
        backgroundColor: Colors.red));
  }

  static void _badNumber(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Sahi 10-digit mobile number nahi hai!"),
        backgroundColor: Colors.red));
  }

  // ---------------- UDHAAR REMINDER ----------------

  /// 1-tap udhaar reminder to a customer on WhatsApp.
  static Future<void> sendUdhaarReminder(
      BuildContext context, Map<String, dynamic> customer) async {
    final phone = normalizeNumber((customer['mobile'] ?? '').toString());
    if (phone.isEmpty) {
      _badNumber(context);
      return;
    }
    final shop = await DBHelper.getShopDetails();
    final name = (customer['name'] ?? '').toString();
    final due = (((customer['total_due'] as num?)?.toDouble()) ?? 0.0);
    final shopName = ((shop['shop_name'] ?? '')).toString();
    final shopPhone = ((shop['phone'] ?? '')).toString();

    final msg = "Namaste $name ji! 🙏\n"
        "$shopName se suchna: aapka udhaar Rs.${due.toStringAsFixed(0)} baki hai.\n"
        "Kripya jald se jald jama karne ki kripa karein.\n\n"
        "Dhanyavad!\n- $shopName${shopPhone.isNotEmpty ? ', $shopPhone' : ''}";

    final ok = await _openChat(phone, msg);
    if (!ok && context.mounted) _noWhatsApp(context);
  }

  // ---------------- BILL PDF SHARE ----------------

  /// Shares a bill PDF via the share sheet (user picks WhatsApp contact).
  static Future<void> shareBillPdf(
      BuildContext context, Map<String, dynamic> billData,
      {List<Map<String, dynamic>>? items}) async {
    try {
      final lines = items ??
          await DBHelper.getBillItems((billData['id'] as num).toInt());
      final file =
          await PDFHelper.generateBill(billData: billData, items: lines);
      final shop = await DBHelper.getShopDetails();
      final shopName = ((shop['shop_name'] ?? '')).toString();
      await Share.shareXFiles([XFile(file.path)],
          text:
              "Bill ${billData['invoice_no']} - Rs.${((billData['net_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} ($shopName)");
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Share failed: $e"), backgroundColor: Colors.red));
      }
    }
  }

  // ---------------- SUPPLIER ORDER ----------------

  /// Sends a purchase order list to a supplier on WhatsApp.
  /// [lines]: [{name, qty}] — qty = order quantity.
  static Future<void> sendSupplierOrder(BuildContext context,
      Map<String, dynamic> supplier, List<Map<String, dynamic>> lines) async {
    final phone = normalizeNumber((supplier['mobile'] ?? '').toString());
    if (phone.isEmpty) {
      _badNumber(context);
      return;
    }
    if (lines.isEmpty) return;
    final shop = await DBHelper.getShopDetails();
    final shopName = ((shop['shop_name'] ?? '')).toString();
    final shopPhone = ((shop['phone'] ?? '')).toString();
    final supName = ((supplier['name'] ?? '')).toString();

    final buf = StringBuffer();
    buf.writeln("Namaste $supName ji! 🙏");
    buf.writeln("$shopName se ORDER:");
    buf.writeln();
    for (int i = 0; i < lines.length; i++) {
      buf.writeln("${i + 1}. ${lines[i]['name']} - ${lines[i]['qty']} pcs");
    }
    buf.writeln();
    buf.writeln("Kripya ye maal jald bhej dein.");
    buf.write("- $shopName${shopPhone.isNotEmpty ? ', $shopPhone' : ''}");

    final ok = await _openChat(phone, buf.toString());
    if (!ok && context.mounted) _noWhatsApp(context);
  }

  // ---------------- EXPIRY CLAIM ----------------

  /// Sends an expiry/short-expiry claim to a supplier on WhatsApp.
  /// [lines]: [{name, batch, expiry, qty, total}]
  static Future<void> sendExpiryClaim(
      BuildContext context,
      Map<String, dynamic> supplier,
      String claimNo,
      String date,
      List<Map<String, dynamic>> lines,
      double totalValue) async {
    final phone = normalizeNumber((supplier['mobile'] ?? '').toString());
    if (phone.isEmpty) {
      _badNumber(context);
      return;
    }
    if (lines.isEmpty) return;
    final shop = await DBHelper.getShopDetails();
    final shopName = ((shop['shop_name'] ?? '')).toString();
    final shopPhone = ((shop['phone'] ?? '')).toString();
    final supName = ((supplier['name'] ?? '')).toString();

    final buf = StringBuffer();
    buf.writeln("Namaste $supName ji! 🙏");
    buf.writeln("$shopName se EXPIRY CLAIM ($claimNo, $date):");
    buf.writeln();
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i];
      buf.writeln(
          "${i + 1}. ${l['name']} | B:${l['batch']} | Exp:${l['expiry']} | Qty:${l['qty']} | Rs.${(((l['total'] as num?)?.toDouble()) ?? 0).toStringAsFixed(0)}");
    }
    buf.writeln();
    buf.writeln("Total Claim Value: Rs.${totalValue.toStringAsFixed(0)}");
    buf.writeln("Kripya iska credit note de dein.");
    buf.write("- $shopName${shopPhone.isNotEmpty ? ', $shopPhone' : ''}");

    final ok = await _openChat(phone, buf.toString());
    if (!ok && context.mounted) _noWhatsApp(context);
  }

  // ---------------- CUSTOM MESSAGE ----------------

  /// Generic WhatsApp message to any 10-digit mobile (used by Refills etc).
  static Future<void> sendCustomMessage(
      BuildContext context, String mobile, String message) async {
    final phone = normalizeNumber(mobile);
    if (phone.isEmpty) {
      if (context.mounted) _badNumber(context);
      return;
    }
    final ok = await _openChat(phone, message);
    if (!ok && context.mounted) _noWhatsApp(context);
  }
}
