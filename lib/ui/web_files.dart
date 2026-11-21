import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

typedef PickedFile = ({Uint8List bytes, String name, String type});

/// Otvara preglednikov dijalog za odabir datoteke.
Future<PickedFile?> pickFile(String accept) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  final done = Completer<web.File?>();
  input.onchange = ((web.Event _) {
    final files = input.files;
    if (!done.isCompleted) {
      done.complete(files != null && files.length > 0 ? files.item(0) : null);
    }
  }).toJS;
  input.addEventListener(
      'cancel',
      ((web.Event _) {
        if (!done.isCompleted) done.complete(null);
      }).toJS);
  input.click();
  final file = await done.future;
  if (file == null) return null;
  final buffer = await file.arrayBuffer().toDart;
  return (bytes: buffer.toDart.asUint8List(), name: file.name, type: file.type);
}

/// Preuzimanje teksta kao datoteke.
void downloadText(String text, String filename, {String mime = 'application/json'}) {
  final blob = web.Blob([text.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}

/// Preuzimanje binarnih podataka (npr. PNG slike) kao datoteke.
void downloadBytes(Uint8List bytes, String filename, {String mime = 'application/octet-stream'}) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
