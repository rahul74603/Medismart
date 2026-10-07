import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:file_picker/file_picker.dart';
import '../db_helper.dart'; // ✅ ये लाइन अब सही कर दी गई है (../ लगा दिया)
import '../services/app_prefs.dart';
import '../services/auto_backup_service.dart';
import '../services/lang_service.dart';
import '../services/staff_mode.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  final _dlCtrl = TextEditingController(); 
  final _termsCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  String _qrPath = '';

  int _receiptWidth = 80;
  bool _autoPrint = true;
  bool _express = true;
  bool _askWa = true;
  String _lastBackup = 'Never';

  bool _isLoading = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _gstCtrl.dispose();
    _dlCtrl.dispose();
    _termsCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    final data = await DBHelper.getShopDetails();
    if(mounted) {
      setState(() {
        _nameCtrl.text = data['shop_name'] ?? '';
        _addressCtrl.text = data['address'] ?? '';
        _phoneCtrl.text = data['phone'] ?? '';
        _gstCtrl.text = data['gstin'] ?? '';
        _dlCtrl.text = data['dl_no'] ?? ''; 
        _termsCtrl.text = data['terms'] ?? '';
        _isLoading = false;
      });
      // Printer + backup prefs
      final width = await AppPrefs.getReceiptWidth();
      final auto = await AppPrefs.getAutoPrint();
      final ex = await AppPrefs.getExpressAdd();
      final wa = await AppPrefs.getAskWhatsApp();
      final upi = await AppPrefs.getUpiId();
      final qr = await AppPrefs.getQrPath();
      final lastBk = await AppPrefs.getLastBackupLabel();
      if (mounted) {
        setState(() {
          _receiptWidth = width;
          _autoPrint = auto;
          _express = ex;
          _askWa = wa;
          _upiCtrl.text = upi;
          _qrPath = qr;
          _lastBackup = lastBk;
        });
      }
    }
  }

  void _savePrinterSettings() async {
    await AppPrefs.setReceiptWidth(_receiptWidth);
    await AppPrefs.setAutoPrint(_autoPrint);
    await AppPrefs.setExpressAdd(_express);
    await AppPrefs.setAskWhatsApp(_askWa);
    await AppPrefs.setUpiId(_upiCtrl.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Printer Settings Saved!"),
          backgroundColor: Colors.green));
    }
  }

  void _backupNowLocal() async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()));
    final path = await AutoBackupService.backupNow();
    if (mounted) Navigator.pop(context);
    if (path != null) {
      final label = await AppPrefs.getLastBackupLabel();
      if (mounted) {
        setState(() => _lastBackup = label);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Backup saved! ($label)"),
            backgroundColor: Colors.green));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Backup failed!"), backgroundColor: Colors.red));
      }
    }
  }

  void _uploadToDrive() async {
    try {
      String? path = await AutoBackupService.latestBackupPath();
      path ??= await AutoBackupService.backupNow();
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("No backup file found!"),
              backgroundColor: Colors.red));
        }
        return;
      }
      final label = await AppPrefs.getLastBackupLabel();
      if (mounted) setState(() => _lastBackup = label);
      await Share.shareXFiles([XFile(path)],
          text: "MediSmart Backup ($label) - Save to Google Drive");
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Share failed: $e")));
      }
    }
  }

  void _saveSettings() async {
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Shop Name is required!")));
      return;
    }

    final db = await DBHelper.database;

    try {
      await db.rawQuery("SELECT dl_no FROM settings LIMIT 0");
    } catch (e) {
      print("Adding missing column dl_no...");
      await db.execute("ALTER TABLE settings ADD COLUMN dl_no TEXT");
    }

    await db.update('settings', {
      'shop_name': _nameCtrl.text,
      'address': _addressCtrl.text,
      'phone': _phoneCtrl.text,
      'gstin': _gstCtrl.text,
      'dl_no': _dlCtrl.text, 
      'terms': _termsCtrl.text
    }, where: "id = ?", whereArgs: [1]); 

    var check = await db.query('settings');
    if (check.isEmpty) {
       await db.insert('settings', {
        'id': 1,
        'shop_name': _nameCtrl.text,
        'address': _addressCtrl.text,
        'phone': _phoneCtrl.text,
        'gstin': _gstCtrl.text,
        'dl_no': _dlCtrl.text,
        'terms': _termsCtrl.text
      });
    }

    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Settings Saved!"), backgroundColor: Colors.green));
  }

  void _backupData() async {
    try {
      String dbPath = await DBHelper.getDbPath();
      await Share.shareXFiles([XFile(dbPath)], text: "MediSmart Database Backup");
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Backup Failed: $e")));
    }
  }
