import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_prefs.dart';
import 'lang_service.dart';
import 'qr_medicine_parser.dart';

class GeminiService {
  static const String _model = 'gemini-2.0-flash';

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

  /// Photo -> medicine fields via Gemini vision.
  static Future<Map<String, String>?> tryImage(Uint8List imageBytes) async {
    try {
      final key = await AppPrefs.getGeminiKey();
      if (key.isEmpty || imageBytes.isEmpty) return null;
      final b64 = base64Encode(imageBytes);
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$key');

      // SMART PROMPT — all Indian pharma label variations
      final prompt = StringBuffer();
      prompt.write('You are an expert Indian pharmaceutical label reader. ');
      prompt.write('Extract ALL visible data from this medicine photo with MAXIMUM accuracy.\n\n');
      prompt.write('CRITICAL RULES:\n');
      prompt.write('1. Read EVERY visible text carefully. Do NOT guess or hallucinate.\n');
      prompt.write('2. If a field is NOT clearly visible, use empty string.\n');
      prompt.write('3. NEVER mix up fields - name is name, batch is batch.\n\n');
      prompt.write('FIELD EXTRACTION GUIDE:\n\n');

      prompt.write('name: The BRAND NAME printed largest on the strip/pack. ');
      prompt.write('Examples: Dolo 650, Crocin, Azithral 500, Pan 40, Becosules, Shelcal 500. ');
      prompt.write('NOT the chemical/salt name.\n\n');

      prompt.write('batch: Look for: Batch, Batch No, Batch No., Batch Number, ');
      prompt.write('Lot, Lot No, Lot No., BN, B.No. ');
      prompt.write('Followed by alphanumeric code like AE2345, T12345.\n\n');

      prompt.write('expiry: Look for ALL these labels: Expiry, Exp, Exp., Expiry Date, ');
      prompt.write('EXP, EXP DATE, Best Before, Best Before:, Use Before, Use By, ');
      prompt.write('Valid Till, Valid Upto, Valid Up To.\n');
      prompt.write('Also duration-based: 24 months from mfg, 18 months from date of manufacture, ');
      prompt.write('24M, 36M, 24 MONTHS, 36 MONTHS.\n');
      prompt.write('Format as DD/MM/YYYY. Month+year only (12/2026, Dec 2026, 12-26) -> day 01. ');
      prompt.write('2-digit year -> 20xx. Duration-based -> calculate from mfg date.\n\n');

      prompt.write('mfg: Look for: MFG, Mfg, Mfd, Mfg., Manufactured on, ');
      prompt.write('Date of Manufacture, MFD, DOM. Format DD/MM/YYYY.\n\n');

      prompt.write('mrp: Look for: MRP, M.R.P., Max Retail Price, MRP Rs, ');
      prompt.write('MRP followed by Rs or rupee symbol. ');
      prompt.write('Return ONLY the number without any currency symbol. ');
      prompt.write('Example: MRP Rs. 45.50 -> return 45.50. Rs 120.00 -> return 120.00.\n\n');

      prompt.write('salts: Look for: Composition, Each film coated tablet contains, ');
      prompt.write('Each tablet/capsule/ml contains, Active ingredients, Ingredients, ');
      prompt.write('Formulation, Each 5ml contains, Each capsule contains. ');
      prompt.write('Include FULL composition with ALL salts and strengths. ');
      prompt.write('Example: Paracetamol 650mg or Amoxicillin 500mg + Clavulanic Acid 125mg. ');
      prompt.write('Multiple salts separated by + sign.\n\n');

      prompt.write('manufacturer: Look for: Manufactured by, Mfg by, Mfr, ');
      prompt.write('Manufactured for, Marketed by, Packed by, Distributed by. ');
      prompt.write('Extract the company name.\n\n');

      prompt.write('gtin: Barcode number. Look for 12-14 digits under a barcode, ');
      prompt.write('or labels GTIN, EAN, UPC.\n\n');

      prompt.write('pack_size: Look for: Pack of, 10 Tablets, 1x10, Strip of 10, ');
      prompt.write('15 tablets, 100ml, 30 Capsules, 10x10, 15 ml.\n\n');

      prompt.write('hsn: Look for: HSN, HSN Code, HSN: followed by 4-8 digit number.\n\n');

      prompt.write('Reply ONLY a JSON object with these exact keys, no other text: ');
      prompt.write('{"name":"","batch":"","expiry":"","mfg":"","mrp":"","salts":"","manufacturer":"","gtin":"","pack_size":"","hsn":""}');

      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt.toString()},
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
}