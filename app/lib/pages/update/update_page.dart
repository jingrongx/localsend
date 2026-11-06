import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/update/update_provider.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';

class UpdatePage extends StatefulWidget {
  /// When true, a check is triggered when the page is opened (manual check).
  final bool autoCheck;

  const UpdatePage({this.autoCheck = false});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.autoCheck) {
        // ignore: discarded_futures
        context.ref.notifier(updateProvider).checkForUpdates();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.ref.watch(updateProvider);
    final t = Translations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.update.title),
      ),
      body: switch (state.status) {
        UpdateStatus.idle => _message(t.update.checkForUpdates),
        UpdateStatus.checking => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              Text(t.update.checking),
            ],
          ),
        ),
        UpdateStatus.upToDate => _message(t.update.upToDate),
        UpdateStatus.available => const _UpdateAvailableView(),
        UpdateStatus.downloading => _DownloadingView(progress: state.downloadProgress),
        UpdateStatus.downloaded => _UpdateReadyView(apkPath: state.downloadedApkPath ?? ''),
        UpdateStatus.error => const _ErrorView(),
      },
    );
  }

  Widget _message(String message) {
    return Center(
      child: Text(message),
    );
  }
}

class _UpdateAvailableView extends StatelessWidget {
  const _UpdateAvailableView();

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final release = context.ref.watch(updateProvider).release;
    if (release == null) {
      return Center(child: Text(t.update.checkFailed));
    }
    return ListView(
      padding: const EdgeInsets.all(15),
      children: [
        Text(
          t.update.newVersion(version: release.version),
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        if (release.changelog != null && release.changelog!.isNotEmpty) ...[
          Text(t.update.releaseNotes, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          MarkdownBody(data: release.changelog!),
          const SizedBox(height: 15),
        ],
        Center(
          child: FilledButton.icon(
            onPressed: () async {
              await context.ref.notifier(updateProvider).downloadUpdate();
            },
            icon: const Icon(Icons.download),
            label: Text(t.update.download),
          ),
        ),
      ],
    );
  }
}

class _DownloadingView extends StatelessWidget {
  final double progress;

  const _DownloadingView({required this.progress});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.update.downloading(progress: (progress * 100).round())),
          const SizedBox(height: 10),
          SizedBox(
            width: 250,
            child: LinearProgressIndicator(value: progress > 0 ? progress : null),
          ),
        ],
      ),
    );
  }
}

class _UpdateReadyView extends StatelessWidget {
  final String apkPath;

  const _UpdateReadyView({required this.apkPath});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 60, color: Colors.green),
          const SizedBox(height: 10),
          Text(t.update.downloaded),
          const SizedBox(height: 15),
          FilledButton.icon(
            onPressed: () async {
              await openFile(context, FileType.apk, apkPath);
            },
            icon: const Icon(Icons.install_mobile),
            label: Text(t.update.install),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView();

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 60),
          const SizedBox(height: 10),
          Text(t.update.checkFailed),
          const SizedBox(height: 15),
          FilledButton.icon(
            onPressed: () async {
              await context.ref.notifier(updateProvider).checkForUpdates();
            },
            icon: const Icon(Icons.refresh),
            label: Text(t.update.retry),
          ),
        ],
      ),
    );
  }
}
