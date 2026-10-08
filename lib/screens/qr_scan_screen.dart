import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/lang_service.dart';

/// Smart QR/barcode scanner. Pops with the scanned raw String,
/// or null if user goes back. Never throws.
/// - Auto-read from camera (shows Found tick before closing)
/// - Gallery photo scan (analyzeImage)
/// - Manual type/paste fallback
/// - Camera-blocked state with Retry (no more black screen)
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _controller;
  late AnimationController _lineAnim;
  bool _done = false;
  bool _paused = false;
  bool _torchOn = false;
  bool _found = false;
  bool _analyzing = false;

  @override
  void initState() {
    super.initState();
    _lineAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    try {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
      );
    } catch (_) {
      _controller = null;
    }
  }

  @override
  void dispose() {
    try {
      _lineAnim.dispose();
    } catch (_) {}
    try {
      _controller?.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done || _paused) return;
    try {
      if (capture.barcodes.isEmpty) return;
      final raw = capture.barcodes.first.rawValue;
      if (raw == null || raw.trim().isEmpty) return;
      _finish(raw.trim());
    } catch (_) {}
  }

  /// Haptic + Found tick, phir result wapas.
  Future<void> _finish(String raw) async {
    if (_done) return;
    _done = true;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
    if (mounted) setState(() => _found = true);
    await Future.delayed(const Duration(milliseconds: 450));
    if (mounted) Navigator.pop(context, raw);
  }

  Future<void> _pickFromGallery() async {
    if (_done || _analyzing) return;
    _paused = true;
    try {
      final img =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!mounted) return;
      if (img == null) return; // user cancelled
      setState(() => _analyzing = true);
      BarcodeCapture? cap;
      try {
        cap = await _controller?.analyzeImage(img.path);
      } catch (_) {
        cap = null;
      }
      if (!mounted) return;
      String raw = '';
      try {
        if (cap != null && cap.barcodes.isNotEmpty) {
          raw = (cap.barcodes.first.rawValue ?? '').trim();
        }
      } catch (_) {}
      setState(() => _analyzing = false);
      if (raw.isNotEmpty) {
        _finish(raw);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(Lang.t('qr_nobarcode')),
            backgroundColor: Colors.red));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _analyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(Lang.t('qr_nobarcode')),
            backgroundColor: Colors.red));
      }
    } finally {
      _paused = false;
    }
  }

  void _typeManually() {
    if (_done) return;
    _paused = true;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lang.t('qr_type_title')),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'GTIN / Batch / EXP ...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Lang.t('cancel'))),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              Navigator.pop(ctx);
              if (v.isNotEmpty) _finish(v);
            },
            child: Text(Lang.t('add')),
          ),
        ],
      ),
    ).then((_) => _paused = false);
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller?.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  Future<void> _retryCamera() async {
    try {
      await _controller?.start();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(Lang.t('qr_title')),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          if (_controller != null)
            MobileScanner(
              controller: _controller!,
              onDetect: _onDetect,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, child) => _cameraBlocked(),
            )
          else
            _cameraBlocked(),
          // Scan box + moving laser line
          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: Colors.tealAccent, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _lineAnim,
                    builder: (ctx, _) => Positioned(
                      top: 12 + _lineAnim.value * 232,
                      left: 12,
                      right: 12,
                      child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                              color: _found ? Colors.green : Colors.red,
                              borderRadius: BorderRadius.circular(2))),
                    ),
                  ),
                  if (_found)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.white),
                            const SizedBox(width: 6),
                            Text(Lang.t('qr_found'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_analyzing)
            Container(
              color: Colors.black54,
              child: const Center(
                  child: CircularProgressIndicator(color: Colors.tealAccent)),
            ),
          // Bottom: hint + 3 buttons
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Text(
                  Lang.t('qr_hint'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _roundBtn(
                        _torchOn ? Icons.flash_on : Icons.flash_off,
                        _torchOn ? Colors.amber : Colors.white,
                        _toggleTorch),
                    _roundBtn(Icons.photo_library, Colors.white,
                        _pickFromGallery,
                        label: Lang.t('qr_gallery')),
                    _roundBtn(Icons.keyboard, Colors.white, _typeManually,
                        label: Lang.t('qr_type')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, Color color, VoidCallback onTap,
      {String? label}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white24)),
            child: Icon(icon, color: color, size: 28),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(label,
                style:
                    const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  /// Camera permission denied / blocked - kaala screen kabhi nahi.
  Widget _cameraBlocked() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography,
                  color: Colors.white54, size: 64),
              const SizedBox(height: 16),
              Text(Lang.t('qr_noperm'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(Lang.t('qr_perm_hint'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _retryCamera,
                icon: const Icon(Icons.refresh),
                label: Text(Lang.t('qr_retry')),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _pickFromGallery,
                icon: const Icon(Icons.photo_library,
                    color: Colors.tealAccent),
                label: Text(Lang.t('qr_gallery'),
                    style:
                        const TextStyle(color: Colors.tealAccent)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
