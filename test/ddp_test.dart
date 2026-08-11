import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_serial_protocol/icicles_serial_protocol.dart';
import 'package:test/test.dart';

const red = Color(0xFFFF0000);
const green = Color(0xFF00FF00);
const blue = Color(0xFF0000FF);

AnimationView view(List<Color> pixels, [List<RadioPanelView> panels = const []]) => AnimationView(
      VisualFrame(duration: const Duration(milliseconds: 16), pixels: pixels),
      panels,
    );

void main() {
  group('encodeDdpFrame', () {
    test('lays out pixels then one color per panel', () {
      final frame = encodeDdpFrame(
        view(
          [red, green],
          [
            RadioPanelView(1, const [blue])
          ],
        ),
        xCount: 1,
        yCount: 2,
      );
      expect(frame, [255, 0, 0, 0, 255, 0, 0, 0, 255]);
    });

    test('transposes column-major view pixels to row-major channels', () {
      const white = Color(0xFFFFFFFF);
      // Column-major source: icicle 0 = [red, green], icicle 1 = [blue, white].
      final frame = encodeDdpFrame(
        view(const [red, green, blue, white]),
        xCount: 2,
        yCount: 2,
      );
      // Row-major wire: row 0 = [red, blue], row 1 = [green, white].
      expect(frame, [255, 0, 0, 0, 0, 255, 0, 255, 0, 255, 255, 255]);
    });

    test('uses the first color of multi-color panels', () {
      final frame = encodeDdpFrame(
        view(
          [red],
          [
            RadioPanelView(1, const [green, blue])
          ],
        ),
        xCount: 1,
        yCount: 1,
      );
      expect(frame.sublist(3), [0, 255, 0]);
    });

    test('fills missing panel slots black and keeps slots ordered by index', () {
      final frame = encodeDdpFrame(
        view(
          [red],
          [
            RadioPanelView(2, const [blue]),
            RadioPanelView(5, const [green]), // out of the 1..2 slot range -> dropped
          ],
        ),
        xCount: 1,
        yCount: 1,
      );
      expect(frame.sublist(3), [0, 0, 0, 0, 0, 255]);
    });
  });

  group('buildDdpPackets', () {
    test('matches the ddp-demo.js header for a single-packet frame', () {
      final frame = Uint8List.fromList([10, 20, 30]);
      final packets = buildDdpPackets(frame);
      expect(packets, hasLength(1));
      expect(packets.single, [0x41, 0x00, 0x01, 0x01, 0, 0, 0, 0, 0, 3, 10, 20, 30]);
    });

    test('chunks large frames at RGB boundaries with push only on the last packet', () {
      final frame = Uint8List.fromList(List.generate(3 * 5, (i) => i));
      final packets = buildDdpPackets(frame, maxDataPerPacket: 7); // 7 -> 6-byte RGB-aligned chunks
      expect(packets, hasLength(3));

      expect(packets[0][0], 0x40); // no push
      expect(packets[1][0], 0x40);
      expect(packets[2][0], 0x41); // push on the final packet

      // offsets u32 BE at [4..8), lengths u16 BE at [8..10)
      expect(packets[0].sublist(4, 10), [0, 0, 0, 0, 0, 6]);
      expect(packets[1].sublist(4, 10), [0, 0, 0, 6, 0, 6]);
      expect(packets[2].sublist(4, 10), [0, 0, 0, 12, 0, 3]);

      final reassembled = packets.expand((p) => p.sublist(ddpHeaderLength)).toList();
      expect(reassembled, frame);
    });

    test('today\'s full device frame fits one datagram', () {
      final frame = Uint8List(256 * 3 + 4 * 3);
      final packets = buildDdpPackets(frame);
      expect(packets, hasLength(1));
      expect(packets.single.length, ddpHeaderLength + 780);
    });
  });
}
