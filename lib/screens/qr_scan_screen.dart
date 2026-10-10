import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/gemini_service.dart';
import '../services/lang_service.dart';

/// Photo-based medicine scanner. Uses Gemini AI to read medicine labels.
/// Returns Map<String,String> with extracted fields, or null if cancelled.
/// All fields are editable — user reviews before saving.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  Uint8List? _imageBytes;
  bool _picking = false;
  bool _analyzing = false;
  bool _showForm = false;
  String _error = '';

  final Map<String, TextEditingController> _ctrls = {};

  static const _fieldOrder = [
    'name', 'salts', 'batch', 'expiry', 'mfg', 'mrp',
    'manufacturer', 'gtin', 'pack_size', 'hsn',
  ];
  static const _fieldLabels = {
    'name': 'Medicine Name', 'salts': 'Salts / Composition',
    'batch': 'Batch No.', 'expiry': 'Expiry Date', 'mfg': 'Mfg Date',
    'mrp': 'MRP (Rs)', 'manufacturer': 'Manufacturer',
    'gtin': 'Barcode / GTIN', 'pack_size': 'Pack Size', 'hsn': 'HSN Code',
  };
  static const _fieldIcons = {
    'name': Icons.medical_services, 'salts': Icons.science,
    'batch': Icons.tag, 'expiry': Icons.event, 'mfg': Icons.calendar_today,
    'mrp': Icons.currency_rupee, 'manufacturer': Icons.factory,
    'gtin': Icons.barcode_reader, 'pack_size': Icons.inventory_2, 'hsn': Icons.numbers,
  };

  @override
  void initState() {
    super.initState();
    for (final k in _fieldOrder) { _ctrls[k] = TextEditingController(); }
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage(true));
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pickImage(bool fromCamera) async {
    if (_picking) return;
    _picking = true;
    try {
      final img = await ImagePicker().pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85, maxWidth: 1920, maxHeight: 1920,
      );
      if (!mounted || img == null) { _picking = false; return; }
      final bytes = await img.readAsBytes();
      if (!mounted) return;
      setState(() { _imageBytes = bytes; _showForm = false; _fields = {}; _error = ''; });
      _analyze();
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera error: $e');
    } finally { _picking = false; }
  }

  Map<String, String> _fields = {};

  Future<void> _analyze() async {
    if (_imageBytes == null || _imageBytes!.isEmpty) return;
    setState(() { _analyzing = true; _error = ''; });
    final result = await GeminiService.tryImageWithLoader(context, _imageBytes!);
    if (!mounted) return;
    if (result == null || result.isEmpty) {
      setState(() { _analyzing = false; _error = 'AI could not read the image. Try a clearer photo.'; });
      return;
    }
    for (final k in _fieldOrder) { _ctrls[k]!.text = (result[k] ?? '').trim(); }
    setState(() { _fields = result; _analyzing = false; _showForm = true; });
  }

  void _save() {
    final out = <String, String>{};
    for (final k in _fieldOrder) { out[k] = _ctrls[k]!.text.trim(); }
    if ((out['name'] ?? '').isEmpty && (out['salts'] ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter at least medicine name or salts'), backgroundColor: Colors.orange,
      ));
      return;
    }
    try { HapticFeedback.mediumImpact(); } catch (_) {}
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(Lang.t('qr_title')),
        backgroundColor: Colors.teal, foregroundColor: Colors.white,
        actions: [
          if (!_showForm)
            IconButton(icon: const Icon(Icons.text_fields), tooltip: 'Enter manually',
              onPressed: () => setState(() { _showForm = true; _error = ''; })),
        ],
      ),
      body: _showForm ? _buildForm() : _buildPhotoStep(),
    );
  }

  Widget _buildPhotoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        if (_imageBytes != null) ...[
          ClipRRect(borderRadius: BorderRadius.circular(16),
            child: Image.memory(_imageBytes!, height: 280, width: double.infinity, fit: BoxFit.cover)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _analyzing ? null : () => _pickImage(false),
              icon: const Icon(Icons.photo_library), label: const Text('Gallery'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(onPressed: _analyzing ? null : () => _pickImage(true),
              icon: const Icon(Icons.camera_alt), label: const Text('Retake'))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(onPressed: _analyzing ? null : _analyze,
              icon: _analyzing ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
              label: Text(_analyzing ? 'Reading...' : 'Scan'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white))),
          ]),
        ] else ...[
          Container(height: 280, width: double.infinity,
            decoration: BoxDecoration(color: Colors.teal.withOpacity(0.05), borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.teal.shade200, width: 2)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.camera_alt, size: 64, color: Colors.teal[300]),
              const SizedBox(height: 16),
              Text('Take a photo of the medicine', style: TextStyle(fontSize: 16, color: Colors.teal[700])),
              const SizedBox(height: 4),
              Text('AI will read all details from the label', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ])),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: _picking ? null : () => _pickImage(true),
              icon: const Icon(Icons.camera_alt), label: const Text('Camera'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(onPressed: _picking ? null : () => _pickImage(false),
              icon: const Icon(Icons.photo_library), label: const Text('Gallery'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)))),
          ]),
        ],
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!)),
            child: Row(children: [
              Icon(Icons.warning_amber, color: Colors.orange[700]),
              const SizedBox(width: 10),
              Expanded(child: Text(_error, style: TextStyle(color: Colors.orange[800]))),
            ])),
        ],
        if (_imageBytes == null) ...[
          const SizedBox(height: 24),
          _tip(Icons.lightbulb_outline, 'Good light + sharp photo = better results'),
          const SizedBox(height: 8),
          _tip(Icons.center_focus_strong, 'Focus on the label with name, batch, expiry'),
          const SizedBox(height: 8),
          _tip(Icons.edit, 'You can edit all fields after AI reads them'),
          const SizedBox(height: 8),
          _tip(Icons.vpn_key, 'Set Gemini API key in Settings first'),
        ],
      ]),
    );
  }

  Widget _tip(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 18, color: Colors.teal[400]),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[600]))),
    ]);
  }

  Widget _buildForm() {
    final hasData = _fields.isNotEmpty;
    return Column(children: [
      if (_imageBytes != null)
        Container(height: 100, width: double.infinity, color: Colors.grey[200],
          child: Stack(children: [
            Center(child: Image.memory(_imageBytes!, height: 100, width: double.infinity, fit: BoxFit.cover)),
            Positioned(top: 4, right: 4, child: IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              onPressed: () => setState(() { _showForm = false; }))),
          ])),
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: hasData ? Colors.green[50] : Colors.blue[50],
        child: Row(children: [
          Icon(hasData ? Icons.check_circle : Icons.edit,
            color: hasData ? Colors.green : Colors.blue, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(
            hasData ? 'AI read ${_fields.values.where((v) => v.isNotEmpty).length} fields — edit if needed'
              : 'Enter medicine details manually',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
              color: hasData ? Colors.green[800] : Colors.blue[800]))),
        ])),
      Expanded(child: ListView(padding: const EdgeInsets.all(16),
        children: _fieldOrder.map((k) => Padding(padding: const EdgeInsets.only(bottom: 12),
          child: TextField(controller: _ctrls[k],
            decoration: InputDecoration(
              labelText: _fieldLabels[k] ?? k,
              prefixIcon: Icon(_fieldIcons[k] ?? Icons.edit,
                color: _ctrls[k]!.text.isNotEmpty ? Colors.teal : Colors.grey, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: _ctrls[k]!.text.isNotEmpty,
              fillColor: _ctrls[k]!.text.isNotEmpty ? Colors.teal.withOpacity(0.05) : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ))),
        ).toList())),
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, -2))
        ]),
        child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: ElevatedButton.icon(onPressed: _save,
            icon: const Icon(Icons.check), label: const Text('Save to Stock'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14)))),
        ])),
    ]);
  }
}