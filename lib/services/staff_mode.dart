import 'package:shared_preferences/shared_preferences.dart';

/// Simple staff mode: hides money-sensitive screens (Reports, Settings,
/// Purchase, Suppliers, Claims) from shop helpers. Owner exits with PIN.
class StaffMode {
  static bool enabled = false;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled = p.getBool('staff_mode') ?? false;
    } catch (_) {
      enabled = false;
    }
  }

  static Future<void> set(bool v) async {
    enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('staff_mode', v);
  }

  static Future<bool> hasPin() async {
    final p = await SharedPreferences.getInstance();
    return ((p.getString('staff_pin') ?? '').length) >= 4;
  }

  static Future<bool> check(String pin) async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('staff_pin') ?? '';
    return saved.length >= 4 && saved == pin;
  }

  static Future<void> setPin(String pin) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('staff_pin', pin);
  }
}
