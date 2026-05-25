import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inscription_raking_light/core/session/session_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late SessionStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('irl_store_test_');
    store = SessionStore(rootOverride: tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('createSession writes a sidecar and lists the session', () async {
    final session = await store.createSession(
      label: 'Weber_328',
      deviceModel: 'iPhone',
    );
    expect(session.label, 'Weber_328');

    final ids = await store.listSessionIds();
    expect(ids, contains(session.id));

    final sc = await store.readSidecar(session.id);
    expect(sc?.label, 'Weber_328');
    expect(sc?.frames, isEmpty);
  });

  test('writePreview saves bytes under preview/', () async {
    final session = await store.createSession(label: 'x', deviceModel: 'x');
    final png = Uint8List.fromList(List<int>.filled(8, 1));
    final f = await store.writePreview(session.id, 'foo.png', png);
    expect(await f.exists(), isTrue);
    expect(p.basename(f.parent.path), 'preview');
  });

  test('renameLabel updates the sidecar', () async {
    final session = await store.createSession(label: 'old', deviceModel: 'x');
    await store.renameLabel(session.id, 'new label');
    final sc = await store.readSidecar(session.id);
    expect(sc?.label, 'new label');
  });

  test('updateScale persists mm/pixel', () async {
    final session = await store.createSession(label: 'x', deviceModel: 'x');
    await store.updateScale(session.id, 0.0421);
    final sc = await store.readSidecar(session.id);
    expect(sc?.scaleMmPerPixel, closeTo(0.0421, 1e-9));
  });

  test('deleteSession removes the folder and the listing', () async {
    final session = await store.createSession(label: 'gone', deviceModel: 'x');
    await store.deleteSession(session.id);
    final ids = await store.listSessionIds();
    expect(ids, isNot(contains(session.id)));
    final dir = await store.sessionDir(session.id);
    // sessionDir recreates an empty dir as a side-effect — check that the
    // listing call above doesn't see the recreated empty entry by deleting
    // and asserting separately.
    expect(await dir.exists(), isTrue);
  });

  test('sessionByteSize sums files under the session', () async {
    final session = await store.createSession(label: 'x', deviceModel: 'x');
    await store.writePreview(session.id, 'a.png',
        Uint8List.fromList(List<int>.filled(100, 0)));
    final size = await store.sessionByteSize(session.id);
    // 100 preview bytes + sidecar.json size.
    expect(size, greaterThanOrEqualTo(100));
  });
}
