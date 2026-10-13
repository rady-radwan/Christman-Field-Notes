import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Longest side of a saved photo, in pixels. Keeps uploads small but readable.
const maxPhotoSide = 2000;

enum MarkTool {
  arrow('Arrow', Icons.north_east),
  box('Box', Icons.crop_square),
  circle('Circle', Icons.circle_outlined),
  cloud('Cloud', Icons.cloud_outlined),
  text('Text', Icons.title),
  pen('Pen', Icons.edit_outlined);

  const MarkTool(this.label, this.icon);
  final String label;
  final IconData icon;
}

const markColors = <(String, Color)>[
  ('Red', Color(0xFFE4252B)),
  ('Yellow', Color(0xFFF5C400)),
  ('Blue', Color(0xFF2F8BFF)),
  ('Black', Color(0xFF000000)),
  ('White', Color(0xFFFFFFFF)),
];

/// One markup, stored in image pixel coordinates.
class Mark {
  Mark(this.tool, this.color, this.points, {this.text});
  final MarkTool tool;
  final Color color;
  final List<Offset> points;
  final String? text;
}

/// Opens [bytes] in the editor. Returns the marked-up photo as JPEG, or null if cancelled.
Future<Uint8List?> openMarkupEditor(BuildContext context, Uint8List bytes, {String title = 'Mark up photo'}) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => MarkupEditorScreen(bytes: bytes, title: title)),
  );
}

class MarkupEditorScreen extends StatefulWidget {
  const MarkupEditorScreen({super.key, required this.bytes, this.title = 'Mark up photo'});
  final Uint8List bytes;
  final String title;

  @override
  State<MarkupEditorScreen> createState() => _MarkupEditorScreenState();
}

class _MarkupEditorScreenState extends State<MarkupEditorScreen> {
  static const _bg = Color(0xFF111417);
  static const _panel = Color(0xFF1B2024);
  static const _border = Color(0xFF3B4248);
  static const _copper = Color(0xFFB98052);

  ui.Image? _image;
  String? _error;
  final List<Mark> _marks = [];
  final List<Mark> _redo = [];
  Mark? _drawing;
  MarkTool _tool = MarkTool.arrow;
  Color _color = markColors.first.$2;
  double _scale = 1;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(widget.bytes);
      final desc = await ui.ImageDescriptor.encoded(buffer);
      final longest = math.max(desc.width, desc.height);
      final f = longest > maxPhotoSide ? maxPhotoSide / longest : 1.0;
      final codec = await desc.instantiateCodec(
        targetWidth: (desc.width * f).round(),
        targetHeight: (desc.height * f).round(),
      );
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _image = frame.image);
    } catch (e) {
      if (mounted) setState(() => _error = 'This file could not be opened as a photo.');
    }
  }

  Offset _toImage(Offset local) => local / _scale;

  void _start(Offset local) {
    if (_tool == MarkTool.text) return;
    final p = _toImage(local);
    setState(() => _drawing = Mark(_tool, _color, [p, p]));
  }

  void _update(Offset local) {
    final d = _drawing;
    if (d == null) return;
    final p = _toImage(local);
    setState(() {
      if (d.tool == MarkTool.pen) {
        d.points.add(p);
      } else {
        d.points[1] = p;
      }
    });
  }

  void _end() {
    final d = _drawing;
    if (d == null) return;
    final size = (d.points.first - d.points.last).distance;
    setState(() {
      if (d.tool == MarkTool.pen ? d.points.length > 2 : size > 6 / _scale) {
        _marks.add(d);
        _redo.clear();
      }
      _drawing = null;
    });
  }

  Future<void> _tapText(Offset local) async {
    if (_tool != MarkTool.text) return;
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add text'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. LEAK HERE'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Add')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      _marks.add(Mark(MarkTool.text, _color, [_toImage(local)], text: text.trim()));
      _redo.clear();
    });
  }

  void _undo() {
    if (_marks.isEmpty) return;
    setState(() => _redo.add(_marks.removeLast()));
  }

  void _redoOne() {
    if (_redo.isEmpty) return;
    setState(() => _marks.add(_redo.removeLast()));
  }

  Future<void> _done() async {
    final image = _image;
    if (image == null) return;
    setState(() => _saving = true);
    try {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.high);
      paintMarks(canvas, _marks, image.width.toDouble());
      final out = await rec.endRecording().toImage(image.width, image.height);
      final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
      final jpg = await compute(
        encodeJpgJob,
        EncodeJob(image.width, image.height, data!.buffer.asUint8List()),
      );
      if (mounted) Navigator.pop(context, jpg);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the photo. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
            child: Row(children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(64, 44)),
                child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'BarlowCondensed', fontWeight: FontWeight.w700, fontSize: 19, color: Colors.white),
                ),
              ),
              FilledButton(
                onPressed: _image == null || _saving ? null : _done,
                style: FilledButton.styleFrom(
                  backgroundColor: _copper,
                  foregroundColor: const Color(0xFF141414),
                  minimumSize: const Size(80, 40),
                  shape: const StadiumBorder(),
                ),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Done'),
              ),
            ]),
          ),
          Expanded(
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: _error != null
                  ? Text(_error!, style: const TextStyle(color: Colors.white))
                  : _image == null
                      ? const CircularProgressIndicator()
                      : LayoutBuilder(builder: (context, box) {
                          final im = _image!;
                          _scale = math.min(box.maxWidth / im.width, box.maxHeight / im.height);
                          final w = im.width * _scale, h = im.height * _scale;
                          return SizedBox(
                            width: w,
                            height: h,
                            child: MouseRegion(
                              cursor: _tool == MarkTool.text ? SystemMouseCursors.text : SystemMouseCursors.precise,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (d) => _start(d.localPosition),
                                onPanUpdate: (d) => _update(d.localPosition),
                                onPanEnd: (_) => _end(),
                                onTapUp: (d) => _tapText(d.localPosition),
                                child: CustomPaint(
                                  size: Size(w, h),
                                  painter: _EditorPainter(im, [..._marks, if (_drawing != null) _drawing!], _scale),
                                ),
                              ),
                            ),
                          );
                        }),
            ),
          ),
          Container(
            color: _panel,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                for (final t in MarkTool.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _ToolButton(
                        tool: t,
                        selected: t == _tool,
                        onTap: () => setState(() => _tool = t),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                for (final (name, color) in markColors)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Semantics(
                      button: true,
                      selected: color == _color,
                      label: name,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _color = color),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: color == _color ? const Color(0xFFD19A6C) : _border, width: 3),
                          ),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                _RoundIcon(icon: Icons.undo, label: 'Undo', onTap: _marks.isEmpty ? null : _undo),
                const SizedBox(width: 6),
                _RoundIcon(icon: Icons.redo, label: 'Redo', onTap: _redo.isEmpty ? null : _redoOne),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tool, required this.selected, required this.onTap});
  final MarkTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? const Color(0xFF3A2B1F) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? const Color(0xFFB98052) : const Color(0xFF3B4248)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(tool.icon, color: Colors.white, size: 22),
              const SizedBox(height: 3),
              Text(tool.label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon),
        color: Colors.white,
        disabledColor: const Color(0xFF5A6168),
        style: IconButton.styleFrom(
          side: const BorderSide(color: Color(0xFF3B4248)),
          minimumSize: const Size(44, 44),
        ),
      );
}

