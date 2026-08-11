import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import 'serial_protocol.dart';

/// Builds the DisplayView payload for [info]'s exact dimensions:
/// `ledsCount * 3` RGB bytes in strip order (frame pixels are already
/// column-major), then `radioPanelsCount` entries of
/// `{panelIndex u8, radioLedsCount * {r, g, b}}`.
///
/// The device requires an exact length match, so the view is adapted: extra
/// pixels/panels are dropped, missing ones are padded black. A panel that has
/// a single color gets it replicated across all of its LEDs. The legacy
/// `AnimationView.toBytes()` wire format (leading type byte, variable-length
/// panel entries) is not compatible with this protocol.
Uint8List encodeDisplayViewPayload(AnimationView view, DeviceInfo info) {
  final payload = Uint8List(info.displayViewPayloadLength);

  final pixels = view.frame.pixels;
  final pixelCount = pixels.length < info.ledsCount ? pixels.length : info.ledsCount;
  for (var i = 0; i < pixelCount; i++) {
    final color = pixels[i];
    payload[i * 3] = color.red;
    payload[i * 3 + 1] = color.green;
    payload[i * 3 + 2] = color.blue;
  }

  final panelsByIndex = {for (final panel in view.radioPanels) panel.index: panel};
  final panelSize = 1 + info.radioLedsCount * 3;
  for (var slot = 1; slot <= info.radioPanelsCount; slot++) {
    final offset = info.ledsCount * 3 + (slot - 1) * panelSize;
    payload[offset] = slot;
    final panel = panelsByIndex[slot];
    if (panel == null) continue; // missing panel stays black
    final colors = panel.colors;
    final ledCount = colors.length == 1
        ? info.radioLedsCount
        : (colors.length < info.radioLedsCount ? colors.length : info.radioLedsCount);
    for (var led = 0; led < ledCount; led++) {
      final color = colors.length == 1 ? colors.first : colors[led];
      payload[offset + 1 + led * 3] = color.red;
      payload[offset + 1 + led * 3 + 1] = color.green;
      payload[offset + 1 + led * 3 + 2] = color.blue;
    }
  }

  return payload;
}
