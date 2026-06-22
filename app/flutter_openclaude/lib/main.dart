import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'workbench/openclaude_app.dart';

export 'workbench/openclaude_app.dart';

void main() {
  runApp(const OpenClaudeApp(autoStartBridge: !kIsWeb));
}
