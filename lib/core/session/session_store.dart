import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:archive/archive_io.dart';

import '../image_ops/registration.dart';
import '../sidecar/sidecar_schema.dart';
import 'session.dart';

/// Reads and writes [Session]s under `<app-docs>/sessions/`.
class SessionStore {
  SessionStore({Directory? rootOverride}) : _rootOverride = rootOverride;

  final Directory? _rootOverride;

  Future<Directory> _root() async {
    if (_rootOverride != null) return _rootOverride;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'sessions'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> sessionDir(String sessionId) async {
    final root = await _root();
    final dir = Directory(p.join(root.path, sessionId));
    if (!await dir.exists()) await dir.create(recursive: true);
    final raw = Directory(p.join(dir.path, 'raw'));
    if (!await raw.exists()) await raw.create(recursive: true);
    return dir;
  }

  Future<File> frameFile(String sessionId, String filename) async {
    final dir = await sessionDir(sessionId);
    return File(p.join(dir.path, 'raw', filename));
  }

  Future<Directory> previewDir(String sessionId) async {
    final dir = await sessionDir(sessionId);
    final preview = Directory(p.join(dir.path, 'preview'));
    if (!await preview.exists()) await preview.create(recursive: true);
    return preview;
  }

  Future<File> writePreview(
    String sessionId,
    String name,
    List<int> bytes,
  ) async {
    final dir = await previewDir(sessionId);
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> deleteSession(String sessionId) async {
    final dir = await sessionDir(sessionId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> renameLabel(String sessionId, String newLabel) =>
      updateDetails(sessionId, label: newLabel);

  /// Update label and/or notes on a session in one sidecar write. Pass
  /// `notes: ''` to clear (any null leaves the existing value alone).
  Future<void> updateDetails(
    String sessionId, {
    String? label,
    String? notes,
  }) async {
    final sc = await readSidecar(sessionId);
    if (sc == null) throw StateError('No sidecar for session $sessionId');
    final updated = SidecarV1(
      sessionId: sc.sessionId,
      label: label ?? sc.label,
      capturedAt: sc.capturedAt,
      deviceModel: sc.deviceModel,
      scaleMmPerPixel: sc.scaleMmPerPixel,
      notes: notes ?? sc.notes,
      frames: sc.frames,
      registration: sc.registration,
    );
    final f = await sidecarFile(sessionId);
    final json =
        const JsonEncoder.withIndent('  ').convert(updated.toJson());
    await f.writeAsString(json);
  }

  /// Import a session zip (one produced by [SessionArchiver]) into the
  /// store. Returns the final session id used on disk.
  ///
  /// Collision handling: if a session with the same id already exists, the
  /// new one is given a `_imp-<hex-timestamp>` suffix so re-importing the
  /// same zip produces a fresh session rather than overwriting.
  ///
  /// Errors:
  ///   - Zip doesn't exist → StateError
  ///   - Zip has no recognisable session folder → StateError
  ///   - Sidecar.json missing inside the zip → StateError
  Future<String> importSessionFromZip(File zip) async {
    if (!await zip.exists()) {
      throw StateError('Import file does not exist: ${zip.path}');
    }
    final tmpRoot = await Directory.systemTemp.createTemp('stela_import_');
    try {
      // 1. Decode the zip into a temp directory.
      await extractFileToDisk(zip.path, tmpRoot.path);

      // 2. Locate the session folder. The exporter always writes one
      //    top-level dir named after the session id, but be defensive in
      //    case a user hand-zipped the contents.
      final entries = await tmpRoot.list().toList();
      Directory? extracted;
      final topDirs = entries.whereType<Directory>().toList();
      if (topDirs.length == 1) {
        extracted = topDirs.first;
      } else if (topDirs.isEmpty) {
        // No top-level folder — treat the tmpRoot itself as the session
        // root (user zipped raw/ + sidecar.json directly).
        extracted = tmpRoot;
      } else {
        throw StateError(
          'Zip has ${topDirs.length} top-level folders — expected one '
          'session folder.',
        );
      }

      // 3. Validate it looks like a Stela session.
      final sidecarSource = File(p.join(extracted.path, 'sidecar.json'));
      if (!await sidecarSource.exists()) {
        throw StateError(
          'sidecar.json not found in the zip — not a Stela session export.',
        );
      }
      Map<String, dynamic> json;
      try {
        json = jsonDecode(await sidecarSource.readAsString())
            as Map<String, dynamic>;
      } catch (e) {
        throw StateError('sidecar.json is not valid JSON: $e');
      }
      var sessionId = json['session_id'] as String? ?? p.basename(extracted.path);
      if (sessionId.isEmpty) {
        sessionId = 's_imp_${DateTime.now().millisecondsSinceEpoch}';
      }

      // 4. Handle id collision.
      final destRoot = await _root();
      var dest = Directory(p.join(destRoot.path, sessionId));
      if (await dest.exists() && (await dest.list().isEmpty) == false) {
        final stamp = DateTime.now()
            .millisecondsSinceEpoch
            .toRadixString(16);
        sessionId = '${sessionId}_imp-$stamp';
        dest = Directory(p.join(destRoot.path, sessionId));
        // Rewrite the sidecar so the id inside matches the on-disk id.
        json['session_id'] = sessionId;
        await sidecarSource.writeAsString(
          const JsonEncoder.withIndent('  ').convert(json),
        );
      }

      // 5. Move the extracted folder into the sessions directory.
      await dest.create(recursive: true);
      await _copyDirContents(extracted, dest);

      return sessionId;
    } finally {
      if (await tmpRoot.exists()) {
        try {
          await tmpRoot.delete(recursive: true);
        } catch (_) {/* best-effort temp cleanup */}
      }
    }
  }

  /// Recursive copy of `src`'s *contents* (not the dir itself) into `dst`.
  Future<void> _copyDirContents(Directory src, Directory dst) async {
    await for (final entity in src.list(recursive: true)) {
      final rel = p.relative(entity.path, from: src.path);
      final dstPath = p.join(dst.path, rel);
      if (entity is Directory) {
        await Directory(dstPath).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(dstPath)).create(recursive: true);
        await entity.copy(dstPath);
      }
    }
  }

  Future<int> sessionByteSize(String sessionId) async {
    final dir = await sessionDir(sessionId);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {/* race with deletion */}
      }
    }
    return total;
  }

  Future<File> sidecarFile(String sessionId) async {
    final dir = await sessionDir(sessionId);
    return File(p.join(dir.path, 'sidecar.json'));
  }

  Future<Session> createSession({
    required String label,
    required String deviceModel,
    DateTime? now,
    SidecarLocation? location,
  }) async {
    final t = now ?? DateTime.now();
    final id = _generateId(t);
    final session = Session(
      id: id,
      label: label,
      capturedAt: t,
      deviceModel: deviceModel,
      frames: [],
      location: location,
    );
    await sessionDir(id);
    await writeSidecar(session);
    return session;
  }

  Future<void> writeSidecar(Session session) async {
    final file = await sidecarFile(session.id);
    final json = const JsonEncoder.withIndent('  ')
        .convert(session.toSidecar().toJson());
    await file.writeAsString(json);
  }

  /// Persist a registration result into the sidecar: top-level registration
  /// metadata + per-frame similarity transforms.
  Future<void> updateRegistration(
    String sessionId,
    RegistrationResult result,
  ) async {
    final sc = await readSidecar(sessionId);
    if (sc == null) {
      throw StateError('No sidecar for session $sessionId');
    }
    final modeName = switch (result.mode) {
      RegistrationMode.none => 'none',
      RegistrationMode.fast => 'fast',
      RegistrationMode.accurate => 'accurate',
      RegistrationMode.orb => 'orb',
    };
    final framesOut = <SidecarFrame>[];
    for (var i = 0; i < sc.frames.length; i++) {
      final f = sc.frames[i];
      final t = i < result.transforms.length ? result.transforms[i] : null;
      framesOut.add(SidecarFrame(
        file: f.file,
        timestampMs: f.timestampMs,
        lightAzimuthDeg: f.lightAzimuthDeg,
        lightElevationDeg: f.lightElevationDeg,
        iso: f.iso,
        exposureUs: f.exposureUs,
        focusDistanceM: f.focusDistanceM,
        transform: t == null
            ? null
            : SidecarFrameTransform(
                tx: t.tx,
                ty: t.ty,
                rotationRad: t.rotationRad,
                scale: t.scale,
              ),
      ));
    }
    final updated = SidecarV1(
      sessionId: sc.sessionId,
      label: sc.label,
      capturedAt: sc.capturedAt,
      deviceModel: sc.deviceModel,
      scaleMmPerPixel: sc.scaleMmPerPixel,
      notes: sc.notes,
      registration: SidecarRegistration(
        mode: modeName,
        validRect: [
          result.validRect.x0,
          result.validRect.y0,
          result.validRect.x1,
          result.validRect.y1,
        ],
        scores: result.scores,
      ),
      frames: framesOut,
    );
    final file = await sidecarFile(sessionId);
    final json =
        const JsonEncoder.withIndent('  ').convert(updated.toJson());
    await file.writeAsString(json);
  }

  Future<void> updateScale(String sessionId, double mmPerPixel) async {
    final sc = await readSidecar(sessionId);
    if (sc == null) {
      throw StateError('No sidecar for session $sessionId');
    }
    final updated = SidecarV1(
      sessionId: sc.sessionId,
      label: sc.label,
      capturedAt: sc.capturedAt,
      deviceModel: sc.deviceModel,
      scaleMmPerPixel: mmPerPixel,
      notes: sc.notes,
      frames: sc.frames,
    );
    final f = await sidecarFile(sessionId);
    final json =
        const JsonEncoder.withIndent('  ').convert(updated.toJson());
    await f.writeAsString(json);
  }

  Future<SidecarV1?> readSidecar(String sessionId) async {
    final f = await sidecarFile(sessionId);
    if (!await f.exists()) return null;
    final raw = await f.readAsString();
    return SidecarV1.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Load an existing session into a mutable [Session]. Returns null if no
  /// sidecar was found for [sessionId].
  Future<Session?> loadSession(String sessionId) async {
    final sc = await readSidecar(sessionId);
    if (sc == null) return null;
    return Session.fromSidecar(sc);
  }

  Future<List<File>> listFrames(String sessionId) async {
    final dir = await sessionDir(sessionId);
    final raw = Directory(p.join(dir.path, 'raw'));
    if (!await raw.exists()) return const [];
    final files = (await raw.list().toList()).whereType<File>().toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return files;
  }

  Future<List<String>> listSessionIds() async {
    final root = await _root();
    final entries = await root.list().toList();
    final ids = <String>[];
    for (final e in entries) {
      if (e is Directory) ids.add(p.basename(e.path));
    }
    ids.sort((a, b) => b.compareTo(a));
    return ids;
  }

  /// Build the next frame filename (e.g. `0001.jpg`) for a session.
  String nextFrameName(Session session, {String extension = 'jpg'}) {
    final n = session.frames.length + 1;
    return '${n.toString().padLeft(4, '0')}.$extension';
  }

  static final _rand = math.Random();

  static String _generateId(DateTime t) {
    final utc = t.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${utc.year}${two(utc.month)}${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
    final suffix = (_rand.nextInt(0xFFFF))
        .toRadixString(16)
        .padLeft(4, '0');
    return 's_${stamp}_$suffix';
  }
}
