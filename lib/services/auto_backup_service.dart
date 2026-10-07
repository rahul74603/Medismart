import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../db_helper.dart';
import 'app_prefs.dart';

/// Daily automatic local backup of the database with rotation.
/// Runs silently on app start (once per day). Never throws.
class AutoBackupService {
  static const int keepLastN = 7;

  /// Call once on app start. Takes a backup if today is not backed up yet.
  static Future<void> runDailyCheck() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final last = await AppPrefs.getLastAutoBackupDay();
      if (last == today) return; // already backed up today
      await backupNow();
    } catch (e) {
      print("AutoBackup daily check failed: $e");
    }
  }

  /// Creates a timestamped backup copy. Returns file path, or null on failure.
  static Future<String?> backupNow() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final bdir = Directory('${dir.path}/MediSmartBackup');
      if (!await bdir.exists()) {
        await bdir.create(recursive: true);
      }

      final now = DateTime.now();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final dest = '${bdir.path}/MediSmart_$stamp.db';

      final src = File(await DBHelper.getDbPath());
      if (!await src.exists()) return null;
      await src.copy(dest);

      // Rotation: keep only last N backups
      final files = bdir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (int i = keepLastN; i < files.length; i++) {
        try {
          await files[i].delete();
        } catch (_) {}
      }

      final today = DateFormat('yyyy-MM-dd').format(now);
      final label = DateFormat('dd MMM yyyy, hh:mm a').format(now);
      await AppPrefs.setLastAutoBackupDay(today);
      await AppPrefs.setLastBackupInfo(dest, label);
      return dest;
    } catch (e) {
      print("AutoBackup failed: $e");
      return null;
    }
  }

  /// Latest backup file path (for sharing/upload to Drive).
  static Future<String?> latestBackupPath() async {
    try {
      final saved = await AppPrefs.getLastBackupPath();
      if (saved != null && await File(saved).exists()) return saved;
      // Fallback: newest file in backup folder
      final dir = await getApplicationDocumentsDirectory();
      final bdir = Directory('${dir.path}/MediSmartBackup');
      if (!await bdir.exists()) return null;
      final files = bdir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      return files.isEmpty ? null : files.first.path;
    } catch (_) {
      return null;
    }
  }
}
