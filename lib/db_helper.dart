import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

class DBHelper {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  // Database Filename - Changed to v2 to force new DB creation
  static Future<String> getDbPath() async {
    return join(await getDatabasesPath(), 'medismart_production_v2.db');
  }

  static Future<Database> _initDB() async {
    String path = await getDbPath();
    return await openDatabase(
      path,
      // 🔥 VERSION 12: Purchase + Sales Return tables, bill_items.stock_id (batch-wise stock)
      version: 12,
      onCreate: (db, version) async {

        // 1. ITEMS / STOCK TABLE (one row = one batch of a product)
        await db.execute('''
          CREATE TABLE items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            chemical TEXT,
            type TEXT,
            batch TEXT,
            rack TEXT,
            quantity INTEGER,
            price REAL,
            wholesale_price REAL,
            gst_percent INTEGER DEFAULT 0,
            expiryDate TEXT,
            min_stock INTEGER DEFAULT 10
          )
        ''');

        // 2. CUSTOMERS TABLE (Added gstin & address)
        await db.execute('''
          CREATE TABLE customers(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            mobile TEXT UNIQUE,
            gstin TEXT,
            address TEXT,
            title TEXT,
            total_due REAL DEFAULT 0.0,
            total_advance REAL DEFAULT 0.0
          )
        ''');

        // 3. BILLS MASTER TABLE (Added bill_type, customer_gstin, customer_address)
        await db.execute('''
          CREATE TABLE bills(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoice_no TEXT UNIQUE,
            customer_name TEXT,
            doctor_name TEXT,
            mobile TEXT,
            date TEXT,
            sub_total REAL,
            discount REAL DEFAULT 0.0,
            gst_percent INTEGER,
            gst_amount REAL,
            net_amount REAL,
            payment_mode TEXT,
            bill_type TEXT DEFAULT 'Retail',
            customer_gstin TEXT,
            customer_address TEXT
          )
        ''');

        // 4. BILL ITEMS TABLE (stock_id = exact batch row sold, for batch-wise stock)
        await db.execute('''
          CREATE TABLE bill_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bill_id INTEGER,
            stock_id INTEGER DEFAULT 0,
            item_name TEXT,
            batch TEXT,
            mrp REAL,
            qty INTEGER,
            free_qty INTEGER DEFAULT 0,
            rate REAL,
            total REAL,
            gst_percent INTEGER DEFAULT 0,
            expiryDate TEXT,
            type TEXT
          )
        ''');

        // 5. SUPPLIERS TABLE
        await db.execute('''
          CREATE TABLE suppliers(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            company TEXT,
            mobile TEXT,
            gstin TEXT,
            address TEXT,
            balance REAL DEFAULT 0.0
          )
        ''');

        // 6. SUPPLIER LEDGER
        await db.execute('''
          CREATE TABLE supplier_ledger(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            supplier_id INTEGER,
            date TEXT,
            description TEXT,
            debit REAL,
            credit REAL,
            balance REAL
          )
        ''');

        // 7. CUSTOMER LEDGER
        await db.execute('''
          CREATE TABLE customer_ledger(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mobile TEXT,
            date TEXT,
            description TEXT,
            debit REAL,
            credit REAL,
            balance REAL
          )
        ''');

        // 8. SHOP SETTINGS
        await db.execute('''
          CREATE TABLE settings(
            id INTEGER PRIMARY KEY,
            shop_name TEXT,
            address TEXT,
            phone TEXT,
            gstin TEXT,
            dl_no TEXT,
            terms TEXT
          )
        ''');

        // 9. PURCHASES (maal kharid - distributor bills)
        await db.execute('''
          CREATE TABLE purchases(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            purchase_no TEXT UNIQUE,
            supplier_id INTEGER,
            supplier_name TEXT,
            supplier_invoice TEXT,
            date TEXT,
            sub_total REAL,
            discount REAL DEFAULT 0.0,
            gst_amount REAL DEFAULT 0.0,
            net_amount REAL,
            paid_amount REAL DEFAULT 0.0,
            payment_mode TEXT
          )
        ''');

        // 10. PURCHASE ITEMS
        await db.execute('''
          CREATE TABLE purchase_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            purchase_id INTEGER,
            item_name TEXT,
            batch TEXT,
            qty INTEGER,
            free_qty INTEGER DEFAULT 0,
            rate REAL,
            mrp REAL,
            gst_percent INTEGER DEFAULT 0,
            expiry TEXT,
            total REAL
          )
        ''');

        // 11. SALES RETURNS (customer ne dawai wapas ki)
        await db.execute('''
          CREATE TABLE sales_returns(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            return_no TEXT UNIQUE,
            bill_id INTEGER,
            invoice_no TEXT,
            customer_name TEXT,
            mobile TEXT,
            date TEXT,
            total_amount REAL,
            refund_mode TEXT,
            reason TEXT
          )
        ''');

        // 12. SALES RETURN ITEMS
        await db.execute('''
          CREATE TABLE sales_return_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            return_id INTEGER,
            bill_id INTEGER,
            item_name TEXT,
            batch TEXT,
            stock_id INTEGER DEFAULT 0,
            qty INTEGER,
            free_qty INTEGER DEFAULT 0,
            rate REAL,
            total REAL
          )
        ''');

        await _insertDummyData(db);
      },

      // ✅ MIGRATION LOGIC
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 8) {
          try {
            await db.execute("ALTER TABLE bills ADD COLUMN customer_gstin TEXT");
            await db.execute("ALTER TABLE bills ADD COLUMN customer_address TEXT");
          } catch (e) { print("Migration Error: $e"); }
        }
        if (oldVersion < 9) {
          try {
            await db.execute("ALTER TABLE bill_items ADD COLUMN gst_percent INTEGER DEFAULT 0");

            final billItems = await db.query('bill_items');
            for (var billItem in billItems) {
              String itemName = (billItem['item_name'] ?? '').toString();
              if (itemName.isNotEmpty) {
                final stockItems = await db.query('items', where: 'name = ?', whereArgs: [itemName]);
                if (stockItems.isNotEmpty) {
                  int gstPercent = (stockItems.first['gst_percent'] ?? 0) as int;
                  await db.update('bill_items', {'gst_percent': gstPercent}, where: 'id = ?', whereArgs: [billItem['id']]);
                }
              }
            }
          } catch (e) { print("Migration Error: $e"); }
        }
        if (oldVersion < 10) {
          try {
            await db.execute("ALTER TABLE bill_items ADD COLUMN expiryDate TEXT");
            await db.execute("ALTER TABLE bill_items ADD COLUMN type TEXT");

            final billItems = await db.query('bill_items');
            for (var billItem in billItems) {
              String itemName = (billItem['item_name'] ?? '').toString();
              if (itemName.isNotEmpty) {
                final stockItems = await db.query('items', where: 'name = ?', whereArgs: [itemName]);
                if (stockItems.isNotEmpty) {
                  String expiryDate = (stockItems.first['expiryDate'] ?? '') as String;
                  String type = (stockItems.first['type'] ?? '') as String;
                  await db.update('bill_items', {'expiryDate': expiryDate, 'type': type}, where: 'id = ?', whereArgs: [billItem['id']]);
                }
              }
            }
          } catch (e) { print("Migration Error: $e"); }
        }

        // 🔥 NEW MIGRATION LOGIC FOR V11 (Safely adds missing columns in restored backups)
        if (oldVersion < 11) {
          try {
            await db.execute("ALTER TABLE bill_items ADD COLUMN expiryDate TEXT");
          } catch (e) { print("expiryDate already exists or error: $e"); }

          try {
            await db.execute("ALTER TABLE bill_items ADD COLUMN type TEXT");
          } catch (e) { print("type already exists or error: $e"); }

          print("Forced upgrade to v11 applied successfully on restored backup.");
        }

        // 🔥 V12: Purchase + Sales Return tables + batch-wise stock (bill_items.stock_id)
        if (oldVersion < 12) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS purchases(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                purchase_no TEXT UNIQUE,
                supplier_id INTEGER,
                supplier_name TEXT,
                supplier_invoice TEXT,
                date TEXT,
                sub_total REAL,
                discount REAL DEFAULT 0.0,
                gst_amount REAL DEFAULT 0.0,
                net_amount REAL,
                paid_amount REAL DEFAULT 0.0,
                payment_mode TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS purchase_items(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                purchase_id INTEGER,
                item_name TEXT,
                batch TEXT,
                qty INTEGER,
                free_qty INTEGER DEFAULT 0,
                rate REAL,
                mrp REAL,
                gst_percent INTEGER DEFAULT 0,
                expiry TEXT,
                total REAL
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS sales_returns(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                return_no TEXT UNIQUE,
                bill_id INTEGER,
                invoice_no TEXT,
                customer_name TEXT,
                mobile TEXT,
                date TEXT,
                total_amount REAL,
                refund_mode TEXT,
                reason TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS sales_return_items(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                return_id INTEGER,
                bill_id INTEGER,
                item_name TEXT,
                batch TEXT,
                stock_id INTEGER DEFAULT 0,
                qty INTEGER,
                free_qty INTEGER DEFAULT 0,
                rate REAL,
                total REAL
              )
            ''');
          } catch (e) { print("V12 table creation error: $e"); }

          try {
            await db.execute("ALTER TABLE bill_items ADD COLUMN stock_id INTEGER DEFAULT 0");
          } catch (e) { print("stock_id already exists or error: $e"); }

          // Best-effort backfill: link old bill lines to their batch rows
          try {
            final oldLines = await db.query('bill_items');
            for (var line in oldLines) {
              int sid = ((line['stock_id'] as num?)?.toInt()) ?? 0;
              if (sid == 0) {
                final rows = await db.query('items', where: 'name = ? AND batch = ?',
                    whereArgs: [(line['item_name'] ?? '').toString(), (line['batch'] ?? '').toString()], limit: 1);
                if (rows.isNotEmpty) {
                  await db.update('bill_items', {'stock_id': rows.first['id']},
                      where: 'id = ?', whereArgs: [line['id']]);
                }
              }
            }
          } catch (e) { print("V12 backfill error: $e"); }

          print("Upgrade to v12 applied successfully.");
        }
      },
    );
  }

  static Future<void> _insertDummyData(Database db) async {
    await db.insert('items', {
      'name': 'Dolo 650', 'chemical': 'Paracetamol', 'type': 'Strip', 'batch': 'DL-202', 'rack': 'A1',
      'quantity': 50, 'price': 30.0, 'wholesale_price': 25.0, 'gst_percent': 12, 'expiryDate': '12/12/2026'
    });

    await db.insert('settings', {
      'shop_name': 'MY MEDICAL STORE',
      'address': 'Gwalior, MP',
      'phone': '6263396446',
      'gstin': '',
      'terms': 'No Return without Bill.'
    });
  }

  // --- CORE FUNCTIONS ---

  static Future<List<Map<String, dynamic>>> getItems() async => (await database).query('items', orderBy: "name ASC");
  static Future<int> addItem(Map<String, dynamic> data) async => (await database).insert('items', data);
  static Future<int> createItem(Map<String, dynamic> data) async => await addItem(data);
  static Future<int> updateItem(Map<String, dynamic> data) async => (await database).update('items', data, where: "id = ?", whereArgs: [data['id']]);
  static Future<int> deleteItem(int id) async => (await database).delete('items', where: "id = ?", whereArgs: [id]);

  // --- EXPIRY + FEFO HELPERS (batch-wise stock) ---

  /// Parses 'dd/MM/yyyy' safely. Returns null if empty/invalid.
  static DateTime? parseExpiry(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(s.trim());
    } catch (_) {
      try {
        return DateFormat('dd/MM/yyyy').parse(s.trim());
      } catch (_) {
        return null;
      }
    }
  }

  /// Sorts batch rows earliest-expiry-first (FEFO). Rows without expiry go last.
  static List<Map<String, dynamic>> sortBatchesFEFO(List<Map<String, dynamic>> rows) {
    final list = List<Map<String, dynamic>>.from(rows);
    list.sort((a, b) {
      final da = parseExpiry(a['expiryDate']?.toString());
      final dbb = parseExpiry(b['expiryDate']?.toString());
      if (da == null && dbb == null) return 0;
      if (da == null) return 1;
      if (dbb == null) return -1;
      return da.compareTo(dbb);
    });
    return list;
  }

  /// All in-stock batches of a product, FEFO ordered.
  static Future<List<Map<String, dynamic>>> getBatchesForSale(String name) async {
    final db = await database;
    final rows = await db.query('items', where: 'name = ? AND quantity > 0', whereArgs: [name]);
    return sortBatchesFEFO(rows);
  }

  static Future<Map<String, dynamic>> getDashboardStats() async {
    final db = await database;
    int lowStock = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM items WHERE quantity <= 10')) ?? 0;

    final allItems = await db.query('items');
    int expiringCount = 0;
    DateTime limit = DateTime.now().add(const Duration(days: 90));
    for (var item in allItems) {
      try {
        DateTime exp = DateFormat('dd/MM/yyyy').parse(item['expiryDate'].toString());
        if (exp.isBefore(limit)) expiringCount++;
      } catch (e) {}
    }

    String today = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final saleRes = await db.rawQuery("SELECT SUM(net_amount) as total FROM bills WHERE date LIKE '$today%'");
    double sale = (saleRes.first['total'] as double?) ?? 0.0;

    return {'sale': sale, 'low_stock': lowStock, 'expiring': expiringCount};
  }

  /// Delete-safe numbering (MAX(id)+1 instead of COUNT).
  static Future<String> getNewInvoiceNo() async {
    final db = await database;
    var res = await db.rawQuery("SELECT COALESCE(MAX(id),0)+1 as nid FROM bills");
    int n = ((res.first['nid'] as num?)?.toInt()) ?? 1;
    return "INV-${n.toString().padLeft(4, '0')}";
  }

  static Future<String> getNewPurchaseNo() async {
    final db = await database;
    var res = await db.rawQuery("SELECT COALESCE(MAX(id),0)+1 as nid FROM purchases");
    int n = ((res.first['nid'] as num?)?.toInt()) ?? 1;
    return "PUR-${n.toString().padLeft(4, '0')}";
  }

  static Future<String> getNewReturnNo() async {
    final db = await database;
    var res = await db.rawQuery("SELECT COALESCE(MAX(id),0)+1 as nid FROM sales_returns");
    int n = ((res.first['nid'] as num?)?.toInt()) ?? 1;
    return "SR-${n.toString().padLeft(4, '0')}";
  }

  static Future<void> saveBill(Map<String, dynamic> bill, List<Map<String, dynamic>> items) async {
    final db = await database;

    // Prepare Bill Data safely (Remove nulls)
    Map<String, dynamic> finalBillData = Map.from(bill);

    // Ensure new columns are present even if null
    if(!finalBillData.containsKey('customer_gstin')) finalBillData['customer_gstin'] = '';
    if(!finalBillData.containsKey('customer_address')) finalBillData['customer_address'] = '';

    int billId = await db.insert('bills', finalBillData);

    for (var item in items) {
      // Fetch expiryDate and type from stock items
      String expiryDate = '';
      String type = '';
      final stockItems = await db.query('items', where: 'name = ?', whereArgs: [item['name']]);
      if (stockItems.isNotEmpty) {
        expiryDate = (stockItems.first['expiryDate'] ?? '') as String;
        type = (stockItems.first['type'] ?? '') as String;
      }

      // Support both 'qty' and 'sold_qty' for backward compatibility
      int qty = ((item['qty'] ?? item['sold_qty']) as num?)?.toInt() ?? 0;
      // Exact batch row sold (batch-wise stock). 0 = legacy fallback by name.
      int stockId = ((item['stock_id'] ?? item['id']) as num?)?.toInt() ?? 0;

      await db.insert('bill_items', {
        'bill_id': billId,
        'stock_id': stockId,
        'item_name': item['name'],
        'batch': item['batch'] ?? '',
        'mrp': item['mrp'] ?? 0.0,
        'qty': qty,
        'free_qty': item['free_qty'] ?? 0,
        'rate': item['price'],
        'total': item['total'],
        'gst_percent': item['gst_percent'] ?? 0,
        'expiryDate': expiryDate,
        'type': type
      });

      // Stock Minus Logic (batch-wise by id, legacy fallback by name)
      int totalQtyToDeduct = qty + ((((item['free_qty'] as num?)?.toInt()) ?? 0));
      if (stockId > 0) {
        await db.rawUpdate("UPDATE items SET quantity = quantity - ? WHERE id = ?", [totalQtyToDeduct, stockId]);
      } else {
        await db.rawUpdate("UPDATE items SET quantity = quantity - ? WHERE name = ?", [totalQtyToDeduct, item['name']]);
      }
    }

    // Save/Update Customer Logic
    if (bill['mobile'] != null && bill['mobile'].length == 10) {
      var cust = await getCustomerByMobile(bill['mobile']);
      double billAmount = bill['net_amount'];
      // Anything other than Udhaar counts as paid (Cash, UPI, Card...)
      double paid = (bill['payment_mode'] == 'Udhaar') ? 0.0 : billAmount;
      double udhaar = (bill['payment_mode'] == 'Udhaar') ? billAmount : 0.0;

      String fullName = bill['customer_name'];
      String cleanName = fullName;
      String title = "Mr";

      // Fix "Mr. Mr." issue by stripping title before saving if it exists
      if(fullName.startsWith("Mr. ")) { title = "Mr."; cleanName = fullName.substring(4); }
      else if(fullName.startsWith("Ms. ")) { title = "Ms."; cleanName = fullName.substring(4); }
      else if(fullName.startsWith("Mrs. ")) { title = "Mrs."; cleanName = fullName.substring(5); }
      else if(fullName.startsWith("Dr. ")) { title = "Dr."; cleanName = fullName.substring(4); }
      else if(fullName.startsWith("M/s ")) { title = "M/s"; cleanName = fullName.substring(4); }

      String? newGstin = bill['customer_gstin'];
      String? newAddress = bill['customer_address'];

      if (cust == null) {
        await db.insert('customers', {
          'name': cleanName, // Save only name, not "Mr. Name"
          'mobile': bill['mobile'],
          'gstin': newGstin ?? '',
          'address': newAddress ?? '',
          'title': title,
          'total_due': udhaar
        });
      } else {
        double oldDue = (cust['total_due'] as num?)?.toDouble() ?? 0.0;
        Map<String, dynamic> updateData = {'total_due': oldDue + udhaar};

        if(newGstin != null && newGstin.isNotEmpty) updateData['gstin'] = newGstin;
        if(newAddress != null && newAddress.isNotEmpty) updateData['address'] = newAddress;
        updateData['name'] = cleanName; // Update clean name

        await db.update('customers', updateData, where: "mobile = ?", whereArgs: [bill['mobile']]);
      }

      await db.insert('customer_ledger', {
        'mobile': bill['mobile'],
        'date': bill['date'],
        'description': "Bill No: ${bill['invoice_no']} (${bill['bill_type'] ?? 'Retail'})",
        'debit': billAmount,
        'credit': paid,
        'balance': udhaar
      });
    }
  }

  static Future<void> deleteBill(int id) async {
    final db = await database;
    await db.delete('bill_items', where: "bill_id = ?", whereArgs: [id]);
    await db.delete('bills', where: "id = ?", whereArgs: [id]);
  }

  static Future<void> deleteBillWithRestoration(int billId, String mobile, double amount, String paymentMode) async {
    final db = await database;
    final items = await db.query('bill_items', where: "bill_id = ?", whereArgs: [billId]);

    for (var item in items) {
      int totalQtyToAdd = (((item['qty'] as num?)?.toInt()) ?? 0) + ((((item['free_qty'] as num?)?.toInt()) ?? 0));
      int stockId = (((item['stock_id'] as num?)?.toInt()) ?? 0);
      if (stockId > 0) {
        // Batch-wise restore to the exact batch sold
        await db.rawUpdate("UPDATE items SET quantity = quantity + ? WHERE id = ?", [totalQtyToAdd, stockId]);
      } else {
        // Legacy fallback: match name + batch first, else name
        String batch = (item['batch'] ?? '').toString();
        final rows = await db.query('items', where: "name = ? AND batch = ?",
            whereArgs: [item['item_name'], batch], limit: 1);
        if (rows.isNotEmpty) {
          await db.rawUpdate("UPDATE items SET quantity = quantity + ? WHERE id = ?", [totalQtyToAdd, rows.first['id']]);
        } else {
          await db.rawUpdate("UPDATE items SET quantity = quantity + ? WHERE name = ?", [totalQtyToAdd, item['item_name']]);
        }
      }
    }

    if (paymentMode == 'Udhaar' && mobile.length == 10) {
      final cust = await getCustomerByMobile(mobile);
      if (cust != null) {
        double currentDue = (cust['total_due'] as num?)?.toDouble() ?? 0.0;
        await db.update('customers', {'total_due': currentDue - amount}, where: "mobile = ?", whereArgs: [mobile]);

        await db.insert('customer_ledger', {
          'mobile': mobile,
          'date': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
          'description': "Bill Reversal (Deleted)",
          'debit': 0.0,
          'credit': amount,
          'balance': currentDue - amount
        });
      }
    }

    await db.delete('bill_items', where: "bill_id = ?", whereArgs: [billId]);
    await db.delete('bills', where: "id = ?", whereArgs: [billId]);
  }

  // --- PURCHASE FUNCTIONS (maal kharid + distributor udhaar) ---

  static Future<int> savePurchase(Map<String, dynamic> purchase, List<Map<String, dynamic>> lines) async {
    final db = await database;
    int purchaseId = await db.insert('purchases', purchase);

    for (var line in lines) {
      await db.insert('purchase_items', {
        'purchase_id': purchaseId,
        'item_name': line['name'],
        'batch': line['batch'] ?? '',
        'qty': line['qty'],
        'free_qty': line['free_qty'] ?? 0,
        'rate': line['rate'],
        'mrp': line['mrp'],
        'gst_percent': line['gst_percent'] ?? 0,
        'expiry': line['expiry'] ?? '',
        'total': line['total'],
      });

      // Stock Plus Logic: same product+batch exists -> merge, else new batch row
      int addQty = (((line['qty'] as num?)?.toInt()) ?? 0) + ((((line['free_qty'] as num?)?.toInt()) ?? 0));
      final existing = await db.query('items', where: 'name = ? AND batch = ?',
          whereArgs: [line['name'], (line['batch'] ?? '').toString()], limit: 1);
      if (existing.isNotEmpty) {
        final row = existing.first;
        int newQty = (((row['quantity'] as num?)?.toInt()) ?? 0) + addQty;
        String newExpiry = (line['expiry'] ?? '').toString().isEmpty
            ? (row['expiryDate'] ?? '').toString()
            : line['expiry'].toString();
        await db.update('items', {
          'quantity': newQty,
          'price': line['mrp'],
          'wholesale_price': line['rate'],
          'gst_percent': line['gst_percent'] ?? 0,
          'expiryDate': newExpiry,
        }, where: 'id = ?', whereArgs: [row['id']]);
      } else {
        // Inherit type/chemical/rack from the same product if it exists
        final same = await db.query('items', where: 'name = ?', whereArgs: [line['name']], limit: 1);
        await db.insert('items', {
          'name': line['name'],
          'chemical': line['chemical'] ?? (same.isNotEmpty ? same.first['chemical'] : ''),
          'type': line['type'] ?? (same.isNotEmpty ? same.first['type'] : 'Tablet'),
          'batch': line['batch'] ?? '',
          'rack': line['rack'] ?? (same.isNotEmpty ? same.first['rack'] : ''),
          'quantity': addQty,
          'price': line['mrp'],
          'wholesale_price': line['rate'],
          'gst_percent': line['gst_percent'] ?? 0,
          'expiryDate': (line['expiry'] ?? '').toString().isEmpty ? '01/01/2030' : line['expiry'],
          'min_stock': 10,
        });
      }
    }

    // Supplier balance + ledger (purchase = credit/udhaar badhta hai, payment = debit/ghatta hai)
    int supplierId = ((purchase['supplier_id'] as num?)?.toInt()) ?? 0;
    double net = (purchase['net_amount'] as num).toDouble();
    double paid = ((purchase['paid_amount'] as num?)?.toDouble()) ?? 0.0;
    if (supplierId > 0) {
      final sup = await db.query('suppliers', where: 'id = ?', whereArgs: [supplierId], limit: 1);
      if (sup.isNotEmpty) {
        double oldBal = (sup.first['balance'] as num?)?.toDouble() ?? 0.0;
        double afterPurchase = oldBal + net;
        double newBal = afterPurchase - paid;
        await db.update('suppliers', {'balance': newBal}, where: 'id = ?', whereArgs: [supplierId]);

        String invLabel = (purchase['supplier_invoice'] ?? '').toString().isEmpty
            ? purchase['purchase_no'].toString()
            : purchase['supplier_invoice'].toString();
        await db.insert('supplier_ledger', {
          'supplier_id': supplierId,
          'date': purchase['date'],
          'description': "Purchase: $invLabel",
          'debit': 0.0,
          'credit': net,
          'balance': afterPurchase
        });
        if (paid > 0) {
          await db.insert('supplier_ledger', {
            'supplier_id': supplierId,
            'date': purchase['date'],
            'description': "Payment (${purchase['payment_mode'] ?? 'Cash'})",
            'debit': paid,
            'credit': 0.0,
            'balance': newBal
          });
        }
      }
    }
    return purchaseId;
  }

  static Future<List<Map<String, dynamic>>> getAllPurchases() async =>
      (await database).query('purchases', orderBy: "id DESC");

  static Future<List<Map<String, dynamic>>> getPurchasesBySupplier(int supplierId) async =>
      (await database).query('purchases', where: "supplier_id = ?", whereArgs: [supplierId], orderBy: "id DESC");

  static Future<List<Map<String, dynamic>>> getPurchaseItems(int purchaseId) async =>
      (await database).query('purchase_items', where: "purchase_id = ?", whereArgs: [purchaseId]);

  /// Deletes a purchase with stock + supplier reversal.
  /// Returns 'ok' on success, else an error message.
  static Future<String> deletePurchase(int purchaseId) async {
    final db = await database;
    final pur = await db.query('purchases', where: 'id = ?', whereArgs: [purchaseId], limit: 1);
    if (pur.isEmpty) return 'Purchase not found';
    final p = pur.first;
    final lines = await getPurchaseItems(purchaseId);

    // 1. Check: maal already sold to ho delete block
    for (var line in lines) {
      int need = (((line['qty'] as num?)?.toInt()) ?? 0) + ((((line['free_qty'] as num?)?.toInt()) ?? 0));
      final rows = await db.query('items', where: 'name = ? AND batch = ?',
          whereArgs: [(line['item_name'] ?? '').toString(), (line['batch'] ?? '').toString()], limit: 1);
      int have = rows.isEmpty ? 0 : ((((rows.first['quantity'] as num?)?.toInt())) ?? 0);
      if (have < need) {
        return 'Cannot delete: ${line['item_name']} ka stock already bik chuka hai';
      }
    }
    // 2. Reverse stock
    for (var line in lines) {
      int need = (((line['qty'] as num?)?.toInt()) ?? 0) + ((((line['free_qty'] as num?)?.toInt()) ?? 0));
      await db.rawUpdate('UPDATE items SET quantity = quantity - ? WHERE name = ? AND batch = ?',
          [need, (line['item_name'] ?? '').toString(), (line['batch'] ?? '').toString()]);
    }
    // 3. Reverse supplier balance + ledger
    int supplierId = ((p['supplier_id'] as num?)?.toInt()) ?? 0;
    double net = (p['net_amount'] as num?)?.toDouble() ?? 0.0;
    double paid = (p['paid_amount'] as num?)?.toDouble() ?? 0.0;
    if (supplierId > 0) {
      final sup = await db.query('suppliers', where: 'id = ?', whereArgs: [supplierId], limit: 1);
      if (sup.isNotEmpty) {
        double oldBal = (sup.first['balance'] as num?)?.toDouble() ?? 0.0;
        double newBal = oldBal - net + paid;
        await db.update('suppliers', {'balance': newBal}, where: 'id = ?', whereArgs: [supplierId]);
        await db.insert('supplier_ledger', {
          'supplier_id': supplierId,
          'date': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
          'description': "Purchase Reversal (${p['purchase_no']})",
          'debit': net,
          'credit': paid,
          'balance': newBal
        });
      }
    }
    await db.delete('purchase_items', where: "purchase_id = ?", whereArgs: [purchaseId]);
    await db.delete('purchases', where: "id = ?", whereArgs: [purchaseId]);
    return 'ok';
  }

  // --- SALES RETURN FUNCTIONS ---

  static Future<int> saveSalesReturn(Map<String, dynamic> ret, List<Map<String, dynamic>> lines) async {
    final db = await database;
    int returnId = await db.insert('sales_returns', ret);

    for (var line in lines) {
      await db.insert('sales_return_items', {
        'return_id': returnId,
        'bill_id': ret['bill_id'],
        'item_name': line['name'],
        'batch': line['batch'] ?? '',
        'stock_id': line['stock_id'] ?? 0,
        'qty': line['qty'],
        'free_qty': line['free_qty'] ?? 0,
        'rate': line['rate'],
        'total': line['total'],
      });
      // Stock wapas jod do (same batch)
      int q = (((line['qty'] as num?)?.toInt()) ?? 0) + ((((line['free_qty'] as num?)?.toInt()) ?? 0));
      int stockId = ((line['stock_id'] as num?)?.toInt()) ?? 0;
      if (stockId > 0) {
        await db.rawUpdate('UPDATE items SET quantity = quantity + ? WHERE id = ?', [q, stockId]);
      } else {
        await db.rawUpdate('UPDATE items SET quantity = quantity + ? WHERE name = ? AND batch = ?',
            [q, (line['name'] ?? '').toString(), (line['batch'] ?? '').toString()]);
      }
    }

    // Udhaar adjust: customer ka due kam karo + ledger entry
    String mobile = (ret['mobile'] ?? '').toString();
    double total = (ret['total_amount'] as num).toDouble();
    if (ret['refund_mode'] == 'Udhaar' && mobile.length == 10) {
      final cust = await getCustomerByMobile(mobile);
      if (cust != null) {
        double due = (cust['total_due'] as num?)?.toDouble() ?? 0.0;
        double newDue = due - total;
        await db.update('customers', {'total_due': newDue}, where: "mobile = ?", whereArgs: [mobile]);
        await db.insert('customer_ledger', {
          'mobile': mobile,
          'date': ret['date'],
          'description': "Sales Return ${ret['return_no']} (Bill ${ret['invoice_no']})",
          'debit': 0.0,
          'credit': total,
          'balance': newDue
        });
      }
    }
    return returnId;
  }

  /// Already-returned qty for a bill line (over-return rokne ke liye).
  static Future<Map<String, int>> getReturnedQty(int billId, String itemName, String batch) async {
    final db = await database;
    final res = await db.rawQuery(
        'SELECT COALESCE(SUM(qty),0) as q, COALESCE(SUM(free_qty),0) as f FROM sales_return_items WHERE bill_id = ? AND item_name = ? AND batch = ?',
        [billId, itemName, batch]);
    return {
      'qty': (((res.first['q'] as num?)?.toInt()) ?? 0),
      'free_qty': (((res.first['f'] as num?)?.toInt()) ?? 0),
    };
  }

  static Future<List<Map<String, dynamic>>> getAllReturns() async =>
      (await database).query('sales_returns', orderBy: "id DESC");

  static Future<List<Map<String, dynamic>>> getReturnItems(int returnId) async =>
      (await database).query('sales_return_items', where: "return_id = ?", whereArgs: [returnId]);

  static Future<List<Map<String, dynamic>>> getAllCustomers() async => (await database).query('customers', orderBy: "name ASC");

  static Future<Map<String, dynamic>?> getCustomerByMobile(String mobile) async {
    final db = await database;
    final res = await db.query('customers', where: "mobile = ?", whereArgs: [mobile]);
    return res.isNotEmpty ? res.first : null;
  }

  static Future<List<Map<String, dynamic>>> getSuppliers() async => (await database).query('suppliers');
  static Future<int> addSupplier(Map<String, dynamic> data) async => (await database).insert('suppliers', data);
  static Future<int> deleteSupplier(int id) async => (await database).delete('suppliers', where: "id = ?", whereArgs: [id]);

  static Future<Map<String, dynamic>?> getSupplierById(int id) async {
    final db = await database;
    final res = await db.query('suppliers', where: "id = ?", whereArgs: [id], limit: 1);
    return res.isNotEmpty ? res.first : null;
  }

  static Future<List<Map<String, dynamic>>> getAllBills() async => (await database).query('bills', orderBy: "id DESC");
  static Future<List<Map<String, dynamic>>> getBillItems(int id) async => (await database).query('bill_items', where: "bill_id = ?", whereArgs: [id]);

  static Future<Map<String, dynamic>> getShopDetails() async {
    final db = await database;
    final res = await db.query('settings');
    if (res.isNotEmpty) return res.first;
    return {'shop_name': 'My Shop', 'address': '', 'phone': '', 'gstin': ''};
  }

  static Future<int> saveShopDetails(Map<String, dynamic> data) async {
    final db = await database;
    await db.delete('settings');
    return await db.insert('settings', data);
  }

  // --- PRODUCT FUNCTIONS (Alias for Items) ---
  static Future<List<Map<String, dynamic>>> getProducts() async => await getItems();

  static Future<int> addProduct(String name, double price, int stock) async {
    return await addItem({
      'name': name,
      'price': price,
      'quantity': stock,
      'chemical': '',
      'type': '',
      'batch': '',
      'rack': '',
      'wholesale_price': price,
      'gst_percent': 0,
      'expiryDate': '',
      'min_stock': 10,
    });
  }

  static Future<int> updateProduct(int id, String name, double price, int stock) async {
    return await updateItem({
      'id': id,
      'name': name,
      'price': price,
      'quantity': stock,
    });
  }

  static Future<int> deleteProduct(int id) async => await deleteItem(id);

  // --- CUSTOMER LEDGER FUNCTIONS ---
  static Future<List<Map<String, dynamic>>> getCustomerLedger(String mobile) async {
    final db = await database;
    return await db.query('customer_ledger', where: "mobile = ?", whereArgs: [mobile], orderBy: "id DESC");
  }

  static Future<int> addPayment(String mobile, double amount, String description) async {
    final db = await database;
    final cust = await getCustomerByMobile(mobile);
    if (cust == null) return 0;

    double currentDue = (cust['total_due'] as num?)?.toDouble() ?? 0.0;
    double newDue = currentDue - amount;

    await db.update('customers', {'total_due': newDue}, where: "mobile = ?", whereArgs: [mobile]);

    return await db.insert('customer_ledger', {
      'mobile': mobile,
      'date': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      'description': description,
      'debit': 0.0,
      'credit': amount,
      'balance': newDue
    });
  }

  // --- BILLS ALIAS ---
  static Future<List<Map<String, dynamic>>> getBills() async => await getAllBills();

  // 🔥🔥 BACKUP & RESTORE FUNCTIONS ADDED HERE 🔥🔥

  static Future<File> getDatabaseFile() async {
    String path = await getDbPath();
    return File(path);
  }

  static Future<bool> restoreDatabase(File backupFile) async {
    try {
      // 1. Pehle database connection close karo taaki lock na ho
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      // 2. Original file ka path lo
      String path = await getDbPath();

      // 3. Backup file ko copy karke purani file ko replace (overwrite) kar do
      await backupFile.copy(path);

      // 4. Database ko naye data ke sath fir se initialize karo
      _database = await _initDB();
      return true;
    } catch (e) {
      print("Restore Error: $e");
      return false;
    }
  }
}
