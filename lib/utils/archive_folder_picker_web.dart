import 'dart:async';
import 'dart:html';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'archive_file_reader.dart';

Future<List<ArchiveFile>?> pickArchiveFolder() async {
  final input = FileUploadInputElement()
    ..multiple = true
    ..accept = '.pdf'
    ..setAttribute('webkitdirectory', '')
    ..setAttribute('directory', '');
  input.click();
  await input.onChange.first;
  final selected = input.files;
  if (selected == null || selected.isEmpty) return null;
  final result = <ArchiveFile>[];
  for (var index = 0; index < selected.length; index++) {
    final file = selected[index];
    if (!file.name.toLowerCase().endsWith('.pdf')) continue;
    final reader = FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoadEnd.first;
    final rawBytes = reader.result;
    final bytes = rawBytes is Uint8List
        ? rawBytes
        : Uint8List.view(rawBytes as ByteBuffer);
    final relative = (file as JSObject)
        .getProperty<JSString?>('webkitRelativePath'.toJS)
        ?.toDart;
    result.add(
      ArchiveFile(
        relative != null && relative.isNotEmpty ? relative : file.name,
        bytes,
      ),
    );
  }
  return result;
}
