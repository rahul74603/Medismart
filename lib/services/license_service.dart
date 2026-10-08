import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App licensing v2 - per-install unique code, owner activates via SMS/WhatsApp.
/// - Code is unique per install (UUID in prefs, NOT the Android build id).
/// - Key derivation is identical on user side and Owner Tool side (no PC needed).
/// - Code reaches the owner via SMS Intent / WhatsApp (no SMS permission,
///   so Play Protect never blocks the install).
class LicenseService {
  static const String ownerNumber = '6263396446'; // SMS (domestic dialling)
  static const String ownerWa = '916263396446'; // wa.me needs country code
  static const String _salt = 'RAHUL_MEDICAL_ERP_2024_SECRET';

  /// Per-install unique ID (generated once, new on reinstall = reactivation).
  static Future<String> getInstallId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString('install_uuid') ?? '';
    if (id.isEmpty) {
      id = _newUuid();
      await p.setString('install_uuid', id);
    }
    return id;
  }

  static String _newUuid() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant
    final h =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// 8-char device CODE shown to the user + sent to the owner.
  static String codeFor(String installId) {
    try {
      return sha256
          .convert(utf8.encode('$installId|$_salt|CODE'))
          .toString()
          .substring(0, 8)
          .toUpperCase();
    } catch (_) {
      return '--------';
    }
  }

  /// 8-char activation KEY from a device code (same on both sides).
  static String keyFor(String code) {
    try {
      return sha256
          .convert(utf8.encode('${code.trim().toUpperCase()}|$_salt|KEY'))
          .toString()
          .substring(0, 8)
          .toUpperCase();
    } catch (_) {
      return 'XXXXXXXX';
    }
  }

  static Future<bool> isLicensed() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool('is_licensed') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setLicensed() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('is_licensed', true);
    } catch (_) {}
  }

}
