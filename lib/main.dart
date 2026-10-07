import 'dart:convert'; 
import 'package:crypto/crypto.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'db_helper.dart';

// Screens Imports
import 'screens/billing_screen.dart';
import 'screens/retail_billing_screen.dart';
import 'screens/purchase_screen.dart';
import 'screens/expiry_claim_screen.dart';
// 🔥 FIX: Hide BillingScreen from history to avoid conflict
import 'screens/history_screen.dart' hide BillingScreen;
import 'services/auto_backup_service.dart'; 
import 'screens/stock_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/suppliers_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/alerts_screen.dart';
import 'services/lang_service.dart';
import 'services/staff_mode.dart';
import 'screens/refill_reminder_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Lang.load();
  await StaffMode.load();
  runApp(const MediSmartApp());
}

class MediSmartApp extends StatelessWidget {
  const MediSmartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MediSmart ERP',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF2F5F8),
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const LicenseCheckScreen(), 
    );
  }
}

class LicenseCheckScreen extends StatefulWidget {
  const LicenseCheckScreen({super.key});

  @override
  State<LicenseCheckScreen> createState() => _LicenseCheckScreenState();
}

class _LicenseCheckScreenState extends State<LicenseCheckScreen> {
  String _deviceId = "Fetching...";
  bool _isLicensed = false;
  bool _isLoading = true;
  final TextEditingController _keyController = TextEditingController();

  final String _secretSalt = "RAHUL_MEDICAL_ERP_2024_SECRET"; 

  // 📅 --- TRIAL DATE SETTING ---
  final String _trialExpiryDate = "2026-02-09";

  @override
  void initState() {
    super.initState();
    _checkLicense();
  }

  void _checkLicense() async {
    final prefs = await SharedPreferences.getInstance();
    bool savedLicense = prefs.getBool('is_licensed') ?? false;

    if (savedLicense) {
      _enterApp();
      return;
    }

    DateTime expiry = DateTime.parse(_trialExpiryDate);
    DateTime today = DateTime.now();

    if (today.isBefore(expiry)) {
      _enterApp();
    } else {
      _getDeviceId();
    }
  }

  void _enterApp() {
    if (mounted) {
      setState(() {
        _isLicensed = true;
        _isLoading = false;
      });
    }
  }

