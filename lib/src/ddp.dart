import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

/// DDP (Distributed Display Protocol) v1 packet building for the icicles
/// controller's UDP receiver (default port 4048, xLights/LedFx compatible).
///
/// Channel space expected by the device: grid RGB in row-major order
/// (x across, y down - the firmware indexer maps this to the physical
/// strip), then one RGB triplet per radio panel. The receiver splits rows by
/// its own xCount and reads panels after its own grid, so the animation
/// dimensions must match the device; out-of-range data is clamped, never
/// overrun.

const int ddpDefaultPort = 4048;
const int ddpHeaderLength = 10;

const int _ddpFlagVersion1 = 0x40;
const int _ddpFlagPush = 0x01;
const int _ddpDataTypeRgb = 0x01;
const int _ddpDefaultDisplayId = 0x01;

/// Flattens [view] into the DDP channel layout: grid pixels as R,G,B in
/// row-major order (the view's pixels are column-major, `x * yCount + y`,
/// so this transposes), then panel slots `1..radioPanelsCount` matched
/// by the 1-based panel index (missing slot stays black), one color per
/// panel — DDP has a flat channel space, so per-LED panel colors cannot
/// be carried.
Uint8List encodeDdpFrame(
  AnimationView view, {
  required int xCount,
  required int yCount,
  required int radioPanelsCount,
}) {
  final pixels = view.frame.pixels;
  final gridPixels = xCount * yCount;
  assert(pixels.length == gridPixels,
      'view has ${pixels.length} pixels but grid is ${xCount}x$yCount');
  final frame = Uint8List(gridPixels * 3 + radioPanelsCount * 3);

  for (var y = 0; y < yCount; y++) {
    for (var x = 0; x < xCount; x++) {
      final source = x * yCount + y;
      if (source >= pixels.length) continue;
      final color = pixels[source];
      final offset = (y * xCount + x) * 3;
      frame[offset] = color.red;
      frame[offset + 1] = color.green;
      frame[offset + 2] = color.blue;
    }
  }

  for (final panel in view.radioPanels) {
    if (panel.index < 1 || panel.index > radioPanelsCount) continue;
    final color = panel.colors.first;
    final offset = gridPixels * 3 + (panel.index - 1) * 3;
    frame[offset] = color.red;
    frame[offset + 1] = color.green;
    frame[offset + 2] = color.blue;
  }

  return frame;
}

/// Splits [frame] into DDP packets: 10-byte header (version 1, RGB data,
/// default display id, offset u32 BE, length u16 BE) + channel data. Chunks
/// are RGB-aligned and the push flag is set only on the final packet, so the
/// device applies the frame once it is complete. Today's whole frame fits a
/// single datagram; chunking covers larger future grids.
List<Uint8List> buildDdpPackets(Uint8List frame, {int maxDataPerPacket = 1440}) {
  assert(maxDataPerPacket >= 3);
  final chunkSize = maxDataPerPacket - (maxDataPerPacket % 3);
  final packets = <Uint8List>[];

  var offset = 0;
  do {
    final end = (offset + chunkSize < frame.length) ? offset + chunkSize : frame.length;
    final length = end - offset;
    final isLast = end >= frame.length;

    final packet = Uint8List(ddpHeaderLength + length);
    packet[0] = _ddpFlagVersion1 | (isLast ? _ddpFlagPush : 0);
    packet[1] = 0; // sequence: unused
    packet[2] = _ddpDataTypeRgb;
    packet[3] = _ddpDefaultDisplayId;
    packet[4] = (offset >> 24) & 0xFF;
    packet[5] = (offset >> 16) & 0xFF;
    packet[6] = (offset >> 8) & 0xFF;
    packet[7] = offset & 0xFF;
    packet[8] = (length >> 8) & 0xFF;
    packet[9] = length & 0xFF;
    packet.setRange(ddpHeaderLength, ddpHeaderLength + length, frame, offset);

    packets.add(packet);
    offset = end;
  } while (offset < frame.length);

  return packets;
}
