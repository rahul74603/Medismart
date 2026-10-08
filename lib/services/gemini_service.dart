import 'dart:async';
import 'dart:convert';
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
