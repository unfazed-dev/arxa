// TEMPORARY diagnostic rail — scroll-animation investigation. Lets the
// arxa lens pull device screenshots from a PROFILE build over the VM
// service (the iOS profile VM lacks the native `screenshot` RPC).
// REMOVE once the investigation closes.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show GlobalKey;

class ShotExtension {
  static GlobalKey? _boundary;

  static void register(GlobalKey boundaryKey) {
    if (!kProfileMode) return; // diagnostic rail: profile only
    _boundary = boundaryKey;
    developer.registerExtension('ext.arxa.shot', (method, params) async {
      try {
        await SchedulerBinding.instance.endOfFrame;
        final boundary = _boundary?.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary == null) {
          return developer.ServiceExtensionResponse.error(
              developer.ServiceExtensionResponse.extensionError, 'no repaint boundary');
        }
        final ui.Image image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return developer.ServiceExtensionResponse.result(
            jsonEncode({'shot': base64Encode(bytes!.buffer.asUint8List())}));
      } catch (e) {
        return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError, e.toString());
      }
    });
  }
}