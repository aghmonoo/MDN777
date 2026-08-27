// Stub interface
import 'dart:typed_data';
import 'file_download_helper_stub.dart'
    if (dart.library.html) 'file_download_helper_web.dart';

void downloadFile(Uint8List bytes, String filename) =>
    downloadFileImpl(bytes, filename);