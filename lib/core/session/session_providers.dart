import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sidecar/sidecar_schema.dart';
import 'session_store.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// List of session ids on disk, newest first.
final sessionListProvider = FutureProvider<List<String>>((ref) async {
  final store = ref.watch(sessionStoreProvider);
  return store.listSessionIds();
});

/// Every session's sidecar, batched into one map for cheap filtering in the
/// Stack / Export search UIs. Re-runs whenever [sessionListProvider] is
/// invalidated, so create / delete / rename / edit-details all flow through.
final sessionSidecarsProvider =
    FutureProvider<Map<String, SidecarV1?>>((ref) async {
  final ids = await ref.watch(sessionListProvider.future);
  final store = ref.read(sessionStoreProvider);
  final result = <String, SidecarV1?>{};
  for (final id in ids) {
    result[id] = await store.readSidecar(id);
  }
  return result;
});
