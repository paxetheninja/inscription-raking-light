import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_store.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// List of session ids on disk, newest first.
final sessionListProvider = FutureProvider<List<String>>((ref) async {
  final store = ref.watch(sessionStoreProvider);
  return store.listSessionIds();
});
