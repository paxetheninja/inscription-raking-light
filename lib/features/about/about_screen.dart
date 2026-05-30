import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _sourceUrl =
      'https://github.com/paxetheninja/inscription-raking-light';
  static const _supportEmail = 'pixelpace.studio@outlook.com';

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
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Report a problem'),
                subtitle: const Text(
                    'Opens email pre-filled with app version and device info'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _reportProblem(context, info),
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

  Future<void> _reportProblem(BuildContext context, PackageInfo? info) async {
    final version = info == null ? 'unknown' : 'v${info.version}+${info.buildNumber}';
    final platform = kIsWeb
        ? 'web'
        : (Platform.isIOS
            ? 'iOS'
            : Platform.isAndroid
                ? 'Android'
                : Platform.operatingSystem);
    final body = '''
Describe what went wrong:



---
App version: $version
Platform: $platform
''';
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': 'Stela: bug report ($version)',
        'body': body,
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          'No mail app available. Reach out to $_supportEmail '
          'or open an issue on GitHub.',
        )),
      );
    }
  }
}
