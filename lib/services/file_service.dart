import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
}

/// Cross-platform save/open via native dialogs (file_picker v12). On desktop
/// this shows the OS save/open panel (which, with the user-selected-files
/// entitlement on macOS, allows writing outside the sandbox); on mobile it
/// routes through the storage framework.
class FileService {
  /// Shows a save dialog and writes [bytes]. Returns a human-readable location
  /// (path or URI), or null if the user cancelled.
  Future<String?> save({
    required String fileName,
    required List<int> bytes,
    required String ext,
  }) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save $fileName',
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    if (uri == null) return null;
    return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  }

  /// Opens a file picker limited to [extensions] and returns its bytes.
  Future<PickedFile?> open(List<String> extensions) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (files.isEmpty) return null;
    final f = files.first;
    final bytes = await f.readAsBytes();
    return PickedFile(f.name, bytes);
  }
}
