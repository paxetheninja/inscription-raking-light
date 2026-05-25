import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/session/session.dart';
import '../../core/session/session_providers.dart';
import 'light_direction.dart';

/// Capture tab — idle until the user starts a session, then opens the camera
/// with auto-exposure / auto-focus. The "Lock" button freezes both so the
/// burst stays consistent while the assistant sweeps the raking light.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  Session? _session;
  bool _locked = false;
  bool _busy = false;
  String? _error;
  String? _lastShotPath;
  LightDirection _light = const LightDirection();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      c.dispose();
      _controller = null;
      if (mounted) setState(() {});
    }
  }

  Future<void> _startSession() async {
    final label = await _promptLabel();
    if (label == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final perm = await Permission.camera.request();
      if (!perm.isGranted) {
        throw StateError('Camera permission not granted.');
      }
      _cameras ??= await availableCameras();
      if (_cameras!.isEmpty) {
        throw StateError('No cameras available on this device.');
      }
      final back = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _controller = controller;

      final store = ref.read(sessionStoreProvider);
      _session = await store.createSession(
        label: label,
        deviceModel: _deviceModel(),
      );
      _locked = false;
      _lastShotPath = null;
      ref.invalidate(sessionListProvider);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleLock() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      if (_locked) {
        await c.setExposureMode(ExposureMode.auto);
        await c.setFocusMode(FocusMode.auto);
      } else {
        await c.setExposureMode(ExposureMode.locked);
        await c.setFocusMode(FocusMode.locked);
      }
      setState(() => _locked = !_locked);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    final s = _session;
    if (c == null || s == null || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await c.takePicture();
      final store = ref.read(sessionStoreProvider);
      final name = store.nextFrameName(s);
      final dest = await store.frameFile(s.id, name);
      await File(shot.path).copy(dest.path);
      try {
        await File(shot.path).delete();
      } catch (_) {/* tmp may already be cleaned */}
      s.frames.add(SessionFrame(
        filename: name,
        capturedAt: DateTime.now(),
        lightAzimuthDeg: _light.azimuthDeg,
        lightElevationDeg: _light.elevationDeg,
      ));
      await store.writeSidecar(s);
      _lastShotPath = dest.path;
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _endSession() async {
    await _controller?.dispose();
    _controller = null;
    _session = null;
    _locked = false;
    _lastShotPath = null;
    if (mounted) setState(() {});
    ref.invalidate(sessionListProvider);
  }

  Future<String?> _promptLabel() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New capture session'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Label (stone name, find no., …)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(ctrl.text.trim().isEmpty ? '—' : ctrl.text.trim()),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  String _deviceModel() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'iOS device';
    if (Platform.isAndroid) return 'Android device';
    return 'unknown';
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return _IdleView(
        onStart: _busy ? null : _startSession,
        busy: _busy,
        error: _error,
      );
    }
    return _ActiveView(
      controller: _controller,
      session: _session!,
      locked: _locked,
      busy: _busy,
      error: _error,
      lastShotPath: _lastShotPath,
      light: _light,
      onLightChanged: (l) => setState(() => _light = l),
      onShutter: _capture,
      onLock: _toggleLock,
      onEnd: _endSession,
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onStart, required this.busy, this.error});

  final VoidCallback? onStart;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Capture', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'Mount the phone on a tripod or hold it steady. An assistant sweeps a '
            'raking light across the stone. Lock exposure & focus once framed, '
            'then tap the shutter at each light position.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.fiber_manual_record),
            label: Text(busy ? 'Opening camera…' : 'Start new session'),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _ActiveView extends StatelessWidget {
  const _ActiveView({
    required this.controller,
    required this.session,
    required this.locked,
    required this.busy,
    required this.error,
    required this.lastShotPath,
    required this.light,
    required this.onLightChanged,
    required this.onShutter,
    required this.onLock,
    required this.onEnd,
  });

  final CameraController? controller;
  final Session session;
  final bool locked;
  final bool busy;
  final String? error;
  final String? lastShotPath;
  final LightDirection light;
  final ValueChanged<LightDirection> onLightChanged;
  final VoidCallback onShutter;
  final VoidCallback onLock;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final preview = (c != null && c.value.isInitialized)
        ? AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: CameraPreview(c),
          )
        : const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(
                avatar: Icon(locked ? Icons.lock : Icons.lock_open, size: 18),
                label: Text(locked ? 'Locked' : 'Auto'),
              ),
              const SizedBox(width: 8),
              Chip(label: Text('${session.frames.length} frames')),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: preview),
          const SizedBox(height: 8),
          LightDirectionPicker(value: light, onChanged: onLightChanged),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                onPressed: onLock,
                icon: Icon(locked ? Icons.lock_open : Icons.lock),
                label: Text(locked ? 'Unlock' : 'Lock AE/AF'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onShutter,
                icon: const Icon(Icons.camera),
                label: Text(busy ? '…' : 'Shutter'),
              ),
              TextButton.icon(
                onPressed: onEnd,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('End'),
              ),
            ],
          ),
          if (lastShotPath != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(File(lastShotPath!), height: 72, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 8),
                  Text('last: ${lastShotPath!.split(Platform.pathSeparator).last}'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
