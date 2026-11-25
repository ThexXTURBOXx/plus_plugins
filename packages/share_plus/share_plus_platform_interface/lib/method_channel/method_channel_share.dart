// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:mime/mime.dart' show extensionFromMime, lookupMimeType;
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Plugin for summoning a platform share sheet.
class MethodChannelShare extends SharePlatform {
  /// [MethodChannel] used to communicate with the platform side.
  @visibleForTesting
  static const MethodChannel channel = MethodChannel(
    'dev.fluttercommunity.plus/share',
  );

  @override
  Future<ShareResult> share(ShareParams params) async {
    final paramsMap = await _toPlatformMap(params);
    final result =
        await channel.invokeMethod<String>('share', paramsMap) ??
        'dev.fluttercommunity.plus/share/unavailable';

    return ShareResult(result, _statusFromResult(result));
  }

  Future<Map<String, dynamic>> _toPlatformMap(ShareParams params) async {
    assert(
      params.text != null ||
          params.uri != null ||
          (params.files != null && params.files!.isNotEmpty),
      'At least one of text, uri or files must be provided',
    );

    final map = <String, dynamic>{
      if (params.text != null) 'text': params.text,
      if (params.subject != null) 'subject': params.subject,
      if (params.title != null) 'title': params.title,
      if (params.uri != null) 'uri': params.uri.toString(),
    };

    if (params.sharePositionOrigin != null) {
      map['originX'] = params.sharePositionOrigin!.left;
      map['originY'] = params.sharePositionOrigin!.top;
      map['originWidth'] = params.sharePositionOrigin!.width;
      map['originHeight'] = params.sharePositionOrigin!.height;
    }

    if (params.files != null) {
      final filesWithPath = await _getFiles(
        params.files!,
        params.fileNameOverrides,
      );
      assert(filesWithPath.every((element) => element.path.isNotEmpty));

      final mimeTypes = filesWithPath
          .map((e) => _mimeTypeForPath(e.path))
          .toList();

      final paths = filesWithPath.map((e) => e.path).toList();
      assert(paths.length == mimeTypes.length);
      assert(mimeTypes.every((element) => element.isNotEmpty));

      map['paths'] = paths;
      map['mimeTypes'] = mimeTypes;
    }

    if (params.excludedCupertinoActivities != null &&
        params.excludedCupertinoActivities!.isNotEmpty) {
      final excludedActivityTypes = params.excludedCupertinoActivities!
          .map((e) => e.value)
          .toList();
      map['excludedCupertinoActivities'] = excludedActivityTypes;
    }

    return map;
  }

  /// Ensure that a file is readable from the file system.
  /// Will create file on-demand under TemporaryDirectory
  /// and return the temporary file otherwise.
  ///
  /// if file doesn't contain path,
  /// then make new file in TemporaryDirectory and return with path
  /// the system will automatically delete files in this
  /// TemporaryDirectory as disk space is needed elsewhere on the device
  Future<FileSystemXFile> _getFile(
    XFile file, {
    String? tempRoot,
    String? nameOverride,
  }) async {
    final filePath = file is FileSystemXFile
        ? file.path
        : (Uri.tryParse(file.uri)?.isScheme('file') == true
            ? Uri.parse(file.uri).toFilePath()
            : '');
    if (filePath.isNotEmpty) {
      return file is FileSystemXFile ? file : FileSystemXFile(filePath);
    } else {
      tempRoot ??= (await getTemporaryDirectory()).path;
      final bytes = await file.readAsBytes();
      final fileName = await file.name();
      // Method returns null as in v2.0.0
      final extension =
          // ignore: dead_null_aware_expression
          extensionFromMime(_mimeTypeForPath(fileName ?? '')) ?? 'bin';

      //By having a UUID v4 folder wrapping the file
      //This path generation algorithm will not only minimize the risk of name collision but also ensure that the filename
      //is not ridiculously long such that some platforms might not show the extension but ellipses
      //which the user needs
      //
      //More importantly it allows us to use real filenames when available
      final tempSubfolderPath = "$tempRoot/${const Uuid().v4()}";
      await Directory(tempSubfolderPath).create(recursive: true);

      // True if filename exists or the filename has a valid extension
      final filenameNotEmptyOrHasValidExt =
          fileName != null && fileName.isNotEmpty ||
          (fileName != null && lookupMimeType(fileName) != null);

      //Per Issue [#3032](https://github.com/fluttercommunity/plus_plugins/issues/3032): use overridden name when available.
      //Per Issue [#1548](https://github.com/fluttercommunity/plus_plugins/issues/1548): attempt to use XFile.name when available
      final filename =
          nameOverride ??
          (filenameNotEmptyOrHasValidExt
              ? fileName
              : "${const Uuid().v1().substring(10)}.$extension");

      final path = "$tempSubfolderPath/$filename";

      //Write the file to FS
      await File(path).writeAsBytes(bytes);

      return FileSystemXFile(path);
    }
  }

  /// A wrapper of [MethodChannelShare._getFile] for multiple files.
  Future<List<FileSystemXFile>> _getFiles(
    List<XFile> files,
    List<String>? fileNameOverrides,
  ) async {
    return Future.wait([
      for (var index = 0; index < files.length; index++)
        _getFile(
          files[index],
          nameOverride: fileNameOverrides?.elementAt(index),
        ),
    ]);
  }

  static String _mimeTypeForPath(String path) {
    return lookupMimeType(path) ?? 'application/octet-stream';
  }

  static ShareResultStatus _statusFromResult(String result) {
    switch (result) {
      case '':
        return ShareResultStatus.dismissed;
      case 'dev.fluttercommunity.plus/share/unavailable':
        return ShareResultStatus.unavailable;
      default:
        return ShareResultStatus.success;
    }
  }
}
