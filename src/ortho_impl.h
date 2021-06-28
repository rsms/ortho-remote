#pragma once
#include "ortho.h"
#include <stdlib.h>

#ifdef NDEBUG
  #define dlog(fmt, ...) ((void)0)
#else
  #include <stdio.h>
  #define dlog(fmt, ...) fprintf(stderr, "# " fmt "\n", ##__VA_ARGS__)
#endif

// _ortho_on_ble_midi parses a MIDI package and calls msgcb if needed.
// returns 1 = called msgcb, 0 = did not call msgcb
int _ortho_on_midi(ortho_msg_fn msgcb, void* userdata, const uint8_t* data, size_t len);

// _ortho_on_ble_midi parses a BLE MIDI package and calls msgcb if needed.
// returns 1 = called msgcb, 0 = did not call msgcb
int _ortho_on_ble_midi(ortho_msg_fn msgcb, void* userdata, const uint8_t* data, size_t len);