  void _getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String id = "UNKNOWN";
    try {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      id = androidInfo.id;
    } catch (e) {
      id = "ERROR";
    }
    if (mounted) setState(() { _deviceId = id; _isLoading = false; });
  }

  void _verifyKey() async {
    String inputKey = _keyController.text.trim();
    var bytes = utf8.encode(_deviceId + _secretSalt);
    var digest = sha256.convert(bytes);
    String correctKey = digest.toString().substring(0, 8).toUpperCase();

    if (inputKey == correctKey) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_licensed', true); 
      setState(() => _isLicensed = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Activated!"), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Key!"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_isLicensed) return const DashboardScreen();

    return Scaffold(
      backgroundColor: Colors.teal.shade900,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              const Icon(Icons.security, size: 80, color: Colors.white),
              const SizedBox(height: 20),
              const Text("TRIAL EXPIRED", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              SelectableText(_deviceId, style: const TextStyle(fontSize: 20, color: Colors.blue)),
              const SizedBox(height: 20),
              TextField(controller: _keyController, textAlign: TextAlign.center, decoration: const InputDecoration(labelText: "Enter Key", filled: true, fillColor: Colors.white)),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _verifyKey, child: const Text("ACTIVATE"))
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double todaySale = 0.0;
  double todayProfit = 0.0;
  int lowStock = 0;
  int expiring = 0;
  String shopName = "MediSmart ERP";

  @override
  void initState() {
    super.initState();
    _loadStats();
    // Daily auto-backup check (silent, once per day)
    AutoBackupService.runDailyCheck();
  }

  void _loadStats() async {
    final data = await DBHelper.getDashboardStats();
    final shop = await DBHelper.getShopDetails();
    if(mounted) {
      setState(() {
        todaySale = data['sale'];
        todayProfit = (data['profit'] as num?)?.toDouble() ?? 0.0;
        lowStock = data['low_stock'];
        expiring = data['expiring'];
        if(shop['shop_name'] != null && shop['shop_name'].toString().isNotEmpty) {
           shopName = shop['shop_name'];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9), // Premium light background
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- TOP CURVED HEADER & OVERLAPPING STATS ---
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Deep Medical Teal Background
                Container(
                  height: 240,
                  padding: const EdgeInsets.only(top: 60, left: 20, right: 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0F766E), // Deep Medical Teal
                        Color(0xFF042F2E), // Very Dark Green/Teal
                      ],
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(40),
                      bottomRight: Radius.circular(40),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  Lang.t('overview'), 
                                  style: TextStyle(color: Colors.tealAccent.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1)
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  shopName, 
                                  maxLines: 2, 
                                  overflow: TextOverflow.ellipsis, 
                                  style: const TextStyle(
                                    color: Colors.white, 
                                    fontSize: 26, 
                                    fontWeight: FontWeight.bold,
                                  )
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 15),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.refresh_rounded, color: Colors.white), 
                              onPressed: _loadStats
                            ),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Overlapping Stats Cards
                Positioned(
                  top: 160,
                  left: 20,
                  right: 20,
                  child: Row(
                    children: [
                      _buildStatCard(
                        Lang.t('today_sale'), 
                        "₹${todaySale.toStringAsFixed(0)}", 
                        Icons.account_balance_wallet, 
                        const Color(0xFF10B981), // Emerald
                        () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ReportsScreen())),
                        sub: "${Lang.t('profit')} ₹${todayProfit.toStringAsFixed(0)}",
                      ),
                      const SizedBox(width: 12),
                      _buildStatCard(
                        Lang.t('low_stock'), 
                        "$lowStock", 
                        Icons.inventory_2_outlined, 
                        const Color(0xFFF59E0B), // Amber
                        () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AlertsScreen(alertType: 'STOCK')))
                      ),
                      const SizedBox(width: 12),
                      _buildStatCard(
                        Lang.t('expiring'), 
                        "$expiring", 
                        Icons.warning_amber_rounded, 
                        const Color(0xFFEF4444), // Red
                        () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AlertsScreen(alertType: 'EXPIRY')))
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Gap for overlapping cards
            const SizedBox(height: 80),

            // --- MENU GRID ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Lang.t('quick_actions'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 15),
                  GridView.count(
                    crossAxisCount: 3,
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                    shrinkWrap: true, // Needed inside SingleChildScrollView
                    physics: const NeverScrollableScrollPhysics(), // Disables inner scrolling
                    childAspectRatio: 0.9, // Adjust height of grid items
                    children: [
                      _buildMenuBtn(Lang.t('m_billing'), FontAwesomeIcons.fileInvoiceDollar, const Color(0xFF0F766E), _showBillingChooser),
                      _buildMenuBtn(Lang.t('m_stock'), FontAwesomeIcons.boxesStacked, const Color(0xFF0284C7), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const StockScreen())).then((_) => _loadStats())),
                      if (!StaffMode.enabled) _buildMenuBtn(Lang.t('m_purchase'), FontAwesomeIcons.cartShopping, const Color(0xFF92400E), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const PurchaseScreen())).then((_) => _loadStats())),
                      if (!StaffMode.enabled) _buildMenuBtn(Lang.t('m_suppliers'), FontAwesomeIcons.truckFast, const Color(0xFF0D9488), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SuppliersScreen())).then((_) => _loadStats())),
                      if (!StaffMode.enabled) _buildMenuBtn(Lang.t('m_claim'), FontAwesomeIcons.hourglassHalf, const Color(0xFFDC2626), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ExpiryClaimScreen())).then((_) => _loadStats())),
                      _buildMenuBtn(Lang.t('m_history'), FontAwesomeIcons.clockRotateLeft, const Color(0xFF6366F1), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const HistoryScreen()))),
                      _buildMenuBtn(Lang.t('m_customers'), FontAwesomeIcons.users, const Color(0xFFD946EF), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const CustomersScreen()))),
                      _buildMenuBtn(Lang.t('m_refills'), FontAwesomeIcons.pills, const Color(0xFF0D9488), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const RefillReminderScreen())).then((_) => _loadStats())),
                      if (!StaffMode.enabled) _buildMenuBtn(Lang.t('m_reports'), FontAwesomeIcons.chartPie, const Color(0xFFF97316), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ReportsScreen()))),
                      if (!StaffMode.enabled) _buildMenuBtn(Lang.t('m_settings'), FontAwesomeIcons.gear, const Color(0xFF64748B), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsScreen())).then((_) => _loadStats())),
                    ],
                  ),
                  const SizedBox(height: 30), // Bottom padding
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- RETAIL / WHOLESALE CHOOSER ---
  void _showBillingChooser() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(Lang.t('new_bill'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _chooserCard(
                      Lang.t('retail'),
                      Lang.t('retail_sub'),
                      FontAwesomeIcons.bolt,
                      Colors.teal,
                      () {
                        Navigator.pop(ctx);
                        Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (c) =>
                                        const RetailBillingScreen()))
                            .then((_) => _loadStats());
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _chooserCard(
                      Lang.t('wholesale'),
                      Lang.t('wholesale_sub'),
                      FontAwesomeIcons.fileInvoiceDollar,
                      const Color(0xFFFF6F00),
                      () {
                        Navigator.pop(ctx);
                        Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (c) => const BillingScreen()))
                            .then((_) => _loadStats());
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chooserCard(String title, String subtitle, IconData icon,
      Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: color)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildStatCard(String title, String val, IconData icon, Color color, VoidCallback onTap, {String? sub}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 12),
              Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              const SizedBox(height: 4),
              Text(title, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              if (sub != null)
                Text(sub, style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuBtn(String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              title, 
              style: const TextStyle(
                fontWeight: FontWeight.w700, 
                fontSize: 13, 
                color: Color(0xFF334155)
              )
            ),
          ],
        ),
      ),
    );
  }
}
