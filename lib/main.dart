
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const MitcrosApp());

class MitcrosApp extends StatelessWidget {
  const MitcrosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mitcros Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5EEAD4),
          brightness: Brightness.dark,
        ),
      ),
      home: const DownloaderHome(),
    );
  }
}

class DownloaderHome extends StatefulWidget {
  const DownloaderHome({super.key});

  @override
  State<DownloaderHome> createState() => _DownloaderHomeState();
}

class _DownloaderHomeState extends State<DownloaderHome> {
  final urlController = TextEditingController();
  final dio = Dio();
  List<File> files = [];
  bool busy = false;
  double progress = 0;
  String message = 'Paste a direct media link to begin.';
  String? error;

  @override
  void initState() {
    super.initState();
    loadFiles();
  }

  @override
  void dispose() {
    urlController.dispose();
    dio.close();
    super.dispose();
  }

  Future<Directory> downloadDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('\${root.path}/Downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> loadFiles() async {
    try {
      final dir = await downloadDirectory();
      final found = dir.listSync().whereType<File>().toList();
      found.sort((a, b) =>
          b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (mounted) setState(() => files = found);
    } catch (_) {}
  }

  Future<void> download() async {
    final uri = Uri.tryParse(urlController.text.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(() => error = 'Enter a valid HTTP or HTTPS direct media URL.');
      return;
    }

    setState(() {
      busy = true;
      progress = 0;
      error = null;
      message = 'Connecting…';
    });

    String? partialPath;
    try {
      final dir = await downloadDirectory();
      var name = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'media_\${DateTime.now().millisecondsSinceEpoch}.bin';
      name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      if (!name.contains('.')) name += '.bin';

      var target = File('\${dir.path}/$name');
      if (await target.exists()) {
        target = File(
          '\${dir.path}/\${DateTime.now().millisecondsSinceEpoch}_$name',
        );
      }
      partialPath = '\${target.path}.part';

      await dio.download(
        uri.toString(),
        partialPath,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            progress = total > 0 ? received / total : 0;
            message = total > 0
                ? 'Downloaded \${(received / 1048576).toStringAsFixed(1)} / '
                    '\${(total / 1048576).toStringAsFixed(1)} MB'
                : 'Receiving data…';
          });
        },
      );

      await File(partialPath).rename(target.path);
      urlController.clear();
      setState(() {
        progress = 1;
        message = 'Download complete!';
      });
      await loadFiles();
    } catch (_) {
      if (partialPath != null) {
        final partial = File(partialPath);
        if (await partial.exists()) {
          try {
            await partial.delete();
          } catch (_) {}
        }
      }
      setState(() {
        error = 'Download failed. Try a direct downloadable media link.';
        message = 'Unable to download this link.';
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mitcros Downloader',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: loadFiles,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh downloads',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.download_for_offline, size: 42),
                  SizedBox(height: 12),
                  Text(
                    'Your media. Your device.',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('A simple downloader with no advertisements.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: urlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Direct media URL',
              hintText: 'https://example.com/video.mp4',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : download,
            icon: const Icon(Icons.download),
            label: Text(busy ? 'Downloading…' : 'Download media'),
          ),
          if (busy || progress > 0) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: busy && progress == 0 ? null : progress,
            ),
          ],
          const SizedBox(height: 10),
          Text(message),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 26),
          Text(
            'MY DOWNLOADS (\${files.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (files.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Your downloaded files will appear here.'),
            ),
          ...files.map((file) => Card(
                child: ListTile(
                  leading: const Icon(Icons.video_file),
                  title: Text(
                    file.uri.pathSegments.last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '\${(file.lengthSync() / 1048576).toStringAsFixed(2)} MB',
                  ),
                  onTap: () => OpenFilex.open(file.path),
                ),
              )),
          const SizedBox(height: 18),
          const Text(
            'Use direct media links and only download content you are '
            'authorized to save. Some video websites do not allow direct downloads.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
