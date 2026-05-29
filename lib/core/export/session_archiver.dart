import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../session/session_store.dart';

/// Zip a session folder (raw/ + preview/ + sidecar.json) into a fresh file
/// in the OS temp directory and return that file.
///
/// The archive's top-level entry is the session id, so unzipping recreates
/// the same `<session-id>/raw/...` layout the desktop pipeline expects.
class SessionArchiver {
  SessionArchiver(this.store);

  final SessionStore store;

  Future<File> zipSession(String sessionId) async {
    final dir = await store.sessionDir(sessionId);
    if (!await dir.exists()) {
      throw StateError('Session $sessionId not found on disk.');
    }
    final tmp = await getTemporaryDirectory();
    final zipPath = p.join(tmp.path, '$sessionId.zip');
    final existing = File(zipPath);
    if (await existing.exists()) await existing.delete();

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addDirectory(dir, includeDirName: true);
    await encoder.close();
    return File(zipPath);
  }

  /// Bundle multiple sessions into a single zip. Each session becomes a
  /// top-level subdirectory inside the archive, keyed by session id —
  /// so unzipping the result on the desktop reproduces the same
  /// `<id>/raw/`, `<id>/preview/`, `<id>/sidecar.json` layout the
  /// desktop pipeline expects.
  ///
  /// Returns a single `.zip` file in the OS temp directory whose name
  /// embeds the export timestamp.
  Future<File> zipMultipleSessions(List<String> sessionIds) async {
    if (sessionIds.isEmpty) {
      throw ArgumentError('No sessions to export.');
    }
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(16);
    final zipPath = p.join(tmp.path, 'stela-export-$stamp.zip');
    final existing = File(zipPath);
    if (await existing.exists()) await existing.delete();

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    for (final id in sessionIds) {
      final dir = await store.sessionDir(id);
      if (!await dir.exists()) continue;
      await encoder.addDirectory(dir, includeDirName: true);
    }
    await encoder.close();
    return File(zipPath);
  }
}
