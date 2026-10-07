import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../db_helper.dart';
import '../services/lang_service.dart';
import 'package:intl/intl.dart';

/// Prescription photo storage. Uses file_picker (gallery/files).
/// NOTE: in-app camera capture needs image_picker (blocked: no pub access).
class PrescriptionScreen extends StatefulWidget {
  final String? mobile;
  final String? customerName;
  const PrescriptionScreen({super.key, this.mobile, this.customerName});

  @override
  State<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends State<PrescriptionScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _list = await DBHelper.getPrescriptions(widget.mobile);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null || res.files.isEmpty) return;
    final path = res.files.first.path;
    if (path == null || path.isEmpty) return;
    final noteC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(Lang.t('rx_add')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(path), height: 180, fit: BoxFit.cover)),
            const SizedBox(height: 8),
            TextField(controller: noteC, decoration: InputDecoration(hintText: Lang.t('rx_note_hint'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(Lang.t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(Lang.t('save'))),
        ],
      ),
    );
    if (ok != true) return;
    await DBHelper.addPrescription({
      'mobile': widget.mobile ?? '',
      'customer_name': widget.customerName ?? '',
      'file_path': path,
      'note': noteC.text.trim(),
      'date': DateFormat('dd/MM/yyyy').format(DateTime.now()),
    });
    _load();
  }

  Future<void> _view(Map<String, dynamic> p) async {
    final path = (p['file_path'] ?? '').toString();
    final f = File(path);
    final exists = path.isNotEmpty && await f.exists();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (exists)
              Flexible(child: InteractiveViewer(child: Image.file(f)))
            else
              const Padding(padding: EdgeInsets.all(24), child: Text('⚠️ Photo file not found')),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (exists)
                    TextButton.icon(
                      onPressed: () => Share.shareXFiles([XFile(path)], text: '${p['note'] ?? ''}'),
                      icon: const Icon(Icons.share),
                      label: Text(Lang.t('share')),
                    ),
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(Lang.t('delete')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(Lang.t('cancel'))),
                            ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(Lang.t('delete'))),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await DBHelper.deletePrescription((p['id'] as num).toInt());
                        _load();
                      }
                    },
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: Text(Lang.t('delete')),
                  ),
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(Lang.t('close'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.customerName != null && widget.customerName!.isNotEmpty
        ? '${Lang.t('rx_title')} — ${widget.customerName}'
        : Lang.t('rx_title');
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: const Color(0xFF7C3AED)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? Center(child: Text(Lang.t('rx_empty'), style: const TextStyle(color: Colors.grey, fontSize: 16)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _list.length,
                    itemBuilder: (_, i) {
                      final p = _list[i];
                      final path = (p['file_path'] ?? '').toString();
                      return GestureDetector(
                        onTap: () => _view(p),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: File(path).existsSync()
                                    ? Image.file(File(path), fit: BoxFit.cover)
                                    : Container(color: Colors.grey.shade200, child: const Icon(Icons.image_not_supported, size: 40)),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: Text(
                                  '${p['note'] ?? ''}\n${p['date'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_a_photo),
        label: Text(Lang.t('rx_add')),
        backgroundColor: const Color(0xFF7C3AED),
      ),
    );
  }
}
