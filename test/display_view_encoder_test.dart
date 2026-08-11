import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_serial_protocol/icicles_serial_protocol.dart';
import 'package:test/test.dart';

const red = Color(0xFFFF0000);
const green = Color(0xFF00FF00);
const blue = Color(0xFF0000FF);

DeviceInfo info({int ledsCount = 4, int radioPanelsCount = 2, int radioLedsCount = 3}) => DeviceInfo(
      protocolVersion: 1,
      xCount: 2,
      yCount: 2,
      ledsCount: ledsCount,
      radioPanelsCount: radioPanelsCount,
      radioLedsCount: radioLedsCount,
    );

AnimationView view(List<Color> pixels, [List<RadioPanelView> panels = const []]) => AnimationView(
      VisualFrame(duration: const Duration(milliseconds: 16), pixels: pixels),
      panels,
    );

void main() {
  group('encodeDisplayViewPayload', () {
    test('always emits the exact device payload length', () {
      final payload = encodeDisplayViewPayload(view([red]), info());
      expect(payload, hasLength(4 * 3 + 2 * (1 + 3 * 3)));
      expect(payload, hasLength(info().displayViewPayloadLength));
    });

    test('writes pixels as R, G, B and pads missing pixels black', () {
      final payload = encodeDisplayViewPayload(view([red, green]), info());
      expect(payload.sublist(0, 12), [255, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0]);
    });

    test('drops pixels beyond the device led count', () {
      final payload = encodeDisplayViewPayload(view([red, red, red, red, green, blue]), info());
      expect(payload.sublist(0, 12), [255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0]);
    });

    test('emits panel slots 1..radioPanelsCount matched by panel index', () {
      final payload = encodeDisplayViewPayload(view([red], [RadioPanelView(2, const [red])]), info());
      // Slot 1 has no matching panel: index byte followed by black LEDs.
      expect(payload.sublist(12, 22), [1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      // Slot 2 matches the provided panel.
      expect(payload.sublist(22, 32), [2, 255, 0, 0, 255, 0, 0, 255, 0, 0]);
    });

    test('replicates a single panel color across all panel leds', () {
      final payload = encodeDisplayViewPayload(view([red], [RadioPanelView(1, const [green])]), info());
      expect(payload.sublist(12, 22), [1, 0, 255, 0, 0, 255, 0, 0, 255, 0]);
    });

    test('copies multi-color panels and pads missing leds black', () {
      final payload = encodeDisplayViewPayload(view([red], [RadioPanelView(1, const [red, blue])]), info());
      expect(payload.sublist(12, 22), [1, 255, 0, 0, 0, 0, 255, 0, 0, 0]);
    });

    test('drops panel colors beyond the device panel led count', () {
      final payload = encodeDisplayViewPayload(view([red], [RadioPanelView(1, const [red, blue, green, red])]), info());
      expect(payload.sublist(12, 22), [1, 255, 0, 0, 0, 0, 255, 0, 255, 0]);
    });

    test('drops panels with out-of-range indexes', () {
      final payload = encodeDisplayViewPayload(view([red], [RadioPanelView(5, const [red])]), info());
      expect(payload.sublist(12, 22), [1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect(payload.sublist(22, 32), [2, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    });

    test('supports devices without radio panels', () {
      final payload = encodeDisplayViewPayload(view([red]), info(radioPanelsCount: 0));
      expect(payload, hasLength(12));
    });
  });
}
