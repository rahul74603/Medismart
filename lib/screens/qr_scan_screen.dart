import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/lang_service.dart';

/// DIAGNOSTIC BUILD — shows live state on overlay so we can see exactly
/// where the pipeline breaks. Will be replaced with clean version once
/// the root cause is confirmed.
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

  // ---- DIAGNOSTIC counters ----
  int _detectCalls = 0; // how many times _onDetect was called
  int _galleryOk = 0; // successful gallery detections
  String _galleryErr = ''; // last gallery error message
  String _lastRaw = ''; // last raw value seen (truncated)

  @override
  void initState() {
    super.initState();
    _lineAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    try {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal, // normal = per-frame + timeout
        facing: CameraFacing.back,
      );
    } catch (e) {
      debugPrint('[QR-DIAG] Controller create FAILED: $e');
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
    _detectCalls++;
    debugPrint('[QR-DIAG] _onDetect #$_detectCalls '
        'barcodes=${capture.barcodes.length}');
    if (mounted) setState(() {}); // update diag counter on screen
    if (_done || _paused) return;
    try {
      if (capture.barcodes.isEmpty) return;
      final raw = capture.barcodes.first.rawValue;
      if (raw == null || raw.trim().isEmpty) return;
      _lastRaw = raw.length > 40 ? '${raw.substring(0, 40)}...' : raw;
      debugPrint('[QR-DIAG] DETECTED: $_lastRaw');
      if (mounted) setState(() {});
      _finish(raw.trim());
    } catch (e) {
      debugPrint('[QR-DIAG] _onDetect EXCEPTION: $e');
    }
  }

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
    _galleryErr = '';
    try {
      final img = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!mounted) return;
      if (img == null) {
        _paused = false;
        return;
      }
      setState(() => _analyzing = true);
      debugPrint('[QR-DIAG] gallery path=${img.path}');
      BarcodeCapture? cap;
      try {
        cap = await _controller?.analyzeImage(img.path);
        debugPrint('[QR-DIAG] analyzeImage result: '
            'cap=${cap != null}, barcodes=${cap?.barcodes.length ?? 0}');
      } catch (e) {
        debugPrint('[QR-DIAG] analyzeImage EXCEPTION: $e');
        _galleryErr = 'analyzeErr: $e';
        cap = null;
      }
      if (!mounted) return;
      String raw = '';
      if (cap != null && cap.barcodes.isNotEmpty) {
        raw = (cap.barcodes.first.rawValue ?? '').trim();
      }
      setState(() => _analyzing = false);
      if (raw.isNotEmpty) {
        _galleryOk++;
        _lastRaw = raw.length > 40 ? '${raw.substring(0, 40)}...' : raw;
        debugPrint('[QR-DIAG] gallery OK: $_lastRaw');
        _finish(raw);
      } else {
        _galleryErr =
            _galleryErr.isEmpty ? 'no barcode in image' : _galleryErr;
        debugPrint('[QR-DIAG] gallery FAIL: $_galleryErr');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${Lang.t('qr_nobarcode')}\n[$_galleryErr]'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4)));
        }
      }
    } catch (e) {
      debugPrint('[QR-DIAG] gallery outer EXCEPTION: $e');
      _galleryErr = 'outer: $e';
      if (mounted) {
        setState(() => _analyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gallery error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4)));
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
    debugPrint('[QR-DIAG] RETRY -- calling start()');
    try {
      await _controller?.start();
      debugPrint('[QR-DIAG] start() returned OK');
    } catch (e) {
      debugPrint('[QR-DIAG] start() EXCEPTION: $e');
    }
    if (mounted) setState(() {});
  }

  // Force-stop then re-start (full restart)
  Future<void> _fullRestart() async {
    debugPrint('[QR-DIAG] FULL RESTART');
    try {
      await _controller?.stop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      await _controller?.start();
      debugPrint('[QR-DIAG] restart start() OK');
    } catch (e) {
      debugPrint('[QR-DIAG] restart start() EXCEPTION: $e');
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(Lang.t('qr_title')),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // ---- Camera preview ----
          if (c != null)
            MobileScanner(
              controller: c,
              onDetect: _onDetect,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, child) {
                debugPrint('[QR-DIAG] errorBuilder: $err');
                return _cameraBlocked();
              },
            )
          else
            _cameraBlocked(),

          // ---- Scan box + laser line ----
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

          // ---- ANALYZING spinner ----
          if (_analyzing)
            Container(
              color: Colors.black54,
              child: const Center(
                  child:
                      CircularProgressIndicator(color: Colors.tealAccent)),
            ),

          // ============================================================
          // DIAGNOSTIC OVERLAY -- top-right corner, always visible
          // ============================================================
          if (c != null)
            Positioned(
              top: 8,
              right: 8,
              child: ValueListenableBuilder<MobileScannerState>(
                valueListenable: c,
                builder: (ctx, state, _) {
                  final errText = state.error != null
                      ? '${state.error!.errorCode}: '
                          '${state.error!.errorDetails?.message ?? "?"}'
                      : 'none';
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.tealAccent, width: 1),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('init: ${state.isInitialized ? "OK" : "NO"}'
                              '  run: ${state.isRunning ? "OK" : "NO"}'),
                          Text('cam: ${state.availableCameras ?? "?"}'
                              '  size: ${state.size.width.toInt()}'
                              'x${state.size.height.toInt()}'),
                          Text('err: $errText'),
                          Text('detect# $_detectCalls'
                              '  last: ${_lastRaw.isEmpty ? "--" : _lastRaw}'),
                          Text(
                              'galleryOk: $_galleryOk'
                              '  gErr: ${_galleryErr.isEmpty ? "--" : _galleryErr}'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // ---- Bottom: hint + 3 buttons + DIAG buttons ----
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Text(
                  Lang.t('qr_hint'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 10),
                // Main 3 buttons
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
                    _roundBtn(
                        Icons.keyboard, Colors.white, _typeManually,
                        label: Lang.t('qr_type')),
                  ],
                ),
                const SizedBox(height: 10),
                // DIAG: restart + Start
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _roundBtn(Icons.restart_alt, Colors.orangeAccent,
                        _fullRestart,
                        label: 'Restart'),
                    _roundBtn(Icons.center_focus_strong,
                        Colors.cyanAccent, _retryCamera,
                        label: 'Start'),
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white24)),
            child: Icon(icon, color: color, size: 24),
          ),
          if (label != null) ...[
            const SizedBox(height: 3),
            Text(label,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ],
      ),
    );
  }

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
                    style: const TextStyle(color: Colors.tealAccent)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
