import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _sourceUrl =
      'https://github.com/paxetheninja/inscription-raking-light';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About Stela')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (ctx, snap) {
          final info = snap.data;
          return ListView(
            children: [
              const SizedBox(height: 16),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 96,
                    height: 96,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  info?.appName ?? 'Stela',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Center(
                child: Text(
                  info == null
                      ? '…'
                      : 'v${info.version} (${info.buildNumber})',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Mobile companion for raking-light documentation of Roman '
                  'inscriptions. Captures a burst with locked exposure, runs '
                  'a stack pipeline (reductions, fusion, Retinex, CLAHE, '
                  'photometric stereo, PCA, multi-scale DoG, black hat) and '
                  'exports a sidecar bundle the desktop pipeline can ingest.',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('Source code'),
                subtitle:
                    const Text('github.com/paxetheninja/inscription-raking-light'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _openUrl(_sourceUrl),
              ),
              ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: const Text('Open-source licenses'),
                subtitle: const Text(
                    'OpenCV, Flutter, the image package, and friends'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: info?.appName ?? 'Stela',
                  applicationVersion:
                      info == null ? null : 'v${info.version}+${info.buildNumber}',
                ),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: Text(
                  'Developed at the University of Graz for documenting Roman '
                  'inscriptions in the field. Contributions welcome.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
