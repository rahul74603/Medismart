import 'package:flutter/material.dart';
import '../db_helper.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> _statsFuture;
  late Future<List<Map<String, dynamic>>> _recentBillsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _statsFuture = DBHelper.getDashboardStats();
    _recentBillsFuture = DBHelper.getBills();
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 6),
                  Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(dynamic v) {
    if (v == null) return "₹0";
    return "₹${(v as num).toStringAsFixed(2)}";
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _load());
        await Future.wait([_statsFuture, _recentBillsFuture]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            FutureBuilder<Map<String, dynamic>>(
              future: _statsFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
                }
                final stats = snap.data ?? {};
                final bills = (stats['total_bills'] ?? 0).toString();
                final sales = _formatAmount(stats['total_sales']);
                final products = (stats['total_products'] ?? 0).toString();
                final customers = (stats['total_customers'] ?? 0).toString();

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildStatCard('Total Bills', bills, Colors.blue, Icons.receipt_long)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildStatCard('Total Sales', sales, Colors.green, Icons.attach_money)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildStatCard('Products', products, Colors.purple, Icons.inventory_2)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildStatCard('Customers', customers, Colors.orange, Icons.people)),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Recent Bills', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _recentBillsFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final bills = snap.data ?? [];
                if (bills.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text('No bills yet', style: TextStyle(color: Colors.grey[600]))),
                  );
                }
                final recent = bills.take(8).toList();
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: recent.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final b = recent[i];
                    final id = b['id'] ?? '';
                    final name = (b['customer_name'] ?? '').toString().isEmpty ? 'Walk-in' : b['customer_name'];
                    final amt = _formatAmount(b['grand_total'] ?? b['total_amount'] ?? 0);
                    final when = b['created_at'] ?? '';
                    final mode = b['payment_mode'] ?? '';
                    return Card(
                      child: ListTile(
                        title: Text('$name • $amt'),
                        subtitle: Text('Bill #$id • $mode\n$when', maxLines: 2, overflow: TextOverflow.ellipsis),
                        isThreeLine: true,
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}