class _EditorPainter extends CustomPainter {
  _EditorPainter(this.image, this.marks, this.scale);
  final ui.Image image;
  final List<Mark> marks;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    paintMarks(canvas, marks, image.width.toDouble());
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EditorPainter old) => true;
}

/// Draws [marks] onto [canvas] in image pixel coordinates.
void paintMarks(Canvas canvas, List<Mark> marks, double imageWidth) {
  final stroke = math.max(3.0, imageWidth / 250);
  for (final m in marks) {
    final paint = Paint()
      ..color = m.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (m.tool) {
      case MarkTool.box:
        canvas.drawRect(Rect.fromPoints(m.points[0], m.points[1]), paint);
      case MarkTool.circle:
        canvas.drawOval(Rect.fromPoints(m.points[0], m.points[1]), paint);
      case MarkTool.arrow:
        _arrow(canvas, m.points[0], m.points[1], paint, stroke);
      case MarkTool.cloud:
        canvas.drawPath(cloudPath(Rect.fromPoints(m.points[0], m.points[1]), stroke * 7), paint);
      case MarkTool.pen:
        final path = Path()..moveTo(m.points.first.dx, m.points.first.dy);
        for (final p in m.points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      case MarkTool.text:
        _label(canvas, m.points.first, m.text ?? '', m.color, imageWidth);
    }
  }
}

void _arrow(Canvas canvas, Offset a, Offset b, Paint paint, double stroke) {
  canvas.drawLine(a, b, paint);
  final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
  final head = stroke * 5;
  for (final side in [-1, 1]) {
    final t = angle + math.pi + side * math.pi / 7;
    canvas.drawLine(b, b + Offset(math.cos(t), math.sin(t)) * head, paint);
  }
}

/// Revision cloud: half-circle bumps around the rectangle, bulging outward.
Path cloudPath(Rect r, double bump) {
  final path = Path()..moveTo(r.left, r.top);
  void edge(Offset from, Offset to) {
    final len = (to - from).distance;
    final n = math.max(2, (len / bump).round());
    for (var i = 1; i <= n; i++) {
      final p = Offset.lerp(from, to, i / n)!;
      path.arcToPoint(p, radius: Radius.circular(len / n / 2), clockwise: true);
    }
  }

  edge(r.topLeft, r.topRight);
  edge(r.topRight, r.bottomRight);
  edge(r.bottomRight, r.bottomLeft);
  edge(r.bottomLeft, r.topLeft);
  return path..close();
}

void _label(Canvas canvas, Offset at, String text, Color bg, double imageWidth) {
  final size = math.max(16.0, imageWidth / 28);
  final lightBg = bg.computeLuminance() > 0.5;
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: lightBg ? const Color(0xFF1A1A1A) : Colors.white,
        fontSize: size,
        fontWeight: FontWeight.w700,
        fontFamily: 'Barlow',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: imageWidth * 0.8);
  final pad = size * 0.35;
  final rect = Rect.fromLTWH(at.dx, at.dy, tp.width + pad * 2, tp.height + pad * 1.4);
  canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(size * 0.2)), Paint()..color = bg);
  tp.paint(canvas, Offset(at.dx + pad, at.dy + pad * 0.7));
}

/// Data passed to the background JPEG encoder.
class EncodeJob {
  EncodeJob(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;
}

Uint8List encodeJpgJob(EncodeJob job) {
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: 85);
}
