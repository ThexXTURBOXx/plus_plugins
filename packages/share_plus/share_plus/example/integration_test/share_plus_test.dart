// Copyright 2019, the Chromium project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Can launch share', (WidgetTester tester) async {
    final params = ShareParams(text: 'message', subject: 'title');
    // Check isNotNull because we cannot wait for ShareResult
    expect(SharePlus.instance.share(params), isNotNull);
  });

  testWidgets('Can launch shareUri', (WidgetTester tester) async {
    final params = ShareParams(uri: Uri.parse('https://example.com'));
    // Check isNotNull because we cannot wait for ShareResult
    expect(SharePlus.instance.share(params), isNotNull);
  }, skip: !Platform.isAndroid && !Platform.isIOS);

  testWidgets('Can shareXFile created using fileSystem', (
    WidgetTester tester,
  ) async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final tempDir = await Directory.systemTemp.createTemp();
    final file = File('${tempDir.path}/image.jpg');
    await file.writeAsBytes(bytes);
    final XFile xFile = XFile.fileSystem(path: file.path);

    final params = ShareParams(files: [xFile], text: 'message', fileNameOverrides: ['image.jpg']);
    expect(SharePlus.instance.share(params), isNotNull);
  });
}
