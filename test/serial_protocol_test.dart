import 'dart:convert';
import 'dart:typed_data';

import 'package:icicles_serial_protocol/icicles_serial_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('crc16', () {
    test('matches the CRC-16/CCITT-FALSE check value', () {
      expect(crc16(Uint8List.fromList(ascii.encode('123456789'))), 0x29B1);
    });

    test('is 0xFFFF for empty input', () {
      expect(crc16(Uint8List(0)), 0xFFFF);
    });
  });

  group('encodeFrame', () {
    test('produces the spec wire bytes for Ping', () {
      expect(
        encodeFrame(IciclesMessageType.ping),
        [0xA5, 0x1C, 0x01, 0x00, 0x00, 0x00, 0x74, 0xF2],
      );
    });

    test('produces the spec wire bytes for End', () {
      expect(
        encodeFrame(IciclesMessageType.end),
        [0xA5, 0x1C, 0x01, 0x0A, 0x00, 0x00, 0xB5, 0x35],
      );
    });

    test('round-trips a payload frame through FrameParser', () {
      final payload = Uint8List.fromList(List.generate(300, (i) => i & 0xFF));
      final frames = FrameParser(maxPayload: payload.length).feed(encodeFrame(IciclesMessageType.displayView, payload));
      expect(frames, hasLength(1));
      expect(frames.single.version, serialProtocolVersion);
      expect(frames.single.type, IciclesMessageType.displayView.value);
      expect(frames.single.payload, payload);
    });

    test('rejects payloads that overflow the u16 length field', () {
      expect(() => encodeFrame(IciclesMessageType.displayView, Uint8List(0x10000)), throwsArgumentError);
    });
  });

  group('FrameParser', () {
    final infoPayload = Uint8List.fromList([1, 32, 8, 0x00, 0x01, 4, 50]);
    final infoFrame = encodeFrame(IciclesMessageType.info, infoPayload);
    final ackFrame = encodeFrame(IciclesMessageType.ack, Uint8List.fromList([0]));

    test('parses a frame delivered one byte at a time', () {
      final parser = FrameParser();
      final frames = <ProtocolFrame>[];
      for (final byte in infoFrame) {
        frames.addAll(parser.feed(Uint8List.fromList([byte])));
      }
      expect(frames, hasLength(1));
      expect(frames.single.payload, infoPayload);
    });

    test('parses two frames from one chunk', () {
      final frames = FrameParser().feed(Uint8List.fromList([...infoFrame, ...ackFrame]));
      expect(frames.map((f) => f.type), [IciclesMessageType.info.value, IciclesMessageType.ack.value]);
    });

    test('skips device log text spliced between frames', () {
      final frames = FrameParser().feed(Uint8List.fromList([
        ...ascii.encode('boot: wifi connecting...\n'),
        ...infoFrame,
        ...ascii.encode('ddp: packet dropped\n'),
        ...ackFrame,
      ]));
      expect(frames.map((f) => f.type), [IciclesMessageType.info.value, IciclesMessageType.ack.value]);
    });

    test('keeps a trailing 0xA5 whose partner byte is still in flight', () {
      final parser = FrameParser();
      expect(parser.feed(Uint8List.fromList([0x00, 0x11, 0xA5])), isEmpty);
      final frames = parser.feed(Uint8List.sublistView(infoFrame, 1));
      expect(frames, hasLength(1));
      expect(frames.single.payload, infoPayload);
    });

    test('resyncs after a false magic with an oversized length field', () {
      final frames = FrameParser().feed(Uint8List.fromList([
        0xA5, 0x1C, 0x01, 0x01, 0xFF, 0xFF, // bogus header claiming a 64 KB payload
        ...infoFrame,
      ]));
      expect(frames, hasLength(1));
      expect(frames.single.type, IciclesMessageType.info.value);
    });

    test('does not hold back frames behind a false magic with a plausible length', () {
      final frames = FrameParser().feed(Uint8List.fromList([
        0xA5, 0x1C, 0x01, 0x01, 0x00, 0x04, // bogus header claiming a 1 KB payload
        ...ackFrame,
      ]));
      expect(frames, hasLength(1));
      expect(frames.single.type, IciclesMessageType.ack.value);
    });

    test('recovers a frame that starts inside a CRC-invalid bogus frame', () {
      // A forged header whose claimed 16-byte payload swallows the real frame:
      // once the bogus frame is complete its CRC fails, and the parser must
      // resync byte by byte instead of skipping the whole claimed span.
      final parser = FrameParser();
      expect(
        parser.feed(Uint8List.fromList([
          0xA5, 0x1C, 0x01, 0x01, 0x10, 0x00, // header claiming 16 payload bytes
          ...infoFrame,
          0x00, 0x00,
        ])),
        isEmpty, // the bogus frame is one byte short of complete
      );
      final frames = parser.feed(Uint8List.fromList([0x00]));
      expect(frames, hasLength(1));
      expect(frames.single.payload, infoPayload);
    });

    test('buffers an incomplete frame until the rest arrives', () {
      final parser = FrameParser();
      expect(parser.feed(Uint8List.sublistView(infoFrame, 0, 5)), isEmpty);
      final frames = parser.feed(Uint8List.sublistView(infoFrame, 5));
      expect(frames, hasLength(1));
      expect(frames.single.payload, infoPayload);
    });
  });

  group('DeviceInfo', () {
    test('decodes the Info payload little-endian', () {
      final info = DeviceInfo.fromPayload(Uint8List.fromList([1, 32, 8, 0x00, 0x01, 4, 50]));
      expect(info.protocolVersion, 1);
      expect(info.xCount, 32);
      expect(info.yCount, 8);
      expect(info.ledsCount, 256);
      expect(info.radioPanelsCount, 4);
      expect(info.radioLedsCount, 50);
    });

    test('computes the DisplayView payload length', () {
      final info = DeviceInfo.fromPayload(Uint8List.fromList([1, 32, 8, 0x00, 0x01, 4, 50]));
      expect(info.displayViewPayloadLength, 256 * 3 + 4 * (1 + 50 * 3));
    });

    test('rejects payloads that are not exactly 7 bytes', () {
      expect(() => DeviceInfo.fromPayload(Uint8List(6)), throwsFormatException);
      expect(() => DeviceInfo.fromPayload(Uint8List(8)), throwsFormatException);
    });
  });
}
