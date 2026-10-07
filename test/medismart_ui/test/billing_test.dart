import 'package:flutter_test/flutter_test.dart';
import 'package:medismart_ui/services/db_helper.dart';
import 'package:medismart_ui/services/billing_service.dart';
import 'package:medismart_ui/models/customer.dart';
import 'package:medismart_ui/models/item.dart';
import 'package:medismart_ui/models/bill.dart';

void main() {
  group('Billing Feature Tests', () {
    late BillingService billingService;

    setUp(() {
      billingService = BillingService();
    });

    test('Customer details should be saved correctly', () async {
      Customer customer = Customer(name: 'John Doe', mobile: '1234567890', address: '123 Main St');
      await DBHelper.saveOrUpdateCustomer(customer.toMap());

      var fetchedCustomer = await DBHelper.getCustomerByMobile('1234567890');
      expect(fetchedCustomer['name'], 'John Doe');
      expect(fetchedCustomer['mobile'], '1234567890');
      expect(fetchedCustomer['address'], '123 Main St');
    });

    test('Bill generation should calculate total correctly', () {
      List<Item> items = [
        Item(name: 'Medicine A', price: 100, qty: 2),
        Item(name: 'Medicine B', price: 200, qty: 1),
      ];
      Bill bill = billingService.generateBill(items);
      expect(bill.totalAmount, 400);
    });

    test('Bill should include GST calculations', () {
      List<Item> items = [
        Item(name: 'Medicine A', price: 100, qty: 2),
      ];
      Bill bill = billingService.generateBill(items, gstPercentage: 18);
      expect(bill.gstAmount, 36);
      expect(bill.netAmount, 436);
    });

    test('Item stock should update correctly after bill generation', () async {
      Item item = Item(name: 'Medicine A', price: 100, qty: 10);
      await DBHelper.saveItem(item.toMap());

      List<Item> itemsToPurchase = [
        Item(name: 'Medicine A', price: 100, qty: 2),
      ];
      await billingService.generateBill(itemsToPurchase);

      var updatedItem = await DBHelper.getItemByName('Medicine A');
      expect(updatedItem['qty'], 8);
    });

    test('Bill history should be retrievable', () async {
      Bill bill = Bill(invoiceNo: 'INV001', customerName: 'John Doe', totalAmount: 400);
      await DBHelper.saveBill(bill.toMap());

      var billHistory = await DBHelper.getBillHistory();
      expect(billHistory.length, greaterThan(0));
      expect(billHistory[0]['invoice_no'], 'INV001');
    });
  });
}