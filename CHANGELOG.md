## 0.2.1

- Depends on _icicles_animation_dart_ `v3.0.0`.

## 0.2.0

- **Breaking:** _encodeDdpFrame_ requires `radioPanelsCount`; panels are sized from the header, out-of-range indexes are skipped.
- _encodeFrame_ rejects payloads larger than 65535 bytes.
- _FrameParser_ default `maxPayload` lowered from 2048 to 16, so a false magic in garbage holds back at most a few real frames.

## 0.1.0

- Serial framing (CRC-16), garbage-tolerant frame parsing, device info, DisplayView and DDP packet encoding.
