import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../editor/markup_editor.dart';
import 'common.dart';

/// The camera is offered on phones and tablets. On Windows photos come from files.
bool get cameraAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Lets the user take or choose photos, then opens each one in the markup editor.
/// Returns the finished JPEG images (skipping any the user cancelled).
Future<List<Uint8List>> pickAndMarkUp(BuildContext context, {required bool camera}) async {
  final picker = ImagePicker();
  final results = <Uint8List>[];
  try {
    final List<XFile> files;
    if (camera) {
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxPhotoSide.toDouble(),
        maxHeight: maxPhotoSide.toDouble(),
        imageQuality: 92,
      );
      files = shot == null ? const [] : [shot];
    } else {
      files = await picker.pickMultiImage(
        maxWidth: maxPhotoSide.toDouble(),
        maxHeight: maxPhotoSide.toDouble(),
        imageQuality: 92,
      );
    }
    for (var i = 0; i < files.length; i++) {
      final bytes = await files[i].readAsBytes();
      if (!context.mounted) break;
      final title = files.length > 1 ? 'Mark up photo ${i + 1} of ${files.length}' : 'Mark up photo';
      final done = await openMarkupEditor(context, bytes, title: title);
      if (done != null) results.add(done);
    }
  } catch (e) {
    if (context.mounted) showError(context, 'Could not open the photo: $e');
  }
  return results;
}

/// Small preview of an unsaved photo with a remove button.
class PendingPhoto extends StatelessWidget {
  const PendingPhoto({super.key, required this.bytes, required this.onRemove, this.size = 84});
  final Uint8List bytes;
  final VoidCallback onRemove;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(bytes, fit: BoxFit.cover)),
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: const Color(0xCC1A1A1A),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Colors.white, semanticLabel: 'Remove photo'),
                ),
              ),
            ),
          ),
        ]),
      );
}
