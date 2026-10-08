import 'package:flutter_test/flutter_test.dart';
import 'package:medismart_ui/services/qr_medicine_parser.dart';

void main() {
  group('QrMedicineParser', () {
    test('parenthesized GS1 AI format', () {
      final d = QrMedicineParser.parse(
          '(01)08901111222228(17)260630(10)AB1234(21)999');
      expect(d.gtin, '08901111222228');
      expect(d.batch, 'AB1234');
      expect(d.expiry, '30/06/2026');
    });

    test('flat GS1 format', () {
      final d =
          QrMedicineParser.parse('010890111122222817260630AB1234');
      expect(d.gtin, '08901111222228');
      expect(d.batch, 'AB1234');
      expect(d.expiry, '30/06/2026');
    });

    test('key-value multiline format', () {
      final d = QrMedicineParser.parse(
          'GTIN: 8901111222228\nBatch No: XZ99\nEXP: 12/2027\nMRP: Rs. 45.50');
      expect(d.gtin, '8901111222228');
      expect(d.batch, 'XZ99');
      expect(d.expiry, '01/12/2027');
      expect(d.mrp, '45.50');
    });

    test('URL with query params', () {
      final d = QrMedicineParser.parse(
          'https://verify.example.com/p?gtin=8901111222228&batch=QW12&exp=01/2028&mrp=120');
      expect(d.gtin, '8901111222228');
      expect(d.batch, 'QW12');
      expect(d.expiry, '01/01/2028');
      expect(d.mrp, '120');
    });

    test('free text with month-name expiry', () {
      final d = QrMedicineParser.parse(
          'Crocin 500mg Batch BT776 Expiry JAN-2027 MRP Rs 32');
      expect(d.batch, 'BT776');
      expect(d.expiry, '01/01/2027');
      expect(d.mrp, '32');
    });

    test('garbage never errors, returns empty', () {
      final d = QrMedicineParser.parse('hello world {!!');
      expect(d.isEmpty, true);
      final n = QrMedicineParser.parse(null);
      expect(n.isEmpty, true);
      final e = QrMedicineParser.parse('');
      expect(e.isEmpty, true);
    });

    test('invalid dates are dropped, not filled', () {
      final d = QrMedicineParser.parse('Batch: OK1\nEXP: 99/99/9999');
      expect(d.batch, 'OK1');
      expect(d.expiry, '');
    });
    test('use before + d-m-yyyy', () {
      final d = QrMedicineParser.parse('Use Before: 1-11-2026');
      expect(d.expiry, '01/11/2026');
    });

    test('best before month-name + lot batch', () {
      final d = QrMedicineParser.parse('Best Before: JAN-2027\nLot: Q12');
      expect(d.expiry, '01/01/2027');
      expect(d.batch, 'Q12');
    });

    test('exp with day month-name year', () {
      final d = QrMedicineParser.parse('EXP: 1 Nov 2026');
      expect(d.expiry, '01/11/2026');
    });

    test('full month name lowercase', () {
      final d = QrMedicineParser.parse('use before 1 november 2026');
      expect(d.expiry, '01/11/2026');
    });

    test('loose comma pairs without colon', () {
      final d = QrMedicineParser.parse(
          'Crocin Advance, Batch AB1, Exp 12/27, MRP 50');
      expect(d.batch, 'AB1');
      expect(d.expiry, '01/12/2027');
      expect(d.mrp, '50');
    });

    test('valid till + packed mfg', () {
      final d = QrMedicineParser.parse(
          'Valid Till 31/12/2026\nPacked On: 01/2024');
      expect(d.expiry, '31/12/2026');
      expect(d.mfg, '01/01/2024');
    });
  });
}
