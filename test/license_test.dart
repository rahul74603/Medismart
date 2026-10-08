import 'package:flutter_test/flutter_test.dart';
import 'package:medismart_ui/services/license_service.dart';

void main() {
  group('LicenseService keys', () {
    test('code is 8-char uppercase', () {
      final c = LicenseService.codeFor('test-install-id-123');
      expect(c.length, 8);
      expect(c, c.toUpperCase());
    });

    test('key is deterministic per code (any case)', () {
      expect(LicenseService.keyFor('ABCD1234'),
          LicenseService.keyFor('abcd1234'));
      expect(LicenseService.keyFor('ABCD1234').length, 8);
    });

    test('different codes give different keys', () {
      expect(
          LicenseService.keyFor('AAAAAAAA') !=
              LicenseService.keyFor('BBBBBBBB'),
          true);
    });
  });
}
