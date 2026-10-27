import 'dart:async';
import 'dart:io';

import 'package:extractor/extractor.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const MitcrosApp());

class MitcrosApp extends StatelessWidget {
  const MitcrosApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mitcros Downloader',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF80CBC4),
            brightness: Brightness.dark,
          ),
        ),
        home: const DownloaderHome(),
      );
}

class DownloaderHome extends StatefulWidget {
  const DownloaderHome({super.key});

  @override
  State<DownloaderHome> createState() => _DownloaderHomeState();
}

class _DownloaderHomeState extends State<DownloaderHome> {
  final _url = TextEditingController();
  final _engine = YoutubeDLFlutter.instance;
  final Map<String, double> _progress = {};
  final Map<String, String> _states = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<File> _files = [];
  VideoInfo? _info;
  List<VideoFormat> _qualities = [];
  VideoFormat? _selected;
  bool _initializing = true;
  bool _busy = false;
  bool _audioOnly = false;
  String _status = 'Starting downloader…';
  String? _error;
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _listenForProgress();
    _initialize();
  }

  void _listenForProgress() {
    _subscriptions.add(_engine.onProgress.listen((p) {
      if (!mounted) return;
      setState(() => _progress[p.processId] = p.progress.clamp(0, 100).toDouble());
    }));
    _subscriptions.add(_engine.onStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _states[s.processId] = s.state.name);
    }));
    _subscriptions.add(_engine.onError.listen((e) {
      if (!mounted) return;
      setState(() {
        _error = e.error;
        _status = 'Download error';
        _busy = false;
      });
    }));
  }

  Future<void> _initialize() async {
    try {
      final result = await _engine.initialize(
        enableFFmpeg: true,
        enableAria2c: false,
      );
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _status = result.success
            ? 'Ready. Paste a supported video or media link.'
            : 'Downloader engine could not start.';
        if (!result.success) _error = result.errorMessage;
      });
      if (result.success) await _loadFiles();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _status = 'Initialization failed';
        _error = e.toString();
      });
    }
  }

  Future<Directory> _downloadDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/Downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _loadFiles() async {
    try {
      final dir = await _downloadDir();
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (mounted) setState(() => _files = files);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read downloads: $e');
    }
  }

  bool _validUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  Future<void> _getInfo() async {
    final url = _url.text.trim();
    if (!_validUrl(url)) {
      setState(() => _error = 'Paste a valid http:// or https:// link first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _qualities = [];
      _selected = null;
      _status = 'Checking link and available formats…';
    });
    try {
      final info = await _engine.getVideoInfo(url);
      final formats = (info.formats ?? <VideoFormat?>[])
          .whereType<VideoFormat>()
          .where((f) => f.vcodec != null && f.vcodec != 'none' && f.height != null)
          .toList()
        ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
      final unique = <int, VideoFormat>{};
      for (final f in formats) {
        unique.putIfAbsent(f.height!, () => f);
      }
      if (!mounted) return;
      setState(() {
        _info = info;
        _qualities = unique.values.toList();
        _status = 'Link checked. Choose video quality or audio only.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not read this link';
        _error = 'This platform may require login, block extraction, or be unsupported. Details: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download({bool audio = false}) async {
    final url = _url.text.trim();
    if (!_validUrl(url)) {
      setState(() => _error = 'Paste a valid media link first.');
      return;
    }
    if (!audio && _info == null) {
      await _getInfo();
      if (_info == null) return;
    }
    final dir = await _downloadDir();
    final id = 'mitcros_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _busy = true;
      _audioOnly = audio;
      _activeId = id;
      _progress[id] = 0;
      _states[id] = 'started';
      _error = null;
      _status = audio ? 'Downloading audio…' : 'Downloading video…';
    });
    try {
      final request = DownloadRequest(
        url: url,
        outputPath: dir.path,
        outputTemplate: '%(title).180B [%(id)s].%(ext)s',
        format: audio
            ? 'bestaudio/best'
            : (_selected == null
                ? 'bestvideo+bestaudio/best'
                : '${_selected!.formatId ?? 'bestvideo'}+bestaudio/best'),
        noPlaylist: true,
        extractAudio: audio,
        audioFormat: audio ? 'mp3' : null,
        audioQuality: audio ? 0 : null,
        embedMetadata: true,
        processId: id,
      );
      final result = await _engine.download(request);
      if (!mounted) return;
      if (result.status == OperationStatus.success && result.outputPath != null) {
        setState(() {
          _status = 'Download complete';
          _states[id] = 'completed';
          _progress[id] = 100;
        });
        await _loadFiles();
      } else {
        setState(() {
          _status = 'Download did not complete';
          _error = result.errorMessage ?? 'The extractor did not return a saved file.';
          _states[id] = 'error';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Download failed';
        _error = e.toString();
        _states[id] = 'error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final id = _activeId;
    if (id == null) return;
    try {
      await _engine.cancelDownload(id);
      if (mounted) setState(() => _status = 'Cancellation requested');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not cancel: $e');
    }
  }

  @override
  void dispose() {
    _url.dispose();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mitcros Downloader', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _loadFiles, icon: const Icon(Icons.refresh), tooltip: 'Refresh downloads')],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Icon(Icons.download_for_offline, size: 42),
            SizedBox(height: 12),
            Text('Your media. Your device.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('On-device media extraction for supported public links. No download server.'),
          ]))),
          const SizedBox(height: 18),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Video, Reel or media link',
              hintText: 'Paste a Facebook, YouTube, Instagram or direct media URL',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy || _initializing ? null : _getInfo,
            icon: const Icon(Icons.search),
            label: const Text('Check link and qualities'),
          ),
          if (_info != null) ...[
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_info!.title ?? 'Media found', style: Theme.of(context).textTheme.titleMedium),
              if (_info!.duration != null) Text('Duration: ${_info!.duration} seconds'),
              if (_qualities.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Video quality'),
                DropdownButton<VideoFormat>(
                  isExpanded: true,
                  value: _selected,
                  hint: const Text('Best available quality'),
                  items: _qualities.map((q) => DropdownMenuItem(value: q, child: Text('${q.height}p${q.ext == null ? '' : ' • ${q.ext!.toUpperCase()}'}'))).toList(),
                  onChanged: _busy ? null : (q) => setState(() => _selected = q),
                ),
              ],
            ]))),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy || _initializing ? null : () => _download(),
            icon: const Icon(Icons.video_file),
            label: const Text('Download video'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || _initializing ? null : () => _download(audio: true),
            icon: const Icon(Icons.audiotrack),
            label: const Text('Download audio (MP3)'),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: (_activeId != null && (_progress[_activeId!] ?? 0) > 0) ? (_progress[_activeId!]! / 100) : null),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _cancel, icon: const Icon(Icons.cancel), label: const Text('Cancel download')),
          ],
          const SizedBox(height: 12),
          Text(_status),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: TextStyle(color: cs.error))),
          const SizedBox(height: 24),
          Text('MY DOWNLOADS (${_files.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (_files.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('Your downloaded files will appear here.')),
          ..._files.map((file) => Card(child: ListTile(
                leading: const Icon(Icons.video_file),
                title: Text(file.uri.pathSegments.last, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${(file.lengthSync() / 1048576).toStringAsFixed(1)} MB • saved on this device'),
                onTap: () => OpenFilex.open(file.path),
              ))),
          const SizedBox(height: 18),
          const Text('Only download content you own or are authorized to save. Private, login-protected, DRM-protected or unsupported links may not work. Files are saved in this app’s local Downloads folder.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
