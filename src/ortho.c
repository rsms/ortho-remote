#include "ortho.h"

const char* ortho_event_name(OrthoEvent ev) {
  switch (ev) {
    case ORTHO_CONNECT:    return "CONNECT";
    case ORTHO_DISCONNECT: return "DISCONNECT";
    case ORTHO_RESTING:    return "RESTING";
    case ORTHO_PRESSED:    return "PRESSED";
    case ORTHO_VALUE:      return "VALUE";
  }
}

// TODO: look into an API like this.
// I tried implementing it for mac but the Core Bluetooth CBCentralManager
// library thingy is not working correctly unless it runs on the main thread.
//
// // ortho_poll blocks until the remote produces a message.
// // Returns 1 when msg was populated, 0 when an error occured.
// int ortho_poll(Ortho*, OrthoMsg* msg_out);
