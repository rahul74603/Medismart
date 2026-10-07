import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import '../services/whatsapp_helper.dart';

/// EXPIRY CLAIM MANAGER
/// Tab 1 - New Claim: expiring batches select karo -> supplier -> claim save + WhatsApp
/// Tab 2 - History: pending/settled claims, settle karne pe stock out + supplier udhaar kam
class ExpiryClaimScreen extends StatefulWidget {
  final int? supplierId;
  final String? supplierName;

  const ExpiryClaimScreen({super.key, this.supplierId, this.supplierName});

  @override
  State<ExpiryClaimScreen> createState() => _ExpiryClaimScreenState();
}

class _ExpiryClaimScreenState extends State<ExpiryClaimScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _suppliers = [];
  int? _selectedSupplierId;

  // Expiry candidates
  List<Map<String, dynamic>> _candidates = [];
  Set<int> _checked = {};
  int _daysFilter = 90;
  bool _loadingCandidates = true;

  // Claims history
  List<Map<String, dynamic>> _claims = [];
  bool _loadingClaims = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _loadAll() async {
    final suppliers = await DBHelper.getSuppliers();
    if (!mounted) return;
    setState(() {
      _suppliers = suppliers;
      if (widget.supplierId != null &&
          suppliers.any((s) => s['id'] == widget.supplierId)) {
        _selectedSupplierId = widget.supplierId;
      }
    });
    _loadCandidates();
    _loadClaims();
  }

  void _loadCandidates() async {
    setState(() => _loadingCandidates = true);
    final items = await DBHelper.getItems();
    final now = DateTime.now();
    final limit = now.add(Duration(days: _daysFilter));
    List<Map<String, dynamic>> out = [];
    for (var r in items) {
      int qty = (((r['quantity'] as num?)?.toInt()) ?? 0);
      if (qty <= 0) continue;
      final exp = DBHelper.parseExpiry((r['expiryDate'] ?? '').toString());
      if (exp == null) continue;
      if (exp.isBefore(limit)) {
        out.add({
          'id': r['id'],
          'name': r['name'],
          'batch': (r['batch'] ?? '').toString(),
          'expiry': (r['expiryDate'] ?? '').toString(),
          'expDate': exp,
          'qty': qty,
          'rate': (((r['wholesale_price'] as num?)?.toDouble()) ?? 0.0),
        });
      }
    }
    out.sort((a, b) =>
        (a['expDate'] as DateTime).compareTo(b['expDate'] as DateTime));
    if (mounted) {
      setState(() {
        _candidates = out;
        _checked = {};
        _loadingCandidates = false;
      });
    }
  }

  void _loadClaims() async {
    setState(() => _loadingClaims = true);
    final data = widget.supplierId != null
        ? await DBHelper.getClaimsBySupplier(widget.supplierId!)
        : await DBHelper.getAllClaims();
    if (mounted) {
      setState(() {
        _claims = data;
        _loadingClaims = false;
      });
    }
  }

  double get _selectedValue {
    double t = 0;
    for (var c in _candidates) {
      if (_checked.contains((c['id'] as num).toInt())) {
        t += (c['qty'] as int) * ((c['rate'] as num).toDouble());
      }
    }
    return t;
  }

  Future<void> _saveClaim({required bool andSend}) async {
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Pehle Supplier select karo!"),
          backgroundColor: Colors.red));
      return;
    }
    if (_checked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Koi batch select nahi kiya!")));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final claimNo = await DBHelper.getNewClaimNo();
      String supName = '';
      Map<String, dynamic>? supplier;
      try {
        supplier = _suppliers
            .firstWhere((s) => s['id'] == _selectedSupplierId);
        supName = supplier['name'].toString();
      } catch (_) {}

      final dateStr =
          DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      final lines = _candidates
          .where((c) => _checked.contains((c['id'] as num).toInt()))
          .map((c) => {
                'name': c['name'],
                'batch': c['batch'],
                'expiry': c['expiry'],
                'qty': c['qty'],
                'rate': c['rate'],
                'total': (c['qty'] as int) *
                    ((c['rate'] as num).toDouble()),
              })
          .toList();

      await DBHelper.saveClaim({
        'claim_no': claimNo,
        'supplier_id': _selectedSupplierId,
        'supplier_name': supName,
        'date': dateStr,
        'total_value': _selectedValue,
        'status': 'Pending',
        'remark': '',
      }, lines);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Claim $claimNo saved!"),
          backgroundColor: Colors.green));

      if (andSend && supplier != null) {
        await WhatsAppHelper.sendExpiryClaim(context, supplier, claimNo,
            dateStr.split(' ').first, lines, _selectedValue);
      }

      _loadClaims();
      setState(() => _checked = {});
      _tab.animateTo(1);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _viewClaim(Map<String, dynamic> claim) async {
    final items =
        await DBHelper.getClaimItems((claim['id'] as num).toInt());
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("${claim['claim_no']} • ${claim['supplier_name']}",
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${claim['date']} • Status: ${claim['status']}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[i];
                    return ListTile(
                      dense: true,
                      title: Text((it['item_name'] ?? '').toString(),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                          "B:${(it['batch'] ?? '-').toString()} • Exp:${(it['expiry'] ?? '-').toString()} • Qty ${it['qty']}",
                          style: const TextStyle(fontSize: 11)),
                      trailing: Text(
                          "₹${((it['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}",
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Close")),
        ],
      ),
    );
  }

  Future<void> _settleClaim(Map<String, dynamic> claim) async {
    bool confirm = await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Settle Claim?"),
            content: Text(
                "${claim['claim_no']} settle hoga:\n• Stock se maal minus hoga\n• ${claim['supplier_name']} ka udhaar Rs.${(((claim['total_value'] as num?)?.toDouble()) ?? 0).toStringAsFixed(0)} kam hoga\n\nDistributor ne maal le liya / credit de diya?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text("NO")),
              TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text("YES, SETTLE",
                      style: TextStyle(color: Colors.green))),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    await DBHelper.settleClaim((claim['id'] as num).toInt());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Claim settled! Stock + udhaar adjusted."),
        backgroundColor: Colors.green));
    _loadClaims();
    _loadCandidates();
  }

  Future<void> _deleteClaim(Map<String, dynamic> claim) async {
    bool confirm = await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Delete Claim?"),
            content: const Text("Pending claim delete ho jayega (koi stock change nahi hoga)."),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text("NO")),
              TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child:
                      const Text("YES", style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    await DBHelper.deleteClaim((claim['id'] as num).toInt());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Claim deleted!")));
    _loadClaims();
  }

  Future<void> _resendClaim(Map<String, dynamic> claim) async {
    final items =
        await DBHelper.getClaimItems((claim['id'] as num).toInt());
    final sup = await DBHelper.getSupplierById(
        ((claim['supplier_id'] as num?)?.toInt()) ?? 0);
    if (!mounted) return;
    if (sup == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Supplier nahi mila!"), backgroundColor: Colors.red));
      return;
    }
    final lines = items
        .map((it) => {
              'name': it['item_name'],
              'batch': it['batch'],
              'expiry': it['expiry'],
              'qty': it['qty'],
              'total': it['total'],
            })
        .toList();
    await WhatsAppHelper.sendExpiryClaim(
        context,
        sup,
        (claim['claim_no'] ?? '').toString(),
        (claim['date'] ?? '').toString().split(' ').first,
        lines,
        ((claim['total_value'] as num?)?.toDouble()) ?? 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        title: Text(widget.supplierName != null
            ? "Expiry Claims: ${widget.supplierName}"
            : "Expiry Claim Manager"),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "New Claim", icon: Icon(Icons.add_box, size: 18)),
            Tab(text: "History", icon: Icon(Icons.history, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ---------- TAB 1: NEW CLAIM ----------
          Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedSupplierId,
                            hint: const Text("Select Supplier *"),
                            isDense: true,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.local_shipping,
                                  size: 18, color: Colors.red),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            items: _suppliers
                                .map((s) => DropdownMenuItem<int>(
                                      value: (s['id'] as num).toInt(),
                                      child: Text("${s['name']}",
                                          overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedSupplierId = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [30, 60, 90, 180].map((d) {
                          final sel = _daysFilter == d;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text("$d days"),
                              selected: sel,
                              selectedColor: Colors.red,
                              labelStyle: TextStyle(
                                  color: sel ? Colors.white : Colors.black,
                                  fontSize: 12),
                              onSelected: (_) {
                                setState(() => _daysFilter = d);
                                _loadCandidates();
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Expiring batches (${_candidates.length})",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    if (_checked.isNotEmpty)
                      Text(
                          "${_checked.length} selected • ₹${_selectedValue.toStringAsFixed(0)}",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                              fontSize: 13)),
                  ],
                ),
              ),
              Expanded(
                child: _loadingCandidates
                    ? const Center(child: CircularProgressIndicator())
                    : _candidates.isEmpty
                        ? const Center(
                            child: Text("Koi expiring batch nahi hai. Good! 🎉",
                                style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _candidates.length,
                            itemBuilder: (ctx, i) {
                              final c = _candidates[i];
                              final id = (c['id'] as num).toInt();
                              final sel = _checked.contains(id);
                              final expired =
                                  (c['expDate'] as DateTime).isBefore(
                                      DateTime.now());
                              return Card(
                                color: sel ? Colors.red.shade50 : Colors.white,
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                      color: sel
                                          ? Colors.red
                                          : Colors.grey.shade200),
                                ),
                                child: CheckboxListTile(
                                  value: sel,
                                  activeColor: Colors.red,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _checked.add(id);
                                      } else {
                                        _checked.remove(id);
                                      }
                                    });
                                  },
                                  title: Text(c['name'],
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                  subtitle: Text(
                                      "B:${c['batch']} • Exp:${c['expiry']} • Qty:${c['qty']} • Rate ₹${((c['rate'] as num).toDouble()).toStringAsFixed(1)}${expired ? ' • EXPIRED' : ''}",
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: expired
                                              ? Colors.red
                                              : Colors.grey[700],
                                          fontWeight: expired
                                              ? FontWeight.bold
                                              : FontWeight.normal)),
                                  secondary: Text(
                                      "₹${((c['qty'] as int) * ((c['rate'] as num).toDouble())).toStringAsFixed(0)}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                ),
                              );
                            },
                          ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => _saveClaim(andSend: false),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(
                              color: Colors.red, width: 2),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("SAVE ONLY",
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving
                            ? null
                            : () => _saveClaim(andSend: true),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.send,
                                color: Colors.white, size: 18),
                        label: const Text("SAVE + WHATSAPP",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ---------- TAB 2: HISTORY ----------
          _loadingClaims
              ? const Center(child: CircularProgressIndicator())
              : _claims.isEmpty
                  ? const Center(
                      child: Text("No claims yet",
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _claims.length,
                      itemBuilder: (ctx, i) {
                        final cl = _claims[i];
                        final pending =
                            (cl['status'] ?? 'Pending') == 'Pending';
                        double val =
                            ((cl['total_value'] as num?)?.toDouble()) ??
                                0.0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("${cl['claim_no']}",
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15)),
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: pending
                                            ? Colors.orange.shade100
                                            : Colors.green.shade100,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                          pending ? "Pending" : "Settled",
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: pending
                                                  ? Colors.orange.shade900
                                                  : Colors.green.shade900)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                    "${cl['supplier_name']} • ${cl['date']}",
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600])),
                                const SizedBox(height: 4),
                                Text("₹${val.toStringAsFixed(0)}",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: Colors.red)),
                                const Divider(),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _viewClaim(cl),
                                      icon: const Icon(Icons.visibility,
                                          size: 16),
                                      label: const Text("View",
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                    if (pending) ...[
                                      TextButton.icon(
                                        onPressed: () => _resendClaim(cl),
                                        icon: const Icon(Icons.send,
                                            size: 16, color: Colors.green),
                                        label: const Text("WhatsApp",
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green)),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => _settleClaim(cl),
                                        icon: const Icon(
                                            Icons.check_circle,
                                            size: 16,
                                            color: Colors.teal),
                                        label: const Text("Settle",
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.teal)),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => _deleteClaim(cl),
                                        icon: const Icon(Icons.delete,
                                            size: 16, color: Colors.red),
                                        label: const Text("Delete",
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.red)),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ],
      ),
    );
  }
}
