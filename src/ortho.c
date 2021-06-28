#include "ortho_impl.h"


// MIDI 1 message protocol constants
// Status Description        Msg size  Byte 1      Byte 2
// 8x     note off           2         pitch       velocity
// 9x     note on            2         pitch       velocity
// Bx     controller change  2         controller  value
// ...
// Source: https://www.cs.cmu.edu/~music/cmsip/readings/davids-midi-spec.htm
#define MIDI1_H_NOTE_OFF 0x8
#define MIDI1_H_NOTE_ON  0x9
#define MIDI1_H_CTRL_CH  0xB

#define MIDI_BLE_SYSEX_START 0xf0
#define MIDI_BLE_SYSEX_END   0xf7


// TODO: look into an API like this.
// I tried implementing it for mac but the Core Bluetooth CBCentralManager
// library thingy is not working correctly unless it runs on the main thread.
//
// // ortho_poll blocks until the remote produces a message.
// // Returns 1 when msg was populated, 0 when an error occured.
// int ortho_poll(Ortho*, OrthoMsg* msg_out);


const char* ortho_event_name(OrthoEvent ev) {
  switch (ev) {
    case ORTHO_CONNECT:    return "CONNECT";
    case ORTHO_DISCONNECT: return "DISCONNECT";
    case ORTHO_RESTING:    return "RESTING";
    case ORTHO_PRESSED:    return "PRESSED";
    case ORTHO_VALUE:      return "VALUE";
  }
  return "?";
}


int _ortho_on_midi(ortho_msg_fn msgcb, void* userdata, const uint8_t* data, size_t len) {
  if (len == 0)
    return 0;

  OrthoMsg msg = {0};

  switch ((data[0] >> 4) & 0xF) {
    case MIDI1_H_NOTE_OFF:
      // payload: 2 bytes
      dlog("button released (pitch %02X, velocity %02X)", data[1], data[2]);
      msg.ev = ORTHO_RESTING;
      break;

    case MIDI1_H_NOTE_ON:
      // payload: 2 bytes (pitch, velocity)
      dlog("button depressed (pitch %02X, velocity %02X)", data[1], data[2]);
      msg.ev = ORTHO_PRESSED;
      break;

    case MIDI1_H_CTRL_CH: {
      // payload: 2 bytes (controller id, value 00–7f)
      msg.value = (float)data[2] / (float)0x7f;
      dlog("rotated (controller %02X, value %f)", data[1], msg.value);
      msg.ev = ORTHO_VALUE;
      break;
    }

    default:
      dlog("unexpected MIDI message 0x%02X", (data[0] & 0x7f));
      return 0;
  }

  msgcb(&msg, userdata);
  return 1;
}


int _ortho_on_ble_midi(ortho_msg_fn msgcb, void* userdata, const uint8_t* data, size_t len) {
  if (len < 3)
    return 0;

  // MIDI BLE Packet:
  //
  // field  | bit: 0  1  2  3  4  5  6  7
  // -------+----- -- -- -- -- -- -- -- --
  // header        1  r  <-timestamp_hi ->
  // timestamp_lo  1  <-  timestamp_lo  ->
  // status        1  <-      code      ->
  // data1         0  ...
  // dataN         0  ...

  if (((0xF0 & data[0]) >> 7) == 0) {
    // unexpected data byte (remaining 7 bits are data bits)
    return 0;
  }

  // MSB is 1 -- this is a status message
  if (data[0] == MIDI_BLE_SYSEX_START || data[0] == MIDI_BLE_SYSEX_END) {
    // ignore
    return 0;
  }

  // uint8_t r = data[0] & 0x40;
  // uint32_t timestamp = ((data[1] & 0x7f)) | ((data[0] & 0x3f) << 8);
  // fprintf(stderr, "[r %u, ts %u] ", r, timestamp);

  return _ortho_on_midi(msgcb, userdata, &data[2], len - 2);
}
