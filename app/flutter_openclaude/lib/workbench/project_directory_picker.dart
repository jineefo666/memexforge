import 'package:flutter/services.dart';

typedef ProjectDirectoryPicker = Future<String?> Function();

const _projectDirectoryChannel = MethodChannel('openclaude/workspace');

ProjectDirectoryPicker createDefaultProjectDirectoryPicker() {
  return pickProjectDirectory;
}

Future<String?> pickProjectDirectory() async {
  try {
    final directory = await _projectDirectoryChannel.invokeMethod<String>(
      'pickDirectory',
    );
    return _normalizePath(directory);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

String? _normalizePath(String? path) {
  final trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.length > 1 && trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}
