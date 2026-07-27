import 'dart:io';
import 'dart:typed_data';

class ArchiveFile {
  const ArchiveFile(this.relativePath, this.bytes);
  final String relativePath;
  final Uint8List bytes;
}

Future<List<ArchiveFile>> readPdfArchive(String rootPath) async {
  final root = Directory(rootPath);
  final files = <ArchiveFile>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.toLowerCase().endsWith('.pdf'))
      continue;
    final relative = entity.path
        .substring(rootPath.length)
        .replaceFirst(RegExp(r'^[/\\]'), '');
    files.add(ArchiveFile(relative, await entity.readAsBytes()));
  }
  return files;
}
