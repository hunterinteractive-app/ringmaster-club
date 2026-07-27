import 'dart:typed_data';

class ArchiveFile {
  const ArchiveFile(this.relativePath, this.bytes);
  final String relativePath;
  final Uint8List bytes;
}

Future<List<ArchiveFile>> readPdfArchive(String rootPath) =>
    throw UnsupportedError(
      'Folder archive import is available on desktop only.',
    );
