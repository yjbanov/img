// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.12

import 'package:flutter/widgets.dart';

import 'src/_img_io.dart'
  if (dart.library.html) 'src/_img_web.dart' as impl;

typedef ImageLoadExceptionCallback = void Function(String);

@immutable
class Img extends StatefulWidget {
  const Img(this.src, {
    this.onError,
  });

  final String src;
  final ImageLoadExceptionCallback? onError;

  @override
  State<StatefulWidget> createState() {
    return impl.ImgState();
  }
}
