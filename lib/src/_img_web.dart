// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.12

import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../img.dart';

const String kPlatformViewType = 'package:img';

class ImgState extends State<Img> {
  final ImageLoader loader = ImageLoader.instance;
  LoadedImage? image;

  @override
  void initState() {
    super.initState();
    if (loader.hasResultFor(widget.src)) {
      image = loader.resultFor(widget.src);
    } else {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final ImageLoadResult result = await loader.load(widget.src);
    if (result.isSuccess) {
      setState(() {
        image = result.image!;
      });
    } else {
      if (widget.onError != null) {
        widget.onError!(result.error!);
      } else {
        html.window.console.warn(result.error!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final LoadedImage? image = this.image;
    if (image == null) {
      return Container();
    } else if (image.image != null) {
      return image.image!;
    } else {
      assert(image.element != null);
      return ImageElementWidget(image.element!);
    }
  }
}

class ImageElementWidget extends StatelessWidget {
  ImageElementWidget(this.element);

  final html.ImageElement element;

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: kPlatformViewType,
      onCreatePlatformView: _onCreatePlatformView,
      surfaceFactory: (BuildContext context, PlatformViewController controller) {
        return PlatformViewSurface(
          controller: controller,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
    );
  }

  ImageElementController _onCreatePlatformView(PlatformViewCreationParams params) {
    final ImageElementController controller = ImageElementController(params.id);
    controller._initialize(element).then((_) {
      params.onPlatformViewCreated(params.id);
    });
    return controller;
  }
}

class ImageElementController extends PlatformViewController {
  ImageElementController(this.viewId);

  @override
  final int viewId;

  bool _initialized = false;

  Future<void> _initialize(html.ImageElement element) async {
    ElementEmbedder.instance.register(viewId, element);
    final Map<String, dynamic> args = <String, dynamic>{
      'id': viewId,
      'viewType': kPlatformViewType,
    };
    await SystemChannels.platform_views.invokeMethod<void>('create', args);
    _initialized = true;
  }

  @override
  Future<void> clearFocus() async {
  }

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {
  }

  @override
  Future<void> dispose() async {
    if (_initialized) {
      await SystemChannels.platform_views.invokeMethod<void>('dispose', viewId);
    }
  }
}

class ElementEmbedder {
  static ElementEmbedder instance = ElementEmbedder();

  ElementEmbedder() {
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      kPlatformViewType,
      (int viewId) {
        return _registeredImages.remove(viewId)!;
      },
    );
  }

  final Map<int, html.ImageElement> _registeredImages = <int, html.ImageElement>{};

  void register(int viewId, html.ImageElement element) {
    _registeredImages[viewId] = element;
  }
}

class ImageLoadException implements Exception {

}

class ImageLoader {
  static ImageLoader instance = ImageLoader();

  // Cache of previously loaded images.
  final Map<String, CachedImage> _cache = <String, CachedImage>{};

  // Cache of previously failed to load images.
  final Set<String> _failedImages = <String>{};

  /// Whether a previously loaded image is available.
  bool hasResultFor(String src) => _cache.containsKey(src);

  /// Returns a previously loaded image, or throws if missing.
  ///
  /// Use [hasResultFor] to check prior to calling this method.
  LoadedImage resultFor(String src) {
    final CachedImage? result = _cache[src];
    if (result == null) {
      throw AssertionError('Image result missing for $src');
    }
    return result.toResult();
  }

  Future<ImageLoadResult> load(String src) async {
    if (_failedImages.contains(src)) {
      throw ImageLoadException();
    }

    final Future<Image> imageFuture = _fetchImage(src);
    final Future<html.ImageElement> elementFuture = _loadImageElement(src);
    final Completer<ImageLoadResult> completer = Completer<ImageLoadResult>();

    final List<Object> errors = <Object>[];
    void reportError(Object error) {
      errors.add(error);
      if (errors.length == 2) {
        // Both methods failed
        completer.completeError(ImageLoadException());
      }
    }

    imageFuture.then((Image image) {
      completer.complete(ImageLoadResult.success(LoadedImage(
        image: image,
      )));
    }, onError: reportError);

    elementFuture.then((html.ImageElement element) {
      imageFuture.whenComplete(() {
        if (errors.isEmpty) {
          // XHR succeeded. <img> not needed.
          return;
        }

        _cache[src] = CachedImage(element: element);
        completer.complete(ImageLoadResult.success(resultFor(src)));
      });
    }, onError: reportError);

    return completer.future;
  }
}

class ImageLoadResult {
  ImageLoadResult.success(this.image)
    : isSuccess = true, error = null;

  ImageLoadResult.failure(this.error)
    : isSuccess = false, image = null;

  final bool isSuccess;
  final LoadedImage? image;
  final String? error;
}

enum RenderMethod {
  drawImage, platformView,
}

class CachedImage {
  CachedImage({
    this.element,
    this.image,
  });

  final html.ImageElement? element;
  final Image? image;

  LoadedImage toResult() {
    return LoadedImage(
      // We must clone the image element because it may appear more than once
      // on the screen.
      element: element?.clone(false) as html.ImageElement?,
      image: image,
    );
  }
}

class LoadedImage {
  LoadedImage({
    this.element,
    this.image,
  });

  final html.ImageElement? element;
  final Image? image;

  RenderMethod get method => image != null
    ? RenderMethod.drawImage
    : RenderMethod.platformView;
}

typedef HttpRequestFactory = html.HttpRequest Function();
HttpRequestFactory httpRequestFactory = () => html.HttpRequest();
void debugRestoreHttpRequestFactory() {
  httpRequestFactory = () => html.HttpRequest();
}

Future<html.ImageElement> _loadImageElement(String url) {
  final Completer<html.ImageElement> completer = Completer<html.ImageElement>();
  final html.ImageElement element = html.ImageElement();
  element.src = url;
  element.onLoad.first.then((_) {
    completer.complete(element);
  });
  element.onError.first.then((_) {
    completer.completeError('Failed to load <img> element.');
  });
  return completer.future;
}

Future<Image> _fetchImage(String url) async {
  final html.HttpRequest request = httpRequestFactory();
  request.open('GET', url, async: true);
  request.responseType = 'arraybuffer';

  final Completer<Uint8List> completer = Completer<Uint8List>();
  request.onError.listen((html.ProgressEvent event) {
    completer.completeError('HTTP request failed.');
  });

  request.onLoad.listen((html.ProgressEvent event) {
    final int status = request.status!;
    final bool accepted = status >= 200 && status < 300;
    final bool fileUri = status == 0; // file:// URIs have status of 0.
    final bool notModified = status == 304;
    final bool unknownRedirect = status > 307 && status < 400;
    final bool success = accepted || fileUri || notModified || unknownRedirect;
    if (!success) {
      completer.completeError('HTTP request failed.');
      return;
    }
    completer.complete(new Uint8List.view((request.response as ByteBuffer)));
  });

  request.send();
  final Uint8List data = await completer.future;
  return Image.memory(data);
}
