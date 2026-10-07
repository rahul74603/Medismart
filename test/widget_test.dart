import 'package:flutter_test/flutter_test.dart';

import 'package:medismart_ui/services/whatsapp_helper.dart';

void main() {
  group('WhatsAppHelper.normalizeNumber', () {
    test('10-digit mobile gets 91 prefix', () {
      expect(WhatsAppHelper.normalizeNumber('9876543210'), '919876543210');
    });

    test('number with spaces and dashes is cleaned', () {
      expect(WhatsAppHelper.normalizeNumber('98-765 43210'), '919876543210');
    });

    test('leading zero is handled', () {
      expect(WhatsAppHelper.normalizeNumber('09876543210'), '919876543210');
    });

    test('already-prefixed 91 number is kept', () {
      expect(WhatsAppHelper.normalizeNumber('919876543210'), '919876543210');
    });

    test('invalid numbers return empty string', () {
      expect(WhatsAppHelper.normalizeNumber(''), '');
      expect(WhatsAppHelper.normalizeNumber('12345'), '');
      expect(WhatsAppHelper.normalizeNumber(null), '');
    });
  });
}
