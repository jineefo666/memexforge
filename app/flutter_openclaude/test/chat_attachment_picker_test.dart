import 'package:flutter_openclaude/workbench/chat_attachment_picker.dart';
import 'package:flutter_openclaude/workbench/workbench_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies image text and generic attachments', () {
    expect(
      chatAttachmentKindForFile(name: 'mockup.png', mimeType: 'image/png'),
      ChatAttachmentKind.image,
    );
    expect(
      chatAttachmentKindForFile(
        name: 'requirements.md',
        mimeType: 'application/octet-stream',
      ),
      ChatAttachmentKind.text,
    );
    expect(
      chatAttachmentKindForFile(
        name: 'archive.zip',
        mimeType: 'application/zip',
      ),
      ChatAttachmentKind.file,
    );
  });

  test('truncates long text previews', () {
    final content = attachmentTextPreview('a' * 13000);

    expect(content.length, lessThan(13000));
    expect(content, endsWith('[Attachment preview truncated]'));
  });
}
