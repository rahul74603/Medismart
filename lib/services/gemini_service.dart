import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_prefs.dart';
import 'lang_service.dart';
import 'qr_medicine_parser.dart';

/// Optional AI fallback for QR codes the local parser can't crack.
/// Uses the user's own Gemini API key (saved in Settings). No key / no net = skipped.
/// NEVER throws - returns null on any failure.
class GeminiService {
  static const String _model = 'gemini-2.0-flash';

  /// Raw QR text in -> normalized QrMedicineData out (or null).
  /// AI output is re-validated through the local parser (kills AI garbage).
  static Future<QrMedicineData?> tryQr(String rawText) async {
    try {
      final key = await AppPrefs.getGeminiKey();
      final clean = rawText.trim();
      if (key.isEmpty || clean.isEmpty) return null;
      final clipped = clean.length > 1200 ? clean.substring(0, 1200) : clean;
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$key');
      const promptHead =
          'You are a medicine label reader. From this medicine QR code text, extract fields. '
          'Rules: dates as DD/MM/YYYY (month-year only -> day 01; 2-digit year -> 20xx); '
          'MRP as number only without Rs or symbols; empty string if a field is missing. '
          'Reply ONLY this JSON object, no other text: '
          '{"batch":"","expiry":"","mfg":"","mrp":"","name":"","gtin":""}\nQR text: """';
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': '$promptHead$clipped"""'}
                  ]
                }
              ],
              'generationConfig': {
                'responseMimeType': 'application/json',
                'temperature': 0
              }
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      final parts = data['candidates']?[0]?['content']?['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final txt = (parts[0]['text'] ?? '').toString();
      if (txt.isEmpty) return null;
      final obj = jsonDecode(txt);
      if (obj is! Map) return null;
      String g(String k) => (obj[k] ?? '').toString();
      final recheck = QrMedicineParser.parse(
          'Batch: ${g('batch')}\nEXP: ${g('expiry')}\nMFG: ${g('mfg')}\nMRP: ${g('mrp')}\nName: ${g('name')}\nGTIN: ${g('gtin')}');
      if (recheck.isEmpty) return null;
      return recheck;
    } catch (_) {
      return null;
    }
  }

  /// Photo (image bytes) -> extracted medicine fields as Map.
  /// Uses Gemini vision to read medicine label from photo.
  static Future<Map<String, String>?> tryImage(Uint8List imageBytes) async {
    try {
      final key = await AppPrefs.getGeminiKey();
      if (key.isEmpty || imageBytes.isEmpty) return null;
      final b64 = base64Encode(imageBytes);
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$key');
      const prompt =
          'You are an expert Indian pharmaceutical label reader. Extract data from this '
          'medicine photo with MAXIMUM accuracy.\n\n'
          'CRITICAL RULES:\n'
          '1. Read EVERY visible text carefully. Do NOT guess or hallucinate.\n'
          '2. If a field is not clearly visible, use empty string "".\n'
          '3. NEVER mix up fields - name is name, batch is batch.\n\n'
          'FIELD EXTRACTION GUIDE:\n\n'
          'name: The BRAND NAME printed largest on the strip/pack. '
          'Examples: "Dolo 650", "Crocin", "Azithral 500", "Pan 40", "
          'Becosules", "Shelcal 500". NOT the chemical name.\n\n'
          'batch: Look for these labels: "Batch", "Batch No", "Batch No.", '
          '"Batch Number", "Lot", "Lot No", "Lot No.", "BN", "B.No", '
          'followed by alphanumeric code like "AE2345", "T12345".\n\n'
          'expiry: Look for these labels: "Expiry", "Exp", "Exp.", '
          '"Expiry Date", "Expiry Date:", "EXP", "EXP DATE", '
          '"Best Before", "Best Before:", "Use Before", "Use By", '
          '"Valid Till", "Valid Upto", "Valid Up To".\n'
          'Also look for duration-based expiry like: "24 months from mfg", '
          '"18 months from date of manufacture", "24M", "36M".\n'
          'Format as DD/MM/YYYY. If only month+year (e.g. "12/2026" or '
          '"Dec 2026" or "12-26"), use day 01 -> "01/12/2026". '
          'If duration-based (e.g. "24 months from MFG 06/2025"), '
          'calculate and return DD/MM/YYYY.\n\n'
          'mfg: Look for "MFG", "Mfg", "Mfd", "Mfg.", "Manufactured on", '
          '"Date of Manufacture", "MFD", "DOM". Format DD/MM/YYYY.\n\n'
          'mrp: Look for "MRP", "M.R.P.", "Max Retail Price", "MRP Rs", '
          '"MRP ₹". Return ONLY the number without Rs/₹/symbols. '
          'For example if it says "MRP Rs. 45.50" return "45.50". '
          'If "₹120.00" return "120.00".\n\n'
          'salts: Look for "Composition", "Each film coated tablet contains", '
          '"Each tablet/capsule/ml contains", "Active ingredients", '
          '"Ingredients", "Formulation", "Each 5ml contains". '
          'Include the FULL composition with ALL salts and their strengths. '
          'Example: "Paracetamol 650mg" or "Amoxicillin 500mg + Clavulanic Acid 125mg". '
          'If multiple salts, include all separated by " + ".\n\n'
          'manufacturer: Look for "Manufactured by", "Mfg by", "Mfr", '
          '"Manufactured for", "Marketed by", "Packed by", "Distributed by", '
          '"Licence No". Extract the company name.\n\n'
          'gtin: The barcode number. Look for digits under a barcode (12-14 digits), '
          'or "GTIN", "EAN", "UPC".\n\n'
          'pack_size: Look for "Pack of", "10 Tablets", "1x10", "Strip of 10", '
          '"15 tablets", "100ml", "30 Capsules", "10x10".\n\n'
          'hsn: Look for "HSN", "HSN Code", "HSN:", followed by 4-8 digit number.\n\n'
          'Reply ONLY a JSON object with these exact keys, no other text: '
          '{"name":"","batch":"","expiry":"","mfg":"","mrp":"","salts":"",'
          '"manufacturer":"","gtin":"","pack_size":"","hsn":""}';
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                    {
                      'inlineData': {
                        'mimeType': 'image/jpeg',
                        'data': b64,
                      }
                    }
                  ]
                }
              ],
              'generationConfig': {
                'responseMimeType': 'application/json',
                'temperature': 0
              }
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      final parts = data['candidates']?[0]?['content']?['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final txt = (parts[0]['text'] ?? '').toString();
      if (txt.isEmpty) return null;
      final obj = jsonDecode(txt);
      if (obj is! Map) return null;
      return obj.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
    } catch (_) {
      return null;
    }
  }

  /// Same as tryImage but with a waiting popup.
  static Future<Map<String, String>?> tryImageWithLoader(
      BuildContext context, Uint8List imageBytes) async {
    try {
      final key = await AppPrefs.getGeminiKey();
      if (key.isEmpty) return null;
      bool open = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(Lang.t('qr_wait'))),
          ]),
        ),
      ).then((_) => open = false);
      final res = await tryImage(imageBytes);
      try {
        if (open) Navigator.pop(context);
      } catch (_) {}
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Same as tryQr but with a waiting popup. Returns null if no key / fail.
  static Future<QrMedicineData?> tryQrWithLoader(
      BuildContext context, String raw) async {
    try {
      final key = await AppPrefs.getGeminiKey();
      if (key.isEmpty) return null;
      bool open = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(Lang.t('qr_wait'))),
          ]),
        ),
      ).then((_) => open = false);
      final res = await tryQr(raw);
      try {
        if (open) Navigator.pop(context);
      } catch (_) {}
      return res;
    } catch (_) {
      return null;
    }
  }
}