void _restoreData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        File backupFile = File(result.files.single.path!);

        if (!backupFile.path.endsWith('.db')) {
           if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a valid .db file!"), backgroundColor: Colors.red));
           return;
        }

        showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));

        bool success = await DBHelper.restoreDatabase(backupFile);

        if(mounted) Navigator.pop(context); // Loading hatao

        if (success) {
          if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Backup Restored! Please restart the app."), backgroundColor: Colors.green));
          _loadSettings(); // Naya data load karne ke liye
        } else {
          if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Restore Failed!"), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }
  void _resetApp() {
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ RESET EVERYTHING?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("This will delete ALL Bills, Customers, Stock and History permanently.", style: TextStyle(color: Colors.red)),
            const SizedBox(height: 10),
            const Text("Type 'DELETE' to confirm:"),
            TextField(controller: confirmCtrl, decoration: const InputDecoration(border: OutlineInputBorder()))
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (confirmCtrl.text == 'DELETE') {
                final db = await DBHelper.database;
                await db.delete('bills');
                await db.delete('bill_items');
                await db.delete('items');
                await db.delete('customers');
                await db.delete('customer_ledger');
                await db.delete('suppliers');
                await db.delete('supplier_ledger');
                await db.delete('purchases');
                await db.delete('purchase_items');
                await db.delete('sales_returns');
                await db.delete('sales_return_items');
                await db.delete('supplier_claims');
                await db.delete('supplier_claim_items');
                Navigator.pop(ctx);
                if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("App Data Reset Successfully!")));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("WIPE DATA"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Lang.t('s_title')), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Lang.t('s_shop'), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
            const SizedBox(height: 15),
            
            _buildTextField("Shop Name", _nameCtrl, Icons.store),
            _buildTextField("Address / Location", _addressCtrl, Icons.location_on),
            _buildTextField("Phone Number", _phoneCtrl, Icons.phone, isNumber: true),
            
            _buildTextField("Drug License No. (D.L.)", _dlCtrl, Icons.verified_user),

            _buildTextField("GSTIN (Optional)", _gstCtrl, Icons.receipt_long),
            
            const SizedBox(height: 20),
            Text(Lang.t('s_terms_h'), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
            const SizedBox(height: 10),
            TextField(
              controller: _termsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: "Terms & Conditions", border: OutlineInputBorder(), hintText: "e.g. Goods once sold will not be taken back."),
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 15)),
                child: const Text("SAVE SHOP DETAILS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),

            const Divider(height: 40, thickness: 2),

            Text(Lang.t('s_printer'), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
            const SizedBox(height: 15),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text("Paper Size:", style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 58, label: Text("58mm")),
                            ButtonSegment(value: 80, label: Text("80mm")),
                          ],
                          selected: {_receiptWidth},
                          onSelectionChanged: (s) => setState(() => _receiptWidth = s.first),
                          style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Auto-print after Retail bill", style: TextStyle(fontSize: 14)),
                    subtitle: const Text("Bill save hote hi print dialog khulega", style: TextStyle(fontSize: 11)),
                    value: _autoPrint,
                    activeColor: Colors.teal,
                    onChanged: (v) => setState(() => _autoPrint = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(Lang.t('ex_express'), style: const TextStyle(fontSize: 14)),
                    subtitle: Text(Lang.t('ex_express_sub'), style: const TextStyle(fontSize: 11)),
                    value: _express,
                    activeColor: Colors.teal,
                    onChanged: (v) => setState(() => _express = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(Lang.t('ex_wa'), style: const TextStyle(fontSize: 14)),
                    subtitle: Text(Lang.t('ex_wa_sub'), style: const TextStyle(fontSize: 11)),
                    value: _askWa,
                    activeColor: Colors.teal,
                    onChanged: (v) => setState(() => _askWa = v),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: _qrPath.isNotEmpty && File(_qrPath).existsSync()
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(File(_qrPath), fit: BoxFit.cover))
                            : const Icon(Icons.qr_code_2, size: 40, color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Shop QR Code (bill pe chapega)",
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _uploadQr,
                                  icon: const Icon(Icons.upload, size: 16),
                                  label: const Text("UPLOAD"),
                                ),
                                if (_qrPath.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: _removeQr,
                                    icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                    label: const Text("Remove", style: TextStyle(color: Colors.red)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _upiCtrl,
                    decoration: const InputDecoration(
                      labelText: "Shop UPI ID (for QR on receipt)",
                      hintText: "e.g. dukaan@upi",
                      prefixIcon: Icon(Icons.qr_code, color: Colors.grey),
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _savePrinterSettings,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                      child: const Text("SAVE PRINTER SETTINGS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Print ke time Android print dialog khulega - wahan apna Bluetooth/USB thermal printer (XPrinter, Epson...) select karo.",
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),

            const Divider(height: 40, thickness: 2),

            Text(Lang.t('s_lang'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'en', label: Text('English')),
                  ButtonSegment(value: 'hi', label: Text('हिंदी')),
                ],
                selected: {Lang.code},
                onSelectionChanged: (s) async {
                  await Lang.set(s.first);
                  if (!context.mounted) return;
                  Navigator.popUntil(context, (r) => r.isFirst);
                },
              ),
            ),

            const Divider(height: 40, thickness: 2),

            Text(Lang.t('s_staff'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(Lang.t('staff_mode')),
                    subtitle: Text(StaffMode.enabled ? Lang.t('staff_on') : Lang.t('staff_off')),
                    value: StaffMode.enabled,
                    onChanged: (v) => _toggleStaff(v),
                  ),
                  ListTile(
                    leading: const Icon(Icons.pin, color: Colors.teal),
                    title: Text(Lang.t('staff_set_pin')),
                    onTap: _setStaffPin,
                  ),
                ],
              ),
            ),

            const Divider(height: 40, thickness: 2),

            Text(Lang.t('s_data'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Text(
                "Auto-Backup ON (roz 1 baar, last 7 safe)\nLast backup: $_lastBackup",
                style: TextStyle(fontSize: 12, color: Colors.green.shade900),
              ),
            ),
            const SizedBox(height: 10),

            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.backup, color: Colors.white)),
              title: const Text("Backup Now"),
              subtitle: const Text("Turant backup lo (phone me safe)"),
              onTap: _backupNowLocal,
            ),

            const SizedBox(height: 10),
            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.cloud_upload, color: Colors.white)),
              title: const Text("Upload to Google Drive"),
              subtitle: const Text("Backup file Drive/WhatsApp pe bhejo"),
              onTap: _uploadToDrive,
            ),

            const SizedBox(height: 10),
            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.share, color: Colors.white)),
              title: const Text("Share Live Database"),
              subtitle: const Text("Current database file share karo"),
              onTap: _backupData,
            ),

            const SizedBox(height: 10),
            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.restore, color: Colors.white)),
              title: const Text("Restore Data"),
              subtitle: const Text("Restore database from an old .db backup file"),
              onTap: _restoreData,
            ),
            
            const SizedBox(height: 10),
            ListTile(
              tileColor: Colors.red.shade50,
              leading: const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.delete_forever, color: Colors.white)),
              title: const Text("Reset All Data", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              subtitle: const Text("Delete everything and start fresh"),
              onTap: _resetApp,
            ),
            
            const SizedBox(height: 20),
            const Center(child: Text("MediSmart ERP v1.0", style: TextStyle(color: Colors.grey))),
          ],
        ),
      ),
    );
  }

    Future<void> _toggleStaff(bool v) async {
    if (v) {
      if (!await StaffMode.hasPin()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('staff_need_pin')), backgroundColor: Colors.red));
        return;
      }
      await StaffMode.set(true);
    } else {
      final pin = await _askPin(Lang.t('staff_exit'));
      if (pin == null) return;
      if (!await StaffMode.check(pin)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('staff_wrong')), backgroundColor: Colors.red));
        return;
      }
      await StaffMode.set(false);
    }
    if (!mounted) return;
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  Future<String?> _askPin(String title) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: InputDecoration(hintText: Lang.t('staff_pin_hint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(Lang.t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: Text(Lang.t('done'))),
        ],
      ),
    );
  }

  Future<void> _setStaffPin() async {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(Lang.t('staff_set_pin')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: c1, keyboardType: TextInputType.number, maxLength: 4, obscureText: true,
                decoration: InputDecoration(hintText: Lang.t('staff_pin_hint'))),
            TextField(controller: c2, keyboardType: TextInputType.number, maxLength: 4, obscureText: true,
                decoration: InputDecoration(hintText: Lang.t('staff_pin_confirm'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(Lang.t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(Lang.t('save'))),
        ],
      ),
    );
    if (ok != true) return;
    if (c1.text.trim().length != 4 || c1.text.trim() != c2.text.trim()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('staff_wrong')), backgroundColor: Colors.red));
      return;
    }
    await StaffMode.setPin(c1.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('done'))));
  }

  Future<void> _uploadQr() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null || res.files.isEmpty) return;
    final path = res.files.first.path ?? '';
    if (path.isEmpty) return;
    await AppPrefs.setQrPath(path);
    if (!mounted) return;
    setState(() => _qrPath = path);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("QR set ho gaya! Ab bill pe yehi chapega."),
        backgroundColor: Colors.green));
  }

  Future<void> _removeQr() async {
    await AppPrefs.setQrPath('');
    if (!mounted) return;
    setState(() => _qrPath = '');
  }

  Widget _buildTextField(String label, TextEditingController ctrl, IconData icon, {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: ctrl,
        keyboardType: isNumber ? TextInputType.phone : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.grey),
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white
        ),
      ),
    );
  }
}