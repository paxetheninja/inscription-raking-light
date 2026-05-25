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
}
