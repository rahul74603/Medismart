/// QR Medicine Parser - PURE DART, no Flutter imports (unit-testable).
/// Reads Indian pharma QR codes in many formats and extracts whatever it can:
/// GTIN/product code, batch, expiry, mfg date, MRP, name.
/// NEVER throws, NEVER returns garbage dates - unknown input = empty fields.

class QrMedicineData {
  String gtin = '';
  String batch = '';
  String expiry = ''; // normalized dd/MM/yyyy when possible
  String mfg = ''; // normalized dd/MM/yyyy when possible
  String mrp = ''; // digits + dot only
  String name = '';
  String raw = '';

  bool get isEmpty =>
      gtin.isEmpty &&
      batch.isEmpty &&
      expiry.isEmpty &&
      mfg.isEmpty &&
      mrp.isEmpty &&
      name.isEmpty;
}

class QrMedicineParser {
  static QrMedicineData parse(String? raw) {
    final d = QrMedicineData();
    if (raw == null) return d;
    try {
      d.raw = raw;
      final text = raw.trim();
      if (text.isEmpty) return d;
      _parseParenthesizedAI(text, d);
      if (d.isEmpty) _parseFlatGS1(text, d);
      if (d.isEmpty) _parseUrl(text, d);
      _parseKeyValues(text, d); // fills gaps in any format
      _parseFreeText(text, d); // fills remaining gaps
      d.expiry = _normDate(d.expiry);
      d.mfg = _normDate(d.mfg);
      d.mrp = _normMrp(d.mrp);
      d.gtin = _normGtin(d.gtin);
      d.batch = d.batch.trim().length > 30 ? '' : d.batch.trim();
      d.name = d.name.trim().length > 100 ? '' : d.name.trim();
    } catch (_) {}
    return d;
  }

  // ---------- (01)xxx(17)xxx(10)xxx ----------
  static void _parseParenthesizedAI(String text, QrMedicineData d) {
    try {
      final re = RegExp(r'\((\d{2,4})\)\s*([^()]+)');
      for (final m in re.allMatches(text)) {
        final ai = m.group(1)!;
        final val = m.group(2)!.trim();
        if (ai == '01') {
          d.gtin = val;
        } else if (ai == '10') {
          d.batch = val;
        } else if (ai == '17') {
          d.expiry = val;
        } else if (ai == '11') {
          d.mfg = val;
        }
      }
    } catch (_) {}
  }

  // ---------- flat GS1: 01<14 digits>17<YYMMDD>10<batch> ----------
  static void _parseFlatGS1(String text, QrMedicineData d) {
    try {
      final flat = text.replaceAll(RegExp(r'[\s\x1D\x1E|]+'), '');
      if (flat.length < 22) return;
      if (!RegExp(r'^\d+$').hasMatch(flat)) return;
      if (!flat.startsWith('01')) return;
      d.gtin = flat.substring(2, 16);
      int i = 16;
      while (i < flat.length) {
        final rest = flat.substring(i);
        if (rest.startsWith('17') && rest.length >= 8) {
          d.expiry = rest.substring(2, 8); // YYMMDD
          i += 8;
        } else if (rest.startsWith('11') && rest.length >= 8) {
          d.mfg = rest.substring(2, 8);
          i += 8;
        } else if (rest.startsWith('15') && rest.length >= 8) {
          i += 8; // best-before, not needed
        } else if (rest.startsWith('10')) {
          // batch = rest (variable length, till end)
          final b = rest.substring(2);
          if (b.isNotEmpty && b.length <= 20) d.batch = b;
          break;
        } else if (rest.startsWith('21')) {
          break; // serial, not needed
        } else {
          i++;
        }
      }
    } catch (_) {}
  }

