import '../db_helper.dart';

/// Barcode support for fast billing.
///
/// WORKS TODAY (no extra package):
/// - Hardware USB/Bluetooth scanners (they type the barcode + Enter)
///   and manual barcode typing: exact match = instant product.
/// - Type the barcode in any billing search box and press Enter/Done.
///
/// FUTURE: camera scanning needs one camera package (e.g. mobile_scanner).
/// Plug it into [scanWithCamera] — the lookup flow below stays the same.
class BarcodeService {
  /// Exact barcode lookup. Returns the matching stock row, or null.
  static Future<Map<String, dynamic>?> lookupByBarcode(String code) async {
    final c = code.trim();
    if (c.length < 3) return null;
    return await DBHelper.getItemByBarcode(c);
  }

  /// Camera scanning hook (Phase 2B). Throws until a scanner package is added.
  static Future<String?> scanWithCamera() async {
    throw UnimplementedError(
        'Camera scanning needs the mobile_scanner package. '
        'Meanwhile use a hardware scanner or type the barcode.');
  }
}
