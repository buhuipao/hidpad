/// HID keyboard usage codes (USB HID Usage Tables, keyboard page 0x07).
abstract final class Usage {
  static const b = 0x05;
  static const enter = 0x28;
  static const escape = 0x29;
  static const backspace = 0x2A;
  static const tab = 0x2B;
  static const space = 0x2C;
  static const capsLock = 0x39;
  static const f1 = 0x3A; // F1..F12 are consecutive
  static const f5 = 0x3E;
  static const printScreen = 0x46;
  static const home = 0x4A;
  static const pageUp = 0x4B;
  static const delete = 0x4C;
  static const end = 0x4D;
  static const pageDown = 0x4E;
  static const right = 0x4F;
  static const left = 0x50;
  static const down = 0x51;
  static const up = 0x52;
  static const numLock = 0x53;
  static const keypadDivide = 0x54;
  static const keypadMultiply = 0x55;
  static const keypadMinus = 0x56;
  static const keypadPlus = 0x57;
  static const keypadEnter = 0x58;
  static const keypad1 = 0x59; // keypad 1..9 are consecutive
  static const keypad0 = 0x62;
  static const keypadDot = 0x63;
}

/// Modifier bits in the first byte of the keyboard report.
abstract final class Mod {
  static const ctrl = 0x01;
  static const shift = 0x02;
  static const alt = 0x04;
  static const gui = 0x08; // Windows / Command key
  static const rightAlt = 0x40; // AltGr
}

/// Mouse button bits in the first byte of the mouse report.
abstract final class MouseButton {
  static const left = 0x01;
  static const right = 0x02;
  static const middle = 0x04;
}

/// Media key usage codes (consumer page 0x0C).
abstract final class Media {
  static const menu = 0x40;
  static const brightnessUp = 0x6F;
  static const brightnessDown = 0x70;
  static const fastForward = 0xB3;
  static const rewind = 0xB4;
  static const next = 0xB5;
  static const previous = 0xB6;
  static const stop = 0xB7;
  static const playPause = 0xCD;
  static const mute = 0xE2;
  static const volumeUp = 0xE9;
  static const volumeDown = 0xEA;
  static const home = 0x223;
}

// Position i holds the character of usage 0x04 + i on a US keyboard, without and with Shift.
// ￿ marks a usage that has no character here.
const _plain = "abcdefghijklmnopqrstuvwxyz1234567890\n￿￿\t -=[]\\￿;'`,./";
const _shifted = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#\$%^&*()￿￿￿￿￿_+{}|￿:"~<>?';

/// The key that types [character] on a US keyboard, or null when there is none.
///
/// ponytail: US layout only. A computer set to another layout gets different symbols.
/// Add per-language tables here when that matters.
({int usage, bool shift})? usKey(String character) {
  if (character == '￿') return null;
  final plain = _plain.indexOf(character);
  if (plain >= 0) return (usage: 0x04 + plain, shift: false);
  final shifted = _shifted.indexOf(character);
  return shifted >= 0 ? (usage: 0x04 + shifted, shift: true) : null;
}
