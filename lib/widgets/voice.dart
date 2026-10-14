import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// A voice message recorded on this device, not uploaded yet.
class RecordedClip {
  RecordedClip({required this.path, required this.audio, required this.length});
  final String path;
  final NewAudio audio;
  final Duration length;
}

String clockText(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Longest voice message, so files stay small.
const maxVoiceLength = Duration(minutes: 5);

/// Opens the recorder in a dialog. Returns the finished recording, or null if cancelled.
Future<RecordedClip?> recordVoice(BuildContext context) =>
    showDialog<RecordedClip>(context: context, barrierDismissible: false, builder: (_) => const _RecorderDialog());

class _RecorderDialog extends StatefulWidget {
  const _RecorderDialog();
  @override
  State<_RecorderDialog> createState() => _RecorderDialogState();
}

class _RecorderDialogState extends State<_RecorderDialog> {
  final _rec = AudioRecorder();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  String? _error;
  String _ext = 'm4a';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        setState(() => _error = 'The microphone is not allowed. Turn on microphone access for this app and try again.');
        return;
      }
      final aac = await _rec.isEncoderSupported(AudioEncoder.aacLc);
      _ext = aac ? 'm4a' : 'wav';
      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, 'voice-${const Uuid().v4()}.$_ext');
      await _rec.start(
        RecordConfig(
          encoder: aac ? AudioEncoder.aacLc : AudioEncoder.wav,
          bitRate: 64000,
          sampleRate: aac ? 44100 : 16000,
          numChannels: 1,
        ),
        path: path,
      );
      setState(() => _recording = true);
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(milliseconds: 250));
        if (_elapsed >= maxVoiceLength) _stop();
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start recording. Check that a microphone is connected.\n($e)');
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    if (!_recording) return;
    _recording = false;
    try {
      final path = await _rec.stop();
      if (path == null) throw Exception('nothing was recorded');
      final file = File(path);
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.pop(context, RecordedClip(path: path, audio: NewAudio(bytes, _ext), length: _elapsed));
    } catch (e) {
      if (mounted) setState(() => _error = 'Recording failed: $e');
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    if (_recording) {
      try {
        await _rec.cancel();
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return AlertDialog(
      title: const Text('Voice message'),
      content: SizedBox(
        width: 340,
        child: _error != null
            ? Text(_error!, style: TextStyle(color: c.urgentText))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 8),
                Icon(Icons.mic, size: 48, color: _recording ? c.urgentText : c.muted),
                const SizedBox(height: 8),
                Text(clockText(_elapsed), style: condensed(34)),
                const SizedBox(height: 4),
                Text(_recording ? 'Recording… speak now' : 'Starting the microphone…',
                    style: TextStyle(color: c.muted)),
                const SizedBox(height: 4),
                Text('Up to ${maxVoiceLength.inMinutes} minutes', style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
      ),
      actions: [
        TextButton(onPressed: _cancel, child: const Text('Cancel')),
        if (_error == null)
          FilledButton.icon(
            onPressed: _recording ? _stop : null,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Stop and attach'),
          ),
      ],
    );
  }
}

/// Small play / pause bar for a voice message.
/// Give [ref] for an uploaded message, or [filePath] for one recorded but not sent yet.
class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, this.ref, this.filePath, this.onRemove, this.label});
  final String? ref;
  final String? filePath;
  final VoidCallback? onRemove;
  final String? label;

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription<dynamic>>[];
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  Duration _len = Duration.zero;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    }));
    _subs.add(_player.onPositionChanged.listen((d) {
      if (mounted) setState(() => _pos = d);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _len = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _pos = Duration.zero);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_state == PlayerState.playing) {
        await _player.pause();
        return;
      }
      if (_loaded && _state == PlayerState.paused) {
        await _player.resume();
        return;
      }
      setState(() {
        _loading = true;
        _error = null;
      });
      final Source source;
      if (widget.filePath != null) {
        source = DeviceFileSource(widget.filePath!);
      } else {
        final uri = await context.read<AppState>().repo.audioUri(widget.ref!);
        source = uri.scheme == 'file' ? DeviceFileSource(uri.toFilePath()) : UrlSource(uri.toString());
      }
      await _player.play(source);
      _loaded = true;
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not play this voice message.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final playing = _state == PlayerState.playing;
    final progress = _len.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / _len.inMilliseconds).clamp(0.0, 1.0);
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(
        color: c.avatarBg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: playing ? 'Pause' : 'Play voice message',
          onPressed: _loading ? null : _toggle,
          style: IconButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.accentInk),
          icon: _loading
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.accentInk))
              : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.graphic_eq, size: 16, color: c.avatarInk),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _error ?? widget.label ?? 'Voice message',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _error != null ? c.urgentText : c.avatarInk),
                ),
              ),
              const SizedBox(width: 8),
              if (_len > Duration.zero)
                Text('${clockText(_pos)} / ${clockText(_len)}', style: TextStyle(fontSize: 12, color: c.avatarInk)),
            ]),
            const SizedBox(height: 4),
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: c.avatarInk.withValues(alpha: 0.18),
                  color: c.avatarInk,
                ),
              ),
            ),
          ]),
        ),
        if (widget.onRemove != null) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Remove voice message',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onRemove,
            icon: Icon(Icons.close, size: 18, color: c.avatarInk),
          ),
        ],
      ]),
    );
  }
}

/// "Record voice" button that adds the recording to [onRecorded].
class RecordVoiceButton extends StatelessWidget {
  const RecordVoiceButton({super.key, required this.onRecorded, this.enabled = true, this.compact = false});
  final void Function(RecordedClip clip) onRecorded;
  final bool enabled;
  final bool compact;

  Future<void> _go(BuildContext context) async {
    final clip = await recordVoice(context);
    if (clip != null) onRecorded(clip);
  }

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    if (compact) {
      return IconButton(
        tooltip: 'Record a voice message',
        onPressed: enabled ? () => _go(context) : null,
        icon: const Icon(Icons.mic_none_rounded),
        color: c.accentText,
        style: IconButton.styleFrom(side: BorderSide(color: c.line2), minimumSize: const Size(44, 44)),
      );
    }
    return OutlinedButton.icon(
      onPressed: enabled ? () => _go(context) : null,
      icon: Icon(Icons.mic_none_rounded, color: c.accentText),
      label: const Text('Record voice message'),
    );
  }
}

/// Shows a list of uploaded voice messages.
class VoiceList extends StatelessWidget {
  const VoiceList({super.key, required this.refs});
  final List<String> refs;

  @override
  Widget build(BuildContext context) {
    if (refs.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < refs.length; i++)
        VoicePlayer(
          key: ValueKey(refs[i]),
          ref: refs[i],
          label: refs.length == 1 ? 'Voice message' : 'Voice message ${i + 1}',
        ),
    ]);
  }
}
