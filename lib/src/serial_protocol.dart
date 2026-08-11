import 'dart:typed_data';

/// Framed USB-serial protocol, version 1.
///
/// Spec: `icicles-controller-esp8266/docs/serial-protocol.md`. Every message,
/// both directions: `A5 1C | version | type | length u16 LE | payload | crc16 LE`
/// where the CRC-16/CCITT-FALSE covers version..payload (magic excluded).

const int serialProtocolVersion = 1;
const int serialMagic0 = 0xA5;
const int serialMagic1 = 0x1C;
const int serialHeaderLength = 6;
const int serialCrcLength = 2;

enum IciclesMessageType {
  // host -> device
  ping(0x00),
  displayView(0x01),
  end(0x0A),
  // device -> host
  info(0x80),
  ack(0x81),
  nack(0x82),
  endAck(0x83);

  const IciclesMessageType(this.value);
  final int value;
}

enum NackCode {
  badCrc(1),
  unsupportedVersion(2),
  unknownType(3),
  badPayloadLength(4),
  frameTooLong(5);

  const NackCode(this.value);
  final int value;

  static NackCode? fromValue(int value) {
    for (final code in values) {
      if (code.value == value) return code;
    }
    return null;
  }
}

/// CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflection, no final XOR.
/// `crc16(ascii "123456789") == 0x29B1`.
int crc16(Uint8List data, [int start = 0, int? end]) {
  var crc = 0xFFFF;
  for (var i = start; i < (end ?? data.length); i++) {
    crc ^= data[i] << 8;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 0x8000 != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  return crc;
}

Uint8List encodeFrame(IciclesMessageType type, [Uint8List? payload]) {
  final length = payload?.length ?? 0;
  final frame = Uint8List(serialHeaderLength + length + serialCrcLength);
  frame[0] = serialMagic0;
  frame[1] = serialMagic1;
  frame[2] = serialProtocolVersion;
  frame[3] = type.value;
  frame[4] = length & 0xFF;
  frame[5] = length >> 8;
  if (payload != null) {
    frame.setRange(serialHeaderLength, serialHeaderLength + length, payload);
  }
  final crc = crc16(frame, 2, serialHeaderLength + length);
  frame[serialHeaderLength + length] = crc & 0xFF;
  frame[serialHeaderLength + length + 1] = crc >> 8;
  return frame;
}

class ProtocolFrame {
  final int version;
  final int type;
  final Uint8List payload;

  const ProtocolFrame({
    required this.version,
    required this.type,
    required this.payload,
  });
}

/// Device description carried by the Info reply. All payload sizes must be
/// derived from it — never hardcoded.
class DeviceInfo {
  final int protocolVersion;
  final int xCount;
  final int yCount;
  final int ledsCount;
  final int radioPanelsCount;
  final int radioLedsCount;

  const DeviceInfo({
    required this.protocolVersion,
    required this.xCount,
    required this.yCount,
    required this.ledsCount,
    required this.radioPanelsCount,
    required this.radioLedsCount,
  });

  factory DeviceInfo.fromPayload(Uint8List payload) {
    if (payload.length != 7) {
      throw FormatException('Info payload must be 7 bytes, got ${payload.length}');
    }
    return DeviceInfo(
      protocolVersion: payload[0],
      xCount: payload[1],
      yCount: payload[2],
      ledsCount: payload[3] | (payload[4] << 8),
      radioPanelsCount: payload[5],
      radioLedsCount: payload[6],
    );
  }

  int get displayViewPayloadLength => ledsCount * 3 + radioPanelsCount * (1 + radioLedsCount * 3);

  @override
  String toString() => 'DeviceInfo(v$protocolVersion, ${xCount}x$yCount, leds: $ledsCount, '
      'radioPanels: $radioPanelsCount x $radioLedsCount leds)';
}

/// Incremental frame parser mirroring the firmware and the JS reference host:
/// hunts for the magic, validates length and CRC, and skips garbage (including
/// device log text spliced between reply frames) byte by byte, so one bad
/// frame never shifts alignment.
class FrameParser {
  FrameParser({this.maxPayload = 2048});

  /// Garbage-rejection bound for the length field, not a real protocol limit;
  /// frames the host receives are at most 7 payload bytes.
  final int maxPayload;

  Uint8List _buf = Uint8List(0);

  /// Consumes [chunk] and returns every complete, CRC-valid frame found.
  List<ProtocolFrame> feed(Uint8List chunk) {
    if (_buf.isEmpty) {
      _buf = Uint8List.fromList(chunk);
    } else {
      _buf = (BytesBuilder(copy: false)
            ..add(_buf)
            ..add(chunk))
          .takeBytes();
    }
    final frames = <ProtocolFrame>[];
    for (;;) {
      final start = _indexOfMagic(_buf);
      if (start < 0) {
        // Keep a trailing A5 in case its partner byte is still in flight.
        _buf = _buf.isNotEmpty && _buf.last == serialMagic0 ? Uint8List.fromList([serialMagic0]) : Uint8List(0);
        return frames;
      }
      if (start > 0) _buf = Uint8List.sublistView(_buf, start);
      if (_buf.length < serialHeaderLength) return frames;
      final length = _buf[4] | (_buf[5] << 8);
      if (length > maxPayload) {
        _buf = Uint8List.sublistView(_buf, 1);
        continue;
      }
      final frameEnd = serialHeaderLength + length + serialCrcLength;
      if (_buf.length < frameEnd) return frames;
      final receivedCrc = _buf[serialHeaderLength + length] | (_buf[serialHeaderLength + length + 1] << 8);
      if (crc16(_buf, 2, serialHeaderLength + length) != receivedCrc) {
        // False magic inside garbage; resume the hunt one byte later.
        _buf = Uint8List.sublistView(_buf, 1);
        continue;
      }
      frames.add(ProtocolFrame(
        version: _buf[2],
        type: _buf[3],
        payload: Uint8List.fromList(Uint8List.sublistView(_buf, serialHeaderLength, serialHeaderLength + length)),
      ));
      _buf = Uint8List.sublistView(_buf, frameEnd);
    }
  }

  static int _indexOfMagic(Uint8List data) {
    for (var i = 0; i + 1 < data.length; i++) {
      if (data[i] == serialMagic0 && data[i + 1] == serialMagic1) return i;
    }
    return -1;
  }
}