  // ---------- https://...?gtin=..&batch=..&exp=.. ----------
  static void _parseUrl(String text, QrMedicineData d) {
    try {
      if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(text)) return;
      final uri = Uri.tryParse(text);
      if (uri == null || !uri.hasQuery) return;
      uri.queryParameters.forEach((k, v) => _assignKey(k, v, d));
    } catch (_) {}
  }

  // ---------- GTIN:123 / Batch=ABC / EXP 12/2027 (lines or ; | separated) ----------
  static void _parseKeyValues(String text, QrMedicineData d) {
    try {
      final parts = text.split(RegExp(r'[\n;|]'));
      for (final p in parts) {
        final m = RegExp(r'^\s*([^:=]{1,25})\s*[:=]\s*(.+?)\s*$').firstMatch(p);
        if (m == null) continue;
        _assignKey(m.group(1)!, m.group(2)!, d);
      }
    } catch (_) {}
  }

  static void _assignKey(String key, String val, QrMedicineData d) {
    try {
      final k = key.toLowerCase().replaceAll(RegExp(r'[\s._\-]'), '');
      final v = val.trim();
      if (v.isEmpty) return;
      if ({'gtin', 'ean', 'eancode', 'productcode', 'pc', 'upc', 'barcode'}
          .contains(k)) {
        if (d.gtin.isEmpty) d.gtin = v;
      } else if ({'batch', 'batchno', 'batchnumber', 'bt', 'bno', 'lot', 'lotno'}
          .contains(k)) {
        if (d.batch.isEmpty) d.batch = v;
      } else if ({'exp', 'expiry', 'expdate', 'expdt', 'expirydate', 'ed', 'doe'}
          .contains(k)) {
        if (d.expiry.isEmpty) d.expiry = v;
      } else if ({'mfg', 'mfgdate', 'mfd', 'mfddate', 'manufacturingdate', 'dom', 'mdate'}
          .contains(k)) {
        if (d.mfg.isEmpty) d.mfg = v;
      } else if ({'mrp', 'price', 'rate', 'amount', 'maxretailprice'}.contains(k)) {
        if (d.mrp.isEmpty) d.mrp = v;
      } else if ({'name', 'product', 'productname', 'brand', 'brandname', 'drug', 'drugname', 'item', 'itemname', 'medicine', 'medicinename', 'pname'}
          .contains(k)) {
        if (d.name.isEmpty) d.name = v;
      }
    } catch (_) {}
  }

  // ---------- free text fallback (only fills EMPTY fields) ----------
  static void _parseFreeText(String text, QrMedicineData d) {
    try {
      if (d.batch.isEmpty) {
        final m = RegExp(
                r'batch(?:\s*(?:no\.?|number))?\s*[:\-]?\s*([A-Za-z0-9][A-Za-z0-9\-\/]{1,19})',
                caseSensitive: false)
            .firstMatch(text);
        if (m != null) d.batch = m.group(1)!.trim();
      }
      if (d.expiry.isEmpty) {
        final m = RegExp(
                r'(?:exp(?:iry|iry|iry\s*date)?|expiry)\s*(?:date)?\s*[:\-]?\s*(\d{1,2}[\/\-\.]\d{2,4}(?:[\/\-\.]\d{2,4})?)',
                caseSensitive: false)
            .firstMatch(text);
        if (m != null) d.expiry = m.group(1)!.trim();
      }
      if (d.expiry.isEmpty) {
        // month-name style: EXP JAN-2027 / Expiry: Feb 26
        final m = RegExp(
                r'(?:exp|expiry)[^A-Za-z0-9]{0,8}((?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*[\s\-\.\/]+\d{2,4})',
                caseSensitive: false)
            .firstMatch(text);
        if (m != null) d.expiry = m.group(1)!.trim();
      }
      if (d.mfg.isEmpty) {
        final m = RegExp(
                r'mfg(?:\s*date)?\s*[:\-]?\s*(\d{1,2}[\/\-\.]\d{2,4}(?:[\/\-\.]\d{2,4})?)',
                caseSensitive: false)
            .firstMatch(text);
        if (m != null) d.mfg = m.group(1)!.trim();
      }
      if (d.mrp.isEmpty) {
        final m = RegExp(r'(?:MRP|Rs\.?|₹)\s*[:\-]?\s*([\d,]+\.?\d*)',
                caseSensitive: false)
            .firstMatch(text);
        if (m != null) d.mrp = m.group(1)!.trim();
      }
      if (d.gtin.isEmpty) {
        final m = RegExp(r'\b(\d{13,14})\b').firstMatch(text);
        if (m != null) d.gtin = m.group(1)!;
      }
    } catch (_) {}
  }

  // ---------- normalize any date -> dd/MM/yyyy ('' if invalid) ----------
  static String _normDate(String v) {
    try {
      var s = v.trim();
      if (s.isEmpty) return '';
      // strip time part if any
      s = s.split(RegExp(r'[T ]')).first;
      // YYMMDD (GS1, 6 digits)
      if (RegExp(r'^\d{6}$').hasMatch(s)) {
        final yy = int.parse(s.substring(0, 2));
        final mm = int.parse(s.substring(2, 4));
        final dd = int.parse(s.substring(4, 6));
        return _valid(2000 + yy, mm, dd);
      }
      // YYYYMMDD (8 digits)
      if (RegExp(r'^\d{8}$').hasMatch(s)) {
        final yyyy = int.parse(s.substring(0, 4));
        final mm = int.parse(s.substring(4, 6));
        final dd = int.parse(s.substring(6, 8));
        return _valid(yyyy, mm, dd);
      }
      // month name: JAN-2027 / Feb 26 / Sept/2026
      final mn = RegExp(
              r'(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*[\s\-\.\/]+(\d{2,4})',
              caseSensitive: false)
          .firstMatch(s);
      if (mn != null) {
        const months = [
          'jan', 'feb', 'mar', 'apr', 'may', 'jun',
          'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
        ];
        var key = mn.group(1)!.toLowerCase();
        if (key.startsWith('sept')) key = 'sep';
        final mm = months.indexOf(key) + 1;
        var yy = int.parse(mn.group(2)!);
        if (yy < 100) yy += 2000;
        return _valid(yy, mm, 1);
      }
      // numeric with separators
      final parts = s.split(RegExp(r'[\/\-\.]'));
      if (parts.length == 3) {
        int a = int.tryParse(parts[0]) ?? -1;
        int b = int.tryParse(parts[1]) ?? -1;
        int c = int.tryParse(parts[2]) ?? -1;
        if (a < 0 || b < 0 || c < 0) return '';
        // YYYY-MM-DD ?
        if (parts[0].length == 4) return _valid(a, b, c);
        // dd-MM-yyyy or MM-dd-yyyy? assume dd/MM/yyyy (Indian)
        int dd = a, mm = b, yy = c;
        if (yy < 100) yy += 2000;
        if (mm > 12 && dd <= 12) {
          final t = mm;
          mm = dd;
          dd = t;
        }
        return _valid(yy, mm, dd);
      }
      if (parts.length == 2) {
        int a = int.tryParse(parts[0]) ?? -1;
        int b = int.tryParse(parts[1]) ?? -1;
        if (a < 0 || b < 0) return '';
        // MM/yyyy or yyyy/MM ?
        if (parts[0].length == 4) return _valid(a, b, 1);
        int mm = a, yy = b;
        if (yy < 100) yy += 2000;
        if (mm < 1 || mm > 12) return '';
        return _valid(yy, mm, 1);
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  static String _valid(int y, int m, int d) {
    try {
      if (y < 2000 || y > 2060 || m < 1 || m > 12 || d < 1 || d > 31) return '';
      final dt = DateTime(y, m, d);
      if (dt.year != y || dt.month != m || dt.day != d) return '';
      final dd = d.toString().padLeft(2, '0');
      final mm = m.toString().padLeft(2, '0');
      return '$dd/$mm/$y';
    } catch (_) {
      return '';
    }
  }

  static String _normMrp(String v) {
    try {
      final m = RegExp(r'\d[\d,]*\.?\d*').firstMatch(v.replaceAll(' ', ''));
      if (m == null) return '';
      final n = m.group(0)!.replaceAll(',', '');
      if (n.isEmpty || double.tryParse(n) == null) return '';
      return n;
    } catch (_) {
      return '';
    }
  }

  static String _normGtin(String v) {
    try {
      final s = v.trim().replaceAll(RegExp(r'\s+'), '');
      if (RegExp(r'^\d{8,14}$').hasMatch(s)) return s;
      return '';
    } catch (_) {
      return '';
    }
  }
}
