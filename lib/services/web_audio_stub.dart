import 'dart:typed_data';

/// Stub for non-web platforms — never called at runtime.
Future<bool> playAudioDataUri(String dataUri) async => false;
Future<bool> playAudioBytes(Uint8List bytes) async => false;
