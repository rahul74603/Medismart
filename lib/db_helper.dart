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
      // 🔥 VERSION BUMP TO 11: To force update old backup files
      version: 11, 
      onCreate: (db, version) async {
        
        // 1. ITEMS / STOCK TABLE
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

        // 4. BILL ITEMS TABLE
        await db.execute('''
          CREATE TABLE bill_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bill_id INTEGER,
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

  static Future<String> getNewInvoiceNo() async {
    final db = await database;
    var res = await db.rawQuery("SELECT COUNT(*) as count FROM bills");
    int count = (Sqflite.firstIntValue(res) ?? 0) + 1;
    return "INV-${count.toString().padLeft(4, '0')}";
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
      int qty = item['qty'] ?? item['sold_qty'];
      
      await db.insert('bill_items', {
        'bill_id': billId,
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
      
      // Stock Minus Logic
      int totalQtyToDeduct = qty + (item['free_qty'] as int? ?? 0);
      await db.rawQuery("UPDATE items SET quantity = quantity - ? WHERE name = ?", [totalQtyToDeduct, item['name']]);
    }

    // Save/Update Customer Logic
    if (bill['mobile'] != null && bill['mobile'].length == 10) {
      var cust = await getCustomerByMobile(bill['mobile']);
      double billAmount = bill['net_amount'];
      double paid = (bill['payment_mode'] == 'Cash') ? billAmount : 0.0;
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
      int totalQtyToAdd = (item['qty'] as int) + (item['free_qty'] as int? ?? 0);
      await db.rawQuery("UPDATE items SET quantity = quantity + ? WHERE name = ?", [totalQtyToAdd, item['item_name']]);
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

  static Future<List<Map<String, dynamic>>> getAllCustomers() async => (await database).query('customers', orderBy: "name ASC");
  
  static Future<Map<String, dynamic>?> getCustomerByMobile(String mobile) async {
    final db = await database;
    final res = await db.query('customers', where: "mobile = ?", whereArgs: [mobile]);
    return res.isNotEmpty ? res.first : null;
  }

  static Future<List<Map<String, dynamic>>> getSuppliers() async => (await database).query('suppliers');
  static Future<int> addSupplier(Map<String, dynamic> data) async => (await database).insert('suppliers', data);
  static Future<int> deleteSupplier(int id) async => (await database).delete('suppliers', where: "id = ?", whereArgs: [id]);

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