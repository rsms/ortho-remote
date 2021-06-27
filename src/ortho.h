#pragma once

typedef struct Ortho Ortho; // opaque

// OrthoEvent describes the type of message
typedef enum {
  // Status
  ORTHO_CONNECT,    // remote has connected
  ORTHO_DISCONNECT, // remote has disconnected

  // Remote input
  ORTHO_RESTING,   // remote is now in "resting" state (i.e. the button was released)
  ORTHO_PRESSED,   // remote is now in "depressed" state (i.e. the button is pressed)
  ORTHO_VALUE,     // remote was rotated (read the actual value from the value field)
} OrthoEvent;

// OrthoMsg is a message from the remote or library
typedef struct OrthoMsg {
  OrthoEvent ev;
  float      value; // value of the remote, range [0.0-1.0] (valid for ev==ORTHO_VALUE)
} OrthoMsg;

// ortho_memalloc_fn is the memory allocator function type (e.g. libc's malloc)
typedef void*(*ortho_memalloc_fn)(unsigned long nbyte);

// ortho_memfree_fn is the memory free function type (e.g. libc's free)
typedef void(*ortho_memfree_fn)(void* ptr);

// ortho_msg_fn is the message callback function type
typedef void(*ortho_msg_fn)(const OrthoMsg* msg, void* userdata);


// ortho_create creates a new Ortho handle
Ortho* ortho_create(ortho_memalloc_fn);

// ortho_free stops & releases internal state and memory
void ortho_free(Ortho*, ortho_memfree_fn);

// ortho_runloop runs forever. It must run on the main thread.
// userdata is some opaque value passed to msgcb.
int ortho_runloop(Ortho*, ortho_msg_fn msgcb, void* userdata);

// ortho_event_name is a convenience function that returns a null-terminated string
// of the event name, useful for printing.
const char* ortho_event_name(OrthoEvent ev);
