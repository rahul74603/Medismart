import 'package:shared_preferences/shared_preferences.dart';

/// App-level preferences (printer settings, backup info).
/// Stored in SharedPreferences so no DB migration is needed.
class AppPrefs {
  static const _kReceiptWidth = 'receipt_width_mm'; // 58 or 80
  static const _kAutoPrint = 'auto_print_receipt'; // bool
  static const _kExpressAdd = 'express_add'; // 1-tap add in retail billing
  static const _kAskWa = 'ask_whatsapp_after_bill'; // prompt WA share after save
  static const _kUpiId = 'shop_upi_id'; // UPI id for QR on receipt
  static const _kQrPath = 'shop_qr_path'; // uploaded QR image path
  static const _kLastAutoBackup = 'last_auto_backup'; // yyyy-MM-dd
  static const _kGemini = 'gemini_api_key'; // user's own key, AI QR fallback
  static const _kLastBackupPath = 'last_backup_path'; // full file path
  static const _kLastBackupTime = 'last_backup_time'; // display string

  static Future<int> getReceiptWidth() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kReceiptWidth) ?? 80;
  }

  static Future<void> setReceiptWidth(int mm) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kReceiptWidth, mm == 58 ? 58 : 80);
  }

  static Future<bool> getAutoPrint() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAutoPrint) ?? true;
  }

  static Future<void> setAutoPrint(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoPrint, v);
  }

  static Future<bool> getExpressAdd() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kExpressAdd) ?? true;
  }

  static Future<void> setExpressAdd(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kExpressAdd, v);
  }

  static Future<bool> getAskWhatsApp() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAskWa) ?? true;
  }

  static Future<void> setAskWhatsApp(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAskWa, v);
  }

  static Future<String> getUpiId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kUpiId) ?? '';
  }

  static Future<String> getGeminiKey() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kGemini) ?? '';
  }

  static Future<void> setGeminiKey(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kGemini, v);
  }

  static Future<void> setUpiId(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUpiId, v.trim());
  }

  static Future<String> getQrPath() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kQrPath) ?? '';
  }

  static Future<void> setQrPath(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kQrPath, v.trim());
  }

  static Future<String?> getLastAutoBackupDay() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastAutoBackup);
  }

  static Future<void> setLastAutoBackupDay(String yyyyMmDd) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastAutoBackup, yyyyMmDd);
  }

  static Future<String?> getLastBackupPath() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastBackupPath);
  }

  static Future<void> setLastBackupInfo(String path, String displayTime) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastBackupPath, path);
    await p.setString(_kLastBackupTime, displayTime);
  }

  static Future<String> getLastBackupLabel() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastBackupTime) ?? 'Never';
  }
}
