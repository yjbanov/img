// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.12

import 'package:flutter/widgets.dart';

import '../img.dart';

class ImgState extends State<Img> {
  @override
  Widget build(BuildContext context) {
    return Image.network(widget.src);
  }
}
