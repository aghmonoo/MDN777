import 'dart:typed_data';
import 'package:flutter/material.dart';

void downloadFileImpl(Uint8List bytes, String filename) {
  debugPrint('downloadFile not supported on this platform: $filename');
}