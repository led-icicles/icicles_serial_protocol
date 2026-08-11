/// Streaming protocols for icicles controllers: the framed USB-serial
/// protocol v1 (spec: `icicles-controller-esp8266/docs/serial-protocol.md`)
/// and DDP packet building for the UDP receiver.
library;

export 'src/ddp.dart';
export 'src/display_view_encoder.dart';
export 'src/serial_protocol.dart';
