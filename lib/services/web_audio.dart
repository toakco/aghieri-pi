import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Play audio from a data URI on web.
/// Converts to Blob URL first — iOS Safari can't play long data URIs.
Future<bool> playAudioDataUri(String dataUri) async {
  try {
    // Extract base64 from data URI and convert to Blob URL
    String blobUrl;
    if (dataUri.startsWith('data:')) {
      final parts = dataUri.split(',');
      final base64Str = parts.length > 1 ? parts[1] : '';
      final bytes = base64Decode(base64Str);
      blobUrl = _createBlobUrl(bytes, 'audio/mpeg');
    } else {
      blobUrl = dataUri;
    }

    final completer = Completer<bool>();
    final audio = web.HTMLAudioElement();
    audio.src = blobUrl;
    audio.volume = 1.0;

    audio.onEnded.listen((_) {
      _revokeBlobUrl(blobUrl);
      if (!completer.isCompleted) completer.complete(true);
    });

    audio.onError.listen((_) {
      _revokeBlobUrl(blobUrl);
      if (!completer.isCompleted) completer.complete(false);
    });

    await audio.play().toDart;

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _revokeBlobUrl(blobUrl);
        return true;
      },
    );
  } catch (e) {
    return false;
  }
}

/// Play audio directly from raw bytes (skips data URI conversion).
Future<bool> playAudioBytes(Uint8List bytes) async {
  try {
    final blobUrl = _createBlobUrl(bytes, 'audio/mpeg');
    final completer = Completer<bool>();
    final audio = web.HTMLAudioElement();
    audio.src = blobUrl;
    audio.volume = 1.0;

    audio.onEnded.listen((_) {
      _revokeBlobUrl(blobUrl);
      if (!completer.isCompleted) completer.complete(true);
    });

    audio.onError.listen((_) {
      _revokeBlobUrl(blobUrl);
      if (!completer.isCompleted) completer.complete(false);
    });

    await audio.play().toDart;

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _revokeBlobUrl(blobUrl);
        return true;
      },
    );
  } catch (e) {
    return false;
  }
}

String _createBlobUrl(Uint8List bytes, String mimeType) {
  final jsArray = bytes.toJS;
  final blob = web.Blob([jsArray].toJS, web.BlobPropertyBag(type: mimeType));
  return web.URL.createObjectURL(blob);
}

void _revokeBlobUrl(String url) {
  try {
    web.URL.revokeObjectURL(url);
  } catch (_) {}
}
