import 'dart:convert';

import 'package:file_selector/file_selector.dart';

import 'workbench_models.dart';

const _maxAttachmentPreviewCharacters = 12000;
const _maxInlineImageAttachmentBytes = 5 * 1024 * 1024;

const _acceptedAttachmentTypes = [
  XTypeGroup(
    label: 'Documents and images',
    extensions: [
      'txt',
      'md',
      'markdown',
      'json',
      'jsonl',
      'yaml',
      'yml',
      'csv',
      'tsv',
      'html',
      'css',
      'js',
      'jsx',
      'ts',
      'tsx',
      'dart',
      'py',
      'java',
      'go',
      'rs',
      'c',
      'cpp',
      'h',
      'hpp',
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'pdf',
    ],
  ),
];

Future<List<ChatAttachment>> pickChatAttachments() async {
  final files = await openFiles(
    acceptedTypeGroups: _acceptedAttachmentTypes,
    confirmButtonText: 'Attach',
  );
  return chatAttachmentsFromFiles(files);
}

Future<List<ChatAttachment>> chatAttachmentsFromFiles(List<XFile> files) async {
  final attachments = <ChatAttachment>[];
  for (var index = 0; index < files.length; index += 1) {
    final file = files[index];
    final name = file.name.isEmpty ? _nameFromPath(file.path) : file.name;
    final mimeType = (file.mimeType ?? '').trim();
    final sizeBytes = await _safeLength(file);
    final kind = chatAttachmentKindForFile(name: name, mimeType: mimeType);
    final content = kind == ChatAttachmentKind.text
        ? await _safeTextPreview(file)
        : null;
    final dataBase64 = kind == ChatAttachmentKind.image
        ? await _safeImageBase64(file, knownSizeBytes: sizeBytes)
        : null;
    attachments.add(
      ChatAttachment(
        id: _attachmentId(name: name, path: file.path, index: index),
        name: name,
        mimeType: mimeType.isEmpty ? _fallbackMimeType(kind) : mimeType,
        sizeBytes: sizeBytes,
        kind: kind,
        path: file.path.isEmpty ? null : file.path,
        content: content,
        dataBase64: dataBase64,
      ),
    );
  }
  return attachments;
}

ChatAttachmentKind chatAttachmentKindForFile({
  required String name,
  required String mimeType,
}) {
  final normalizedMimeType = mimeType.toLowerCase();
  final extension = _extensionForName(name);
  if (normalizedMimeType.startsWith('image/') ||
      {'png', 'jpg', 'jpeg', 'gif', 'webp'}.contains(extension)) {
    return ChatAttachmentKind.image;
  }
  if (normalizedMimeType.startsWith('text/') ||
      {
        'txt',
        'md',
        'markdown',
        'json',
        'jsonl',
        'yaml',
        'yml',
        'csv',
        'tsv',
        'html',
        'css',
        'js',
        'jsx',
        'ts',
        'tsx',
        'dart',
        'py',
        'java',
        'go',
        'rs',
        'c',
        'cpp',
        'h',
        'hpp',
      }.contains(extension)) {
    return ChatAttachmentKind.text;
  }
  return ChatAttachmentKind.file;
}

String attachmentTextPreview(String content) {
  if (content.length <= _maxAttachmentPreviewCharacters) return content;
  return '${content.substring(0, _maxAttachmentPreviewCharacters)}\n[Attachment preview truncated]';
}

Future<int> _safeLength(XFile file) async {
  try {
    return await file.length();
  } catch (_) {
    return 0;
  }
}

Future<String?> _safeTextPreview(XFile file) async {
  try {
    return attachmentTextPreview(await file.readAsString());
  } catch (_) {
    return null;
  }
}

Future<String?> _safeImageBase64(
  XFile file, {
  required int knownSizeBytes,
}) async {
  if (knownSizeBytes > _maxInlineImageAttachmentBytes) return null;
  try {
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxInlineImageAttachmentBytes) return null;
    return base64Encode(bytes);
  } catch (_) {
    return null;
  }
}

String _attachmentId({
  required String name,
  required String path,
  required int index,
}) {
  final source = path.isEmpty ? name : path;
  final sanitized = source
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
  return 'attachment-$index-$sanitized';
}

String _nameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final separator = normalized.lastIndexOf('/');
  if (separator == -1) return normalized.isEmpty ? 'attachment' : normalized;
  final name = normalized.substring(separator + 1);
  return name.isEmpty ? 'attachment' : name;
}

String _extensionForName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot == -1 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

String _fallbackMimeType(ChatAttachmentKind kind) {
  return switch (kind) {
    ChatAttachmentKind.image => 'image/*',
    ChatAttachmentKind.text => 'text/plain',
    ChatAttachmentKind.file => 'application/octet-stream',
  };
}
